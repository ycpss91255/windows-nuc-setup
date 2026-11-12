//go:build windows

package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"unsafe"
)

func shortTestPath(t *testing.T, path string) string {
	t.Helper()
	input, err := syscall.UTF16PtrFromString(path)
	if err != nil {
		t.Fatal(err)
	}
	buffer := make([]uint16, 32768)
	n, _, callErr := syscall.NewLazyDLL("kernel32.dll").NewProc("GetShortPathNameW").Call(uintptr(unsafe.Pointer(input)), uintptr(unsafe.Pointer(&buffer[0])), uintptr(len(buffer)))
	if n == 0 || n >= uintptr(len(buffer)) {
		t.Skipf("8.3 short path unavailable: %v", callErr)
	}
	short := syscall.UTF16ToString(buffer[:n])
	if strings.EqualFold(filepath.Clean(short), filepath.Clean(path)) {
		t.Skip("8.3 short names unavailable on this volume")
	}
	return short
}

func TestOutputParentRejectsWindowsJunctions(t *testing.T) {
	root := t.TempDir()
	target := filepath.Join(root, "target")
	if err := os.Mkdir(target, 0700); err != nil {
		t.Fatal(err)
	}
	child := filepath.Join(target, "child")
	if err := os.Mkdir(child, 0700); err != nil {
		t.Fatal(err)
	}
	junction := filepath.Join(root, "junction")
	cmd := exec.Command("cmd.exe", "/c", "mklink", "/J", junction, target)
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("create test junction: %v %s", err, out)
	}
	for _, parent := range []string{junction, filepath.Join(junction, "child")} {
		if err := writeVerifiedOutput(filepath.Join(parent, "verified"), nil, map[string][]byte{}, options{}, "explicit"); err == nil {
			t.Fatalf("junction or ancestor accepted: %s", parent)
		}
	}
}
