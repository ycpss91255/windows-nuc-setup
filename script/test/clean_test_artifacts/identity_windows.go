//go:build windows

package main

import (
	"fmt"
	"syscall"
)

func directoryIdentity(path string) (string, error) {
	p, e := syscall.UTF16PtrFromString(path)
	if e != nil {
		return "", e
	}
	h, e := syscall.CreateFile(p, 0, syscall.FILE_SHARE_READ|syscall.FILE_SHARE_WRITE|syscall.FILE_SHARE_DELETE, nil, syscall.OPEN_EXISTING, syscall.FILE_FLAG_BACKUP_SEMANTICS|0x00200000, 0)
	if e != nil {
		return "", e
	}
	defer syscall.CloseHandle(h)
	var info syscall.ByHandleFileInformation
	if e = syscall.GetFileInformationByHandle(h, &info); e != nil {
		return "", e
	}
	if info.FileAttributes&syscall.FILE_ATTRIBUTE_REPARSE_POINT != 0 || info.FileAttributes&syscall.FILE_ATTRIBUTE_DIRECTORY == 0 {
		return "", fmt.Errorf("directory is reparse or not a directory")
	}
	return fmt.Sprintf("%08x:%08x%08x", info.VolumeSerialNumber, info.FileIndexHigh, info.FileIndexLow), nil
}
