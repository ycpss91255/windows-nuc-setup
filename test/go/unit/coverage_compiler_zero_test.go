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
