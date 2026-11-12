package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	c "windows_setup/script/test/repo_coverage"
)

// This targeted subprocess produces the compiler baseline without running this test recursively.
func TestCoverageCompilerBaselineProbe(t *testing.T) {}

func TestAllProductionSourcesHaveCompilerBaseline(t *testing.T) {
	profile := filepath.Join(t.TempDir(), "coverage.out")
	cmd := exec.Command("go", "test", "-count=1", "-run", "^TestCoverageCompilerBaselineProbe$", "-coverprofile="+profile, ".")
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("compiler baseline: %v %s", err, out)
	}
	data, err := os.ReadFile(profile)
	if err != nil {
		t.Fatal(err)
	}
	entries, err := os.ReadDir(".")
	if err != nil {
		t.Fatal(err)
	}
	sources := map[string][]byte{}
	for _, entry := range entries {
		name := entry.Name()
		if !strings.HasSuffix(name, ".go") || strings.HasSuffix(name, "_test.go") {
			continue
		}
		b, err := os.ReadFile(name)
		if err != nil {
			t.Fatal(err)
		}
		sources["script/test/report_bundle_tool/"+name] = b
	}
	if _, _, err := c.NormalizeGo([][]byte{data}, sources, "windows_setup"); err != nil {
		t.Fatalf("all owned production sources must have compiler baseline: %v", err)
	}
}
