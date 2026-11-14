package main

import (
	"encoding/json"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func TestSampleRunsBothFreshTestSetsAndStopsOnFailure(t *testing.T) {
	plan := samplePlan("native", "report", "fixture", "root", "sha", "url")
	if len(plan) != 4 || plan[0].Args[0] != "test" || plan[1].Args[0] != "test" {
		t.Fatalf("missing required test sets: %+v", plan)
	}
	for _, c := range plan[:2] {
		found := false
		for _, a := range c.Args {
			if a == "-count=1" {
				found = true
			}
		}
		if !found {
			t.Fatalf("test result reuse permitted: %+v", c)
		}
	}
	if plan[0].Artifact != "native" || plan[1].Artifact != "report" || plan[0].Fixture != "fixture" || plan[1].Fixture != "fixture" {
		t.Fatalf("fixture provenance mismatch: %+v", plan)
	}
	calls := 0
	_, err := runSample(plan, func(c command) error {
		calls++
		if calls == 2 {
			return errors.New("failed real test")
		}
		return nil
	})
	if err == nil || calls != 2 {
		t.Fatalf("failed test did not stop sample: calls=%d err=%v", calls, err)
	}
}

func TestDiagnosticRequiresCompleteIdentityAndOnlyWritesSuccess(t *testing.T) {
	dir := t.TempDir()
	out := filepath.Join(dir, "sample.json")
	cfg := configuration{Native: "native", Report: "report", Fixture: "fixture", Root: "root", SHA: strings.Repeat("a", 40), RunURL: "https://github.com/example/repo/actions/runs/123", Output: out, Attempt: 1, Sample: "cold_1"}
	if err := runDiagnostic(cfg, func(command) error { return errors.New("failed") }); err == nil {
		t.Fatal("failure accepted")
	}
	if _, err := os.Stat(out); !os.IsNotExist(err) {
		t.Fatal("failure published successful sample")
	}
	cfg.RunURL = ""
	if err := runDiagnostic(cfg, func(command) error { return nil }); err == nil {
		t.Fatal("missing identity accepted")
	}
	cfg.RunURL = "https://github.com/example/repo/actions/runs/123"
	if err := runDiagnostic(cfg, func(command) error { return nil }); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(out)
	if err != nil {
		t.Fatal(err)
	}
	var summary struct {
		Commit, RunURL string
		Observations   []observation
	}
	if err = json.Unmarshal(data, &summary); err != nil {
		t.Fatal(err)
	}
	if summary.Commit != cfg.SHA || summary.RunURL != cfg.RunURL || len(summary.Observations) != 4 {
		t.Fatalf("incomplete sample: %s", data)
	}
	if err := runDiagnostic(cfg, func(command) error { return nil }); err == nil {
		t.Fatal("overwrote existing sample")
	}
}

func TestRealDiagnosticCLIExecutesFreshCommandsAndStopsOnFailure(t *testing.T) {
	root, err := filepath.Abs("../../..")
	if err != nil {
		t.Fatal(err)
	}
	dir := t.TempDir()
	fakeSource := filepath.Join(dir, "fake.go")
	fakeGo := filepath.Join(dir, "go.exe")
	if runtime.GOOS != "windows" {
		fakeGo = filepath.Join(dir, "go")
	}
	source := `package main
import("fmt";"os";"strings")
func main(){f,e:=os.OpenFile(os.Getenv("FAKE_LOG"),os.O_CREATE|os.O_APPEND|os.O_WRONLY,0600);if e!=nil{os.Exit(2)};fmt.Fprintln(f,strings.Join(os.Args[1:]," ")+" | "+os.Getenv("WINDOWS_SETUP_ARTIFACT_DIR"));f.Close();if os.Getenv("FAKE_FAIL")!="" && strings.Contains(strings.Join(os.Args[1:]," "),"./..."){os.Exit(7)}}`
	if err = os.WriteFile(fakeSource, []byte(source), 0600); err != nil {
		t.Fatal(err)
	}
	goexe := filepath.Join(runtime.GOROOT(), "bin", "go")
	if runtime.GOOS == "windows" {
		goexe += ".exe"
	}
	binary := filepath.Join(dir, "diagnostic.exe")
	if runtime.GOOS != "windows" {
		binary = filepath.Join(dir, "diagnostic")
	}
	for _, args := range [][]string{{"build", "-o", fakeGo, fakeSource}, {"build", "-mod=vendor", "-cover", "-coverpkg=./script/test/...", "-o", binary, "./script/test/cache_diagnostic"}} {
		cmd := exec.Command(goexe, args...)
		cmd.Dir = root
		if b, e := cmd.CombinedOutput(); e != nil {
			t.Fatalf("fixture build: %v %s", e, b)
		}
	}
	cover := os.Getenv("WINDOWS_SETUP_CLI_COVERAGE_DIR")
	if cover == "" {
		cover = t.TempDir()
	}
	for _, fail := range []bool{false, true} {
		log := filepath.Join(t.TempDir(), "calls.log")
		out := filepath.Join(t.TempDir(), "sample.json")
		args := []string{"--native", "native", "--report", "report", "--fixture", "fixture", "--root", root, "--sha", strings.Repeat("a", 40), "--run-url", "https://github.com/example/repo/actions/runs/123", "--attempt", "1", "--sample", "cold_1", "--output", out}
		cmd := exec.Command(binary, args...)
		cmd.Env = append(os.Environ(), "PATH="+dir+string(os.PathListSeparator)+os.Getenv("PATH"), "GOCOVERDIR="+cover, "FAKE_LOG="+log)
		if fail {
			cmd.Env = append(cmd.Env, "FAKE_FAIL=1")
		}
		b, e := cmd.CombinedOutput()
		if (e == nil) == fail {
			t.Fatalf("unexpected exit %v %s", e, b)
		}
		calls, e := os.ReadFile(log)
		if e != nil {
			t.Fatal(e)
		}
		lines := strings.Split(strings.TrimSpace(string(calls)), "\n")
		expected := 4
		if fail {
			expected = 2
		}
		if len(lines) != expected || !strings.Contains(lines[0], "test -count=1 ./test/go/integration") || !strings.Contains(lines[0], " | native") || !strings.Contains(lines[1], "test -count=1 ./... | report") {
			t.Fatalf("unexpected calls: %s", calls)
		}
		_, e = os.Stat(out)
		if (e == nil) == fail {
			t.Fatalf("unexpected sample output: %v", e)
		}
	}
}
