package integration_test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestMaintenanceDistributionNeedsNoPython(t *testing.T) {
	root, _ := filepath.Abs("../../..")
	for _, dir := range []string{"script", "test"} {
		e := filepath.WalkDir(filepath.Join(root, dir), func(p string, d os.DirEntry, e error) error {
			if e != nil {
				return e
			}
			if !d.IsDir() && strings.HasSuffix(p, ".py") {
				t.Errorf("Python maintenance dependency remains: %s", filepath.Base(p))
			}
			return nil
		})
		if e != nil {
			t.Fatal(e)
		}
	}
	for _, p := range []string{".github/workflows/windows_tests.yml", "dockerfile/windows_tests.dockerfile", "script/docker/container_test.ps1"} {
		b, e := os.ReadFile(filepath.Join(root, p))
		if e != nil {
			t.Fatal(e)
		}
		if strings.Contains(strings.ToLower(string(b)), "python") {
			t.Errorf("runtime dependency remains in %s", p)
		}
	}
}
