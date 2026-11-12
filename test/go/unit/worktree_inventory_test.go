package unit_test

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	rc "windows_setup/script/test/repo_coverage"
)

func TestRepoCoverageRootWorktreeIsOnlyDevelopmentExclusion(t *testing.T) {
	root := t.TempDir()
	files := map[string]string{
		"worktree/branch/core/other.ps1": "Write-Output 'another checkout'",
		"worktree/branch/main.go":        "package main\nfunc main() {}\n",
		"worktree_extra/owned.go":        "package owned\nfunc Run() {}\n",
		"core/worktree/owned.ps1":        "Write-Output 'delivery source'",
		"untracked.ps1":                  "Write-Output 'new source'",
	}
	for name, data := range files {
		p := filepath.Join(root, filepath.FromSlash(name))
		if err := os.MkdirAll(filepath.Dir(p), 0700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(p, []byte(data), 0600); err != nil {
			t.Fatal(err)
		}
	}
	inv, err := rc.ScanInventory(root)
	if err != nil {
		t.Fatal(err)
	}
	got := map[string]bool{}
	for _, s := range inv.Sources {
		got[s.Path] = true
	}
	for _, name := range []string{"worktree_extra/owned.go", "core/worktree/owned.ps1", "untracked.ps1"} {
		if !got[name] {
			t.Errorf("自有來源不得被隱藏：%s", name)
		}
	}
	for name := range got {
		if strings.HasPrefix(name, "worktree/") {
			t.Errorf("其他工作樹不應進入來源清單：%s", name)
		}
	}
	found := false
	for _, x := range inv.Excluded {
		if x.Path == "worktree/" && x.Reason != "" {
			found = true
		}
	}
	if !found {
		t.Error("根工作樹排除必須記錄原因")
	}
}

func TestRepoCoverageRootWorktreeSymlinkIsNotSilentlyExcluded(t *testing.T) {
	root := t.TempDir()
	target := t.TempDir()
	if err := os.Symlink(target, filepath.Join(root, "worktree")); err != nil {
		t.Skipf("此環境無權建立符號連結：%v", err)
	}
	inv, err := rc.ScanInventory(root)
	if err != nil {
		t.Fatal(err)
	}
	for _, b := range inv.Blockers {
		if strings.Contains(b, "worktree") {
			return
		}
	}
	t.Fatal("根工作樹為符號連結時必須保留 blocker")
}

func TestRootWorktreeGitIgnoreOnlyAtRepositoryRoot(t *testing.T) {
	root := t.TempDir()
	cmd := exec.Command("git", "-C", root, "init", "-q")
	if b, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("git init: %v %s", err, b)
	}
	ignore, err := os.ReadFile(filepath.Join("..", "..", "..", ".gitignore"))
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, ".gitignore"), ignore, 0600); err != nil {
		t.Fatal(err)
	}
	check := func(path string) bool {
		return exec.Command("git", "-C", root, "check-ignore", "-q", "--no-index", path).Run() == nil
	}
	if !check("worktree/branch/owned.go") {
		t.Error("根開發工作樹未被 Git 忽略")
	}
	for _, p := range []string{"worktree_extra/owned.go", "core/worktree/owned.go"} {
		if check(p) {
			t.Errorf("自有來源不應被忽略：%s", p)
		}
	}
}
