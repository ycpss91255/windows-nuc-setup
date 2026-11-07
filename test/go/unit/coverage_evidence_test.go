package unit_test

import (
	"encoding/json"
	"strings"
	"testing"
	a "windows_setup/script/test/acceptance"
)

func TestCoverageEvidenceTruth(t *testing.T) {
	files := []string{"windows_setup/script/test/a.go", "windows_setup/script/test/cli/main.go"}
	profile := []byte("mode: set\n" + files[0] + ":1.1,2.1 8 1\n" + files[1] + ":1.1,2.1 2 0\n")
	p := a.CoverageProvenance{Commit: strings.Repeat("a", 40), RunUrl: "https://github.com/example/repo/actions/runs/1", MeasuredAt: "2026-11-08T00:00:00Z", SourceState: "Clean", GoVersion: "go1.27.3", Environment: "Synthetic fixture Windows Go"}
	c, canonical, e := a.CreateCoverageEvidence([][]byte{profile}, files, p)
	if e != nil {
		t.Fatal(e)
	}
	low := []byte(strings.ReplaceAll(string(profile), " 8 1", " 8 0"))
	failed, failedProfile, gateErr := a.CreateCoverageEvidence([][]byte{low}, files, p)
	if gateErr == nil || failed.TotalStatements != 10 || failed.Covered != 0 || len(failedProfile) == 0 {
		t.Fatal("failed threshold must retain truthful diagnostic evidence and fail")
	}
	data, _ := json.Marshal(c)
	if c.Percent != 80 || c.Covered != 8 || c.TotalStatements != 10 {
		t.Fatalf("incorrect evidence %+v", c)
	}
	if _, e = a.ValidateCoverageEvidence(data, canonical, files, p.Commit, p.RunUrl); e != nil {
		t.Fatal(e)
	}
	for _, kind := range []string{"stale_sha", "forged_percent", "missing_cli", "profile_tamper", "wrong_scope", "wrong_run", "dirty"} {
		t.Run(kind, func(t *testing.T) {
			q := c
			raw := append([]byte(nil), canonical...)
			list := files
			sha, run := p.Commit, p.RunUrl
			switch kind {
			case "stale_sha":
				sha = strings.Repeat("b", 40)
			case "forged_percent":
				q.Percent = 100
			case "missing_cli":
				list = append(append([]string{}, files...), "windows_setup/script/test/other/main.go")
			case "profile_tamper":
				raw = append(raw, ' ')
			case "wrong_scope":
				q.Scope = "whole-repository"
			case "wrong_run":
				run += "0"
			case "dirty":
				q.SourceState = "Dirty"
			}
			b, _ := json.Marshal(q)
			if _, e := a.ValidateCoverageEvidence(b, raw, list, sha, run); e == nil {
				t.Fatal("invalid coverage evidence accepted")
			}
		})
	}
}
