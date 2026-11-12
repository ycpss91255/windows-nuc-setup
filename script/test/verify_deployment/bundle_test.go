package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func Test報表封裝驗證與外層身分(t *testing.T) {
	tag, sha, run := "v0.2.5", strings.Repeat("a", 40), "https://github.com/example/repo/actions/runs/3"
	archive := filepath.Join(t.TempDir(), "report.zip")
	payload := []byte("actual archive bytes")
	if err := os.WriteFile(archive, payload, 0600); err != nil {
		t.Fatal(err)
	}
	a := assetFromBytes("windows_setup_report_"+tag+".zip", payload)
	meta := func(assets []releaseAsset) []byte {
		b, _ := json.Marshal(map[string]any{"tag_name": tag, "draft": false, "immutable": true, "assets": assets})
		return b
	}
	summary, profile := []byte("summary"), []byte("profile")
	old := runReportVerifier
	defer func() { runReportVerifier = old }()
	calls := 0
	origin := "explicit"
	runReportVerifier = func(tool string, args ...string) error {
		calls++
		out := ""
		for i := range args {
			if args[i] == "--output-dir" {
				out = args[i+1]
			}
		}
		if err := os.MkdirAll(filepath.Join(out, "native"), 0700); err != nil {
			return err
		}
		if err := os.WriteFile(filepath.Join(out, "native", "summary.json"), summary, 0600); err != nil {
			return err
		}
		if err := os.WriteFile(filepath.Join(out, "native", "go_coverage.out"), profile, 0600); err != nil {
			return err
		}
		r := map[string]any{"archive_sha256": strings.TrimPrefix(a.Digest, "sha256:"), "archive_size": a.Size, "version": tag, "commit": sha, "run_url": run, "run_attempt": 2, "summary_sha256": strings.TrimPrefix(assetFromBytes("", summary).Digest, "sha256:"), "profile_sha256": strings.TrimPrefix(assetFromBytes("", profile).Digest, "sha256:"), "context_origin": origin}
		b, _ := json.Marshal(r)
		return os.WriteFile(filepath.Join(out, "verified.json"), b, 0600)
	}
	got, err := prepareReleaseBundle(meta([]releaseAsset{a}), tag, sha, run, 2, "trusted", archive)
	if err != nil || got.ArchiveDigest != a.Digest || string(got.Summary) != "summary" || calls != 1 {
		t.Fatalf("valid bundle: %v", err)
	}
	origin = "immutable_archive_manifest"
	if _, err = prepareReleaseBundle(meta([]releaseAsset{a}), tag, sha, run, 2, "trusted", archive); err == nil {
		t.Fatal("拒絕非 explicit 來源")
	}
	origin = "explicit"
	for _, tc := range []struct {
		name    string
		assets  []releaseAsset
		attempt int
		path    string
	}{
		{"混合", []releaseAsset{a, {Name: "quality.json"}}, 2, archive},
		{"重複", []releaseAsset{a, a}, 2, archive},
		{"attempt錯誤", []releaseAsset{a}, 1, archive},
		{"缺archive", []releaseAsset{a}, 2, ""},
		{"錯誤digest", []releaseAsset{{Name: a.Name, Size: a.Size, Digest: "sha256:" + strings.Repeat("b", 64)}}, 2, archive},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if _, e := prepareReleaseBundle(meta(tc.assets), tag, sha, run, tc.attempt, "trusted", tc.path); e == nil {
				t.Fatal(fmt.Sprint("應拒絕 ", tc.name))
			}
		})
	}
}
