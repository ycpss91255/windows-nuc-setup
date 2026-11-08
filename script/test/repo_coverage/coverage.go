// Package repo_coverage combines complete executable-line evidence collected
// locally by language-specific collectors. It does not infer coverage from tests.
package repo_coverage

import (
	"fmt"
	"path"
	"sort"
	"strings"
)

const Metric = "complete-executable-lines-v1"
const SchemaVersion = 1

type Source struct{ Path, Language string }
type Report struct {
	SchemaVersion int
	Metric        string
	Files         map[string]map[int]bool
}
type Counts struct{ Covered, Executable int }
type Result struct {
	SchemaVersion       int
	Metric              string
	Complete            bool
	Covered, Executable int
	Percent             *float64
	Missing             []string
	Languages           map[string]Counts
}

// RelativePath accepts canonical repository-relative file names on every host.
// It deliberately refuses rooted paths, drive letters and parent traversal.
func RelativePath(name string) (string, error) {
	name = strings.ReplaceAll(strings.TrimSpace(name), `\`, "/")
	if name == "" || strings.HasPrefix(name, "/") || strings.ContainsAny(name, ":\x00") {
		return "", fmt.Errorf("invalid relative source path %q", name)
	}
	for _, part := range strings.Split(name, "/") {
		if part == ".." {
			return "", fmt.Errorf("source path escapes repository: %q", name)
		}
	}
	name = path.Clean(name)
	if name == "." {
		return "", fmt.Errorf("source path is not a file")
	}
	return name, nil
}

// Merge requires an explicit inventory: omitted source files never disappear
// from the coverage scope. Language collectors must merge fine-grained counters
// before declaring this metric; ordinary Cobertura line-hit reports are refused.
func Merge(sources []Source, reports ...Report) (Result, error) {
	r := Result{SchemaVersion: SchemaVersion, Metric: Metric, Complete: true, Languages: map[string]Counts{}}
	if len(sources) == 0 {
		return r, fmt.Errorf("source inventory is empty")
	}
	scope := map[string]string{}
	casePaths := map[string]string{}
	for _, source := range sources {
		name, err := RelativePath(source.Path)
		if err != nil {
			return r, err
		}
		if source.Language == "" {
			return r, fmt.Errorf("source has no language: %s", name)
		}
		fold := strings.ToLower(name)
		if _, exists := casePaths[fold]; exists {
			return r, fmt.Errorf("duplicate inventory source: %s", name)
		}
		casePaths[fold] = name
		scope[name] = source.Language
	}
	merged := map[string]map[int]bool{}
	for _, report := range reports {
		if report.SchemaVersion != SchemaVersion || report.Metric != Metric {
			return r, fmt.Errorf("incompatible coverage schema or metric")
		}
		for raw, lines := range report.Files {
			name, err := RelativePath(raw)
			if err != nil {
				return r, err
			}
			canonical, ok := casePaths[strings.ToLower(name)]
			if !ok {
				return r, fmt.Errorf("out-of-scope report source: %s", name)
			}
			if merged[canonical] == nil {
				merged[canonical] = map[int]bool{}
			}
			for line, hit := range lines {
				if line <= 0 {
					return r, fmt.Errorf("invalid executable line: %s:%d", name, line)
				}
				merged[canonical][line] = merged[canonical][line] || hit
			}
		}
	}
	for name, language := range scope {
		lines, present := merged[name]
		if !present {
			r.Missing = append(r.Missing, name)
			r.Complete = false
			continue
		}
		c := r.Languages[language]
		for _, hit := range lines {
			c.Executable++
			r.Executable++
			if hit {
				c.Covered++
				r.Covered++
			}
		}
		r.Languages[language] = c
	}
	sort.Strings(r.Missing)
	if r.Complete && r.Executable > 0 {
		value := 100 * float64(r.Covered) / float64(r.Executable)
		r.Percent = &value
	}
	return r, nil
}
