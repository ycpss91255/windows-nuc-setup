package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	a "windows_setup/script/test/acceptance"
	c "windows_setup/script/test/repo_coverage"
)

type deploymentTransport func(*http.Request) (*http.Response, error)

func (f deploymentTransport) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }

type unreadableBadge struct{ closed bool }

func (*unreadableBadge) Read([]byte) (int, error) {
	return 0, errors.New("synthetic badge read failure")
}
func (b *unreadableBadge) Close() error { b.closed = true; return nil }

// This is intentionally synthetic validation input, never measurement evidence.
// Only the compiler profile of the actual run function contributes coverage.
func deploymentPages(t *testing.T, source string) (map[string][]byte, string, string) {
	t.Helper()
	name := "script/test/example/value.go"
	p := filepath.Join(source, filepath.FromSlash(name))
	if err := os.MkdirAll(filepath.Dir(p), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(p, []byte("package example\nfunc Value() int { return 1 }\n"), 0600); err != nil {
		t.Fatal(err)
	}
	for _, args := range [][]string{{"init", "-q"}, {"add", "--", name}} {
		cmd := exec.Command("git", append([]string{"-C", source}, args...)...)
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("synthetic tracked source: %v %s", err, out)
		}
	}
	inv, err := c.ScanInventory(source)
	if err != nil {
		t.Fatal(err)
	}
	if len(inv.Sources) != 1 {
		t.Fatalf("unexpected fixture inventory: %+v", inv)
	}
	inv.Sources[0].ExpectedLines = []int{2}
	sha, runURL := strings.Repeat("a", 40), "https://github.com/example/windows_setup/actions/runs/1"
	stamp := "2026-01-01T00:00:00Z"
	art, err := c.CreateEvidence(inv, []c.Report{{SchemaVersion: 1, Metric: c.Metric, Files: map[string]map[int]bool{name: {2: true}}}}, c.Identity{Commit: sha, RunUrl: runURL, MeasuredAt: stamp, SourceState: "Clean"})
	if err != nil {
		t.Fatal(err)
	}
	var evidence c.Evidence
	if err = json.Unmarshal(art.Summary, &evidence); err != nil {
		t.Fatal(err)
	}
	yes := true
	r := a.Report{SchemaVersion: 2, RequestedLayer: "All", Commit: sha, RunUrl: runURL, SourceState: "Clean", Coverage: "Measured", RefType: "Branch", RefName: "main", Environment: "Synthetic command validation fixture", Version: "v0.1.0", MeasuredAt: stamp, Success: true, RepoCoverage: &evidence, Totals: a.Totals{SuitesExecuted: 2, AssertionsExecuted: 2, AssertionsPassed: 2}}
	for _, layer := range []string{"Unit", "Integration"} {
		r.Checks = append(r.Checks, a.Check{Name: layer, Layer: layer, Status: "Passed", Executed: true, Passed: &yes, Assertions: []a.Assertion{{Name: "synthetic contract", Passed: &yes}}})
	}
	data, err := json.Marshal(r)
	if err != nil {
		t.Fatal(err)
	}
	m := map[string][]byte{"main/summary.json": data, "main/repo_coverage.json": art.Summary, "main/coverage_inventory.json": art.Inventory, "main/coverage.xml": art.XML, "main/junit.xml": []byte(`<testsuites><testsuite name="Unit"><testcase/></testsuite><testsuite name="Integration"><testcase/></testsuite></testsuites>`), "main/summary.md": []byte(sha + " " + stamp), "main/index.html": []byte(`<h2>單元與隔離整合測試通過</h2><a href="summary.json">JSON</a><a href="summary.md">MD</a><a href="junit.xml">JUnit</a>`), "versions.json": []byte(`[]`), "index.html": []byte(`<h1>目前程式檢查通過</h1><h2>整體覆蓋率</h2><p>100.0%（1/1 可執行行）</p><p>aaaaaaa 2026-01-01 00:00:00 UTC</p><a href="main/index.html">結果</a><a href="https://github.com/example/windows_setup/blob/main/readme.md">說明</a>`)}
	for _, n := range []string{"unit", "integration", "coverage"} {
		label, status, color := n+" branch", "passed", "#4c1"
		if n == "coverage" {
			status = "100.0%"
			color = "#007ec6"
		}
		l, q := len(label)*7+12, len(status)*7+12
		m["main/"+n+".svg"] = []byte(fmt.Sprintf(`<svg xmlns="http://www.w3.org/2000/svg" height="20" width="%d"><rect width="%d" fill="#555"/><rect width="%d" fill="%s"/><g font-size="11"><text>%s</text><text>%s</text></g></svg>`, l+q, l, q, color, label, status))
	}
	return m, sha, runURL
}

func TestDeploymentCases(t *testing.T) {
	source := t.TempDir()
	pages, sha, runURL := deploymentPages(t, source)
	previous, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	if err = os.Chdir(source); err != nil {
		t.Fatal(err)
	}
	defer os.Chdir(previous)
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		data, ok := pages[strings.TrimPrefix(r.URL.Path, "/")]
		if !ok {
			http.NotFound(w, r)
			return
		}
		_, _ = w.Write(data)
	}))
	defer server.Close()
	transport := http.DefaultTransport
	defer func() { http.DefaultTransport = transport }()
	trusted := server.Client().Transport
	badgeMode := "valid"
	var unreadable *unreadableBadge
	http.DefaultTransport = deploymentTransport(func(req *http.Request) (*http.Response, error) {
		if req.URL.Host != "github.com" {
			if req.URL.Host != strings.TrimPrefix(server.URL, "https://") {
				return nil, fmt.Errorf("unexpected external request: %s", req.URL.Host)
			}
			return trusted.RoundTrip(req)
		}
		if badgeMode == "network" {
			return nil, errors.New("synthetic GitHub network failure")
		}
		status, body := 200, `<svg xmlns="http://www.w3.org/2000/svg"/>`
		switch badgeMode {
		case "status":
			status = 503
		case "namespace":
			body = `<svg xmlns="urn:wrong"/>`
		case "not_svg":
			body = `<html xmlns="http://www.w3.org/2000/svg"/>`
		case "malformed":
			body = `<svg`
		case "redirect_http", "redirect_loop":
			status = 302
		}
		response := &http.Response{StatusCode: status, Header: make(http.Header), Body: io.NopCloser(strings.NewReader(body)), Request: req}
		if badgeMode == "body" {
			unreadable = &unreadableBadge{}
			response.Body = unreadable
		}
		if badgeMode == "redirect_http" {
			response.Header.Set("Location", "http://github.com/unsafe")
		}
		if badgeMode == "redirect_loop" {
			response.Header.Set("Location", req.URL.String())
		}
		return response, nil
	})
	doc := filepath.Join(t.TempDir(), "readme.md")
	validDoc := "![coverage](" + server.URL + "/main/coverage.svg)\n![CI](https://github.com/example/windows_setup/actions/workflows/windows_tests.yml/badge.svg)\n"
	writeDoc := func(s string) {
		t.Helper()
		if err := os.WriteFile(doc, []byte(s), 0600); err != nil {
			t.Fatal(err)
		}
	}
	writeDoc(validDoc)
	invoke := func(args ...string) error {
		oldFlags, oldArgs := flag.CommandLine, os.Args
		defer func() { flag.CommandLine, os.Args = oldFlags, oldArgs }()
		flag.CommandLine = flag.NewFlagSet("deployment", flag.ContinueOnError)
		flag.CommandLine.SetOutput(io.Discard)
		os.Args = append([]string{"verify_deployment"}, args...)
		return run()
	}
	args := func() []string {
		return []string{"--base-url", server.URL, "--readme", doc, "--expected-sha", sha, "--expected-run-url", runURL}
	}
	t.Setenv("GITHUB_STEP_SUMMARY", "")
	t.Run("tag_public_evidence", func(t *testing.T) {
		oldSleep := deploymentSleep
		deploymentSleep = func(time.Duration) {}
		defer func() { deploymentSleep = oldSleep }()
		tag := "v0.2.4"
		owned := []string{"windows_setup/script/test/example/value.go"}
		goEvidence, profile, err := a.CreateCoverageEvidence([][]byte{[]byte("mode: set\n" + owned[0] + ":2.1,2.27 1 1\n")}, owned, a.CoverageProvenance{Commit: sha, RunUrl: runURL, MeasuredAt: "2026-01-01T00:00:00Z", SourceState: "Clean", GoVersion: "go1.27.3", Environment: "Synthetic tag fixture"})
		if err != nil {
			t.Fatal(err)
		}
		digest := fmt.Sprintf("sha256:%x", sha256.Sum256(profile))
		prefix := "versions/" + tag + "/"
		for n, b := range pages {
			if strings.HasPrefix(n, "main/") {
				pages[prefix+strings.TrimPrefix(n, "main/")] = append([]byte(nil), b...)
			}
		}
		var raw map[string]any
		if err := json.Unmarshal(pages[prefix+"summary.json"], &raw); err != nil {
			t.Fatal(err)
		}
		raw["RefType"] = "Release"
		raw["RefName"] = tag
		raw["Version"] = tag
		raw["GoCoverage"] = goEvidence
		summary, _ := json.Marshal(raw)
		pages[prefix+"summary.json"] = summary
		pages[prefix+"go_coverage.json"], _ = json.Marshal(goEvidence)
		pages[prefix+"go_coverage.out"] = profile
		for _, n := range []string{"unit", "integration", "coverage"} {
			pages[prefix+n+".svg"] = []byte(strings.ReplaceAll(string(pages[prefix+n+".svg"]), n+" branch", n+" release"))
			label := n + " release"
			value := "passed"
			color := "#4c1"
			if n == "coverage" {
				value = "100.0%"
				color = "#007ec6"
			}
			l, q := len(label)*7+12, len(value)*7+12
			pages[prefix+n+".svg"] = []byte(fmt.Sprintf(`<svg xmlns="http://www.w3.org/2000/svg" height="20" width="%d"><rect width="%d" fill="#555"/><rect width="%d" fill="%s"/><g font-size="11"><text>%s</text><text>%s</text></g></svg>`, l+q, l, q, color, label, value))
		}
		label, value := "go coverage release", "100.0%"
		l, q := len(label)*7+12, len(value)*7+12
		pages[prefix+"go_coverage.svg"] = []byte(fmt.Sprintf(`<svg xmlns="http://www.w3.org/2000/svg" height="20" width="%d"><rect width="%d" fill="#555"/><rect width="%d" fill="#4c1"/><g font-size="11"><text>%s</text><text>%s</text></g></svg>`, l+q, l, q, label, value))
		pages[prefix+"index.html"] = append(pages[prefix+"index.html"], []byte(`<details><summary>分項量測明細</summary><p>Go 程式敘述覆蓋率：100.0% · 1/1 statements；全部自有 Go 工具（含 CLI），不含 PowerShell 或第三方程式，不等於整體覆蓋率。</p><a href="go_coverage.json">Go JSON</a><a href="go_coverage.out">Go profile</a></details>`)...)
		pages[prefix+"index.html"] = append(pages[prefix+"index.html"], []byte(`<p>版本 `+tag+` · 提交 <code>`+sha+`</code></p><a href="`+runURL+`">GitHub Actions 執行紀錄</a>`)...)
		pages[prefix+"summary.md"] = append(pages[prefix+"summary.md"], []byte("\nGo 程式敘述覆蓋率（分項）：100.0%；1/1 statements；全部自有 Go 工具含 CLI，不含 PowerShell 或第三方程式，不等於整體覆蓋率。")...)
		metadata := filepath.Join(t.TempDir(), "release.json")
		writeRelease := func(d string) {
			t.Helper()
			sum := sha256.Sum256(pages[prefix+"summary.json"])
			b, _ := json.Marshal(map[string]any{"tag_name": tag, "draft": false, "immutable": true, "assets": []any{map[string]any{"name": "go_coverage.out", "digest": d, "size": len(profile)}, map[string]any{"name": "quality.json", "digest": fmt.Sprintf("sha256:%x", sum), "size": len(pages[prefix+"summary.json"])}}})
			if e := os.WriteFile(metadata, b, 0600); e != nil {
				t.Fatal(e)
			}
		}
		writeRelease(digest)
		pages["versions.json"] = []byte(`[{"Version":"v0.2.4","Status":"Verified","Path":"versions/v0.2.4/index.html"}]`)
		defer func() {
			delete(pages, prefix+"index.html")
			delete(pages, prefix+"summary.json")
			delete(pages, prefix+"go_coverage.out")
			pages["versions.json"] = []byte(`[]`)
		}()
		tagArgs := append(args(), "--mode", "release", "--tag", tag, "--release-metadata", metadata)
		if e := invoke(tagArgs...); e != nil {
			t.Fatalf("valid tag publication rejected: %v", e)
		}
		for _, name := range []string{"index.html", "summary.json", "go_coverage.out"} {
			t.Run("missing_"+name, func(t *testing.T) {
				old := pages[prefix+name]
				delete(pages, prefix+name)
				defer func() { pages[prefix+name] = old }()
				if e := invoke(tagArgs...); e == nil {
					t.Fatal("missing page or evidence accepted")
				}
			})
		}
		for _, kind := range []string{"version", "commit", "run_link", "hidden_version", "hidden_commit", "hidden_run"} {
			t.Run("page_identity_"+kind, func(t *testing.T) {
				old := pages[prefix+"index.html"]
				value := string(old)
				switch kind {
				case "version":
					value = strings.Replace(value, "版本 "+tag, "版本 v9.9.9", 1)
				case "commit":
					value = strings.Replace(value, sha, strings.Repeat("b", 40), 1)
				case "run_link":
					value = strings.Replace(value, runURL, runURL+"0", 1)
				case "hidden_version":
					value = strings.Replace(value, "版本 "+tag, "<!-- 版本 "+tag+" -->", 1)
				case "hidden_commit":
					value = strings.Replace(value, "<code>"+sha+"</code>", "<!-- "+sha+" -->", 1)
				case "hidden_run":
					value = strings.Replace(value, `<a href="`+runURL+`">GitHub Actions 執行紀錄</a>`, `<!-- <a href="`+runURL+`">run</a> -->`, 1)
				}
				if value == string(old) {
					t.Fatal("mutation did not change page")
				}
				pages[prefix+"index.html"] = []byte(value)
				defer func() { pages[prefix+"index.html"] = old }()
				if e := invoke(tagArgs...); e == nil {
					t.Fatal("wrong or hidden page identity accepted")
				}
			})
		}
		t.Run("wrong_source", func(t *testing.T) {
			var changed map[string]any
			json.Unmarshal(summary, &changed)
			changed["Commit"] = strings.Repeat("b", 40)
			pages[prefix+"summary.json"], _ = json.Marshal(changed)
			writeRelease(digest)
			defer func() { pages[prefix+"summary.json"] = summary; writeRelease(digest) }()
			if e := invoke(tagArgs...); e == nil {
				t.Fatal("wrong source accepted")
			}
		})
		t.Run("wrong_run", func(t *testing.T) {
			var changed map[string]any
			json.Unmarshal(summary, &changed)
			changed["RunUrl"] = runURL + "0"
			pages[prefix+"summary.json"], _ = json.Marshal(changed)
			writeRelease(digest)
			defer func() { pages[prefix+"summary.json"] = summary; writeRelease(digest) }()
			if e := invoke(tagArgs...); e == nil {
				t.Fatal("wrong run accepted")
			}
		})
		t.Run("wrong_digest", func(t *testing.T) {
			writeRelease("sha256:" + strings.Repeat("0", 64))
			defer writeRelease(digest)
			if e := invoke(tagArgs...); e == nil {
				t.Fatal("wrong release digest accepted")
			}
		})
		for _, kind := range []string{"draft", "string_immutable", "wrong_tag", "duplicate_asset", "missing_quality"} {
			t.Run("release_"+kind, func(t *testing.T) {
				b, _ := os.ReadFile(metadata)
				var r map[string]any
				json.Unmarshal(b, &r)
				switch kind {
				case "draft":
					r["draft"] = true
				case "string_immutable":
					r["immutable"] = "true"
				case "wrong_tag":
					r["tag_name"] = "v9.9.9"
				case "duplicate_asset":
					a := r["assets"].([]any)
					r["assets"] = append(a, a[0])
				case "missing_quality":
					a := r["assets"].([]any)
					r["assets"] = a[:1]
				}
				v, _ := json.Marshal(r)
				os.WriteFile(metadata, v, 0600)
				defer writeRelease(digest)
				if e := invoke(tagArgs...); e == nil {
					t.Fatal("invalid release metadata accepted")
				}
			})
		}
		t.Run("mutable_release", func(t *testing.T) {
			b, _ := os.ReadFile(metadata)
			var r map[string]any
			json.Unmarshal(b, &r)
			r["immutable"] = false
			v, _ := json.Marshal(r)
			os.WriteFile(metadata, v, 0600)
			defer writeRelease(digest)
			if e := invoke(tagArgs...); e == nil {
				t.Fatal("mutable release accepted")
			}
		})
		t.Run("bounded_retry", func(t *testing.T) {
			old := pages[prefix+"go_coverage.out"]
			delete(pages, prefix+"go_coverage.out")
			defer func() { pages[prefix+"go_coverage.out"] = old }()
			waits := 0
			deploymentSleep = func(time.Duration) { waits++ }
			defer func() { deploymentSleep = func(time.Duration) {} }()
			if e := invoke(tagArgs...); e == nil || waits != 11 {
				t.Fatalf("expected bounded retry: %d %v", waits, e)
			}
		})
		t.Run("below_whole_threshold", func(t *testing.T) {
			inv, e := c.ScanInventory(source)
			if e != nil {
				t.Fatal(e)
			}
			inv.Sources[0].ExpectedLines = []int{2}
			art, e := c.CreateEvidence(inv, []c.Report{{SchemaVersion: 1, Metric: c.Metric, Files: map[string]map[int]bool{"script/test/example/value.go": {2: false}}}}, c.Identity{Commit: sha, RunUrl: runURL, MeasuredAt: "2026-01-01T00:00:00Z", SourceState: "Clean"})
			if e != nil {
				t.Fatal(e)
			}
			keys := []string{"summary.json", "repo_coverage.json", "coverage_inventory.json", "coverage.xml", "coverage.svg"}
			saved := map[string][]byte{}
			for _, k := range keys {
				saved[k] = pages[prefix+k]
			}
			defer func() {
				for k, v := range saved {
					pages[prefix+k] = v
				}
				writeRelease(digest)
			}()
			var x map[string]any
			json.Unmarshal(summary, &x)
			var evidence any
			json.Unmarshal(art.Summary, &evidence)
			x["RepoCoverage"] = evidence
			pages[prefix+"summary.json"], _ = json.Marshal(x)
			pages[prefix+"repo_coverage.json"] = art.Summary
			pages[prefix+"coverage_inventory.json"] = art.Inventory
			pages[prefix+"coverage.xml"] = art.XML
			label, value := "coverage release", "0.0%"
			l, q := len(label)*7+12, len(value)*7+12
			pages[prefix+"coverage.svg"] = []byte(fmt.Sprintf(`<svg xmlns="http://www.w3.org/2000/svg" height="20" width="%d"><rect width="%d" fill="#555"/><rect width="%d" fill="#007ec6"/><g font-size="11"><text>%s</text><text>%s</text></g></svg>`, l+q, l, q, label, value))
			writeRelease(digest)
			if e = invoke(tagArgs...); e == nil || !strings.Contains(e.Error(), "精確80%") {
				t.Fatalf("low whole coverage accepted or failed for wrong reason: %v", e)
			}
		})
		t.Run("below_go_threshold", func(t *testing.T) {
			low, lowProfile, e := a.CreateCoverageEvidence([][]byte{[]byte("mode: set\n" + owned[0] + ":2.1,2.27 2 0\n")}, owned, a.CoverageProvenance{Commit: sha, RunUrl: runURL, MeasuredAt: "2026-01-01T00:00:00Z", SourceState: "Clean", GoVersion: "go1.27.3", Environment: "Synthetic tag fixture"})
			if e == nil {
				t.Fatal("fixture must be below threshold")
			}
			oldSummary, oldJSON, oldProfile := pages[prefix+"summary.json"], pages[prefix+"go_coverage.json"], pages[prefix+"go_coverage.out"]
			defer func() {
				pages[prefix+"summary.json"] = oldSummary
				pages[prefix+"go_coverage.json"] = oldJSON
				pages[prefix+"go_coverage.out"] = oldProfile
				writeRelease(digest)
			}()
			var x map[string]any
			json.Unmarshal(summary, &x)
			x["GoCoverage"] = low
			pages[prefix+"summary.json"], _ = json.Marshal(x)
			pages[prefix+"go_coverage.json"], _ = json.Marshal(low)
			pages[prefix+"go_coverage.out"] = lowProfile
			// Keep immutable outer digests consistent so the failure reaches the real threshold validator.
			oldProfileBytes := profile
			profile = lowProfile
			writeRelease(fmt.Sprintf("sha256:%x", sha256.Sum256(lowProfile)))
			profile = oldProfileBytes
			if e = invoke(tagArgs...); e == nil || !strings.Contains(e.Error(), "below exact threshold") {
				t.Fatalf("low Go coverage accepted or failed for wrong reason: %v", e)
			}
		})
		t.Run("changed_profile", func(t *testing.T) {
			pages[prefix+"go_coverage.out"] = append(append([]byte(nil), profile...), 'x')
			defer func() { pages[prefix+"go_coverage.out"] = profile }()
			if e := invoke(tagArgs...); e == nil {
				t.Fatal("changed profile accepted")
			}
		})
	})
	t.Run("release_parameters_required", func(t *testing.T) {
		if e := invoke(append(args(), "--mode", "release")...); e == nil {
			t.Fatal("missing release inputs accepted")
		}
		if e := invoke(append(args(), "--mode", "unknown")...); e == nil {
			t.Fatal("unknown mode accepted")
		}
	})
	t.Run("required_parameters", func(t *testing.T) {
		if err := invoke(); err == nil || !strings.Contains(err.Error(), "必要") {
			t.Fatalf("missing flags: %v", err)
		}
	})
	t.Run("https_required", func(t *testing.T) {
		a := args()
		a[1] = "http://example.invalid"
		if err := invoke(a...); err == nil || !strings.Contains(err.Error(), "HTTPS") {
			t.Fatalf("HTTP accepted: %v", err)
		}
	})
	t.Run("missing_readme", func(t *testing.T) {
		a := args()
		a[3] = filepath.Join(t.TempDir(), "missing")
		if err := invoke(a...); err == nil {
			t.Fatal("missing readme accepted")
		}
	})
	t.Run("missing_source_tree", func(t *testing.T) {
		if err := os.Chdir(t.TempDir()); err != nil {
			t.Fatal(err)
		}
		defer os.Chdir(source)
		if err := invoke(args()...); err == nil {
			t.Fatal("missing source tree accepted")
		}
	})
	t.Run("full_https_success", func(t *testing.T) {
		if err := invoke(args()...); err != nil {
			t.Fatalf("valid synthetic publication rejected: %v", err)
		}
	})
	t.Run("summary_file", func(t *testing.T) {
		p := filepath.Join(t.TempDir(), "summary.md")
		t.Setenv("GITHUB_STEP_SUMMARY", p)
		if err := invoke(args()...); err != nil {
			t.Fatal(err)
		}
		b, err := os.ReadFile(p)
		if err != nil || !bytes.Contains(b, []byte(sha)) || !bytes.Contains(b, []byte("1/1")) {
			t.Fatalf("summary lacks verified identity/counts: %s %v", b, err)
		}
	})
	t.Run("summary_write_failure", func(t *testing.T) {
		t.Setenv("GITHUB_STEP_SUMMARY", t.TempDir())
		if err := invoke(args()...); err == nil {
			t.Fatal("summary write failure hidden")
		}
	})
	t.Run("missing_ci_badge", func(t *testing.T) {
		writeDoc(strings.Split(validDoc, "\n")[0])
		defer writeDoc(validDoc)
		if err := invoke(args()...); err == nil || !strings.Contains(err.Error(), "唯一") {
			t.Fatalf("missing CI badge: %v", err)
		}
	})
	for _, mode := range []string{"network", "status", "body", "namespace", "not_svg", "malformed", "redirect_http", "redirect_loop"} {
		t.Run("ci_"+mode, func(t *testing.T) {
			badgeMode = mode
			defer func() { badgeMode = "valid" }()
			if err := invoke(args()...); err == nil {
				t.Fatalf("bad CI badge accepted: %s", mode)
			}
			if mode == "body" && (unreadable == nil || !unreadable.closed) {
				t.Fatal("response body was not closed on failed read")
			}
		})
	}
}
