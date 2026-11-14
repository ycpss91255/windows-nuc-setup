package main

import (
 "bytes"
 "os"
 "path/filepath"
 "strings"
 "testing"
 "time"
)

func TestOwnedArtifactsRequireSelectionCompletionAndExpiry(t *testing.T) {
 parent := t.TempDir()
 root := filepath.Join(parent, "owned")
 now := time.Date(2026, 1, 3, 0, 0, 0, 0, time.UTC)
 var out bytes.Buffer
 if err := run([]string{"init", root}, &out, now); err != nil { t.Fatal(err) }
 if err := run([]string{"create", root, "done"}, &out, now); err != nil { t.Fatal(err) }
 if err := os.WriteFile(filepath.Join(root,"done","payload"), []byte("fixture"), 0600); err != nil { t.Fatal(err) }
 if err := run([]string{"finish", root, "done", "2026-01-02T00:00:00Z"}, &out, now); err != nil { t.Fatal(err) }
 if err := run([]string{"create", root, "active"}, &out, now); err != nil { t.Fatal(err) }
 if err := os.Mkdir(filepath.Join(root,"unknown"), 0700); err != nil { t.Fatal(err) }
 out.Reset()
 if err := run([]string{"clean", root, "done"}, &out, now); err != nil { t.Fatal(err) }
 if !strings.Contains(out.String(), "done") { t.Fatalf("preview missing selection: %q", out.String()) }
 if _, err := os.Stat(filepath.Join(root,"done","payload")); err != nil { t.Fatal("dry run deleted fixture", err) }
 if err := run([]string{"clean", root, "active", "--delete"}, &out, now); err == nil { t.Fatal("active artifact accepted") }
 if err := run([]string{"clean", root, "unknown", "--delete"}, &out, now); err == nil { t.Fatal("unknown artifact accepted") }
 if err := run([]string{"clean", root, "done", "--delete"}, &out, now); err != nil { t.Fatal(err) }
 if _, err := os.Stat(filepath.Join(root,"done")); !os.IsNotExist(err) { t.Fatal("completed selected fixture remains", err) }
 if _, err := os.Stat(filepath.Join(root,"active")); err != nil { t.Fatal("active fixture removed", err) }
}

func TestRejectExistingRootTraversalAndFutureExpiry(t *testing.T) {
 parent := t.TempDir(); root := filepath.Join(parent,"owned"); var out bytes.Buffer
 now := time.Date(2026, 1, 3, 0, 0, 0, 0, time.UTC)
 if err := run([]string{"init", parent}, &out, now); err == nil { t.Fatal("existing root accepted") }
 if err := run([]string{"init", root}, &out, now); err != nil { t.Fatal(err) }
 if err := run([]string{"create", root, "../escape"}, &out, now); err == nil { t.Fatal("traversal accepted") }
 if err := run([]string{"create", root, "future"}, &out, now); err != nil { t.Fatal(err) }
 if err := run([]string{"finish", root, "future", "2026-02-01T00:00:00Z"}, &out, now); err != nil { t.Fatal(err) }
 if err := run([]string{"clean", root, "future", "--delete"}, &out, now); err == nil { t.Fatal("unexpired artifact accepted") }
}

func TestRejectReparseWithinSelectedArtifact(t *testing.T) {
 parent := t.TempDir(); root := filepath.Join(parent,"owned"); outside := filepath.Join(parent,"outside"); var out bytes.Buffer
 now := time.Date(2026,1,3,0,0,0,0,time.UTC)
 if err := os.Mkdir(outside,0700); err != nil { t.Fatal(err) }
 if err := os.WriteFile(filepath.Join(outside,"keep"), []byte("fixture"),0600); err != nil { t.Fatal(err) }
 if err := run([]string{"init",root},&out,now); err != nil { t.Fatal(err) }
 if err := run([]string{"create",root,"linked"},&out,now); err != nil { t.Fatal(err) }
 if err := os.Symlink(outside,filepath.Join(root,"linked","link")); err != nil { t.Skipf("symlink unavailable: %v",err) }
 if err := run([]string{"finish",root,"linked","2026-01-02T00:00:00Z"},&out,now); err != nil { t.Fatal(err) }
 if err := run([]string{"clean",root,"linked","--delete"},&out,now); err == nil { t.Fatal("reparse accepted") }
 if _,err := os.Stat(filepath.Join(outside,"keep")); err != nil { t.Fatal(err) }
}
