package integration_test

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"
	a "windows_setup/script/test/acceptance"
)

func TestSourceGateUsesShiftF10WithoutAuditShortcut(t *testing.T) {
	root := t.TempDir()
	for name, content := range map[string]string{
		"readme.md": "[![CI](https://github.com/example/setup/actions/workflows/windows.yml/badge.svg)](https://example.com)\ninit.cmd windows.cmd Shift+F10 -AfterRestart -VerifyOnly\n",
		"init.cmd":  "@echo off", "windows.cmd": "@echo off", ".github/workflows/windows.yml": "name: Windows",
	} {
		p := filepath.Join(root, name)
		if err := os.MkdirAll(filepath.Dir(p), 0755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(p, []byte(content), 0644); err != nil {
			t.Fatal(err)
		}
	}
	for _, args := range [][]string{{"init", "--quiet"}, {"add", "."}} {
		cmd := exec.Command("git", append([]string{"-C", root}, args...)...)
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("git: %s: %v", out, err)
		}
	}
	if _, err := a.ValidateSource(root); err != nil {
		t.Fatalf("Shift+F10 instructions must not require audit shortcut: %v", err)
	}
}

func TestRepositorySourceGate(t *testing.T) {
	root, e := os.Getwd()
	if e != nil {
		t.Fatal(e)
	}
	root = filepath.Clean(filepath.Join(root, "../../.."))
	doc, e := a.ValidateSource(root)
	if e != nil || doc == "" {
		t.Fatalf("actual repository naming/entry/vendor source contract: %v", e)
	}
}
