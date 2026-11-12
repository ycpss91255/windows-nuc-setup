//go:build windows

package main

import (
	"fmt"
	"os"
	"path/filepath"
	"syscall"
)

// canonicalSafeParent rejects every reparse-point ancestor before expanding
// ordinary Windows short names. The caller must exclude concurrent writers.
func canonicalSafeParent(path string) (string, error) {
	absolute, err := filepath.Abs(path)
	if err != nil {
		return "", err
	}
	for current := absolute; ; current = filepath.Dir(current) {
		info, err := os.Lstat(current)
		if err != nil {
			return "", err
		}
		attr, ok := info.Sys().(*syscall.Win32FileAttributeData)
		if !ok || !info.IsDir() || attr.FileAttributes&syscall.FILE_ATTRIBUTE_REPARSE_POINT != 0 {
			return "", fmt.Errorf("output parent must not contain reparse points")
		}
		if filepath.Dir(current) == current {
			break
		}
	}
	return filepath.EvalSymlinks(absolute)
}
