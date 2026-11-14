package unit_test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	rc "windows_setup/script/test/repo_coverage"
)

func TestRuntimeCoverageInventoryScopeAndUnknownExecutable(t *testing.T) {
	root := t.TempDir()
	files := map[string]string{
		"core/start.ps1":             "Write-Output 'fixture'\n",
		"modules/demo/app.ps1":       "Write-Output 'fixture'\n",
		"modules/demo/native/app.cs": "class Demo { int Value() { return 1; } }\n",
		"core/launch.cmd":            "@echo off\r\npowershell.exe -File \"%~dp0start.ps1\"\r\n",
		"script/test/tool.go":        "package main\nfunc main() {}\n",
	}
	for name, data := range files {
		path := filepath.Join(root, filepath.FromSlash(name))
		if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(data), 0600); err != nil {
			t.Fatal(err)
		}
	}
	inv, err := rc.ScanRuntimeInventory(root)
	if err != nil {
		t.Fatal(err)
	}
	got := map[string]bool{}
	for _, s := range inv.Sources {
		got[s.Path] = true
	}
	if len(got) != 3 || !got["core/start.ps1"] || !got["modules/demo/app.ps1"] || !got["modules/demo/native/app.cs"] {
		t.Fatalf("incorrect runtime roster: %v", got)
	}
	if len(inv.Blockers) != 0 {
		t.Fatalf("valid scope blocked: %v", inv.Blockers)
	}
	for _, name := range []string{"core/native/new.cs", "modules/demo/new.py"} {
		path := filepath.Join(root, filepath.FromSlash(name))
		if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte("fixture"), 0600); err != nil {
			t.Fatal(err)
		}
		inv, err = rc.ScanRuntimeInventory(root)
		if err != nil {
			t.Fatal(err)
		}
		found := false
		for _, blocker := range inv.Blockers {
			if strings.HasPrefix(blocker, name+":") {
				found = true
			}
		}
		if !found {
			t.Errorf("new unsupported runtime executable not blocked: %s", name)
		}
	}
}
