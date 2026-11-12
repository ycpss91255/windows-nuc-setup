package main

import (
 "os"
 "os/exec"
 "path/filepath"
 "testing"
)

// The consumer contract drives a separate, opt-in Go test as an external caller.
func TestConsumerFixtureContract(t *testing.T) {
 root := filepath.Join(t.TempDir(), "fixture")
 cmd := exec.Command("go", "test", "-count=1", "-run", "^TestExportSyntheticConsumerFixture$", ".")
 cmd.Env = append(os.Environ(), "WINDOWS_SETUP_BUNDLE_FIXTURE_DIR="+root)
 if out, err := cmd.CombinedOutput(); err != nil { t.Fatalf("generator failed: %v\n%s", err, out) }
 for _, name := range []string{"fixture.json", "windows_setup_report_v0.1.0.zip", "source/.git/HEAD"} {
  if _, err := os.Stat(filepath.Join(root, filepath.FromSlash(name))); err != nil { t.Errorf("missing fixture output %s: %v", name, err) }
 }
}
