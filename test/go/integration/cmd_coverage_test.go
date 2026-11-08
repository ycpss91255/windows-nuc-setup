package integration_test

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	rc "windows_setup/script/test/repo_coverage"
)

func TestCMDOriginalLaunchersWithRealProbe(t *testing.T) {
	if runtime.GOOS != "windows" {
		t.Skip("cmd.exe is a Windows shell")
	}
	repo, _ := filepath.Abs("../../..")
	probe := filepath.Join(t.TempDir(), "powershell.exe")
	probeSource := filepath.Join(t.TempDir(), "main.go")
	probeBytes, err := os.ReadFile(filepath.Join(repo, "test/fixtures/cmd_probe/main.go.txt"))
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(probeSource, probeBytes, 0600); err != nil {
		t.Fatal(err)
	}
	build := exec.Command(filepath.Join(runtime.GOROOT(), "bin", "go.exe"), "build", "-mod=vendor", "-o", probe, probeSource)
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
	if len(sources) == 0 || len(catalogs) != len(sources) || len(report.Files) != len(sources) {
		t.Fatalf("not all launchers measured: %d", len(catalogs))
	}
	for _, file := range report.Files {
		for _, hit := range file {
			if !hit {
				t.Fatal("launcher not hit")
			}
		}
	}
	tool := filepath.Join(t.TempDir(), "coverage.exe")
	build = exec.Command(filepath.Join(runtime.GOROOT(), "bin", "go.exe"), "build", "-mod=vendor", "-cover", "-coverpkg=./script/test/...", "-o", tool, "./script/test/repo_coverage_tool")
	build.Dir = repo
	if out, err := build.CombinedOutput(); err != nil {
		t.Fatalf("tool build %v %s", err, out)
	}
	run := func(ok bool, args ...string) {
		t.Helper()
		c := exec.Command(tool, args...)
		c.Env = os.Environ()
		if d := os.Getenv("WINDOWS_SETUP_CLI_COVERAGE_DIR"); d != "" {
			c.Env = append(c.Env, "GOCOVERDIR="+d)
		}
		out, err := c.CombinedOutput()
		if (err == nil) != ok {
			t.Fatalf("CLI %v %v %s", args, err, out)
		}
	}
	evidencePath := filepath.Join(t.TempDir(), "cmd.json")
	run(true, "cmd-measure", "--source-root", snapshot, "--probe-executable", probe, "--output", evidencePath)
	run(false, "cmd-measure", "--source-root", snapshot, "--probe-executable", probe, "--output", evidencePath)
	run(false, "cmd-measure")
	git := func(args ...string) string {
		t.Helper()
		c := exec.Command("git", append([]string{"-C", snapshot}, args...)...)
		out, err := c.CombinedOutput()
		if err != nil {
			t.Fatalf("git %v %s", err, out)
		}
		return strings.TrimSpace(string(out))
	}
	git("init")
	git("config", "user.name", "Coverage Fixture")
	git("config", "user.email", "fixture@example.invalid")
	git("add", ".")
	git("commit", "-m", "fixture")
	sha := git("rev-parse", "HEAD")
	output := filepath.Join(t.TempDir(), "result")
	run(true, "collect", "--source-root", snapshot, "--output-dir", output, "--expected-sha", sha, "--cmd-evidence", evidencePath)
	run(true, "verify", "--artifact-dir", output, "--expected-sha", sha, "--require-complete", "--minimum-percent", "100")
	for _, mutate := range []func(*rc.CMDEvidence){
		func(e *rc.CMDEvidence) { e.Sources[0].Runs[0].Arguments = []string{"wrong target"} },
		func(e *rc.CMDEvidence) { e.Sources[0].CopiedAfterSHA256 = strings.Repeat("0", 64) },
		func(e *rc.CMDEvidence) { e.Sources[0].Runs[0].Directory = "wrong directory" },
		func(e *rc.CMDEvidence) { e.Sources[0].Runs[0].Invocations = 0 },
		func(e *rc.CMDEvidence) { e.Sources[0].Runs[1].ExitCode = 0 },
		func(e *rc.CMDEvidence) { e.Sources = e.Sources[1:] },
	} {
		data, _ := json.Marshal(evidence)
		var changed rc.CMDEvidence
		json.Unmarshal(data, &changed)
		mutate(&changed)
		if _, _, err := rc.NormalizeCMD(changed, sources); err == nil {
			t.Fatal("forged command evidence accepted")
		}
	}
	if err := os.WriteFile(filepath.Join(snapshot, "unknown.cmd"), []byte("@echo off\necho unsupported\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := rc.CollectCMD(snapshot, probe); err == nil {
		t.Fatal("unknown launcher executed")
	}
}
