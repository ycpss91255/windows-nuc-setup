package main

import (
	"path/filepath"
	"testing"
	rc "windows_setup/script/test/repo_coverage"
)

func TestQualitySummaryRealSourceInventory(t *testing.T) {
	root, err := filepath.Abs("../../..")
	if err != nil {
		t.Fatal(err)
	}
	inventory, err := rc.ScanInventory(root)
	if err != nil {
		t.Fatal(err)
	}
	if len(inventory.Blockers) != 0 {
		t.Fatalf("actual source inventory blocked: %v", inventory.Blockers)
	}
	for _, source := range inventory.Sources {
		if source.Path == "script/test/ci_quality_summary.ps1" && source.Language == "powershell" {
			return
		}
	}
	t.Fatal("quality summary helper missing from measured PowerShell sources")
}
