package integration_test

import (
	"encoding/json"
	"encoding/xml"
	"fmt"
	"os"
	"strings"
	"testing"
	a "windows_setup/script/test/acceptance"
	c "windows_setup/script/test/repo_coverage"
)

func TestSyntheticCoverageBadgeState(t *testing.T) {
	percent := 80.8631695809
	for _, tc := range []struct {
		name         string
		evidence     *c.Evidence
		schema       int
		value, color string
	}{
		{"complete", &c.Evidence{Result: c.Result{Complete: true, Percent: &percent}}, 2, "80.9%", "#007ec6"},
		{"incomplete", &c.Evidence{Result: c.Result{Complete: false, Missing: []string{"core/missing.ps1"}}}, 2, "not measured", "#9f9f9f"},
		{"legacy_without_repo_evidence", nil, 1, "not measured", "#9f9f9f"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			r := a.Report{SchemaVersion: tc.schema, RefType: "Branch", Commit: strings.Repeat("a", 40), RunUrl: "https://github.com/example/repo/actions/runs/1", RepoCoverage: tc.evidence}
			before, _ := json.Marshal(r)
			data := badge(r, "coverage")
			if err := a.ValidateSVG(data, r, "coverage"); err != nil {
				t.Fatalf("synthetic coverage badge rejects its own evidence state: %v", err)
			}
			var svg struct {
				Width string `xml:"width,attr"`
				Rects []struct {
					Width string `xml:"width,attr"`
					Fill  string `xml:"fill,attr"`
				} `xml:"rect"`
				Group struct {
					Texts []string `xml:"text"`
				} `xml:"g"`
			}
			if err := xml.Unmarshal(data, &svg); err != nil {
				t.Fatal(err)
			}
			if len(svg.Rects) != 2 || len(svg.Group.Texts) != 2 || svg.Group.Texts[0] != "coverage branch" || svg.Group.Texts[1] != tc.value || svg.Rects[1].Fill != tc.color || svg.Width != fmt.Sprint((len("coverage branch")+len(tc.value))*7+24) {
				t.Fatalf("wrong synthetic geometry/status/color: %s", data)
			}
			after, _ := json.Marshal(r)
			if string(before) != string(after) {
				t.Fatal("badge rendering changed the source report/evidence")
			}
		})
	}
}

func TestSyntheticKeepsActualCoverageIdentity(t *testing.T) {
	original := files(t, os.Getenv("WINDOWS_SETUP_ARTIFACT_DIR"))
	before := decode(t, original)
	generated := synthetic(t, original, true, "Branch")
	after := decode(t, generated)
	want, _ := json.Marshal(before.RepoCoverage)
	got, _ := json.Marshal(after.RepoCoverage)
	if string(want) != string(got) || before.Commit != after.Commit || before.RunUrl != after.RunUrl {
		t.Fatal("synthetic fixture changed actual coverage counters or source identity")
	}
	if err := a.ValidateSVG(generated["coverage.svg"], after, "coverage"); err != nil {
		t.Fatalf("actual artifact must retain its coverage state in the synthetic badge: %v", err)
	}
}
