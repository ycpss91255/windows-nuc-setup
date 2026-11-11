package repo_coverage

import (
	"encoding/xml"
	"sort"
)

func normalizedXML(inventory Inventory, reports []Report) ([]byte, error) {
	// Merge validates the scope, catalog, metric and each input line first.
	if _, err := inventory.Merge(reports...); err != nil {
		return nil, err
	}
	files := map[string]map[int]bool{}
	for _, report := range reports {
		for name, lines := range report.Files {
			canonical, _ := RelativePath(name)
			if files[canonical] == nil {
				files[canonical] = map[int]bool{}
			}
			for line, hit := range lines {
				files[canonical][line] = files[canonical][line] || hit
			}
		}
	}
	type line struct {
		Number int `xml:"number,attr"`
		Hits   int `xml:"hits,attr"`
	}
	type class struct {
		Filename string `xml:"filename,attr"`
		Lines    []line `xml:"lines>line"`
	}
	doc := struct {
		XMLName xml.Name `xml:"coverage"`
		Schema  int      `xml:"coverage-schema,attr"`
		Metric  string   `xml:"coverage-metric,attr"`
		Classes []class  `xml:"packages>package>classes>class"`
	}{Schema: SchemaVersion, Metric: Metric}
	names := []string{}
	for name := range files {
		names = append(names, name)
	}
	sort.Strings(names)
	for _, name := range names {
		c := class{Filename: name, Lines: []line{}}
		numbers := []int{}
		for n := range files[name] {
			numbers = append(numbers, n)
		}
		sort.Ints(numbers)
		for _, n := range numbers {
			hit := 0
			if files[name][n] {
				hit = 1
			}
			c.Lines = append(c.Lines, line{n, hit})
		}
		doc.Classes = append(doc.Classes, c)
	}
	data, err := xml.MarshalIndent(doc, "", "  ")
	return append([]byte(xml.Header), data...), err
}
