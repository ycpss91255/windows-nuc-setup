//go:build !windows

package main

import "testing"

func shortTestPath(t *testing.T, path string) string {
	t.Helper()
	t.Skip("Windows short names only")
	return ""
}
