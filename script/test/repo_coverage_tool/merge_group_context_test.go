package main

import (
	"bytes"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	a "windows_setup/script/test/acceptance"
)

// This is an owned synthetic merge context, not a GitHub-hosted queue run.
func TestMergeGroupNativeStageProvenance(t *testing.T) {
	f := newNativeStageFixture(t)
	git := func(args ...string) string {
		t.Helper()
		c := exec.Command("git", append([]string{"-C", f.root}, args...)...)
		b, err := c.CombinedOutput()
		if err != nil {
			t.Fatalf("fixture git %v: %s: %v", args, b, err)
		}
		return strings.TrimSpace(string(b))
	}
	git("checkout", "-q", "-b", "queue-candidate")
	git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-q", "--allow-empty", "-m", "candidate")
	git("checkout", "-q", "-")
	git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "merge", "-q", "--no-ff", "queue-candidate", "-m", "synthetic merge group")
	oldSHA := f.sha
	f.sha = git("rev-parse", "HEAD")
	if len(strings.Fields(git("rev-list", "--parents", "-n", "1", "HEAD"))) != 3 {
		t.Fatal("fixture must be a two-parent merge")
	}
	ref := "refs/heads/gh-readonly-queue/main/pr-123-0123456789abcdef"
	git("update-ref", ref, f.sha)
	git("checkout", "-q", "--detach", ref)
	t.Setenv("GITHUB_EVENT_NAME", "merge_group")
	t.Setenv("GITHUB_REF", ref)
	t.Setenv("GITHUB_SHA", f.sha)
	t.Setenv("GITHUB_RUN_ID", "42")
	t.Setenv("GITHUB_RUN_ATTEMPT", "2")
	for _, name := range []string{filepath.Join(f.report, "summary.json"), filepath.Join(f.report, "summary.md")} {
		b, err := os.ReadFile(name)
		if err != nil {
			t.Fatal(err)
		}
		b = bytes.ReplaceAll(b, []byte(oldSHA), []byte(f.sha))
		if strings.HasSuffix(name, "summary.json") {
			var v map[string]any
			if err := json.Unmarshal(b, &v); err != nil {
				t.Fatal(err)
			}
			v["RefName"] = strings.TrimPrefix(ref, "refs/heads/")
			b, err = json.Marshal(v)
			if err != nil {
				t.Fatal(err)
			}
		}
		if err := os.WriteFile(name, b, 0600); err != nil {
			t.Fatal(err)
		}
	}
	files, err := a.OwnedGoFiles(f.root)
	if err != nil {
		t.Fatal(err)
	}
	coverage, profile, err := a.CreateCoverageEvidence([][]byte{[]byte("mode: set\nwindows_setup/script/test/owned.go:2.1,2.30 1 1\n")}, files, a.CoverageProvenance{Commit: f.sha, RunUrl: f.run, MeasuredAt: "2026-11-08T00:00:00Z", SourceState: "Clean", GoVersion: "go1.27.3", Environment: "Synthetic merge context"})
	if err != nil {
		t.Fatal(err)
	}
	data, err := json.Marshal(coverage)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(f.goDir, "go_coverage.json"), data, 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(f.goDir, "go_coverage.out"), profile, 0600); err != nil {
		t.Fatal(err)
	}
	stage := filepath.Join(t.TempDir(), "stage")
	var out bytes.Buffer
	if err := run(f.args("native-stage-pack", "", stage), &out); err != nil {
		t.Fatalf("pack synthetic merge source: %v", err)
	}
	if err := run(f.args("native-stage-restore", stage, filepath.Join(t.TempDir(), "restored")), &out); err != nil {
		t.Fatalf("restore same merge source: %v", err)
	}
	for _, tc := range []struct{ name, option, value string }{{"wrong source SHA", "--expected-sha", oldSHA}, {"wrong run", "--expected-run-url", "https://github.com/example/setup/actions/runs/43"}, {"wrong attempt", "--run-attempt", "1"}} {
		t.Run(tc.name, func(t *testing.T) {
			args := f.args("native-stage-restore", stage, filepath.Join(t.TempDir(), "restored"))
			for i := range args {
				if args[i] == tc.option {
					args[i+1] = tc.value
					break
				}
			}
			if err := run(args, &out); err == nil {
				t.Fatal("mismatched provenance accepted")
			}
		})
	}
	if err := os.Remove(filepath.Join(stage, "go", "go_coverage.out")); err != nil {
		t.Fatal(err)
	}
	if err := run(f.args("native-stage-restore", stage, filepath.Join(t.TempDir(), "incomplete")), &out); err == nil {
		t.Fatal("incomplete native stage accepted")
	}
}
