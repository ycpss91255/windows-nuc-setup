//go:build windows

package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"unsafe"
)

var createDirectory2 = syscall.NewLazyDLL("kernel32.dll").NewProc("CreateDirectory2W")

func createOwnedDirectory(path, name string, root bool) error {
	parent := filepath.Dir(path)
	vol := filepath.VolumeName(parent)
	current := vol + string(os.PathSeparator)
	parts := strings.Split(strings.TrimPrefix(parent, current), string(os.PathSeparator))
	var held []lockedEntry
	defer func() {
		for i := len(held) - 1; i >= 0; i-- {
			syscall.CloseHandle(held[i].h)
		}
	}()
	lock := func(p string) error {
		x, _, e := openLocked(p, false)
		if e != nil {
			return e
		}
		if !x.dir {
			syscall.CloseHandle(x.h)
			return errors.New("parent is not directory")
		}
		held = append(held, x)
		return nil
	}
	if e := lock(current); e != nil {
		return e
	}
	for _, part := range parts {
		if part != "" {
			current = filepath.Join(current, part)
			if e := lock(current); e != nil {
				return e
			}
		}
	}
	if !root {
		mark, _, e := openLocked(filepath.Join(parent, rootMarker), true)
		if e != nil {
			return e
		}
		defer syscall.CloseHandle(mark.h)
		b, e := readLocked(mark.h)
		if e != nil || mark.dir || string(b) != rootContent {
			return errors.New("invalid root marker")
		}
	}
	if testCreateDirectory2Unavailable {
		return errors.New("atomic directory creation unavailable")
	}
	if e := createDirectory2.Find(); e != nil {
		return fmt.Errorf("atomic directory creation unavailable: %w", e)
	}
	p, e := syscall.UTF16PtrFromString(path)
	if e != nil {
		return e
	}
	h, _, callErr := createDirectory2.Call(uintptr(unsafe.Pointer(p)), 0x00100081, uintptr(syscall.FILE_SHARE_READ), 1, 0)
	if h == uintptr(syscall.InvalidHandle) {
		return fmt.Errorf("atomic directory creation: %w", callErr)
	}
	dir := syscall.Handle(h)
	defer syscall.CloseHandle(dir)
	var info syscall.ByHandleFileInformation
	if e = syscall.GetFileInformationByHandle(dir, &info); e != nil {
		return e
	}
	if info.FileAttributes&syscall.FILE_ATTRIBUTE_REPARSE_POINT != 0 || info.FileAttributes&syscall.FILE_ATTRIBUTE_DIRECTORY == 0 {
		return errors.New("invalid new directory")
	}
	if afterCreateDirectoryHook != nil {
		afterCreateDirectoryHook(path)
	}
	marker, data := rootMarker, []byte(rootContent)
	if !root {
		marker = itemMarker
		id := fmt.Sprintf("%08x:%08x%08x", info.VolumeSerialNumber, info.FileIndexHigh, info.FileIndexLow)
		data, e = json.Marshal(metadata{Kind: "windows_setup_disposable_v1", Name: name, ID: id})
		if e != nil {
			return e
		}
	}
	mp, e := syscall.UTF16PtrFromString(filepath.Join(path, marker))
	if e != nil {
		return e
	}
	mh, e := syscall.CreateFile(mp, syscall.GENERIC_WRITE, syscall.FILE_SHARE_READ, nil, syscall.CREATE_NEW, syscall.FILE_ATTRIBUTE_NORMAL|openReparse, 0)
	if e != nil {
		return e
	}
	defer syscall.CloseHandle(mh)
	var n uint32
	if e = syscall.WriteFile(mh, data, &n, nil); e != nil {
		return e
	}
	if int(n) != len(data) {
		return errors.New("short marker write")
	}
	return syscall.FlushFileBuffers(mh)
}
