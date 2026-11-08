package unit_test

import (
	"fmt"
	"path/filepath"
	"strings"
	"testing"

	rc "windows_setup/script/test/repo_coverage"
)

func cobertura(files string) []byte {
	return []byte(`<coverage line-rate="1" coverage-schema="1" coverage-metric="complete-executable-lines-v1"><packages><package><classes>` + files + `</classes></package></packages></coverage>`)
}

func TestRepoCoverageUnionAndCompleteScope(t *testing.T) {
	root := t.TempDir()
	one, err := rc.ParseCobertura(cobertura(`<class filename="core/setup.ps1"><lines><line number="2" hits="1"/><line number="7" hits="0"/></lines></class><class filename="core/types.ps1"><lines/></class>`), root)
	if err != nil {
		t.Fatal(err)
	}
	two, err := rc.ParseCobertura(cobertura(`<class filename="core\setup.ps1"><lines><line number="2" hits="0"/><line number="7" hits="3"/></lines></class><class filename="script/check.go"><lines><line number="3" hits="0"/></lines></class>`), root)
	if err != nil {
		t.Fatal(err)
	}
	scope := []rc.Source{{Path: "core/setup.ps1", Language: "powershell"}, {Path: "core/types.ps1", Language: "powershell"}, {Path: "script/check.go", Language: "go"}}
	result, err := rc.Merge(scope, one, two)
	if err != nil {
		t.Fatal(err)
	}
	if !result.Complete || result.Covered != 2 || result.Executable != 3 || result.Percent == nil || *result.Percent < 66.66 || *result.Percent > 66.67 {
		t.Fatalf("bad actual-count union: %+v", result)
	}
	if result.Languages["powershell"].Covered != 2 || result.Languages["powershell"].Executable != 2 || result.Languages["go"].Covered != 0 {
		t.Fatalf("bad language detail: %+v", result.Languages)
	}
	missing, err := rc.Merge(append(scope, rc.Source{Path: "modules/not_run.ps1", Language: "powershell"}), one, two)
	if err != nil {
		t.Fatal(err)
	}
	if missing.Complete || missing.Percent != nil || len(missing.Missing) != 1 || missing.Missing[0] != "modules/not_run.ps1" {
		t.Fatalf("missing source became whole repo percentage: %+v", missing)
	}
}

func TestRepoCoberturaStrictEvidence(t *testing.T) {
	root := t.TempDir()
	for _, tc := range []struct{ name, xml string }{
		{"malformed", `<coverage>`},
		{"wrong_root", `<anything/>`},
		{"no_sources", `<coverage><packages/></coverage>`},
		{"missing_line", string(cobertura(`<class filename="x.go"><lines><line hits="1"/></lines></class>`))},
		{"zero_line", string(cobertura(`<class filename="x.go"><lines><line number="0" hits="1"/></lines></class>`))},
		{"negative_hit", string(cobertura(`<class filename="x.go"><lines><line number="1" hits="-1"/></lines></class>`))},
		{"missing_hit", string(cobertura(`<class filename="x.go"><lines><line number="1"/></lines></class>`))},
		{"bad_hit", string(cobertura(`<class filename="x.go"><lines><line number="1" hits="abc"/></lines></class>`))},
		{"escape", string(cobertura(`<class filename="../x.go"><lines/></class>`))},
		{"blank_path", string(cobertura(`<class filename=""><lines/></class>`))},
		{"foreign_drive", string(cobertura(`<class filename="Z:\outside\x.go"><lines/></class>`))},
		{"outside_source", `<coverage><sources><source>../other</source></sources><packages><package><classes><class filename="x.go"><lines/></class></classes></package></packages></coverage>`},
		{"ambiguous_source", `<coverage><sources><source>core</source><source>modules</source></sources><packages><package><classes><class filename="x.go"><lines/></class></classes></package></packages></coverage>`},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if _, err := rc.ParseCobertura([]byte(tc.xml), root); err == nil {
				t.Fatal("accepted invalid evidence")
			}
		})
	}
	abs := filepath.ToSlash(filepath.Join(root, "core", "x.go"))
	valid := fmt.Sprintf(`<coverage><sources><source>%s</source></sources><packages><package><classes><class filename="core/x.go"><lines><line number="4" hits="1"/></lines></class><class filename="%s"><lines><line number="4" hits="0"/></lines></class></classes></package></packages></coverage>`, filepath.ToSlash(root), abs)
	report, err := rc.ParseCobertura([]byte(valid), root)
	if err != nil || len(report.Files) != 1 || !report.Files["core/x.go"][4] {
		t.Fatalf("canonical duplicate union failed: %+v %v", report, err)
	}
}

func TestRepoCoverageRejectsUntrustworthyInventory(t *testing.T) {
	report := rc.Report{SchemaVersion: rc.SchemaVersion, Metric: rc.Metric, Files: map[string]map[int]bool{"x.go": {1: true}}}
	for _, scope := range [][]rc.Source{nil, {{Path: "../x.go", Language: "go"}}, {{Path: "x.go", Language: ""}}, {{Path: "x.go", Language: "go"}, {Path: "x.go", Language: "powershell"}}} {
		if _, err := rc.Merge(scope, report); err == nil {
			t.Fatalf("accepted bad scope: %+v", scope)
		}
	}
	if _, err := rc.Merge([]rc.Source{{Path: "different.go", Language: "go"}}, report); err == nil {
		t.Fatal("out-of-scope report accepted")
	}
	if _, err := rc.Merge([]rc.Source{{Path: "x.go", Language: "go"}}, rc.Report{SchemaVersion: rc.SchemaVersion, Metric: rc.Metric, Files: map[string]map[int]bool{"x.go": {0: true}}}); err == nil {
		t.Fatal("invalid direct line evidence accepted")
	}
	result, err := rc.Merge([]rc.Source{{Path: "types.go", Language: "go"}}, rc.Report{SchemaVersion: rc.SchemaVersion, Metric: rc.Metric, Files: map[string]map[int]bool{"types.go": {}}})
	if err != nil || !result.Complete || result.Percent != nil || result.Executable != 0 {
		t.Fatalf("empty executable scope must not manufacture 100%%: %+v %v", result, err)
	}
	if _, err := rc.ParseCobertura([]byte(strings.Repeat("x", 20)), t.TempDir()); err == nil {
		t.Fatal("plain text accepted")
	}
}
