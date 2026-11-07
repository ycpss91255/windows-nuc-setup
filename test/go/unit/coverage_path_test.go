package unit_test

import (
	"runtime"
	"testing"
	a "windows_setup/script/test/acceptance"
)

func TestCoverageExternalVolumes(t *testing.T) {
	source, out := "/source", "/outside"
	if runtime.GOOS == "windows" {
		source, out = `E:\source`, `C:\outside`
	}
	if e := a.CoverageOutputLocation(source, out); e != nil {
		t.Fatalf("external output on another volume rejected: %v", e)
	}
	if e := a.CoverageOutputLocation(source, source); e == nil {
		t.Fatal("source accepted as output")
	}
	if e := a.CoverageOutputLocation(source, source+"/reports"); e == nil {
		t.Fatal("source child accepted as output")
	}
}
