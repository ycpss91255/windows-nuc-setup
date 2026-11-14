package main

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestActualCheckoutSource(t *testing.T) {
	d := t.TempDir()
	git := func(args ...string) string {
		t.Helper()
		c := exec.Command("git", args...)
		c.Dir = d
		c.Env = append(os.Environ(), "GIT_AUTHOR_NAME=Fixture", "GIT_AUTHOR_EMAIL=fixture@example.invalid", "GIT_COMMITTER_NAME=Fixture", "GIT_COMMITTER_EMAIL=fixture@example.invalid")
		b, e := c.CombinedOutput()
		if e != nil {
			t.Fatalf("git %v: %s: %v", args, b, e)
		}
		return strings.TrimSpace(string(b))
	}
	git("init", "-q")
	git("config", "user.name", "Fixture")
	git("config", "user.email", "fixture@example.invalid")
	os.WriteFile(filepath.Join(d, "file"), []byte("base"), 0600)
	git("add", "file")
	git("commit", "-qm", "base")
	base := git("rev-parse", "HEAD")
	os.WriteFile(filepath.Join(d, "file"), []byte("head"), 0600)
	git("commit", "-qam", "head")
	head := git("rev-parse", "HEAD")
	tree := git("rev-parse", head+"^{tree}")
	commit := func(message string, parents ...string) string {
		args := []string{"commit-tree", tree}
		for _, p := range parents {
			args = append(args, "-p", p)
		}
		args = append(args, "-m", message)
		return git(args...)
	}
	actual := commit("actual", base, head)
	regenerated := commit("regenerated", base, head)
	wrong := commit("wrong", head, base)
	badTree := git("commit-tree", base+"^{tree}", "-p", base, "-p", head, "-m", "bad tree")
	git("checkout", "--detach", "-q", actual)
	event := filepath.Join(d, "event.json")
	writeEvent := func(b, h string) {
		t.Helper()
		data, _ := json.Marshal(map[string]any{"number": 1, "pull_request": map[string]any{"number": 1, "base": map[string]any{"sha": b, "ref": "main", "repo": map[string]string{"full_name": "fixture/repo"}}, "head": map[string]string{"sha": h}}})
		if err := os.WriteFile(event, data, 0600); err != nil {
			t.Fatal(err)
		}
	}
	authority := filepath.Join(d, "authority.json")
	writeAuthority := func(ref, baseSHA, sha string) {
		t.Helper()
		v := map[string]any{"number": 1, "state": "open", "base": map[string]any{"ref": ref, "sha": baseSHA, "repo": map[string]string{"full_name": "fixture/repo"}}, "head": map[string]string{"sha": sha}}
		b, _ := json.Marshal(v)
		if err := os.WriteFile(authority, b, 0600); err != nil {
			t.Fatal(err)
		}
	}
	writeAuthority("main", base, head)
	cases := []struct {
		name, checkout, runSHA, eventBase, eventHead, expectedBase, expectedHead string
		ok                                                                       bool
	}{
		{"actual checkout", actual, actual, base, head, base, head, true},
		{"regenerated actual checkout", regenerated, regenerated, base, head, base, head, true},
		{"regenerated is not actual", regenerated, actual, base, head, base, head, false},
		{"changed base", actual, actual, head, head, base, head, false},
		{"changed head", actual, actual, base, base, base, head, false},
		{"parents reversed", wrong, wrong, base, head, base, head, false},
		{"wrong tree", badTree, badTree, base, head, base, head, false},
		{"missing metadata", actual, actual, "", head, base, head, false},
	}
	t.Run("missing independent authority", func(t *testing.T) {
		git("checkout", "--detach", "-q", actual)
		writeEvent(base, head)
		c := exec.Command("go", "run", ".", "-repo", d, "-event", event, "-checkout", actual, "-run-sha", actual, "-base", base, "-head", head)
		if b, err := c.CombinedOutput(); err == nil {
			t.Fatalf("missing independent authority was accepted: %s", b)
		}
	})
	t.Run("CLI errors", func(t *testing.T) {
		for _, args := range [][]string{{"-unknown"}, {"extra"}, {"-event", event}} {
			if run(args) == nil {
				t.Fatalf("accepted %v", args)
			}
		}
	})
	t.Run("main advanced after event", func(t *testing.T) {
		git("checkout", "--detach", "-q", actual)
		writeEvent(base, head)
		writeAuthority("main", head, head)
		args := []string{"-authority", authority, "-repo", d, "-event", event, "-checkout", actual, "-run-sha", actual, "-base", base, "-head", head}
		if err := run(args); err == nil {
			t.Fatal("stale integration accepted after main advanced")
		}
	})
	t.Run("retargeted live PR", func(t *testing.T) {
		writeEvent(base, head)
		writeAuthority("other", base, head)
		if err := authorityCheck(event, authority); err == nil {
			t.Fatal("retarget accepted")
		}
		writeAuthority("main", base, head)
	})
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			git("checkout", "--detach", "-q", tc.checkout)
			writeEvent(tc.eventBase, tc.eventHead)
			writeAuthority("main", tc.eventBase, tc.eventHead)
			if err := check(d, event, tc.checkout, tc.runSHA, tc.expectedBase, tc.expectedHead); (err == nil) != tc.ok {
				t.Fatalf("direct check: want success=%v, got %v", tc.ok, err)
			}
			args := []string{"-authority", authority, "-repo", d, "-event", event, "-checkout", tc.checkout, "-run-sha", tc.runSHA, "-base", tc.expectedBase, "-head", tc.expectedHead}
			if err := run(args); (err == nil) != tc.ok {
				t.Fatalf("run: want success=%v, got %v", tc.ok, err)
			}
			c := exec.Command("go", "run", ".", "-authority", authority, "-repo", d, "-event", event, "-checkout", tc.checkout, "-run-sha", tc.runSHA, "-base", tc.expectedBase, "-head", tc.expectedHead)
			b, e := c.CombinedOutput()
			if (e == nil) != tc.ok {
				t.Fatalf("want success=%v, got %v: %s", tc.ok, e, b)
			}
		})
	}
}
func TestRejectStaleMainRef(t *testing.T) {
	d := t.TempDir()
	event := filepath.Join(d, "event.json")
	authority := filepath.Join(d, "authority.json")
	base := strings.Repeat("a", 40)
	head := strings.Repeat("b", 40)
	liveMain := strings.Repeat("c", 40)
	identity := map[string]any{"number": 1, "state": "open", "base": map[string]any{"ref": "main", "sha": base, "repo": map[string]string{"full_name": "fixture/repo"}}, "head": map[string]string{"sha": head}}
	eventData, _ := json.Marshal(map[string]any{"number": 1, "pull_request": identity})
	authorityData, _ := json.Marshal(identity)
	if err := os.WriteFile(event, eventData, 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(authority, authorityData, 0600); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PREFLIGHT_MAIN_SHA", liveMain)
	if err := authorityCheck(event, authority); err == nil {
		t.Fatal("accepted stale PR base despite advanced main ref")
	}
}
