//go:build !windows

package main

import (
	"errors"
	"path/filepath"
	"runtime"
)

func canonicalSafeParent(path string) (string, error) {
	absolute, err := filepath.Abs(path)
	if err != nil {
		return "", err
	}
	resolved, err := filepath.EvalSymlinks(absolute)
	if err != nil {
		return "", err
	}
	if !sameOutputParent(absolute, resolved, runtime.GOOS) {
		return "", errors.New("output parent must not contain symlinks")
	}
	return resolved, nil
}
