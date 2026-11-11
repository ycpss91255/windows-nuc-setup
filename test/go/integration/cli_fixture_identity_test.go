package integration_test

import (
	"encoding/json"
	"os"
	"reflect"
	"strings"
	"testing"
)

// identityFixture creates synthetic identity scenarios without changing the
// actual artifact or relabelling another checkout's counters as new evidence.
func identityFixture(t *testing.T, original map[string][]byte, commit, run string) map[string][]byte {
	t.Helper()
	m := copyFiles(original)
	before := decode(t, m)
	var raw map[string]json.RawMessage
	if err := json.Unmarshal(m["summary.json"], &raw); err != nil {
		t.Fatal(err)
	}
	put := func(key string, value any) { raw[key], _ = json.Marshal(value) }
	put("Commit", commit)
	put("RunUrl", run)
	put("Environment", "Synthetic CLI identity fixture, not real source evidence")
	if commit != before.Commit {
		delete(raw, "RepoCoverage")
		delete(raw, "GoCoverage")
		put("Coverage", "NotMeasured")
		for _, name := range []string{"repo_coverage.json", "coverage_inventory.json", "coverage.xml", "go_coverage.json", "go_coverage.out", "go_coverage.svg"} {
			delete(m, name)
		}
	} else {
		if run == "" {
			delete(raw, "GoCoverage")
			for _, name := range []string{"go_coverage.json", "go_coverage.out", "go_coverage.svg"} {
				delete(m, name)
			}
		}
		if before.RepoCoverage != nil {
			before.RepoCoverage.RunUrl = run
			b, err := json.Marshal(before.RepoCoverage)
			if err != nil {
				t.Fatal(err)
			}
			raw["RepoCoverage"] = b
			m["repo_coverage.json"] = append([]byte(nil), b...)
		}
		if data, ok := raw["GoCoverage"]; ok && string(data) != "null" {
			var coverage map[string]json.RawMessage
			if err := json.Unmarshal(data, &coverage); err != nil {
				t.Fatal(err)
			}
			coverage["RunUrl"], _ = json.Marshal(run)
			coverage["Environment"], _ = json.Marshal("Synthetic CLI identity fixture")
			b, err := json.Marshal(coverage)
			if err != nil {
				t.Fatal(err)
			}
			raw["GoCoverage"] = b
			m["go_coverage.json"] = append([]byte(nil), b...)
		}
	}
	m["summary.json"], _ = json.Marshal(raw)
	m["summary.md"] = []byte(strings.ReplaceAll(string(m["summary.md"]), before.Commit, commit))
	if before.RunUrl != "" {
		m["summary.md"] = []byte(strings.ReplaceAll(string(m["summary.md"]), before.RunUrl, run))
	}
	if commit != before.Commit {
		m["coverage.svg"] = badge(decode(t, m), "coverage")
	}
	return m
}

func TestCLIIdentityFixturePreservesOriginalCounters(t *testing.T) {
	original := files(t, os.Getenv("WINDOWS_SETUP_ARTIFACT_DIR"))
	snapshot := copyFiles(original)
	before := decode(t, original)
	local := identityFixture(t, original, before.Commit, "")
	after := decode(t, local)
	if after.Commit != before.Commit || after.RunUrl != "" || !strings.Contains(after.Environment, "Synthetic") {
		t.Fatal("local fixture identity not explicit")
	}
	if before.RepoCoverage != nil {
		if after.RepoCoverage == nil || after.RepoCoverage.RunUrl != "" || !reflect.DeepEqual(after.RepoCoverage.Result, before.RepoCoverage.Result) || after.RepoCoverage.InventorySHA256 != before.RepoCoverage.InventorySHA256 || after.RepoCoverage.NormalizedSHA256 != before.RepoCoverage.NormalizedSHA256 {
			t.Fatal("local fixture changed actual counters or retained the old run identity")
		}
	}
	for _, name := range []string{"coverage_inventory.json", "coverage.xml"} {
		if !reflect.DeepEqual(local[name], original[name]) {
			t.Fatalf("local identity changed raw source counters: %s", name)
		}
	}
	if !reflect.DeepEqual(original, snapshot) {
		t.Fatal("identity fixture changed the actual artifact")
	}
	foreign := identityFixture(t, original, strings.Repeat("d", 40), "https://github.com/example/fixture/actions/runs/1")
	report := decode(t, foreign)
	if report.RepoCoverage != nil || report.Coverage != "NotMeasured" {
		t.Fatal("new checkout retained old aggregate coverage")
	}
	for _, name := range []string{"repo_coverage.json", "coverage_inventory.json", "coverage.xml", "go_coverage.json", "go_coverage.out", "go_coverage.svg"} {
		if _, ok := foreign[name]; ok {
			t.Fatalf("new checkout retained an unrelated source sidecar: %s", name)
		}
	}
	if !reflect.DeepEqual(original, snapshot) {
		t.Fatal("foreign fixture changed the actual artifact")
	}
}

// An empty run is local and cannot retain Go evidence that requires a CI run.
// Exercise both source contexts even when ordinary PR input is only native-stage.
func TestLocalIdentityDropsCIGoEvidence(t *testing.T) {
	original := files(t, os.Getenv("WINDOWS_SETUP_ARTIFACT_DIR"))
	for _, ref := range []string{"Branch", "Release"} {
		for _, stage := range []string{"native-stage", "attached"} {
			t.Run(ref+"/"+stage, func(t *testing.T) {
				m := synthetic(t, original, true, ref)
				var raw map[string]json.RawMessage
				if err := json.Unmarshal(m["summary.json"], &raw); err != nil {
					t.Fatal(err)
				}
				if stage == "attached" {
					raw["GoCoverage"] = json.RawMessage(`{"RunUrl":"https://github.com/example/repo/actions/runs/1"}`)
					m["go_coverage.json"] = []byte(`{}`)
					m["go_coverage.out"] = []byte("profile")
					m["go_coverage.svg"] = []byte("badge")
				} else {
					delete(raw, "GoCoverage")
					for _, name := range []string{"go_coverage.json", "go_coverage.out", "go_coverage.svg"} {
						delete(m, name)
					}
				}
				m["summary.json"], _ = json.Marshal(raw)
				local := identityFixture(t, m, decode(t, m).Commit, "")
				var result map[string]json.RawMessage
				if err := json.Unmarshal(local["summary.json"], &result); err != nil {
					t.Fatal(err)
				}
				if _, ok := result["GoCoverage"]; ok {
					t.Fatal("local fixture retained CI Go evidence")
				}
				for _, name := range []string{"go_coverage.json", "go_coverage.out", "go_coverage.svg"} {
					if _, ok := local[name]; ok {
						t.Fatalf("local fixture retained CI sidecar: %s", name)
					}
				}
			})
		}
	}
}
