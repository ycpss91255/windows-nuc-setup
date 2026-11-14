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
	if err := run([]string{"init", root}, &out, now); err != nil {
		t.Fatal(err)
	}
	if err := run([]string{"create", root, "done"}, &out, now); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "done", "payload"), []byte("fixture"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := run([]string{"finish", root, "done", "2026-01-02T00:00:00Z"}, &out, now); err != nil {
		t.Fatal(err)
	}
	if err := run([]string{"create", root, "active"}, &out, now); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(filepath.Join(root, "unknown"), 0700); err != nil {
		t.Fatal(err)
	}
	out.Reset()
	if err := run([]string{"clean", root, "done"}, &out, now); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out.String(), "done") {
		t.Fatalf("preview missing selection: %q", out.String())
	}
	if _, err := os.Stat(filepath.Join(root, "done", "payload")); err != nil {
		t.Fatal("dry run deleted fixture", err)
	}
	if err := run([]string{"clean", root, "active", "--delete"}, &out, now); err == nil {
		t.Fatal("active artifact accepted")
	}
	if err := run([]string{"clean", root, "unknown", "--delete"}, &out, now); err == nil {
		t.Fatal("unknown artifact accepted")
	}
	if err := run([]string{"clean", root, "done", "--delete"}, &out, now); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(root, "done")); !os.IsNotExist(err) {
		t.Fatal("completed selected fixture remains", err)
	}
	if _, err := os.Stat(filepath.Join(root, "active")); err != nil {
		t.Fatal("active fixture removed", err)
	}
}

func TestRejectExistingRootTraversalAndFutureExpiry(t *testing.T) {
	parent := t.TempDir()
	root := filepath.Join(parent, "owned")
	var out bytes.Buffer
	now := time.Date(2026, 1, 3, 0, 0, 0, 0, time.UTC)
	if err := run([]string{"init", parent}, &out, now); err == nil {
		t.Fatal("existing root accepted")
	}
	if err := run([]string{"init", root}, &out, now); err != nil {
		t.Fatal(err)
	}
	if err := run([]string{"create", root, "../escape"}, &out, now); err == nil {
		t.Fatal("traversal accepted")
	}
	if err := run([]string{"create", root, "future"}, &out, now); err != nil {
		t.Fatal(err)
	}
	if err := run([]string{"finish", root, "future", "2026-02-01T00:00:00Z"}, &out, now); err != nil {
		t.Fatal(err)
	}
	if err := run([]string{"clean", root, "future", "--delete"}, &out, now); err == nil {
		t.Fatal("unexpired artifact accepted")
	}
}

func TestRejectReparseWithinSelectedArtifact(t *testing.T) {
	parent := t.TempDir()
	root := filepath.Join(parent, "owned")
	outside := filepath.Join(parent, "outside")
	var out bytes.Buffer
	now := time.Date(2026, 1, 3, 0, 0, 0, 0, time.UTC)
	if err := os.Mkdir(outside, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(outside, "keep"), []byte("fixture"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := run([]string{"init", root}, &out, now); err != nil {
		t.Fatal(err)
	}
	if err := run([]string{"create", root, "linked"}, &out, now); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(outside, filepath.Join(root, "linked", "link")); err != nil {
		t.Skipf("symlink unavailable: %v", err)
	}
	if err := run([]string{"finish", root, "linked", "2026-01-02T00:00:00Z"}, &out, now); err != nil {
		t.Fatal(err)
	}
	if err := run([]string{"clean", root, "linked", "--delete"}, &out, now); err == nil {
		t.Fatal("reparse accepted")
	}
	if _, err := os.Stat(filepath.Join(outside, "keep")); err != nil {
		t.Fatal(err)
	}
}

func TestCopiedMarkerDoesNotAuthorizeAnotherDirectory(t *testing.T) {
	parent := t.TempDir()
	root := filepath.Join(parent, "owned")
	now := time.Date(2026, 1, 3, 0, 0, 0, 0, time.UTC)
	var out bytes.Buffer
	for _, args := range [][]string{{"init", root}, {"create", root, "original"}, {"finish", root, "original", "2026-01-02T00:00:00Z"}} {
		if err := run(args, &out, now); err != nil {
			t.Fatal(err)
		}
	}
	copied := filepath.Join(root, "unowned")
	if err := os.Mkdir(copied, 0700); err != nil {
		t.Fatal(err)
	}
	marker, err := os.ReadFile(filepath.Join(root, "original", itemMarker))
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(copied, itemMarker), marker, 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(copied, "keep"), []byte("fixture"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := run([]string{"clean", root, "unowned", "--delete"}, &out, now); err == nil {
		t.Fatal("copied marker authorized an unowned directory")
	}
	if _, err := os.Stat(filepath.Join(copied, "keep")); err != nil {
		t.Fatal("unowned data removed", err)
	}
}

func TestReplacedItemWithSameNameDoesNotInheritOwnership(t *testing.T) {
	parent := t.TempDir()
	root := filepath.Join(parent, "owned")
	now := time.Date(2026, 1, 3, 0, 0, 0, 0, time.UTC)
	var out bytes.Buffer
	for _, a := range [][]string{{"init", root}, {"create", root, "item"}, {"finish", root, "item", "2026-01-02T00:00:00Z"}} {
		if err := run(a, &out, now); err != nil {
			t.Fatal(err)
		}
	}
	original := filepath.Join(root, "item")
	marker, err := os.ReadFile(filepath.Join(original, itemMarker))
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Rename(original, filepath.Join(root, "moved")); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(original, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(original, itemMarker), marker, 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(original, "keep"), []byte("fixture"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := run([]string{"clean", root, "item", "--delete"}, &out, now); err == nil {
		t.Fatal("replacement inherited ownership")
	}
	if _, err := os.Stat(filepath.Join(original, "keep")); err != nil {
		t.Fatal("replacement removed", err)
	}
}

func TestDeleteRejectsReplacementAfterValidation(t *testing.T) {
	parent := t.TempDir()
	root := filepath.Join(parent, "owned")
	now := time.Date(2026, 1, 3, 0, 0, 0, 0, time.UTC)
	var out bytes.Buffer
	for _, a := range [][]string{{"init", root}, {"create", root, "item"}, {"finish", root, "item", "2026-01-02T00:00:00Z"}} {
		if err := run(a, &out, now); err != nil {
			t.Fatal(err)
		}
	}
	path := filepath.Join(root, "item")
	replacement := filepath.Join(root, "replacement")
	if err := os.Mkdir(replacement, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(replacement, "keep"), []byte("fixture"), 0600); err != nil {
		t.Fatal(err)
	}
	var swapErr error
	called := false
	beforeDeleteHook = func() {
		called = true
		if swapErr = os.Rename(path, filepath.Join(root, "moved")); swapErr != nil {
			return
		}
		swapErr = os.Rename(replacement, path)
	}
	defer func() { beforeDeleteHook = nil }()
	err := run([]string{"clean", root, "item", "--delete"}, &out, now)
	if !called {
		t.Fatalf("delete hook not reached: %v", err)
	}
	if swapErr == nil {
		if err == nil {
			t.Error("replacement accepted during deletion")
		}
		if _, e := os.Stat(filepath.Join(path, "keep")); e != nil {
			t.Errorf("replacement data removed: %v", e)
		}
	} else if _, e := os.Stat(filepath.Join(replacement, "keep")); e != nil {
		t.Errorf("unmoved replacement data removed: %v", e)
	}
}

func TestConcurrentChildCreationPreservesNewData(t *testing.T) {
	parent := t.TempDir()
	root := filepath.Join(parent, "owned")
	now := time.Date(2026, 1, 3, 0, 0, 0, 0, time.UTC)
	var out bytes.Buffer
	for _, a := range [][]string{{"init", root}, {"create", root, "item"}, {"finish", root, "item", "2026-01-02T00:00:00Z"}} {
		if e := run(a, &out, now); e != nil {
			t.Fatal(e)
		}
	}
	path := filepath.Join(root, "item", "new")
	var createErr error
	called := false
	beforeDeleteHook = func() { called = true; createErr = os.WriteFile(path, []byte("fixture"), 0600) }
	defer func() { beforeDeleteHook = nil }()
	err := run([]string{"clean", root, "item", "--delete"}, &out, now)
	if !called {
		t.Fatalf("hook not reached: %v", err)
	}
	if createErr == nil {
		if err == nil {
			t.Error("accepted concurrent new child")
		}
		if _, e := os.Stat(path); e != nil {
			t.Errorf("concurrent child lost: %v", e)
		}
		if _, e := os.Stat(filepath.Join(root, "item", itemMarker)); e != nil {
			t.Errorf("ownership marker lost after partial deletion: %v", e)
		}
	}
}

func TestEnumeratedChildReplacementIsNotDeleted(t *testing.T) {
	parent := t.TempDir()
	root := filepath.Join(parent, "owned")
	now := time.Date(2026, 1, 3, 0, 0, 0, 0, time.UTC)
	var out bytes.Buffer
	for _, a := range [][]string{{"init", root}, {"create", root, "item"}, {"finish", root, "item", "2026-01-02T00:00:00Z"}} {
		if e := run(a, &out, now); e != nil {
			t.Fatal(e)
		}
	}
	child := filepath.Join(root, "item", "child")
	if e := os.WriteFile(child, []byte("original"), 0600); e != nil {
		t.Fatal(e)
	}
	var swapErr error
	called := false
	afterEnumerateHook = func() {
		if called {
			return
		}
		called = true
		swapErr = os.Rename(child, filepath.Join(root, "moved"))
		if swapErr == nil {
			swapErr = os.WriteFile(child, []byte("replacement"), 0600)
		}
	}
	defer func() { afterEnumerateHook = nil }()
	err := run([]string{"clean", root, "item", "--delete"}, &out, now)
	if !called || swapErr != nil {
		t.Fatalf("swap not performed: called=%v error=%v clean=%v", called, swapErr, err)
	}
	if err == nil {
		t.Error("replacement accepted")
	}
	if b, e := os.ReadFile(child); e != nil || string(b) != "replacement" {
		t.Errorf("replacement lost: %q %v", b, e)
	}
}

func TestConcurrentChildReplacementCannotEscape(t *testing.T) {
	parent := t.TempDir()
	root := filepath.Join(parent, "owned")
	outside := filepath.Join(parent, "outside")
	now := time.Date(2026, 1, 3, 0, 0, 0, 0, time.UTC)
	var out bytes.Buffer
	if e := os.Mkdir(outside, 0700); e != nil {
		t.Fatal(e)
	}
	if e := os.WriteFile(filepath.Join(outside, "keep"), []byte("fixture"), 0600); e != nil {
		t.Fatal(e)
	}
	for _, a := range [][]string{{"init", root}, {"create", root, "item"}, {"finish", root, "item", "2026-01-02T00:00:00Z"}} {
		if e := run(a, &out, now); e != nil {
			t.Fatal(e)
		}
	}
	child := filepath.Join(root, "item", "child")
	if e := os.Mkdir(child, 0700); e != nil {
		t.Fatal(e)
	}
	var swapErr error
	called := false
	beforeDeleteHook = func() {
		called = true
		swapErr = os.Rename(child, filepath.Join(root, "moved"))
		if swapErr == nil {
			swapErr = os.Symlink(outside, child)
		}
	}
	defer func() { beforeDeleteHook = nil }()
	err := run([]string{"clean", root, "item", "--delete"}, &out, now)
	if !called {
		t.Fatalf("hook not reached: %v", err)
	}
	if swapErr == nil && err == nil {
		t.Error("accepted child reparse replacement")
	}
	if _, e := os.Stat(filepath.Join(outside, "keep")); e != nil {
		t.Fatalf("outside fixture changed: %v", e)
	}
}

func TestMarkerChangeAfterReadCannotAuthorizeDelete(t *testing.T) {
	parent := t.TempDir()
	root := filepath.Join(parent, "owned")
	now := time.Date(2026, 1, 3, 0, 0, 0, 0, time.UTC)
	var out bytes.Buffer
	for _, a := range [][]string{{"init", root}, {"create", root, "item"}, {"finish", root, "item", "2026-01-02T00:00:00Z"}} {
		if e := run(a, &out, now); e != nil {
			t.Fatal(e)
		}
	}
	p := filepath.Join(root, "item")
	if e := os.WriteFile(filepath.Join(p, "keep"), []byte("fixture"), 0600); e != nil {
		t.Fatal(e)
	}
	var changeErr error
	called := false
	afterMarkerReadHook = func() { called = true; changeErr = os.WriteFile(filepath.Join(p, itemMarker), []byte("changed"), 0600) }
	defer func() { afterMarkerReadHook = nil }()
	err := run([]string{"clean", root, "item", "--delete"}, &out, now)
	if !called {
		t.Fatalf("hook not reached: %v", err)
	}
	if changeErr == nil {
		if err == nil {
			t.Error("changed marker authorized deletion")
		}
		if _, e := os.Stat(filepath.Join(p, "keep")); e != nil {
			t.Errorf("fixture removed: %v", e)
		}
	}
}
