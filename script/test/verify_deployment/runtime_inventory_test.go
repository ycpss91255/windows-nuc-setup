package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	c "windows_setup/script/test/repo_coverage"
)

func TestPublishedRuntimeInventoryUsesRuntimeScope(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, "core", "sample.ps1")
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte("Write-Output 1"), 0600); err != nil {
		t.Fatal(err)
	}
	inv, err := c.ScanRuntimeInventory(root)
	if err != nil {
		t.Fatal(err)
	}
	data, err := json.Marshal(inv)
	if err != nil {
		t.Fatal(err)
	}
	evidence := &c.Evidence{SchemaVersion: c.RuntimeSchemaVersion, Metric: c.RuntimeMetric, Scope: c.RuntimeScope}
	if err := validatePublishedInventory(evidence, root, data); err != nil {
		t.Fatalf("runtime inventory rejected: %v", err)
	}
	if err := os.WriteFile(path, []byte("Write-Output 2"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := validatePublishedInventory(evidence, root, data); err == nil {
		t.Fatal("changed source accepted")
	}
}
