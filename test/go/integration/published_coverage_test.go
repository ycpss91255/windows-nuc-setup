package integration_test

import (
	"encoding/json"
	"strings"
	"testing"
	a "windows_setup/script/test/acceptance"
	c "windows_setup/script/test/repo_coverage"
)

func TestPublishedOverallCoverageRequiresExactEighty(t *testing.T) {
	for _, covered := range []int{4, 3} {
		lines := map[int]bool{}
		for line := 1; line <= 5; line++ {
			lines[line] = line <= covered
		}
		inv := c.Inventory{Sources: []c.Source{{Path: "core/example.ps1", Language: "powershell", SHA256: strings.Repeat("a", 64), ExpectedLines: []int{1, 2, 3, 4, 5}}}}
		id := c.Identity{Commit: strings.Repeat("b", 40), RunUrl: "https://github.com/example/repo/actions/runs/1", MeasuredAt: "2026-11-08T00:00:00Z", SourceState: "Clean"}
		files, err := c.CreateEvidence(inv, []c.Report{{SchemaVersion: 1, Metric: c.Metric, Files: map[string]map[int]bool{"core/example.ps1": lines}}}, id)
		if err != nil {
			t.Fatal(err)
		}
		summary, _ := json.Marshal(map[string]json.RawMessage{"RepoCoverage": files.Summary})
		m := map[string][]byte{"repo_coverage.json": files.Summary, "coverage_inventory.json": files.Inventory, "coverage.xml": files.XML}
		_, err = a.ValidateRepoCoverageReport(reader(m), summary, id.Commit, id.RunUrl, true)
		if (err == nil) != (covered == 4) {
			t.Fatalf("published %d/5 threshold decision: %v", covered, err)
		}
	}
}
