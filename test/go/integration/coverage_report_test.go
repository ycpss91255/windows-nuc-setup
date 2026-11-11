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
	label := "go coverage"
	value := "80.0%"
	left, right := len(label)*7+12, len(value)*7+12
	data["go_coverage.svg"] = []byte(fmt.Sprintf(`<svg xmlns="http://www.w3.org/2000/svg" height="20" width="%d" aria-label="go coverage branch: 80.0%%"><title>go coverage branch: 80.0%%</title><defs><linearGradient id="s" x2="0" y2="100%%"><stop offset="0" stop-color="#bbb" stop-opacity=".1"/><stop offset="1" stop-opacity=".1"/></linearGradient><clipPath id="r"><rect width="%d" height="20" rx="3" fill="#fff"/></clipPath></defs><g clip-path="url(#r)"><rect width="%d" height="20" fill="#555"/><rect x="%d" width="%d" height="20" fill="#97ca00"/><rect width="%d" height="20" fill="url(#s)"/></g><g fill="#fff" font-family="DejaVu Sans,Verdana,Geneva,sans-serif" font-size="11" text-anchor="middle"><text x="%d" y="15" fill="#010101" fill-opacity=".3">%s</text><text x="%d" y="14">%s</text><text x="%d" y="15" fill="#010101" fill-opacity=".3">%s</text><text x="%d" y="14">%s</text></g></svg>`, left+right, left+right, left, left, right, left+right, left/2, label, left/2, label, left+right/2, value, left+right/2, value))
	goBlock := `<h2>Go 程式敘述覆蓋率</h2><p>80.0% · 8/10 statements；全部自有 Go 工具（含 CLI），不含 PowerShell 或第三方程式。</p><p>PowerShell 覆蓋率：尚未量測</p><a href="go_coverage.json">Go JSON</a><a href="go_coverage.out">Go profile</a>`
	if r.SchemaVersion == 2 {
		goBlock = `<details><summary>分項量測明細</summary><p>Go 程式敘述覆蓋率：80.0% · 8/10 statements；全部自有 Go 工具（含 CLI），不含 PowerShell 或第三方程式，不等於整體覆蓋率。</p><a href="go_coverage.json">Go JSON</a><a href="go_coverage.out">Go profile</a></details>`
	}
	data["index.html"] = append(data["index.html"], []byte(goBlock)...)
	data["summary.md"] = append(data["summary.md"], []byte("\nGo 程式敘述覆蓋率：80.0%；全部自有 Go 工具（含 CLI），不含 PowerShell 或第三方程式。\nGo statements: 8/10；PowerShell 覆蓋率未量測。")...)
	if r.SchemaVersion == 2 {
		data["summary.md"] = append(data["summary.md"], []byte("\nGo 程式敘述覆蓋率（分項）：80.0%；8/10 statements；全部自有 Go 工具含 CLI，不含 PowerShell 或第三方程式，不等於整體覆蓋率。")...)
	}
	if e = a.ValidateGoCoverageReport(reader(data), owned, r.Commit, r.RunUrl, true); e != nil {
		t.Fatal(e)
	}
	legacy := copyFiles(data)
	oldLabel := "go coverage " + strings.ToLower(r.RefType)
	legacy["go_coverage.svg"] = []byte(fmt.Sprintf(`<svg xmlns="http://www.w3.org/2000/svg" height="20" width="%d"><rect width="%d" fill="#555"/><rect width="%d" fill="#4c1"/><g font-size="11"><text>%s</text><text>%s</text></g></svg>`, (len(oldLabel)+len(value))*7+24, len(oldLabel)*7+12, len(value)*7+12, oldLabel, value))
	if e := a.ValidateGoCoverageReport(reader(legacy), owned, r.Commit, r.RunUrl, true); e != nil {
		t.Fatalf("recorded historical badge must remain valid: %v", e)
	}
	for _, change := range [][2]string{{`rx="3"`, `rx="0"`}, {`y="15"`, `y="14"`}, {`#97ca00`, `#4c1`}, {`stop-color="#bbb"`, `stop-color="#fff"`}, {`font-size="11"`, `font-size="12"`}, {`fill-opacity=".3"`, `fill-opacity=".8"`}, {`clip-path="url(#r)"`, `clip-path="url(#bad)"`}, {`aria-label="go coverage branch: 80.0%"`, `aria-label="go coverage release: 80.0%"`}, {`x="44"`, `x="45"`}} {
		bad := copyFiles(data)
		bad["go_coverage.svg"] = []byte(strings.ReplaceAll(string(bad["go_coverage.svg"]), change[0], change[1]))
		if e := a.ValidateGoCoverageReport(reader(bad), owned, r.Commit, r.RunUrl, true); e == nil {
			t.Fatalf("invalid flat badge accepted: %v", change)
		}
	}
	if _, e = a.ValidateReport(reader(data), r.Commit, r.RunUrl, false); e != nil {
		t.Fatalf("full report must consume attached coverage: %v", e)
	}
	for _, kind := range []string{"missing", "badge_percent", "summary_disagrees", "stale_run", "profile_hash", "missing_json", "missing_profile", "missing_svg", "bad_svg_namespace", "bad_sidecar_json", "bad_summary_json", "release_attachment", "missing_visible_go", "hidden_go", "html_fraction", "md_percent", "profile_link"} {
		t.Run(kind, func(t *testing.T) {
			m := copyFiles(data)
			run := r.RunUrl
			switch kind {
			case "missing_visible_go":
				m["index.html"] = []byte(strings.ReplaceAll(string(m["index.html"]), goBlock, ""))
			case "hidden_go":
				m["index.html"] = []byte(strings.ReplaceAll(string(m["index.html"]), goBlock, "<details><summary>Hidden</summary>"+goBlock+"</details>"))
			case "html_fraction":
				m["index.html"] = []byte(strings.ReplaceAll(string(m["index.html"]), "8/10 statements", "9/10 statements"))
			case "md_percent":
				m["summary.md"] = []byte(strings.ReplaceAll(string(m["summary.md"]), "80.0%", "99.0%"))
			case "profile_link":
				m["index.html"] = []byte(strings.ReplaceAll(string(m["index.html"]), `href="go_coverage.out"`, `href="wrong.out"`))
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
