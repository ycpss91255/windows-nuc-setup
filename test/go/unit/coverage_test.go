package unit_test

import (
	"strings"
	"testing"
	a "windows_setup/script/test/acceptance"
)

func TestCoverageUnionAndExactThreshold(t *testing.T) {
	files := []string{"windows_setup/script/test/a.go", "windows_setup/script/test/cli/main.go"}
	first := []byte("mode: set\n" + files[0] + ":1.1,2.1 8 1\n" + files[1] + ":1.1,2.1 2 0\n")
	second := []byte("mode: set\n" + files[0] + ":1.1,2.1 8 0\n" + files[1] + ":1.1,2.1 2 1\n")
	m, e := a.EvaluateCoverage([][]byte{first, second}, files)
	if e != nil || m.Covered != 10 || m.TotalStatements != 10 || m.Percent != 100 {
		t.Fatalf("duplicate blocks must union, not inflate: %+v %v", m, e)
	}
	if _, e := a.EvaluateCoverage([][]byte{first, append(second, []byte(files[0]+":3.1,4.1 1 1\n")...)}, files); e == nil {
		t.Fatal("CLI profile added blocks absent from authoritative test baseline")
	}
	m, e = a.EvaluateCoverage([][]byte{first}, files)
	if e != nil || m.Covered != 8 || m.TotalStatements != 10 {
		t.Fatalf("exact 80 must pass: %+v %v", m, e)
	}
	low := []byte("mode: set\n" + files[0] + ":1.1,2.1 79999 1\n" + files[1] + ":1.1,2.1 20001 0\n")
	if _, e = a.EvaluateCoverage([][]byte{low}, files); e == nil {
		t.Fatal("79.999 must fail even if display rounds to 80")
	}
	if _, e = a.EvaluateCoverage([][]byte{first}, append(files, "windows_setup/script/test/forgotten/main.go")); e == nil {
		t.Fatal("omitted CLI denominator accepted")
	}
	if _, e = a.EvaluateCoverage([][]byte{[]byte(strings.ReplaceAll(string(first), " 8 1", " 0 1"))}, files); e == nil {
		t.Fatal("zero statement block accepted")
	}
}
