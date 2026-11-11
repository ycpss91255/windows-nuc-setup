package main

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"testing"

	rc "windows_setup/script/test/repo_coverage"
)

func TestCollectExecutableLineCoverage(t *testing.T) {
	root, err := filepath.Abs("../../..")
	if err != nil {
		t.Fatal(err)
	}
	profile := filepath.Join(t.TempDir(), "collect.out")
	goexe := filepath.Join(runtime.GOROOT(), "bin", "go")
	if runtime.GOOS == "windows" {
		goexe += ".exe"
	}
	cmd := exec.Command(goexe, "test", "-mod=vendor", "-count=1", "-run", "^TestCollectInputCases$", "-coverprofile="+profile, "./script/test/repo_coverage_tool")
	cmd.Dir = root
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("real collector cases: %v\n%s", err, out)
	}
	data, err := os.ReadFile(profile)
	if err != nil {
		t.Fatal(err)
	}
	filtered := []byte("mode: set\n")
	for _, line := range bytes.Split(data, []byte("\n")) {
		if bytes.HasPrefix(line, []byte("windows_setup/script/test/repo_coverage_tool/collect.go:")) {
			filtered = append(filtered, line...)
			filtered = append(filtered, '\n')
		}
	}
	source, err := os.ReadFile(filepath.Join(root, "script/test/repo_coverage_tool/collect.go"))
	if err != nil {
		t.Fatal(err)
	}
	report, _, err := rc.NormalizeGo([][]byte{filtered}, map[string][]byte{"script/test/repo_coverage_tool/collect.go": source}, "windows_setup")
	if err != nil {
		t.Fatal(err)
	}
	hit := 0
	for _, covered := range report.Files["script/test/repo_coverage_tool/collect.go"] {
		if covered {
			hit++
		}
	}
	t.Logf("actual collector cases: %d/%d complete executable lines", hit, len(report.Files["script/test/repo_coverage_tool/collect.go"]))
	if hit < 105 {
		t.Fatalf("collector raw-input and publication boundaries cover %d real complete executable lines; require 105", hit)
	}
}
