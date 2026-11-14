//go:build !windows

package main

import "errors"

func directoryIdentity(path string) (string, error) {
	return "", errors.New("directory identity unsupported on this platform")
}

func canonicalTemp(raw string) (string, string, error) {
	return "", "", errors.New("unsupported platform")
}
