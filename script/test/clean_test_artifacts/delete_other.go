//go:build !windows

package main

import (
	"errors"
	"time"
)

func safeDelete(root, name, id string, now time.Time) error {
	return errors.New("deletion unsupported on this platform")
}

func safeFinish(root, name, id, expiry string) error {
	return errors.New("finish unsupported on this platform")
}

func createOwnedDirectory(path, name string, root bool) error {
	return errors.New("creation unsupported on this platform")
}
