package integration_test

import (
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func TestCLICommands(t *testing.T) {
	root, _ := filepath.Abs("../../..")
	goexe := filepath.Join(runtime.GOROOT(), "bin", "go")
	if runtime.GOOS == "windows" {
		goexe += ".exe"
	}
	r := decode(t, files(t, os.Getenv("WINDOWS_SETUP_ARTIFACT_DIR")))
	run := func(args ...string) (string, error) {
		c := exec.Command(goexe, args...)
		c.Dir = root
		b, e := c.CombinedOutput()
		return string(b), e
	}
	t.Run("valid_report", func(t *testing.T) {
		b, e := run("run", "./script/test/requirements_gate", "--artifact-dir", os.Getenv("WINDOWS_SETUP_ARTIFACT_DIR"), "--source-root", root, "--expected-sha", r.Commit, "--expected-run-url", r.RunUrl)
		if e != nil || !strings.Contains(b, "需求驗收通過") {
			t.Fatalf("%s %v", b, e)
		}
	})
	t.Run("wrong_sha_exit", func(t *testing.T) {
		b, e := run("run", "./script/test/requirements_gate", "--artifact-dir", os.Getenv("WINDOWS_SETUP_ARTIFACT_DIR"), "--source-root", root, "--expected-sha", strings.Repeat("0", 40), "--expected-run-url", r.RunUrl)
		if e == nil || !strings.Contains(b, "需求驗收失敗") {
			t.Fatalf("%s %v", b, e)
		}
	})
	t.Run("https_only", func(t *testing.T) {
		b, e := run("run", "./script/test/verify_deployment", "--base-url", "http://example.com/", "--readme", filepath.Join(root, "readme.md"), "--expected-sha", r.Commit, "--expected-run-url", r.RunUrl)
		if e == nil || !strings.Contains(b, "HTTPS") {
			t.Fatalf("%s %v", b, e)
		}
	})
}
