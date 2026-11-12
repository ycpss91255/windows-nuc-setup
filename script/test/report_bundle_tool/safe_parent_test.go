package main

import (
	"os"
	"path/filepath"
	"runtime"
	"testing"
	"time"
)

type fakeWindowsInfo struct {
	system    any
	directory bool
}

func (f fakeWindowsInfo) Name() string { return "fixture" }
func (f fakeWindowsInfo) Size() int64  { return 0 }
func (f fakeWindowsInfo) Mode() os.FileMode {
	if f.directory {
		return os.ModeDir
	}
	return 0
}
func (f fakeWindowsInfo) ModTime() time.Time { return time.Time{} }
func (f fakeWindowsInfo) IsDir() bool        { return f.directory }
func (f fakeWindowsInfo) Sys() any           { return f.system }

func TestWindowsDirectoryAttributesFailClosed(t *testing.T) {
	cases := []struct {
		name string
		info os.FileInfo
		want bool
	}{
		{"nil info", nil, false},
		{"file", fakeWindowsInfo{&struct{ FileAttributes uint32 }{}, false}, false},
		{"nil metadata", fakeWindowsInfo{nil, true}, false},
		{"nonpointer", fakeWindowsInfo{struct{ FileAttributes uint32 }{}, true}, false},
		{"nil pointer", fakeWindowsInfo{(*struct{ FileAttributes uint32 })(nil), true}, false},
		{"pointer to nonstruct", fakeWindowsInfo{new(uint32), true}, false},
		{"missing field", fakeWindowsInfo{&struct{ Other uint32 }{}, true}, false},
		{"wrong type", fakeWindowsInfo{&struct{ FileAttributes uint64 }{}, true}, false},
		{"reparse", fakeWindowsInfo{&struct{ FileAttributes uint32 }{0x400}, true}, false},
		{"ordinary", fakeWindowsInfo{&struct{ FileAttributes uint32 }{0x10}, true}, true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := ordinaryWindowsDirectory(tc.info); got != tc.want {
				t.Fatalf("got %v want %v", got, tc.want)
			}
		})
	}
	if runtime.GOOS == "windows" {
		info, err := os.Lstat(t.TempDir())
		if err != nil || !ordinaryWindowsDirectory(info) {
			t.Fatalf("ordinary Windows metadata rejected: %v", err)
		}
	}
}

func TestNonWindowsParentPolicyRetainsLinkRejection(t *testing.T) {
	root, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	if _, err := canonicalSafeParentForOS(root, "linux"); err != nil {
		t.Fatalf("ordinary parent: %v", err)
	}
	link := filepath.Join(t.TempDir(), "link")
	if err := os.Symlink(root, link); err != nil {
		t.Skipf("symlink unavailable: %v", err)
	}
	if _, err := canonicalSafeParentForOS(link, "linux"); err == nil {
		t.Fatal("non-Windows policy accepted link")
	}
}
