package unit_test

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	rc "windows_setup/script/test/repo_coverage"
)

func cobertura(files string) []byte {
	return []byte(`<coverage line-rate="1" coverage-schema="1" coverage-metric="complete-executable-lines-v1"><packages><package><classes>` + files + `</classes></package></packages></coverage>`)
}

func TestRepoCoverageInventoryDoesNotHideExecutableSources(t *testing.T) {
	root := t.TempDir()
	files := map[string]string{
		"core/main.ps1":                         "Write-Output 'ok'",
		"script/main.go":                        "package main\nfunc main(){}",
		"entry.cmd":                             "@echo off\npowershell.exe -File core/main.ps1",
		"native/logic.cs":                       "public class Native { public static int Run(){return 1;} }",
		".github/helper.ps1":                    "Write-Output 'owned code'",
		"test/example.ps1":                      "test fixture",
		"vendor/pkg/main.go":                    "third-party",
		"modules/debloat/win11debloat/main.ps1": "third-party",
		"doc/example.ps1":                       "documentation example",
		"readme.md":                             "information",
		"Dockerfile":                            "FROM image\nRUN powershell -File script/build.ps1",
		".github/workflows/check.yml":           "jobs:\n  test:\n    steps:\n      - run: powershell -File script/check.ps1\n",
		"config.json":                           "{}",
	}
	for name, contents := range files {
		p := filepath.Join(root, filepath.FromSlash(name))
		if err := os.MkdirAll(filepath.Dir(p), 0700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(p, []byte(contents), 0600); err != nil {
			t.Fatal(err)
		}
	}
	inv, err := rc.ScanInventory(root)
	if err != nil {
		t.Fatal(err)
	}
	if len(inv.Sources) != 5 || len(inv.Blockers) != 0 {
		t.Fatalf("unexpected scope: %+v", inv)
	}
	for _, excluded := range inv.Excluded {
		if excluded.Reason == "" {
			t.Fatal("silent exclusion")
		}
	}
	if err := os.WriteFile(filepath.Join(root, "new.py"), []byte("print('new language')"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, ".github/workflows/check.yml"), []byte("jobs:\n  test:\n    steps:\n      - run: |\n          if ($value -lt 80) { throw 'coverage' }\n"), 0600); err != nil {
		t.Fatal(err)
	}
	inv, err = rc.ScanInventory(root)
	if err != nil || len(inv.Blockers) != 2 {
		t.Fatalf("unknown language or workflow logic hidden: %+v %v", inv, err)
	}
	result, err := inv.Merge()
	if err != nil || result.Complete || result.Percent != nil || len(result.Blockers) != 2 {
		t.Fatalf("incomplete inventory became measured: %+v %v", result, err)
	}
}

func TestRepoCoverageEmbeddedCodeIsNotPowerShellCoverage(t *testing.T) {
	root := t.TempDir()
	files := map[string]string{
		"extern.ps1":    `Add-Type -TypeDefinition 'using System.Runtime.InteropServices; public class Native { [DllImport("a.dll")] public static extern int Call(); }'`,
		"managed.ps1":   "Add-Type -TypeDefinition @\"\npublic class Native { public static int Call() { return 1; } }\n\"@",
		"generated.ps1": `[IO.File]::WriteAllText('compare.js','function run(){ return 1; }')`,
		"assembly.ps1":  "Add-Type -AssemblyName System.Drawing",
	}
	for name, contents := range files {
		if err := os.WriteFile(filepath.Join(root, name), []byte(contents), 0600); err != nil {
			t.Fatal(err)
		}
	}
	inv, err := rc.ScanInventory(root)
	if err != nil || len(inv.Sources) != 4 || len(inv.Blockers) != 2 {
		t.Fatalf("embedded code scope wrong: %+v %v", inv, err)
	}
	found := false
	for _, e := range inv.Excluded {
		if e.Path == "extern.ps1#csharp" && strings.Contains(e.Reason, "declaration") {
			found = true
		}
	}
	if !found {
		t.Fatal("pure extern declaration must be explained, not counted as managed executable lines")
	}
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
	scope := []rc.Source{{Path: "core/setup.ps1", Language: "powershell", ExpectedLines: []int{2, 7}}, {Path: "core/types.ps1", Language: "powershell", ExpectedLines: []int{}}, {Path: "script/check.go", Language: "go", ExpectedLines: []int{3}}}
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
	result, err := rc.Merge([]rc.Source{{Path: "types.go", Language: "go", ExpectedLines: []int{}}}, rc.Report{SchemaVersion: rc.SchemaVersion, Metric: rc.Metric, Files: map[string]map[int]bool{"types.go": {}}})
	if err != nil || !result.Complete || result.Percent != nil || result.Executable != 0 {
		t.Fatalf("empty executable scope must not manufacture 100%%: %+v %v", result, err)
	}
	if _, err := rc.ParseCobertura([]byte(strings.Repeat("x", 20)), t.TempDir()); err == nil {
		t.Fatal("plain text accepted")
	}
}

func TestRepoCoverageCannotHideExecutableCatalog(t *testing.T) {
	scope := []rc.Source{{Path: "a.go", Language: "go", SHA256: strings.Repeat("a", 64), ExpectedLines: []int{2}}, {Path: "b.ps1", Language: "powershell", SHA256: strings.Repeat("b", 64), ExpectedLines: []int{3, 4}}}
	report := rc.Report{SchemaVersion: rc.SchemaVersion, Metric: rc.Metric, Files: map[string]map[int]bool{"a.go": {2: true}, "b.ps1": {}}}
	if _, err := rc.Merge(scope, report); err == nil {
		t.Fatal("empty class concealed known executable source")
	}
	report.Files["b.ps1"] = map[int]bool{3: true}
	if _, err := rc.Merge(scope, report); err == nil {
		t.Fatal("part of denominator omitted")
	}
	report.Files["b.ps1"] = map[int]bool{3: true, 4: false, 9: true}
	if _, err := rc.Merge(scope, report); err == nil {
		t.Fatal("foreign line inflated numerator")
	}
	report.Files["b.ps1"] = map[int]bool{3: true, 4: false}
	r, err := rc.Merge(scope, report)
	if err != nil || !r.Complete || r.Executable != 3 || r.Covered != 2 {
		t.Fatalf("valid exact catalog refused: %+v %v", r, err)
	}
	scope[1].ExpectedLines = nil
	r, err = rc.Merge(scope, report)
	if err != nil || r.Complete || r.Percent != nil {
		t.Fatalf("unanalyzed source became complete: %+v %v", r, err)
	}
	inv := rc.Inventory{Sources: scope}
	if _, err := rc.BindCatalogs(inv, []rc.Catalog{{Path: "b.ps1", SHA256: strings.Repeat("c", 64), Lines: []int{3, 4}}}); err == nil {
		t.Fatal("stale catalog hash accepted")
	}
	bound, err := rc.BindCatalogs(inv, []rc.Catalog{{Path: "b.ps1", SHA256: strings.Repeat("b", 64), Lines: []int{3, 4}}})
	if err != nil || len(bound.Sources[1].ExpectedLines) != 2 {
		t.Fatalf("catalog could not bind: %+v %v", bound, err)
	}
}
