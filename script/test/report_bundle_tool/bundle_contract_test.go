package main

import (
	"archive/zip"
	"bytes"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	a "windows_setup/script/test/acceptance"
	c "windows_setup/script/test/repo_coverage"
)

func syntheticNativeReport(t *testing.T, source string) (map[string][]byte, string, string) {
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
	commitCmd := exec.Command("git", "-C", source, "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-qm", "fixture")
	if out, err := commitCmd.CombinedOutput(); err != nil {
		t.Fatalf("commit fixture: %v %s", err, out)
	}
	commitBytes, err := exec.Command("git", "-C", source, "rev-parse", "HEAD").Output()
	if err != nil {
		t.Fatal(err)
	}
	inv, err := c.ScanInventory(source)
	if err != nil {
		t.Fatal(err)
	}
	if len(inv.Sources) != 1 {
		t.Fatalf("unexpected fixture inventory: %+v", inv)
	}
	inv.Sources[0].ExpectedLines = []int{2}
	sha, runURL := strings.TrimSpace(string(commitBytes)), "https://github.com/example/windows_setup/actions/runs/1"
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

func TestReportBundleExportPreservesValidatedReports(t *testing.T) {
	source := t.TempDir()
	original, sha, runURL := syntheticNativeReport(t, source)
	version := "v0.1.0"
	native := map[string][]byte{}
	for name, data := range original {
		if strings.HasPrefix(name, "main/") {
			native[strings.TrimPrefix(name, "main/")] = append([]byte(nil), data...)
		}
	}
	var summary map[string]any
	if err := json.Unmarshal(native["summary.json"], &summary); err != nil {
		t.Fatal(err)
	}
	summary["RefType"] = "Release"
	summary["RefName"] = version
	summary["Version"] = version
	summary["Environment"] = "Synthetic native fixture"
	owned := []string{"windows_setup/script/test/example/value.go"}
	goEvidence, profile, err := a.CreateCoverageEvidence([][]byte{[]byte("mode: set\n" + owned[0] + ":2.1,2.27 1 1\n")}, owned, a.CoverageProvenance{Commit: sha, RunUrl: runURL, MeasuredAt: "2026-01-01T00:00:00Z", SourceState: "Clean", GoVersion: "go1.27.3", Environment: "Synthetic Go fixture"})
	if err != nil {
		t.Fatal(err)
	}
	summary["GoCoverage"] = goEvidence
	native["summary.json"], _ = json.Marshal(summary)
	native["go_coverage.json"], _ = json.Marshal(goEvidence)
	native["go_coverage.out"] = profile
	for _, name := range []string{"unit", "integration", "coverage"} {
		value, color := "passed", "#4c1"
		if name == "coverage" {
			value, color = "100.0%", "#007ec6"
		}
		label := name + " release"
		l, q := len(label)*7+12, len(value)*7+12
		native[name+".svg"] = []byte(fmt.Sprintf(`<svg xmlns="http://www.w3.org/2000/svg" height="20" width="%d"><rect width="%d" fill="#555"/><rect width="%d" fill="%s"/><g font-size="11"><text>%s</text><text>%s</text></g></svg>`, l+q, l, q, color, label, value))
	}
	label, value := "go coverage release", "100.0%"
	l, q := len(label)*7+12, len(value)*7+12
	native["go_coverage.svg"] = []byte(fmt.Sprintf(`<svg xmlns="http://www.w3.org/2000/svg" height="20" width="%d"><rect width="%d" fill="#555"/><rect width="%d" fill="#4c1"/><g font-size="11"><text>%s</text><text>%s</text></g></svg>`, l+q, l, q, label, value))
	native["index.html"] = append(native["index.html"], []byte(`<details><summary>分項量測明細</summary><p>Go 程式敘述覆蓋率：100.0% · 1/1 statements；全部自有 Go 工具（含 CLI），不含 PowerShell 或第三方程式，不等於整體覆蓋率。</p><a href="go_coverage.json">Go JSON</a><a href="go_coverage.out">Go profile</a></details>`)...)
	native["summary.md"] = append(native["summary.md"], []byte("\nGo 程式敘述覆蓋率（分項）：100.0%；1/1 statements；全部自有 Go 工具含 CLI，不含 PowerShell 或第三方程式，不等於整體覆蓋率。")...)
	container := map[string][]byte{}
	for _, name := range []string{"index.html", "summary.json", "summary.md", "junit.xml", "unit.svg", "integration.svg", "coverage.svg"} {
		container[name] = append([]byte(nil), native[name]...)
	}
	delete(summary, "GoCoverage")
	delete(summary, "RepoCoverage")
	summary["Coverage"] = "NotMeasured"
	summary["Environment"] = "Windows container / Synthetic fixture"
	container["summary.json"], _ = json.Marshal(summary)
	container["index.html"] = original["main/index.html"]
	container["summary.md"] = original["main/summary.md"]
	label, value = "coverage release", "not measured"
	l, q = len(label)*7+12, len(value)*7+12
	container["coverage.svg"] = []byte(fmt.Sprintf(`<svg xmlns="http://www.w3.org/2000/svg" height="20" width="%d"><rect width="%d" fill="#555"/><rect width="%d" fill="#9f9f9f"/><g font-size="11"><text>%s</text><text>%s</text></g></svg>`, l+q, l, q, label, value))
	reader := func(m map[string][]byte) a.Reader {
		return func(name string) ([]byte, error) {
			b, ok := m[name]
			if !ok {
				return nil, fmt.Errorf("missing %s", name)
			}
			return b, nil
		}
	}
	for _, m := range []map[string][]byte{native, container} {
		if _, err := a.ValidateReport(reader(m), sha, runURL, false); err != nil {
			t.Fatalf("fixture report invalid: %v", err)
		}
	}
	if _, err := a.ValidateRepoCoverageReport(reader(native), native["summary.json"], sha, runURL, true); err != nil {
		t.Fatal(err)
	}
	if err := a.ValidateGoCoverageReport(reader(native), owned, sha, runURL, true); err != nil {
		t.Fatal(err)
	}
	root := t.TempDir()
	nativeDir := filepath.Join(root, "windows-test-reports-1-1")
	containerDir := filepath.Join(root, "docker-test-reports-1-1")
	for _, pair := range []struct {
		dir   string
		files map[string][]byte
	}{{nativeDir, native}, {containerDir, container}} {
		if err := os.MkdirAll(pair.dir, 0700); err != nil {
			t.Fatal(err)
		}
		for name, data := range pair.files {
			if err := os.WriteFile(filepath.Join(pair.dir, name), data, 0600); err != nil {
				t.Fatal(err)
			}
		}
	}
	out := filepath.Join(root, "windows_setup_report_v0.1.0.zip")
	cmd := exec.Command("go", "run", ".", "export", "--native-dir", nativeDir, "--container-dir", containerDir, "--source-root", source, "--version", version, "--commit", sha, "--run-url", runURL, "--run-attempt", "1", "--output", out)
	if data, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("valid same-run reports must export: %v\n%s", err, data)
	}
	z, err := zip.OpenReader(out)
	if err != nil {
		t.Fatal(err)
	}
	defer z.Close()
	files := map[string][]byte{}
	for _, f := range z.File {
		r, e := f.Open()
		if e != nil {
			t.Fatal(e)
		}
		var b bytes.Buffer
		_, e = b.ReadFrom(r)
		r.Close()
		if e != nil {
			t.Fatal(e)
		}
		if _, ok := files[f.Name]; ok {
			t.Fatalf("duplicate ZIP entry %s", f.Name)
		}
		files[f.Name] = b.Bytes()
	}
	for _, entry := range []struct {
		prefix string
		files  map[string][]byte
	}{{"native/", native}, {"windows_container/", container}} {
		for name, want := range entry.files {
			if !bytes.Equal(files[entry.prefix+name], want) {
				t.Fatalf("original bytes changed: %s%s", entry.prefix, name)
			}
		}
	}
	for _, name := range []string{"index.html", "report_scope.md", "manifest.json"} {
		if len(files[name]) == 0 {
			t.Fatalf("missing %s", name)
		}
	}
	var manifest struct {
		SchemaVersion int    `json:"schema_version"`
		Version       string `json:"version"`
		Commit        string `json:"commit"`
		RunURL        string `json:"run_url"`
		RunAttempt    int    `json:"run_attempt"`
		Provenance    string `json:"provenance"`
		Files         []struct {
			Path   string `json:"path"`
			Size   int64  `json:"size"`
			SHA256 string `json:"sha256"`
		} `json:"files"`
	}
	if err := json.Unmarshal(files["manifest.json"], &manifest); err != nil {
		t.Fatal(err)
	}
	if manifest.SchemaVersion != 1 || manifest.Version != version || manifest.Commit != sha || manifest.RunURL != runURL || manifest.RunAttempt != 1 || !strings.Contains(manifest.Provenance, "not an independent provenance attestation") {
		t.Fatal("manifest identity or trust boundary mismatch")
	}
	seen := map[string]bool{}
	for _, entry := range manifest.Files {
		data, ok := files[entry.Path]
		if !ok || seen[entry.Path] || entry.Path == "manifest.json" {
			t.Fatalf("invalid manifest entry %s", entry.Path)
		}
		seen[entry.Path] = true
		sum := sha256.Sum256(data)
		if entry.Size != int64(len(data)) || entry.SHA256 != fmt.Sprintf("%x", sum) {
			t.Fatalf("digest mismatch %s", entry.Path)
		}
	}
	if len(seen) != len(files)-1 {
		t.Fatal("manifest does not cover every non-manifest ZIP file")
	}
	verify := func(path string, attempt string) error {
		t.Helper()
		cmd := exec.Command("go", "run", ".", "verify", "--archive", path, "--source-root", source, "--version", version, "--commit", sha, "--run-url", runURL, "--run-attempt", attempt)
		data, err := cmd.CombinedOutput()
		if err != nil {
			return fmt.Errorf("%w: %s", err, data)
		}
		return nil
	}
	if err := verify(out, "1"); err != nil {
		t.Fatalf("valid archive must verify: %v", err)
	}
	for _, kind := range []string{"tampered", "missing", "extra", "traversal", "duplicate", "wrong_attempt"} {
		t.Run(kind, func(t *testing.T) {
			if kind == "wrong_attempt" {
				if err := verify(out, "2"); err == nil {
					t.Fatal("wrong attempt accepted")
				}
				return
			}
			p := filepath.Join(t.TempDir(), "candidate.zip")
			f, e := os.Create(p)
			if e != nil {
				t.Fatal(e)
			}
			w := zip.NewWriter(f)
			for name, data := range files {
				if kind == "missing" && name == "native/summary.json" {
					continue
				}
				if kind == "tampered" && name == "native/summary.json" {
					data = append(append([]byte(nil), data...), ' ')
				}
				entry, e := w.Create(name)
				if e != nil {
					t.Fatal(e)
				}
				if _, e = entry.Write(data); e != nil {
					t.Fatal(e)
				}
			}
			if kind == "extra" || kind == "traversal" || kind == "duplicate" {
				name := "extra.txt"
				if kind == "traversal" {
					name = "../escape"
				}
				if kind == "duplicate" {
					name = "native/summary.json"
				}
				entry, e := w.Create(name)
				if e != nil {
					t.Fatal(e)
				}
				entry.Write([]byte("unexpected"))
			}
			if e = w.Close(); e != nil {
				t.Fatal(e)
			}
			f.Close()
			if err := verify(p, "1"); err == nil {
				t.Fatalf("invalid archive accepted: %s", kind)
			}
		})
	}
}
