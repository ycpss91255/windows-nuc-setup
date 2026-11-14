package main

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
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

func TestReadWorkerTimingsUsesOnlyExpectedFilesAndRejectsTampering(t *testing.T) {
	dir := t.TempDir()
	c := rc.PowerShellWorkerContext{Commit: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", RunUrl: "https://github.com/example/repo/actions/runs/123", RunAttempt: 1, GlobalIndex: 0, TestFile: "test/a.ps1", TestSHA256: "a", ProcessId: 10}
	good := timingReceipt{1, c, []timingPhase{{"startup", 1}, {"pester_instrumentation_and_test", 2}, {"serialization", 3}}}
	raw, _ := json.Marshal(good)
	path := filepath.Join(dir, "worker_0.timing.json")
	if err := os.WriteFile(path, raw, 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := readWorkerTimings(dir, []rc.PowerShellWorkerContext{c}); err != nil {
		t.Fatal(err)
	}
	for _, bad := range [][]byte{[]byte(`{}`), append(append([]byte{}, raw...), []byte(` {}`)...), bytes.Replace(raw, []byte(`"RunAttempt":1`), []byte(`"RunAttempt":2`), 1), bytes.Replace(raw, []byte(`"SchemaVersion":1`), []byte(`"SchemaVersion":1,"Unexpected":"private"`), 1)} {
		if err := os.WriteFile(path, bad, 0600); err != nil {
			t.Fatal(err)
		}
		if _, err := readWorkerTimings(dir, []rc.PowerShellWorkerContext{c}); err == nil {
			t.Fatal("accepted tampered input")
		}
	}
	if err := os.Remove(path); err != nil {
		t.Fatal(err)
	}
	if _, err := readWorkerTimings(dir, []rc.PowerShellWorkerContext{c}); err == nil {
		t.Fatal("accepted missing input")
	}
}

func TestShardPackExportsTimingOnlyAfterWorkerIdentityValidation(t *testing.T) {
	root, manifest, sha := shardCLIFixture(t)
	dir := filepath.Join(t.TempDir(), "safe")
	writeShardCLIProof(t, root, dir, 123, true)
	bindShardCLIProof(t, root, dir, sha, 0, 2, 1)
	data, err := os.ReadFile(filepath.Join(dir, "worker_0.json"))
	if err != nil {
		t.Fatal(err)
	}
	var worker struct{ Context rc.PowerShellWorkerContext }
	if err = json.Unmarshal(data, &worker); err != nil {
		t.Fatal(err)
	}
	private := t.TempDir()
	timing := timingReceipt{1, worker.Context, []timingPhase{{"startup", 1}, {"pester_instrumentation_and_test", 2}, {"serialization", 3}}}
	data, _ = json.Marshal(timing)
	if err = os.WriteFile(filepath.Join(private, "worker_0.timing.json"), data, 0600); err != nil {
		t.Fatal(err)
	}
	output := filepath.Join(t.TempDir(), "timing")
	args := append(shardCLIArgs(root, manifest, sha), "--shard-index", "0", "--evidence-dir", dir, "--timing-input-dir", private, "--timing-output-dir", output)
	if err = powershellShardPack(args, &bytes.Buffer{}); err != nil {
		t.Fatal(err)
	}
	if _, err = os.Stat(filepath.Join(output, "timing.json")); err != nil {
		t.Fatal(err)
	}
}
