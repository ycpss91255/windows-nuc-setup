package main

import (
	"testing"
	rc "windows_setup/script/test/repo_coverage"
)

func TestTimingRosterRequiresEveryActualWorkerOnce(t *testing.T) {
	contexts := []rc.PowerShellWorkerContext{
		{Commit: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", RunUrl: "https://github.com/example/repo/actions/runs/123", RunAttempt: 1, GlobalIndex: 0, TestFile: "test/a.ps1", TestSHA256: "a", ProcessId: 10},
		{Commit: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", RunUrl: "https://github.com/example/repo/actions/runs/123", RunAttempt: 1, GlobalIndex: 1, TestFile: "test/b.ps1", TestSHA256: "b", ProcessId: 11},
	}
	phases := []timingPhase{{"startup", 1}, {"pester_instrumentation_and_test", 2}, {"serialization", 3}}
	good := []timingReceipt{{1, contexts[0], phases}, {1, contexts[1], phases}}
	if err := validateTimingRoster(contexts, good); err != nil {
		t.Fatal(err)
	}
	cases := map[string][]timingReceipt{
		"missing": good[:1], "duplicate": {good[0], good[0]},
		"wrong_attempt":   {good[0], {1, rc.PowerShellWorkerContext{RunAttempt: 2, GlobalIndex: 1}, phases}},
		"wrong_suite":     {good[0], {1, rc.PowerShellWorkerContext{GlobalIndex: 1, TestFile: "other"}, phases}},
		"negative":        {good[0], {1, contexts[1], []timingPhase{{"startup", -1}, {"pester_instrumentation_and_test", 2}, {"serialization", 3}}}},
		"duplicate_phase": {good[0], {1, contexts[1], []timingPhase{{"startup", 1}, {"startup", 2}, {"serialization", 3}}}},
	}
	for name, receipts := range cases {
		t.Run(name, func(t *testing.T) {
			if err := validateTimingRoster(contexts, receipts); err == nil {
				t.Fatal("accepted invalid receipt set")
			}
		})
	}
}
