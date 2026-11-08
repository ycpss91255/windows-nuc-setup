package unit_test

import (
	"os"
	"path"
	"path/filepath"
	"strings"
	"testing"
)

// This repository deliberately uses deny-all plus explicit files/directories.
// Verify that concrete contract rather than mistaking a Dockerfile COPY for a
// file that Docker actually receives in its filtered build context.
func TestDockerCopySourcesAreInEffectiveExplicitBuildContext(t *testing.T) {
	root := filepath.Join("../../..")
	ignore, err := os.ReadFile(filepath.Join(root, ".dockerignore"))
	if err != nil {
		t.Fatal(err)
	}
	allowed := map[string]bool{}
	denied := false
	for _, raw := range strings.Split(string(ignore), "\n") {
		line := strings.TrimSpace(raw)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if !denied {
			if line != "**" {
				t.Fatal("build context must start denied")
			}
			denied = true
			continue
		}
		if strings.HasPrefix(line, "!") {
			allowed[strings.TrimSuffix(line[1:], "/")] = true
		} else {
			allowed[strings.TrimSuffix(line, "/")] = false
		}
	}
	if !denied {
		t.Fatal("build context has no deny-all")
	}
	docker, err := os.ReadFile(filepath.Join(root, "dockerfile/windows_tests.dockerfile"))
	if err != nil {
		t.Fatal(err)
	}
	copies := 0
	for _, line := range strings.Split(string(docker), "\n") {
		fields := strings.Fields(line)
		if len(fields) == 0 || fields[0] != "COPY" {
			continue
		}
		if len(fields) != 3 {
			t.Fatal("review new COPY syntax against explicit context", line)
		}
		source := fields[1]
		copies++
		if _, err := os.Stat(filepath.Join(root, filepath.FromSlash(source))); err != nil {
			t.Fatal(err)
		}
		for current := source; current != "."; current = path.Dir(current) {
			if !allowed[current] {
				t.Fatalf("Docker COPY source excluded by deny-all context: %s (missing %s)", source, current)
			}
		}
	}
	if copies == 0 {
		t.Fatal("no Docker COPY inputs verified")
	}
}
