package unit_test

import (
	"path/filepath"
	"strings"
	"testing"
	rc "windows_setup/script/test/repo_coverage"
)

func TestCIPipelineDoesNotHideExecutableLogic(t *testing.T) {
	root, _ := filepath.Abs("../../..")
	inventory, err := rc.ScanInventory(root)
	if err != nil {
		t.Fatal(err)
	}
	for _, blocker := range inventory.Blockers {
		if strings.HasPrefix(blocker, ".github/workflows/windows_tests.yml:") || strings.HasPrefix(blocker, "dockerfile/windows_tests.dockerfile:") {
			t.Fatal(blocker)
		}
	}
}
