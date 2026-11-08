package integration_test

import (
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"testing"
	rc "windows_setup/script/test/repo_coverage"
)

func TestCMDOriginalLaunchersWithRealProbe(t *testing.T) {
	if runtime.GOOS != "windows" {
		t.Skip("cmd.exe is a Windows shell")
	}
	repo, _ := filepath.Abs("../../..")
	probe := filepath.Join(t.TempDir(), "powershell.exe")
	build := exec.Command(filepath.Join(runtime.GOROOT(), "bin", "go.exe"), "build", "-mod=vendor", "-o", probe, "./test/fixtures/cmd_probe")
	build.Dir = repo
	if out, err := build.CombinedOutput(); err != nil {
		t.Fatalf("probe build: %v %s", err, out)
	}
	inv, err := rc.ScanInventory(repo)
	if err != nil {
		t.Fatal(err)
	}
	snapshot := filepath.Join(t.TempDir(), "launcher 空白 測試")
	sources := map[string][]byte{}
	for _, s := range inv.Sources {
		if s.Language != "cmd" {
			continue
		}
		b, e := os.ReadFile(filepath.Join(repo, filepath.FromSlash(s.Path)))
		if e != nil {
			t.Fatal(e)
		}
		p := filepath.Join(snapshot, filepath.FromSlash(s.Path))
		os.MkdirAll(filepath.Dir(p), 0700)
		os.WriteFile(p, b, 0600)
		sources[s.Path] = b
	}
	evidence, err := rc.CollectCMD(snapshot, probe)
	if err != nil {
		t.Fatal(err)
	}
	report, catalogs, err := rc.NormalizeCMD(evidence, sources)
	if err != nil {
		t.Fatal(err)
	}
	if len(catalogs) != 30 || len(report.Files) != 30 {
		t.Fatalf("not all launchers measured: %d", len(catalogs))
	}
	for _, file := range report.Files {
		for _, hit := range file {
			if !hit {
				t.Fatal("launcher not hit")
			}
		}
	}
	evidence.Sources[0].Runs[0].Arguments = []string{"wrong target"}
	if _, _, err := rc.NormalizeCMD(evidence, sources); err == nil {
		t.Fatal("forged argv accepted")
	}
	if err := os.WriteFile(filepath.Join(snapshot, "unknown.cmd"), []byte("@echo off\necho unsupported\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := rc.CollectCMD(snapshot, probe); err == nil {
		t.Fatal("unknown launcher executed")
	}
}
