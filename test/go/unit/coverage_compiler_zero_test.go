package unit_test

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
	"testing"

	a "windows_setup/script/test/acceptance"
	rc "windows_setup/script/test/repo_coverage"
)

func TestCompilerZeroStatementBlocksRemainCanonical(t *testing.T) {
	root := t.TempDir()
	dir := filepath.Join(root, "script", "test", "fixture")
	if err := os.MkdirAll(dir, 0700); err != nil {
		t.Fatal(err)
	}
	files := map[string]string{
		filepath.Join(root, "go.mod"):         "module windows_setup\n\ngo 1.27.3\n",
		filepath.Join(dir, "fixture.go"):      "package fixture\nfunc Wait(ch <-chan struct{}) { select { case <-ch: } }\n",
		filepath.Join(dir, "fixture_test.go"): "package fixture\nimport \"testing\"\nfunc TestWait(t *testing.T) { ch:=make(chan struct{}); close(ch); Wait(ch) }\n",
	}
	for path, data := range files {
		if err := os.WriteFile(path, []byte(data), 0600); err != nil {
			t.Fatal(err)
		}
	}
	t.Setenv("GOTOOLCHAIN", "local")
	t.Setenv("GOPROXY", "off")
	t.Setenv("GOSUMDB", "off")
	t.Setenv("GOWORK", "off")
	t.Setenv("GOFLAGS", "-mod=mod")
	profilePath := filepath.Join(root, "coverage.out")
	goexe := filepath.Join(runtime.GOROOT(), "bin", "go")
	if runtime.GOOS == "windows" {
		goexe += ".exe"
	}
	cmd := exec.Command(goexe, "test", "-count=1", "-coverprofile="+profilePath, "./script/test/fixture")
	cmd.Dir = root
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("isolated compiler fixture failed: %v\n%s", err, out)
	}
	raw, err := os.ReadFile(profilePath)
	if err != nil {
		t.Fatal(err)
	}
	zero := regexp.MustCompile(`(?m)^windows_setup/script/test/fixture/fixture\.go:[0-9.]+,[0-9.]+ 0 [0-9]+$`).Find(raw)
	if zero == nil {
		t.Fatalf("compiler emitted no zero block: %s", raw)
	}
	scope := []string{"windows_setup/script/test/fixture/fixture.go"}
	provenance := a.CoverageProvenance{Commit: strings.Repeat("a", 40), RunUrl: "https://github.com/example/repo/actions/runs/123", MeasuredAt: "2026-01-01T00:00:00Z", SourceState: "Clean", GoVersion: runtime.Version(), Environment: "isolated fixture"}
	evidence, canonical, err := a.CreateCoverageEvidence([][]byte{raw, raw}, scope, provenance)
	if err != nil {
		t.Fatalf("legitimate compiler zero block rejected: %v", err)
	}
	if evidence.TotalStatements <= 0 || evidence.Covered != evidence.TotalStatements || !strings.Contains(string(canonical), string(zero)) {
		t.Fatalf("canonical profile lost block or totals: %+v", evidence)
	}
	data, err := json.Marshal(evidence)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = a.ValidateCoverageEvidence(data, canonical, scope, provenance.Commit, provenance.RunUrl); err != nil {
		t.Fatalf("consumer rejected canonical profile: %v", err)
	}
	source := []byte(files[filepath.Join(dir, "fixture.go")])
	lineReport, catalogs, err := rc.NormalizeGo([][]byte{canonical}, map[string][]byte{"script/test/fixture/fixture.go": source}, "windows_setup")
	if err != nil || len(catalogs) != 1 || len(catalogs[0].Lines) != 1 || !lineReport.Files["script/test/fixture/fixture.go"][2] {
		t.Fatalf("zero block changed executable-line mapping: %v %+v", err, catalogs)
	}
	if runtime.GOOS == "windows" {
		helper, err := filepath.Abs("../../../script/test/go_coverage.ps1")
		if err != nil {
			t.Fatal(err)
		}
		if err = os.WriteFile(filepath.Join(root, "go_coverage.out"), canonical, 0600); err != nil {
			t.Fatal(err)
		}
		if err = os.WriteFile(filepath.Join(root, "coverage.json"), data, 0600); err != nil {
			t.Fatal(err)
		}
		script := `$ErrorActionPreference='Stop'; $env:PSModulePath=(Join-Path $PSHOME 'Modules')+';'+$env:PSModulePath; . $env:FIXTURE_GO_HELPER; $c=Get-Content -Raw -Encoding UTF8 -LiteralPath $env:FIXTURE_GO_JSON|ConvertFrom-Json; Assert-GoCoverageProfile -Coverage $c -Directory $env:FIXTURE_GO_DIR; Write-Host '@@ASSERT@@{"Name":"compiler profile accepted by PowerShell","Passed":true}'`
		ps := exec.Command("powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", script)
		ps.Env = append(os.Environ(), "FIXTURE_GO_HELPER="+helper, "FIXTURE_GO_JSON="+filepath.Join(root, "coverage.json"), "FIXTURE_GO_DIR="+root)
		if output, err := ps.CombinedOutput(); err != nil {
			t.Fatalf("PowerShell consumer rejected compiler profile: %v\n%s", err, output)
		}
	}
	zeroOnly := []byte("mode: set\n" + string(zero) + "\n")
	if _, err = a.EvaluateCoverage([][]byte{zeroOnly}, scope); err == nil {
		t.Fatal("zero total accepted")
	}
}

func TestZeroBlocksDoNotRelaxCoverageConstraints(t *testing.T) {
	file := "windows_setup/script/test/fixture/fixture.go"
	valid := "mode: set\n" + file + ":1.1,2.1 4 1\n" + file + ":3.1,4.1 1 0\n" + file + ":5.1,5.1 0 1\n"
	for name, profiles := range map[string][][]byte{
		"empty cli":           {[]byte(valid), []byte("mode: set\n")},
		"negative statements": {[]byte(strings.Replace(valid, " 0 1", " -1 1", 1))},
		"negative count":      {[]byte(strings.Replace(valid, " 0 1", " 0 -1", 1))},
		"new cli block":       {[]byte(valid), []byte("mode: set\n" + file + ":6.1,6.1 0 1\n")},
		"contradictory cli":   {[]byte(valid), []byte("mode: set\n" + file + ":5.1,5.1 1 1\n")},
	} {
		if _, err := a.EvaluateCoverage(profiles, []string{file}); err == nil {
			t.Errorf("%s accepted", name)
		}
	}
	if _, err := a.EvaluateCoverage([][]byte{[]byte(valid)}, []string{file, "windows_setup/script/test/missing/main.go"}); err == nil {
		t.Fatal("omitted owned source accepted")
	}
}

func TestZeroOnlyBlocksDoNotSatisfyOwnedSourceCoverage(t *testing.T) {
	covered := "windows_setup/script/test/a/main.go"
	zeroOnly := "windows_setup/script/test/missing/main.go"
	profile := "mode: set\n" + covered + ":1.1,2.1 4 1\n" + covered + ":3.1,4.1 1 0\n" + zeroOnly + ":1.1,1.1 0 1\n"
	if _, err := a.EvaluateCoverage([][]byte{[]byte(profile)}, []string{covered, zeroOnly}); err == nil {
		t.Fatal("zero-only block counted as owned source evidence")
	}
}

func TestCompilerSelectCommunicationsDoNotHideCaseBodies(t *testing.T) {
	root := t.TempDir()
	dir := filepath.Join(root, "script", "test", "select_fixture")
	if err := os.MkdirAll(dir, 0700); err != nil {
		t.Fatal(err)
	}
	source := "package selectfixture\nfunc Transfer(in <-chan int, out chan<- int) {\n select {\n case v := <-in:\n  out <- v\n default:\n  _ = in\n }\n}\n"
	files := map[string]string{filepath.Join(root, "go.mod"): "module windows_setup\n\ngo 1.27.3\n", filepath.Join(dir, "select.go"): source, filepath.Join(dir, "select_test.go"): "package selectfixture\nimport \"testing\"\nfunc TestTransfer(t *testing.T) { in:=make(chan int,1);out:=make(chan int,1);in<-1;Transfer(in,out) }\n"}
	for path, data := range files {
		if err := os.WriteFile(path, []byte(data), 0600); err != nil {
			t.Fatal(err)
		}
	}
	t.Setenv("GOTOOLCHAIN", "local")
	t.Setenv("GOPROXY", "off")
	t.Setenv("GOSUMDB", "off")
	t.Setenv("GOWORK", "off")
	t.Setenv("GOFLAGS", "-mod=mod")
	profile := filepath.Join(root, "coverage.out")
	goexe := filepath.Join(runtime.GOROOT(), "bin", "go")
	if runtime.GOOS == "windows" {
		goexe += ".exe"
	}
	cmd := exec.Command(goexe, "test", "-count=1", "-coverprofile="+profile, "./script/test/select_fixture")
	cmd.Dir = root
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("fixture compilation: %v\n%s", err, out)
	}
	raw, err := os.ReadFile(profile)
	if err != nil {
		t.Fatal(err)
	}
	path := "script/test/select_fixture/select.go"
	report, _, err := rc.NormalizeGo([][]byte{raw}, map[string][]byte{path: []byte(source)}, "windows_setup")
	if err != nil {
		t.Fatal(err)
	}
	lines := report.Files[path]
	if len(lines) != 4 || !lines[3] || !lines[4] || !lines[5] || lines[7] {
		t.Fatalf("unexpected line coverage: %+v", lines)
	}
	if _, ok := lines[7]; !ok {
		t.Fatal("uncovered default body missing")
	}
}

func TestCompilerSelectClauseEntriesStayInLineCoverage(t *testing.T) {
	source := "package branchfixture\nfunc Choose(first, second <-chan int) int {\n select {\n case <-first:\n  return 1\n case <-second:\n default:\n  return 0\n }\n return 2\n}\n"
	for _, tc := range []struct {
		name, setup                           string
		first, second, body, otherwise, after bool
	}{
		{"first selected", "a:=make(chan int,1);a<-1;Choose(a,nil)", true, false, true, false, false},
		{"empty second selected", "b:=make(chan int,1);b<-1;Choose(nil,b)", false, true, false, false, true},
		{"default selected", "Choose(nil,nil)", false, false, false, true, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			root := t.TempDir()
			dir := filepath.Join(root, "script", "test", "branch_fixture")
			if err := os.MkdirAll(dir, 0700); err != nil {
				t.Fatal(err)
			}
			inputs := map[string]string{filepath.Join(root, "go.mod"): "module windows_setup\n\ngo 1.27.3\n", filepath.Join(dir, "branch.go"): source, filepath.Join(dir, "branch_test.go"): "package branchfixture\nimport \"testing\"\nfunc TestChoose(t *testing.T) { " + tc.setup + " }\n"}
			for p, s := range inputs {
				if err := os.WriteFile(p, []byte(s), 0600); err != nil {
					t.Fatal(err)
				}
			}
			t.Setenv("GOTOOLCHAIN", "local")
			t.Setenv("GOPROXY", "off")
			t.Setenv("GOSUMDB", "off")
			t.Setenv("GOWORK", "off")
			t.Setenv("GOFLAGS", "-mod=mod")
			out := filepath.Join(root, "coverage.out")
			goexe := filepath.Join(runtime.GOROOT(), "bin", "go")
			if runtime.GOOS == "windows" {
				goexe += ".exe"
			}
			cmd := exec.Command(goexe, "test", "-count=1", "-coverprofile="+out, "./script/test/branch_fixture")
			cmd.Dir = root
			if b, err := cmd.CombinedOutput(); err != nil {
				t.Fatalf("compiler fixture: %v\n%s", err, b)
			}
			raw, err := os.ReadFile(out)
			if err != nil {
				t.Fatal(err)
			}
			path := "script/test/branch_fixture/branch.go"
			sources := map[string][]byte{path: []byte(source)}
			report, _, err := rc.NormalizeGo([][]byte{raw}, sources, "windows_setup")
			if err != nil {
				t.Fatalf("real compiler profile: %v\n%s", err, raw)
			}
			lines := report.Files[path]
			for line, want := range map[int]bool{3: true, 4: tc.first, 5: tc.body, 6: tc.second, 8: tc.otherwise, 10: tc.after} {
				got, ok := lines[line]
				if !ok || got != want {
					t.Errorf("line %d got=%t present=%t want=%t", line, got, ok, want)
				}
			}
			pattern := regexp.MustCompile(`(?m)^windows_setup/script/test/branch_fixture/branch\.go:6\.[0-9]+,6\.[0-9]+ 0 [0-9]+\n`)
			if !pattern.Match(raw) {
				t.Fatalf("missing real empty-case counter: %s", raw)
			}
			without := pattern.ReplaceAll(raw, nil)
			if _, _, err = rc.NormalizeGo([][]byte{without}, sources, "windows_setup"); err == nil {
				t.Fatal("missing clause entry counter accepted")
			}
		})
	}
}

func TestCompilerSameLineSelectUsesConservativeUnion(t *testing.T) {
	root := t.TempDir()
	dir := filepath.Join(root, "script", "test", "same_fixture")
	if err := os.MkdirAll(dir, 0700); err != nil {
		t.Fatal(err)
	}
	source := "package samefixture\nfunc Choose(a,b <-chan int) { select { case <-a: case <-b: } }\n"
	inputs := map[string]string{filepath.Join(root, "go.mod"): "module windows_setup\n\ngo 1.27.3\n", filepath.Join(dir, "same.go"): source, filepath.Join(dir, "same_test.go"): "package samefixture\nimport \"testing\"\nfunc TestChoose(t *testing.T) { a:=make(chan int,1);a<-1;Choose(a,nil) }\n"}
	for p, s := range inputs {
		if err := os.WriteFile(p, []byte(s), 0600); err != nil {
			t.Fatal(err)
		}
	}
	t.Setenv("GOTOOLCHAIN", "local")
	t.Setenv("GOPROXY", "off")
	t.Setenv("GOSUMDB", "off")
	t.Setenv("GOWORK", "off")
	t.Setenv("GOFLAGS", "-mod=mod")
	out := filepath.Join(root, "coverage.out")
	goexe := filepath.Join(runtime.GOROOT(), "bin", "go")
	if runtime.GOOS == "windows" {
		goexe += ".exe"
	}
	cmd := exec.Command(goexe, "test", "-count=1", "-coverprofile="+out, "./script/test/same_fixture")
	cmd.Dir = root
	if b, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("compiler fixture: %v\n%s", err, b)
	}
	raw, err := os.ReadFile(out)
	if err != nil {
		t.Fatal(err)
	}
	path := "script/test/same_fixture/same.go"
	report, _, err := rc.NormalizeGo([][]byte{raw}, map[string][]byte{path: []byte(source)}, "windows_setup")
	if err != nil {
		t.Fatalf("same-line select: %v\n%s", err, raw)
	}
	hit, ok := report.Files[path][2]
	if !ok || hit {
		t.Fatalf("same-line unselected case should conservatively keep line uncovered: %v", report.Files[path])
	}
}
