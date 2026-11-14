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
	"time"
	"unsafe"
)

var setFileInformationByHandle = syscall.NewLazyDLL("kernel32.dll").NewProc("SetFileInformationByHandle")

const deleteAccess = 0x00010000
const openReparse = 0x00200000

type lockedEntry struct {
	h    syscall.Handle
	path string
	dir  bool
}

func openLocked(path string, deletable bool) (lockedEntry, string, error) {
	var x lockedEntry
	p, e := syscall.UTF16PtrFromString(path)
	if e != nil {
		return x, "", e
	}
	access := uint32(syscall.GENERIC_READ)
	share := uint32(syscall.FILE_SHARE_READ | syscall.FILE_SHARE_WRITE)
	if deletable {
		access = deleteAccess | syscall.GENERIC_READ
		share = syscall.FILE_SHARE_READ
	}
	h, e := syscall.CreateFile(p, access, share, nil, syscall.OPEN_EXISTING, syscall.FILE_FLAG_BACKUP_SEMANTICS|openReparse, 0)
	if e != nil {
		return x, "", e
	}
	var i syscall.ByHandleFileInformation
	if e = syscall.GetFileInformationByHandle(h, &i); e != nil {
		syscall.CloseHandle(h)
		return x, "", e
	}
	if i.FileAttributes&syscall.FILE_ATTRIBUTE_REPARSE_POINT != 0 {
		syscall.CloseHandle(h)
		return x, "", errors.New("reparse point rejected")
	}
	x = lockedEntry{h: h, path: path, dir: i.FileAttributes&syscall.FILE_ATTRIBUTE_DIRECTORY != 0}
	return x, fmt.Sprintf("%08x:%08x%08x", i.VolumeSerialNumber, i.FileIndexHigh, i.FileIndexLow), nil
}
func readLocked(h syscall.Handle) ([]byte, error) {
	buf := make([]byte, 65537)
	var n uint32
	if err := syscall.ReadFile(h, buf, &n, nil); err != nil {
		return nil, err
	}
	if n > 65536 {
		return nil, errors.New("marker too large")
	}
	return buf[:n], nil
}

func safeDelete(root, name, expectedID string, now time.Time) (result error) {
	abs, e := filepath.Abs(root)
	if e != nil {
		return e
	}
	abs = filepath.Clean(abs)
	// Lock each existing ancestor before opening its descendant so none can be renamed.
	vol := filepath.VolumeName(abs)
	current := vol + string(os.PathSeparator)
	parts := strings.Split(strings.TrimPrefix(abs, current), string(os.PathSeparator))
	var ancestors []lockedEntry
	defer func() {
		for i := len(ancestors) - 1; i >= 0; i-- {
			syscall.CloseHandle(ancestors[i].h)
		}
	}()
	x, _, e := openLocked(current, false)
	if e != nil {
		return e
	}
	ancestors = append(ancestors, x)
	for _, part := range parts {
		if part == "" {
			continue
		}
		current = filepath.Join(current, part)
		x, _, e = openLocked(current, false)
		if e != nil {
			return e
		}
		if !x.dir {
			syscall.CloseHandle(x.h)
			return errors.New("ancestor not directory")
		}
		ancestors = append(ancestors, x)
	}
	anchor, e := os.OpenRoot(abs)
	if e != nil {
		return e
	}
	defer anchor.Close()
	rootMark, _, e := openLocked(filepath.Join(abs, rootMarker), true)
	if e != nil {
		return e
	}
	defer syscall.CloseHandle(rootMark.h)
	if rootMark.dir {
		return errors.New("invalid root marker")
	}
	b, e := readLocked(rootMark.h)
	if e != nil || string(b) != rootContent {
		return errors.New("invalid root marker")
	}
	p := filepath.Join(abs, name)
	first, id, e := openLocked(p, true)
	if e != nil {
		return e
	}
	if !first.dir || id != expectedID {
		syscall.CloseHandle(first.h)
		return errors.New("item identity changed")
	}
	entries := []lockedEntry{first}
	defer func() {
		for _, v := range entries {
			if v.h != syscall.InvalidHandle {
				syscall.CloseHandle(v.h)
			}
		}
	}()
	itemRoot, e := anchor.OpenRoot(name)
	if e != nil {
		return fmt.Errorf("open item root: %w", e)
	}
	defer itemRoot.Close()
	mark, _, e := openLocked(filepath.Join(p, itemMarker), true)
	if e != nil {
		return e
	}
	entries = append(entries, mark)
	if mark.dir {
		return errors.New("invalid item marker")
	}
	b, e = readLocked(mark.h)
	if e != nil {
		return e
	}
	var m metadata
	if json.Unmarshal(b, &m) != nil || m.Kind != "windows_setup_disposable_v1" || m.Name != name || m.ID != id {
		return errors.New("item marker changed")
	}
	markerRemoved := false
	defer func() {
		if result == nil || !markerRemoved {
			return
		}
		f, err := os.OpenFile(filepath.Join(p, itemMarker), os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
		if err == nil {
			_, err = f.Write(b)
			if closeErr := f.Close(); err == nil {
				err = closeErr
			}
		}
		if err != nil {
			result = fmt.Errorf("%w; restore ownership marker: %v", result, err)
		}
	}()
	expiry, e := time.Parse(time.RFC3339, m.Expires)
	if e != nil || now.Before(expiry) {
		return errors.New("item active or not expired")
	}
	if afterMarkerReadHook != nil {
		afterMarkerReadHook()
	}
	var collect func(string) error
	collect = func(dir string) error {
		rel, e := filepath.Rel(p, dir)
		if e != nil {
			return e
		}
		f, e := itemRoot.Open(rel)
		if e != nil {
			return e
		}
		children, e := f.ReadDir(-1)
		f.Close()
		if e != nil {
			return fmt.Errorf("enumerate: %w", e)
		}
		if afterEnumerateHook != nil {
			afterEnumerateHook()
		}
		for _, child := range children {
			if dir == p && child.Name() == itemMarker {
				continue
			}
			q := filepath.Join(dir, child.Name())
			ent, _, e := openLocked(q, true)
			if e != nil {
				return e
			}
			entries = append(entries, ent)
			if ent.dir {
				if e = collect(q); e != nil {
					return e
				}
			}
		}
		return nil
	}
	if e = collect(p); e != nil {
		return e
	}
	if beforeDeleteHook != nil {
		beforeDeleteHook()
	}
	// The handles, including all directories, remain open and deny write/delete sharing.
	// Delete children first, closing each marked handle before its parent.
	itemRoot.Close()
	for i := len(entries) - 1; i >= 0; i-- {
		flag := byte(1)
		ok, _, callErr := setFileInformationByHandle.Call(uintptr(entries[i].h), 4, uintptr(unsafe.Pointer(&flag)), 1)
		if ok == 0 {
			return fmt.Errorf("mark deletion %s: %w", entries[i].path, callErr)
		}
		if e = syscall.CloseHandle(entries[i].h); e != nil {
			return e
		}
		entries[i].h = syscall.InvalidHandle
		if i == 1 {
			markerRemoved = true
		}
	}
	return nil
}
