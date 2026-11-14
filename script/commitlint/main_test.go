package main

import (
 "os"
 "os/exec"
 "path/filepath"
 "strings"
 "testing"
)

func run(t *testing.T, args ...string) (string, error) {
 t.Helper()
 cmd := exec.Command("go", append([]string{"run", "."}, args...)...)
 cmd.Env = os.Environ()
 out, err := cmd.CombinedOutput()
 return string(out), err
}
func TestLint(t *testing.T) {
 for _, tc := range []struct{name, msg string; valid bool}{
  {"中文", "修正：避免重複執行\n\n測試：通過", true},
  {"英文", "fix: correct execution", false},
  {"私密路徑", "修正：設定 C:\\Users\\alice\\secret", false},
  {"憑證", "修正：token=abcdefghijklmnop", false},
 } { t.Run(tc.name, func(t *testing.T) {
  p := filepath.Join(t.TempDir(), "message")
  if err := os.WriteFile(p, []byte(tc.msg), 0600); err != nil { t.Fatal(err) }
  out, err := run(t, "lint", p)
  if (err == nil) != tc.valid { t.Fatalf("valid=%v err=%v output=%s", tc.valid, err, out) }
  if !tc.valid && strings.Contains(out, tc.msg) { t.Fatal("不得輸出完整訊息") }
 }) }
}
func TestInstallPreservesExistingHook(t *testing.T) {
 repo := t.TempDir()
 init := exec.Command("git", "init", "-q", repo)
 if out, err := init.CombinedOutput(); err != nil { t.Fatalf("git init: %v %s", err, out) }
 hook := filepath.Join(repo, ".git", "hooks", "commit-msg")
 if err := os.WriteFile(hook, []byte("existing"), 0700); err != nil { t.Fatal(err) }
 if _, err := run(t, "install", repo); err == nil { t.Fatal("existing hook should block installation") }
 data, err := os.ReadFile(hook); if err != nil || string(data) != "existing" { t.Fatalf("existing hook changed: %v", err) }
}
func TestInstallAndCommit(t *testing.T) {
 repo := t.TempDir()
 for _, args := range [][]string{{"init", "-q", repo}, {"-C", repo, "config", "user.name", "Fixture"}, {"-C", repo, "config", "user.email", "fixture@example.invalid"}} {
  if out, err := exec.Command("git", args...).CombinedOutput(); err != nil { t.Fatalf("git: %v %s", err, out) }
 }
 if out, err := run(t, "install", repo); err != nil { t.Fatalf("install: %v %s", err, out) }
 cmd := exec.Command("git", "-C", repo, "commit", "--allow-empty", "-m", "english only")
 if out, err := cmd.CombinedOutput(); err == nil { t.Fatalf("invalid commit accepted: %s", out) }
 cmd = exec.Command("git", "-C", repo, "commit", "--allow-empty", "-m", "測試：隔離提交")
 if out, err := cmd.CombinedOutput(); err != nil { t.Fatalf("valid commit rejected: %v %s", err, out) }
}
