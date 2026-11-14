//go:build !windows

package main

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestUnsupportedPlatformDoesNotCreateOrDelete(t *testing.T) {
	parent := t.TempDir()
	root := filepath.Join(parent, "owned")
	var out bytes.Buffer
	if err := run([]string{"init", root}, &out, time.Now()); err == nil {
		t.Fatal("init accepted on unsupported platform")
	}
	if _, err := os.Stat(root); !os.IsNotExist(err) {
		t.Fatalf("unexpected root created: %v", err)
	}
	if err := os.Mkdir(root, 0700); err != nil {
		t.Fatal(err)
	}
	keep := filepath.Join(root, "keep")
	if err := os.WriteFile(keep, []byte("fixture"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := safeDelete(root, "keep", "unused", time.Now()); err == nil {
		t.Fatal("delete accepted on unsupported platform")
	}
	if got, err := os.ReadFile(keep); err != nil || string(got) != "fixture" {
		t.Fatalf("fixture changed: %q %v", got, err)
	}
	if err := safeFinish(root, "keep", "unused", ""); err == nil {
		t.Fatal("finish accepted on unsupported platform")
	}
}
