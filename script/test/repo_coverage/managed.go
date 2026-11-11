package repo_coverage

import (
	"encoding/xml"
	"fmt"
	"regexp"
	"sort"
	"strings"
	"unicode/utf16"
)

type managedRange struct {
	SourceID    string `xml:"source_id,attr"`
	StartLine   int    `xml:"start_line,attr"`
	EndLine     int    `xml:"end_line,attr"`
	StartColumn int    `xml:"start_column,attr"`
	EndColumn   int    `xml:"end_column,attr"`
	Covered     string `xml:"covered,attr"`
}
type managedFunction struct {
	Token  string         `xml:"token,attr"`
	Name   string         `xml:"name,attr"`
	Type   string         `xml:"type_name,attr"`
	Ranges []managedRange `xml:"ranges>range"`
}
type managedSource struct {
	ID        string `xml:"id,attr"`
	Path      string `xml:"path,attr"`
	Algorithm string `xml:"checksum_type,attr"`
	SHA256    string `xml:"checksum,attr"`
}
type managedModule struct {
	ID        string            `xml:"id,attr"`
	Functions []managedFunction `xml:"functions>function"`
	Sources   []managedSource   `xml:"source_files>source_file"`
}
type managedXML struct {
	XMLName xml.Name        `xml:"results"`
	Modules []managedModule `xml:"modules>module"`
}

// ParseManagedCoverage consumes one Microsoft native coverage export. It never
// unions partial XML statuses: callers must merge native binaries first.
func ParseManagedCoverage(data []byte, root string, originals map[string][]byte) (Report, []Catalog, error) {
	r, c, _, e := parseManaged(data, root, originals)
	return r, c, e
}

func parseManaged(data []byte, root string, originals map[string][]byte) (Report, []Catalog, map[string]string, error) {
	result := Report{SchemaVersion: 1, Metric: Metric, Files: map[string]map[int]bool{}}
	catalogs := []Catalog{}
	roster := map[string]string{}
	fail := func(message string) (Report, []Catalog, map[string]string, error) {
		return result, nil, nil, fmt.Errorf("managed coverage: %s", message)
	}
	var document managedXML
	if err := xml.Unmarshal(data, &document); err != nil {
		return result, nil, nil, err
	}
	if len(document.Modules) == 0 || len(originals) == 0 {
		return fail("empty source or module inventory")
	}
	modules := map[string]bool{}
	seen := map[string]bool{}
	for _, module := range document.Modules {
		if !regexp.MustCompile(`^[A-Fa-f0-9]{40}$`).MatchString(module.ID) || modules[module.ID] || len(module.Sources) == 0 || len(module.Functions) == 0 {
			return fail("invalid or duplicate module")
		}
		modules[module.ID] = true
		sourceIDs := map[string]string{}
		for _, source := range module.Sources {
			name, err := sourcePath(root, source.Path, nil)
			if err != nil {
				return result, nil, nil, err
			}
			original, ok := originals[name]
			if !ok || source.ID == "" || sourceIDs[source.ID] != "" || seen[name] || source.Algorithm != "SHA256" || !strings.EqualFold(source.SHA256, digest(original)) {
				return fail("source roster or PDB checksum differs")
			}
			sourceIDs[source.ID] = name
			seen[name] = true
			result.Files[name] = map[int]bool{}
		}
		functions := map[string]bool{}
		for _, function := range module.Functions {
			if !regexp.MustCompile(`^0x[0-9a-fA-F]+$`).MatchString(function.Token) || function.Name == "" || function.Type == "" || functions[function.Token] || len(function.Ranges) == 0 {
				return fail("missing or duplicate managed function")
			}
			functions[function.Token] = true
			for _, point := range function.Ranges {
				name, ok := sourceIDs[point.SourceID]
				if !ok {
					return fail("unknown source counter")
				}
				lines := strings.Split(string(originals[name]), "\n")
				valid := func(line, column int) bool {
					return line > 0 && line <= len(lines) && column > 0 && column <= len(utf16.Encode([]rune(strings.TrimSuffix(lines[line-1], "\r"))))+1
				}
				if !valid(point.StartLine, point.StartColumn) || !valid(point.EndLine, point.EndColumn) || point.EndLine < point.StartLine || point.EndLine == point.StartLine && point.EndColumn <= point.StartColumn {
					return fail("range outside actual source")
				}
				if point.Covered != "yes" && point.Covered != "no" && point.Covered != "partial" {
					return fail("unknown native coverage status")
				}
				key := fmt.Sprintf("%s|%s|%s|%s|%s|%d:%d:%d:%d", module.ID, function.Token, function.Type, function.Name, name, point.StartLine, point.StartColumn, point.EndLine, point.EndColumn)
				if _, exists := roster[key]; exists {
					return fail("duplicate native counter")
				}
				roster[key] = point.Covered
				old, exists := result.Files[name][point.StartLine]
				result.Files[name][point.StartLine] = point.Covered == "yes" && (!exists || old)
			}
		}
	}
	if len(seen) != len(originals) {
		return fail("owned managed source omitted")
	}
	for name, points := range result.Files {
		if len(points) == 0 {
			return fail("source lacks executable catalog")
		}
		lines := []int{}
		for line := range points {
			lines = append(lines, line)
		}
		sort.Ints(lines)
		catalogs = append(catalogs, Catalog{Path: name, SHA256: digest(originals[name]), Lines: lines})
	}
	sort.Slice(catalogs, func(i, j int) bool { return catalogs[i].Path < catalogs[j].Path })
	return result, catalogs, roster, nil
}
