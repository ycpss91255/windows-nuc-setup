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

func TestGoBadgeExactREADMEURL(t *testing.T) {
	base := "https://example.github.io/site/"
	p, e := a.GoCoverageBadgePath("![Go]("+base+"main/go_coverage.svg?style=actual)", base)
	if e != nil || p != "go_coverage.svg?style=actual" {
		t.Fatalf("exact README target lost: %s %v", p, e)
	}
	for _, doc := range []string{"", "![Go](https://other.example/main/go_coverage.svg)", "![Go](" + base + "main/go_coverage.svg) ![duplicate](" + base + "main/go_coverage.svg)"} {
		if _, e := a.GoCoverageBadgePath(doc, base); e == nil {
			t.Fatal("missing, foreign or duplicate Go badge accepted")
		}
	}
}

func TestMalformedCoverageProfilesRejected(t *testing.T) {
	f := "windows_setup/script/test/a.go"
	valid := "mode: set\n" + f + ":1.1,2.1 1 1\n"
	for _, profile := range []string{"", "mode: mystery\n" + f + ":1.1,2.1 1 1\n", "mode: set\nC:/Users/person/private.go:1.1,2.1 1 1\n", "mode: set\n" + f + ":1.1,2.1 99999999999999999999999999 1\n", "mode: set\n" + f + ":1.1,2.1 1 99999999999999999999999999\n", "mode: set\nwindows_setup/script/test/other.go:1.1,2.1 1 1\n"} {
		if _, e := a.EvaluateCoverage([][]byte{[]byte(profile)}, []string{f}); e == nil {
			t.Fatalf("malformed profile accepted: %q", profile)
		}
	}
	for _, scope := range [][]string{nil, {"windows_setup/script/test/a_test.go"}, {"external/a.go"}} {
		if _, e := a.EvaluateCoverage([][]byte{[]byte(valid)}, scope); e == nil {
			t.Fatal("invalid source scope accepted")
		}
	}
	if _, e := a.EvaluateCoverage([][]byte{[]byte(valid), []byte(strings.ReplaceAll(valid, " 1 1", " 2 1"))}, []string{f}); e == nil {
		t.Fatal("contradictory statements accepted")
	}
}
