package main

import (
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"runtime"
)

// Windows reparse points are rejected before ordinary short names are expanded.
// The caller must exclude concurrent writers in its private parent directory.
func canonicalSafeParent(path string) (string, error) {
	return canonicalSafeParentForOS(path, runtime.GOOS)
}

func canonicalSafeParentForOS(path, platform string) (string, error) {
	absolute, err := filepath.Abs(path)
	if err != nil {
		return "", err
	}
	if platform == "windows" {
		for current := absolute; ; current = filepath.Dir(current) {
			info, err := os.Lstat(current)
			if err != nil {
				return "", err
			}
			if !ordinaryWindowsDirectory(info) {
				return "", errors.New("output parent must not contain reparse points")
			}
			if filepath.Dir(current) == current {
				break
			}
		}
		return filepath.EvalSymlinks(absolute)
	}
	resolved, err := filepath.EvalSymlinks(absolute)
	if err != nil {
		return "", err
	}
	if !sameOutputParent(absolute, resolved, platform) {
		return "", errors.New("output parent must not contain symlinks")
	}
	return resolved, nil
}

func ordinaryWindowsDirectory(info os.FileInfo) bool {
	if info == nil || !info.IsDir() {
		return false
	}
	attributes := reflect.ValueOf(info.Sys())
	if !attributes.IsValid() || attributes.Kind() != reflect.Ptr || attributes.IsNil() {
		return false
	}
	attributes = attributes.Elem()
	if attributes.Kind() != reflect.Struct {
		return false
	}
	field := attributes.FieldByName("FileAttributes")
	if !field.IsValid() || !field.CanInterface() || field.Kind() != reflect.Uint32 {
		return false
	}
	const fileAttributeReparsePoint = uint64(0x400)
	return field.Uint()&fileAttributeReparsePoint == 0
}
