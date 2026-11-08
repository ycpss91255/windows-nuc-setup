package main

import (
	"bytes"
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
