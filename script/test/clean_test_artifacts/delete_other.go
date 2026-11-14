//go:build !windows

package main

import (
	"errors"
	"time"
)

func safeDelete(root, name, id string, now time.Time) error {
	return errors.New("deletion unsupported on this platform")
}
