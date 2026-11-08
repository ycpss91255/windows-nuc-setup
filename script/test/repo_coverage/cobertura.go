package repo_coverage

import (
	"encoding/xml"
	"fmt"
	"path/filepath"
	"strconv"
	"strings"
)

type coberturaDocument struct {
	XMLName xml.Name `xml:"coverage"`
	Schema  string   `xml:"coverage-schema,attr"`
	Metric  string   `xml:"coverage-metric,attr"`
	Sources []string `xml:"sources>source"`
	Classes []struct {
		Filename string `xml:"filename,attr"`
		Lines    []struct {
			Number string `xml:"number,attr"`
			Hits   string `xml:"hits,attr"`
		} `xml:"lines>line"`
	} `xml:"packages>package>classes>class"`
}

func withinRoot(root, name string) (string, error) {
	root, err := filepath.Abs(root)
	if err != nil {
		return "", err
	}
	name = strings.ReplaceAll(name, `\`, "/")
	if !filepath.IsAbs(filepath.FromSlash(name)) {
		return "", fmt.Errorf("expected absolute collector source %q", name)
	}
	rel, err := filepath.Rel(root, filepath.Clean(filepath.FromSlash(name)))
	if err != nil {
		return "", err
	}
	return RelativePath(filepath.ToSlash(rel))
}

func sourcePath(root, name string, sources []string) (string, error) {
	name = strings.ReplaceAll(strings.TrimSpace(name), `\`, "/")
	if filepath.IsAbs(filepath.FromSlash(name)) {
		return withinRoot(root, name)
	}
	rel, err := RelativePath(name)
	if err != nil {
		return "", err
	}
	if len(sources) == 0 {
		return rel, nil
	}
	paths := map[string]bool{}
	for _, source := range sources {
		base := filepath.FromSlash(strings.ReplaceAll(strings.TrimSpace(source), `\`, "/"))
		if base == "" {
			base = root
		} else if !filepath.IsAbs(base) {
			base = filepath.Join(root, base)
		}
		candidate, err := withinRoot(root, filepath.Join(base, filepath.FromSlash(rel)))
		if err != nil {
			return "", err
		}
		paths[candidate] = true
	}
	if len(paths) != 1 {
		return "", fmt.Errorf("ambiguous collector source: %s", name)
	}
	for name := range paths {
		return name, nil
	}
	return "", fmt.Errorf("missing collector source")
}

// ParseCobertura reads raw per-line evidence, never trusts aggregate XML rates.
// Only documents emitted by a complete-line normalizer carry the required
// schema and metric attributes. Raw third-party Cobertura cannot be merged as
// complete-line evidence without the language-specific normalization step.
func ParseCobertura(data []byte, root string) (Report, error) {
	r := Report{Files: map[string]map[int]bool{}}
	var doc coberturaDocument
	if err := xml.Unmarshal(data, &doc); err != nil {
		return r, err
	}
	if len(doc.Classes) == 0 {
		return r, fmt.Errorf("Cobertura contains no source classes")
	}
	r.Metric = doc.Metric
	if doc.Schema != "" {
		version, err := strconv.Atoi(doc.Schema)
		if err != nil {
			return r, fmt.Errorf("invalid coverage schema")
		}
		r.SchemaVersion = version
	}
	for _, class := range doc.Classes {
		name, err := sourcePath(root, class.Filename, doc.Sources)
		if err != nil {
			return r, err
		}
		if r.Files[name] == nil {
			r.Files[name] = map[int]bool{}
		}
		for _, line := range class.Lines {
			n, err := strconv.Atoi(line.Number)
			if err != nil || n <= 0 {
				return r, fmt.Errorf("invalid executable line in %s", name)
			}
			hits, err := strconv.ParseInt(line.Hits, 10, 64)
			if err != nil || hits < 0 {
				return r, fmt.Errorf("invalid hits at %s:%d", name, n)
			}
			r.Files[name][n] = r.Files[name][n] || hits > 0
		}
	}
	return r, nil
}
