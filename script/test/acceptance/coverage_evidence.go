package acceptance

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"reflect"
	"regexp"
	"strings"
	"time"
)

type CoverageProvenance struct{ Commit, RunUrl, MeasuredAt, SourceState, GoVersion, Environment string }
type GoCoverage struct {
	SchemaVersion                                                                  int
	Scope, Metric                                                                  string
	Covered, TotalStatements                                                       int
	Percent                                                                        float64
	Threshold                                                                      int
	Commit, RunUrl, MeasuredAt, SourceState, GoVersion, Environment, ProfileSHA256 string
	Packages                                                                       []string
}

func coverageProvenance(p CoverageProvenance) error {
	if !regexp.MustCompile(`^[a-f0-9]{40}$`).MatchString(p.Commit) || p.SourceState != "Clean" || !regexp.MustCompile(`^go\d+\.\d+\.\d+$`).MatchString(p.GoVersion) || strings.TrimSpace(p.Environment) == "" {
		return fmt.Errorf("invalid Go coverage source identity")
	}
	if p.RunUrl != "" && !regexp.MustCompile(`^https://github\.com/[^/]+/[^/]+/actions/runs/\d+$`).MatchString(p.RunUrl) {
		return fmt.Errorf("invalid Go coverage run identity")
	}
	if _, e := time.Parse(time.RFC3339, p.MeasuredAt); e != nil {
		return fmt.Errorf("invalid Go coverage measurement time")
	}
	if regexp.MustCompile(`(?i)([A-Z]:[\\/]|/home/|/Users/)`).MatchString(p.Environment) {
		return fmt.Errorf("private path in Go coverage environment")
	}
	return nil
}
func CreateCoverageEvidence(profiles [][]byte, files []string, p CoverageProvenance) (GoCoverage, []byte, error) {
	c := GoCoverage{}
	if e := coverageProvenance(p); e != nil {
		return c, nil, e
	}
	m, e := EvaluateCoverage(profiles, files)
	if e != nil {
		return c, nil, e
	}
	digest := sha256.Sum256(m.Profile)
	c = GoCoverage{SchemaVersion: 1, Scope: "all-owned-go-including-cli", Metric: "statements", Covered: m.Covered, TotalStatements: m.TotalStatements, Percent: m.Percent, Threshold: 80, Commit: p.Commit, RunUrl: p.RunUrl, MeasuredAt: p.MeasuredAt, SourceState: p.SourceState, GoVersion: p.GoVersion, Environment: p.Environment, ProfileSHA256: hex.EncodeToString(digest[:]), Packages: m.Packages}
	return c, m.Profile, nil
}
func ValidateCoverageEvidence(data, profile []byte, files []string, sha, run string) (GoCoverage, error) {
	var c GoCoverage
	if e := decode(data, &c); e != nil {
		return c, e
	}
	p := CoverageProvenance{c.Commit, c.RunUrl, c.MeasuredAt, c.SourceState, c.GoVersion, c.Environment}
	if e := coverageProvenance(p); e != nil {
		return c, e
	}
	if c.SchemaVersion != 1 || c.Scope != "all-owned-go-including-cli" || c.Metric != "statements" || c.Threshold != 80 || c.Commit != sha || c.RunUrl != run {
		return c, fmt.Errorf("Go coverage scope, threshold or source mismatch")
	}
	digest := sha256.Sum256(profile)
	if c.ProfileSHA256 != hex.EncodeToString(digest[:]) {
		return c, fmt.Errorf("Go coverage profile digest mismatch")
	}
	expected, canonical, e := CreateCoverageEvidence([][]byte{profile}, files, p)
	if e != nil {
		return c, e
	}
	if string(profile) != string(canonical) || !reflect.DeepEqual(c, expected) {
		return c, fmt.Errorf("Go coverage numbers, package list or canonical profile mismatch")
	}
	var raw map[string]json.RawMessage
	if e = json.Unmarshal(data, &raw); e != nil {
		return c, e
	}
	for _, f := range []string{"Covered", "TotalStatements", "Percent", "Threshold"} {
		if v, ok := raw[f]; !ok || string(v) == "null" {
			return c, fmt.Errorf("Go coverage numeric field missing")
		}
	}
	return c, nil
}
