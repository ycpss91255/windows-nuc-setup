package integration_test

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"testing"
	a "windows_setup/script/test/acceptance"
)

func TestGoCoveragePublishedEvidence(t *testing.T) {
	original := files(t, os.Getenv("WINDOWS_SETUP_ARTIFACT_DIR"))
	// These cases deliberately construct optional historical and required-current states.
	var historical map[string]any
	json.Unmarshal(original["summary.json"], &historical)
	delete(historical, "GoCoverage")
	original["summary.json"], _ = json.Marshal(historical)
	r := decode(t, original)
	owned := []string{"windows_setup/script/test/example.go"}
	profile := []byte("mode: set\n" + owned[0] + ":1.1,2.1 8 1\n" + owned[0] + ":3.1,4.1 2 0\n")
	c, canonical, e := a.CreateCoverageEvidence([][]byte{profile}, owned, a.CoverageProvenance{Commit: r.Commit, RunUrl: r.RunUrl, MeasuredAt: r.MeasuredAt, SourceState: "Clean", GoVersion: "go1.27.3", Environment: "Synthetic fixture Go"})
	if e != nil {
		t.Fatal(e)
	}
	data := copyFiles(original)
	data["go_coverage.json"], _ = json.Marshal(c)
	data["go_coverage.out"] = canonical
	var s map[string]any
	json.Unmarshal(data["summary.json"], &s)
	s["GoCoverage"] = c
	data["summary.json"], _ = json.Marshal(s)
	label := "go coverage " + strings.ToLower(r.RefType)
	value := "80.0%"
	left, right := len(label)*7+12, len(value)*7+12
	data["go_coverage.svg"] = []byte(fmt.Sprintf(`<svg xmlns="http://www.w3.org/2000/svg" height="20" width="%d"><rect width="%d" fill="#555"/><rect width="%d" fill="#4c1"/><g font-size="11"><text>%s</text><text>%s</text></g></svg>`, left+right, left, right, label, value))
	if e = a.ValidateGoCoverageReport(reader(data), owned, r.Commit, r.RunUrl, true); e != nil {
		t.Fatal(e)
	}
	if _, e = a.ValidateReport(reader(data), r.Commit, r.RunUrl, false); e != nil {
		t.Fatalf("full report must consume attached coverage: %v", e)
	}
	for _, kind := range []string{"missing", "badge_percent", "summary_disagrees", "stale_run", "profile_hash", "missing_json", "missing_profile", "missing_svg", "bad_svg_namespace", "bad_sidecar_json", "bad_summary_json", "release_attachment"} {
		t.Run(kind, func(t *testing.T) {
			m := copyFiles(data)
			run := r.RunUrl
			switch kind {
			case "missing_json":
				delete(m, "go_coverage.json")
			case "missing_profile":
				delete(m, "go_coverage.out")
			case "missing_svg":
				delete(m, "go_coverage.svg")
			case "bad_svg_namespace":
				m["go_coverage.svg"] = []byte(`<svg xmlns="wrong"/>`)
			case "bad_sidecar_json":
				m["go_coverage.json"] = []byte(`{`)
			case "bad_summary_json":
				m["summary.json"] = []byte(`{`)
			case "release_attachment":
				var q map[string]any
				json.Unmarshal(m["summary.json"], &q)
				q["RefType"] = "Release"
				m["summary.json"], _ = json.Marshal(q)
			case "missing":
				m = original
			case "badge_percent":
				m["go_coverage.svg"] = []byte(strings.ReplaceAll(string(m["go_coverage.svg"]), "80.0%", "99.0%"))
			case "summary_disagrees":
				q := c
				q.Covered = 10
				s["GoCoverage"] = q
				m["summary.json"], _ = json.Marshal(s)
			case "stale_run":
				run += "0"
			case "profile_hash":
				m["go_coverage.out"] = append(m["go_coverage.out"], ' ')
			}
			if e := a.ValidateGoCoverageReport(reader(m), owned, r.Commit, run, true); e == nil {
				t.Fatal("invalid published Go coverage accepted")
			}
		})
	}
	if e = a.ValidateGoCoverageReport(reader(original), owned, r.Commit, r.RunUrl, false); e != nil {
		t.Fatalf("historical evidence must remain optional: %v", e)
	}
}

func TestCoverageCDNRetryIsBounded(t *testing.T) {
	original := files(t, os.Getenv("WINDOWS_SETUP_ARTIFACT_DIR"))
	r := decode(t, original)
	p := portal(t, synthetic(t, original, r.Success, "Branch"))
	calls, sleeps := 0, 0
	_, e := a.VerifyWithRetry(reader(p), readme(), r.Commit, r.RunUrl, base, 3, func() { sleeps++ }, func() error {
		calls++
		if calls < 3 {
			return fmt.Errorf("sidecar not synchronized")
		}
		return nil
	})
	if e != nil || calls != 3 || sleeps != 2 {
		t.Fatalf("coverage validation not part of bounded retry: calls=%d sleeps=%d err=%v", calls, sleeps, e)
	}
}
