package main

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"regexp"
	a "windows_setup/script/test/acceptance"
	c "windows_setup/script/test/repo_coverage"
)

type releaseAsset struct {
	Name   string `json:"name"`
	Digest string `json:"digest"`
	Size   int64  `json:"size"`
}
type releaseMetadata struct {
	Tag       string         `json:"tag_name"`
	Draft     *bool          `json:"draft"`
	Immutable *bool          `json:"immutable"`
	Assets    []releaseAsset `json:"assets"`
}

func verifyTag(read a.Reader, metadata []byte, tag, sha, run string, files []string) error {
	if !regexp.MustCompile(`^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-rc[1-9][0-9]*)?$`).MatchString(tag) {
		return fmt.Errorf("invalid release tag")
	}
	var release releaseMetadata
	if e := json.Unmarshal(metadata, &release); e != nil {
		return e
	}
	if release.Tag != tag || release.Draft == nil || *release.Draft || release.Immutable == nil || !*release.Immutable {
		return fmt.Errorf("release identity or immutable state mismatch")
	}
	assets := map[string]releaseAsset{}
	for _, v := range release.Assets {
		if v.Name == "quality.json" || v.Name == "go_coverage.out" {
			if _, ok := assets[v.Name]; ok {
				return fmt.Errorf("duplicate release evidence")
			}
			assets[v.Name] = v
		}
	}
	for _, n := range []string{"quality.json", "go_coverage.out"} {
		v, ok := assets[n]
		if !ok || v.Size <= 0 || !regexp.MustCompile(`^sha256:[a-f0-9]{64}$`).MatchString(v.Digest) {
			return fmt.Errorf("missing or invalid release evidence: %s", n)
		}
	}
	index, e := read("versions.json")
	if e != nil {
		return e
	}
	var versions []struct{ Version, Status, Path string }
	if e = json.Unmarshal(index, &versions); e != nil {
		return e
	}
	count := 0
	prefix := "versions/" + tag + "/"
	for _, v := range versions {
		if v.Version == tag {
			count++
			if v.Status != "Verified" || v.Path != prefix+"index.html" {
				return fmt.Errorf("release listing invalid")
			}
		}
	}
	if count != 1 {
		return fmt.Errorf("release listing missing or duplicated")
	}
	reader := func(n string) ([]byte, error) { return read(prefix + n) }
	summary, e := reader("summary.json")
	if e != nil {
		return e
	}
	match := func(data []byte, asset releaseAsset) bool {
		sum := sha256.Sum256(data)
		return int64(len(data)) == asset.Size && fmt.Sprintf("sha256:%x", sum) == asset.Digest
	}
	if !match(summary, assets["quality.json"]) {
		return fmt.Errorf("published summary differs from immutable release")
	}
	profile, e := reader("go_coverage.out")
	if e != nil {
		return e
	}
	if !match(profile, assets["go_coverage.out"]) {
		return fmt.Errorf("published profile differs from immutable release")
	}
	report, e := a.ValidateReport(reader, sha, run, false)
	if e != nil {
		return e
	}
	if report.SchemaVersion != 2 || report.RefType != "Release" || report.RefName != tag || report.Version != tag || !report.Success || report.Totals.UnexecutedSuites != 0 {
		return fmt.Errorf("published release report identity mismatch")
	}
	if _, e = a.ValidateRepoCoverageReport(reader, summary, sha, run, true); e != nil {
		return e
	}
	inventory, e := reader("coverage_inventory.json")
	if e != nil {
		return e
	}
	if e = c.ValidateInventory(".", inventory); e != nil {
		return e
	}
	if e = a.ValidateGoCoverageReport(reader, files, sha, run, true); e != nil {
		return e
	}
	return nil
}
