package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
)

var legacyEvidence = map[string]bool{"quality.json": true, "quality-manifest.json": true, "index.html": true, "summary.md": true, "junit.xml": true, "unit.svg": true, "integration.svg": true, "system.svg": true, "coverage.svg": true, "repo_coverage.json": true, "coverage_inventory.json": true, "coverage.xml": true, "go_coverage.out": true, "go_coverage.json": true, "go_coverage.svg": true, "summary.json": true}

func classifyReleaseEvidence(assets []releaseAsset, tag string) (string, error) {
	zipName := "windows_setup_report_" + tag + ".zip"
	z, raw := 0, false
	for _, a := range assets {
		if strings.EqualFold(a.Name, zipName) {
			if a.Name != zipName {
				return "", fmt.Errorf("noncanonical report archive")
			}
			z++
		}
		if legacyEvidence[strings.ToLower(a.Name)] {
			raw = true
		}
		if strings.HasPrefix(strings.ToLower(a.Name), "windows_setup_report_") && !strings.EqualFold(a.Name, zipName) {
			return "", fmt.Errorf("foreign report archive")
		}
	}
	if z > 1 || (z > 0 && raw) {
		return "", fmt.Errorf("ambiguous report evidence")
	}
	if z == 1 {
		return "bundle", nil
	}
	return "raw", nil
}
func assetFromBytes(name string, b []byte) releaseAsset {
	h := sha256.Sum256(b)
	return releaseAsset{Name: name, Size: int64(len(b)), Digest: fmt.Sprintf("sha256:%x", h)}
}

var runReportVerifier = func(tool string, args ...string) error {
	b, err := exec.Command(tool, args...).CombinedOutput()
	if err != nil {
		return fmt.Errorf("bundle verifier failed: %v: %s", err, b)
	}
	return nil
}

func prepareReleaseBundle(metadata []byte, tag, sha, run string, attempt int, tool, archive string) (*verifiedBundle, error) {
	var r releaseMetadata
	if err := json.Unmarshal(metadata, &r); err != nil {
		return nil, err
	}
	if r.Tag != tag || r.Draft == nil || *r.Draft || r.Immutable == nil || !*r.Immutable {
		return nil, fmt.Errorf("release identity or immutable state mismatch")
	}
	kind, err := classifyReleaseEvidence(r.Assets, tag)
	if err != nil {
		return nil, err
	}
	if kind == "raw" {
		if archive != "" {
			return nil, fmt.Errorf("archive not declared")
		}
		return nil, nil
	}
	if tool == "" || archive == "" || attempt < 1 {
		return nil, fmt.Errorf("bundle verifier, archive and attempt required")
	}
	var outer releaseAsset
	for _, a := range r.Assets {
		if a.Name == "windows_setup_report_"+tag+".zip" {
			outer = a
		}
	}
	if outer.Size <= 0 || !regexp.MustCompile(`^sha256:[a-f0-9]{64}$`).MatchString(outer.Digest) {
		return nil, fmt.Errorf("invalid archive metadata")
	}
	info, err := os.Lstat(archive)
	if err != nil || !info.Mode().IsRegular() || info.Size() != outer.Size || info.Size() > 256*1024*1024 {
		return nil, fmt.Errorf("invalid archive file")
	}
	payload, err := os.ReadFile(archive)
	if err != nil {
		return nil, err
	}
	actual := assetFromBytes(outer.Name, payload)
	if actual.Size != outer.Size || actual.Digest != outer.Digest {
		return nil, fmt.Errorf("archive digest mismatch")
	}
	parent, err := os.MkdirTemp("", "tag-report-verify-")
	if err != nil {
		return nil, err
	}
	defer os.RemoveAll(parent)
	out := filepath.Join(parent, "verified")
	if err := runReportVerifier(tool, "verify", "--archive", archive, "--output-dir", out, "--source-root", ".", "--version", tag, "--commit", sha, "--run-url", run, "--run-attempt", strconv.Itoa(attempt)); err != nil {
		return nil, err
	}
	b, err := os.ReadFile(filepath.Join(out, "verified.json"))
	if err != nil {
		return nil, err
	}
	var v struct {
		ArchiveSHA256 string `json:"archive_sha256"`
		ArchiveSize   int64  `json:"archive_size"`
		Version       string `json:"version"`
		Commit        string `json:"commit"`
		RunURL        string `json:"run_url"`
		RunAttempt    int    `json:"run_attempt"`
		SummarySHA256 string `json:"summary_sha256"`
		ProfileSHA256 string `json:"profile_sha256"`
		ContextOrigin string `json:"context_origin"`
	}
	d := json.NewDecoder(bytes.NewReader(b))
	d.DisallowUnknownFields()
	if err = d.Decode(&v); err != nil {
		return nil, err
	}
	if d.Decode(new(any)) != io.EOF {
		return nil, fmt.Errorf("invalid verifier receipt")
	}
	if v.ArchiveSHA256 != strings.TrimPrefix(outer.Digest, "sha256:") || v.ArchiveSize != outer.Size || v.Version != tag || v.Commit != sha || v.RunURL != run || v.RunAttempt != attempt || v.ContextOrigin != "explicit" {
		return nil, fmt.Errorf("verifier receipt identity mismatch")
	}
	summary, err := os.ReadFile(filepath.Join(out, "native", "summary.json"))
	if err != nil {
		return nil, err
	}
	profile, err := os.ReadFile(filepath.Join(out, "native", "go_coverage.out"))
	if err != nil {
		return nil, err
	}
	if assetFromBytes("", summary).Digest != "sha256:"+v.SummarySHA256 || assetFromBytes("", profile).Digest != "sha256:"+v.ProfileSHA256 {
		return nil, fmt.Errorf("verified output mismatch")
	}
	return &verifiedBundle{Summary: summary, Profile: profile, ArchiveDigest: outer.Digest}, nil
}
