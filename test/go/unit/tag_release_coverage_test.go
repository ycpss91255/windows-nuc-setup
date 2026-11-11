package unit_test

import (
	"encoding/json"
	"fmt"
	"strings"
	"testing"

	a "windows_setup/script/test/acceptance"
)

// This is a small explicit synthetic contract fixture, never measured CI data.
func tagReleaseGoFixture(t *testing.T, ref string) (map[string][]byte, []string, string, string) {
	t.Helper()
	sha, run := strings.Repeat("a", 40), "https://github.com/example/repo/actions/runs/123"
	files := []string{"windows_setup/script/test/example.go"}
	c, profile, err := a.CreateCoverageEvidence([][]byte{[]byte("mode: set\n" + files[0] + ":1.1,2.1 8 1\n" + files[0] + ":3.1,4.1 2 0\n")}, files,
		a.CoverageProvenance{Commit: sha, RunUrl: run, MeasuredAt: "2026-11-09T00:00:01Z", SourceState: "Clean", GoVersion: "go1.27.3", Environment: "Synthetic Tag gate contract fixture"})
	if err != nil {
		t.Fatal(err)
	}
	passed := true
	report := map[string]any{
		"SchemaVersion": 2, "RefType": ref, "RefName": "v1.2.3", "Version": "v1.2.3", "Commit": sha, "RunUrl": run,
		"SourceState": "Clean", "RequestedLayer": "All", "Success": true, "Coverage": "NotMeasured", "MeasuredAt": "2026-11-09T00:00:00Z",
		"Checks": []a.Check{{Name: "synthetic_unit", Layer: "Unit", Executed: true, Passed: &passed, Status: "Passed", Assertions: []a.Assertion{{Name: "synthetic contract", Passed: &passed}}}},
		"Totals": a.Totals{SuitesExecuted: 1, AssertionsExecuted: 1, AssertionsPassed: 1}, "GoCoverage": c,
	}
	if ref == "Branch" {
		report["RefName"] = "main"
	}
	summary, _ := json.Marshal(report)
	metadata, _ := json.Marshal(c)
	label, value := "go coverage "+strings.ToLower(ref), "80.0%"
	return map[string][]byte{
		"summary.json": summary, "go_coverage.json": metadata, "go_coverage.out": profile,
		"go_coverage.svg": []byte(fmt.Sprintf(`<svg xmlns="http://www.w3.org/2000/svg" height="20" width="%d"><rect width="%d" fill="#555"/><rect width="%d" fill="#4c1"/><g font-size="11"><text>%s</text><text>%s</text></g></svg>`, (len(label)+len(value))*7+24, len(label)*7+12, len(value)*7+12, label, value)),
		"index.html":      []byte(`<details><summary>分項量測明細</summary><p>Go 程式敘述覆蓋率 80.0% 8/10 statements 全部自有 Go 工具（含 CLI） 不含 PowerShell 或第三方程式 不等於整體覆蓋率</p><a href="go_coverage.json">JSON</a><a href="go_coverage.out">profile</a></details>`),
		"summary.md":      []byte("Go 程式敘述覆蓋率（分項）：80.0%；8/10 statements；全部自有 Go 工具含 CLI；不含 PowerShell 或第三方程式；不等於整體覆蓋率"),
	}, files, sha, run
}

func TestFreshTagReleaseGoCoverageGate(t *testing.T) {
	for _, ref := range []string{"Branch", "Release"} {
		t.Run(ref, func(t *testing.T) {
			data, files, sha, run := tagReleaseGoFixture(t, ref)
			if err := a.ValidateGoCoverageReport(func(n string) ([]byte, error) { return data[n], nil }, files, sha, run, true); err != nil {
				t.Fatalf("current clean schema2 %s Go evidence must pass before whole-repo aggregation: %v", ref, err)
			}
		})
	}
}

func TestTagReleaseGoCoverageRejectsInvalidIdentity(t *testing.T) {
	mutations := map[string]func(map[string]any){
		"historical_schema1":     func(r map[string]any) { r["SchemaVersion"] = 1 },
		"unsupported_schema":     func(r map[string]any) { r["SchemaVersion"] = 3 },
		"unknown_ref_type":       func(r map[string]any) { r["RefType"] = "Tag" },
		"wrong_tag":              func(r map[string]any) { r["RefName"] = "main" },
		"wrong_version":          func(r map[string]any) { r["Version"] = "v1.2.4" },
		"noncanonical_tag":       func(r map[string]any) { r["Version"] = "v01.2.3"; r["RefName"] = "v01.2.3" },
		"dirty":                  func(r map[string]any) { r["SourceState"] = "Dirty" },
		"partial_tests":          func(r map[string]any) { r["RequestedLayer"] = "Unit" },
		"failed_tests":           func(r map[string]any) { r["Success"] = false },
		"unexecuted_tests":       func(r map[string]any) { r["Totals"].(map[string]any)["UnexecutedSuites"] = 1 },
		"foreign_summary_commit": func(r map[string]any) { r["Commit"] = strings.Repeat("b", 40) },
		"foreign_summary_run":    func(r map[string]any) { r["RunUrl"] = "https://github.com/example/repo/actions/runs/124" },
		"missing_identity":       func(r map[string]any) { delete(r, "Checks") },
	}
	for name, mutate := range mutations {
		t.Run(name, func(t *testing.T) {
			data, files, sha, run := tagReleaseGoFixture(t, "Release")
			var r map[string]any
			if err := json.Unmarshal(data["summary.json"], &r); err != nil {
				t.Fatal(err)
			}
			mutate(r)
			data["summary.json"], _ = json.Marshal(r)
			if err := a.ValidateGoCoverageReport(func(n string) ([]byte, error) { return data[n], nil }, files, sha, run, true); err == nil {
				t.Fatal("invalid Release identity must not gain the fresh-schema2 exception")
			}
		})
	}
}
