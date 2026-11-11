package repo_coverage

import (
	"fmt"
	"regexp"
	"sort"
	"strings"
)

type Catalog struct {
	Path, SHA256 string
	Lines        []int
}

// BindCatalogs connects language-analyzer line inventories to the exact source
// bytes inventoried from the checkout. Nil and empty inventories are distinct.
func BindCatalogs(inventory Inventory, catalogs []Catalog) (Inventory, error) {
	out := inventory
	out.Sources = append([]Source(nil), inventory.Sources...)
	indices := map[string]int{}
	for i, source := range out.Sources {
		name, err := RelativePath(source.Path)
		if err != nil {
			return out, err
		}
		indices[strings.ToLower(name)] = i
	}
	seen := map[string]bool{}
	for _, catalog := range catalogs {
		name, err := RelativePath(catalog.Path)
		if err != nil {
			return out, err
		}
		key := strings.ToLower(name)
		i, ok := indices[key]
		if !ok || seen[key] {
			return out, fmt.Errorf("unknown or duplicate executable catalog: %s", name)
		}
		seen[key] = true
		if !regexp.MustCompile(`^[a-fA-F0-9]{64}$`).MatchString(catalog.SHA256) || !strings.EqualFold(out.Sources[i].SHA256, catalog.SHA256) {
			return out, fmt.Errorf("catalog source digest mismatch: %s", name)
		}
		if catalog.Lines == nil {
			return out, fmt.Errorf("catalog was not analyzed: %s", name)
		}
		lines := append([]int{}, catalog.Lines...)
		sort.Ints(lines)
		for n, line := range lines {
			if line <= 0 || n > 0 && line == lines[n-1] {
				return out, fmt.Errorf("invalid executable catalog line: %s", name)
			}
		}
		out.Sources[i].ExpectedLines = lines
	}
	return out, nil
}
