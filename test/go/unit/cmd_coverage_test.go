package unit_test

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	rc "windows_setup/script/test/repo_coverage"
)

func TestCMDLauncherCatalogAndUnsupportedSyntax(t *testing.T) {
	source := []byte("@echo off\r\npowershell.exe -NoProfile -File \"%~dp0core\\run.ps1\" %*\r\n")
	launcher, err := rc.ParseCMDLauncher(source)
	if err != nil || launcher.Line != 2 || !launcher.ForwardArguments {
		t.Fatalf("%+v %v", launcher, err)
	}
	for _, bad := range []string{string(source) + "echo extra\n", strings.ReplaceAll(string(source), " %*", " & echo bad"), strings.ReplaceAll(string(source), "%~dp0", "%USERPROFILE%"), "@echo off\nif 1==1 echo no\n", strings.ReplaceAll(string(source), "-File", "-Command"), strings.ReplaceAll(string(source), "run.ps1", "run.ps1\" & evil \"")} {
		if _, err := rc.ParseCMDLauncher([]byte(bad)); err == nil {
			t.Fatalf("accepted unsupported %q", bad)
		}
	}
}

func TestCMDInventoryExplainsDirectiveAndUnknownCommands(t *testing.T) {
	root := t.TempDir()
	os.WriteFile(filepath.Join(root, "known.cmd"), []byte("@echo off\npowershell.exe -File \"%~dp0run.ps1\"\n"), 0600)
	os.WriteFile(filepath.Join(root, "unknown.cmd"), []byte("@echo off\necho unknown\n"), 0600)
	inv, err := rc.ScanInventory(root)
	if err != nil {
		t.Fatal(err)
	}
	if len(inv.Blockers) != 1 || !strings.Contains(inv.Blockers[0], "unknown.cmd") {
		t.Fatalf("unsupported CMD missing blocker: %+v", inv)
	}
	found := false
	for _, e := range inv.Excluded {
		if e.Path == "known.cmd#echo" && strings.Contains(e.Reason, "display directive") {
			found = true
		}
	}
	if !found {
		t.Fatal("echo exclusion not explicitly recorded")
	}
}

func TestCMDRejectsAmbiguousRawJSON(t *testing.T) {
	for _, bad := range []string{`{"SchemaVersion":1,"SchemaVersion":2}`, `{"Unexpected":1}`, `{} {}`} {
		if _, err := rc.DecodeCMDEvidence([]byte(bad)); err == nil {
			t.Fatal("ambiguous evidence accepted")
		}
	}
	data, _ := json.Marshal(rc.CMDEvidence{SchemaVersion: 1})
	if _, err := rc.DecodeCMDEvidence(data); err != nil {
		t.Fatal(err)
	}
}
