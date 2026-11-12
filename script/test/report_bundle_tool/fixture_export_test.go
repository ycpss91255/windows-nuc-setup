package main

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	a "windows_setup/script/test/acceptance"
)

// The consumer contract drives a separate, opt-in Go test as an external caller.
func TestConsumerFixtureContract(t *testing.T) {
	root := filepath.Join(t.TempDir(), "fixture")
	cmd := exec.Command("go", "test", "-count=1", "-run", "^TestExportSyntheticConsumerFixture$", ".")
	cmd.Env = append(os.Environ(), "WINDOWS_SETUP_BUNDLE_FIXTURE_DIR="+root)
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("generator failed: %v\n%s", err, out)
	}
	for _, name := range []string{"fixture.json", "windows_setup_report_v0.1.0.zip", "source/.git/HEAD"} {
		if _, err := os.Stat(filepath.Join(root, filepath.FromSlash(name))); err != nil {
			t.Errorf("missing fixture output %s: %v", name, err)
		}
	}
}

// TestExportSyntheticConsumerFixture creates private, explicitly synthetic test data.
// Invoke only with a fresh absolute directory in WINDOWS_SETUP_BUNDLE_FIXTURE_DIR.
func TestExportSyntheticConsumerFixture(t *testing.T) {
	root := os.Getenv("WINDOWS_SETUP_BUNDLE_FIXTURE_DIR")
	if root == "" {
		t.Skip("fixture output not requested")
	}
	if !filepath.IsAbs(root) {
		t.Fatal("fixture destination must be absolute")
	}
	root = filepath.Clean(root)
	parent := filepath.Dir(root)
	resolved, err := filepath.EvalSymlinks(parent)
	if err != nil || !sameOutputParent(parent, resolved, runtime.GOOS) {
		t.Fatal("fixture parent must exist and not contain links")
	}
	if err := os.Mkdir(root, 0700); err != nil {
		t.Fatalf("fixture destination must be new: %v", err)
	}
	source := filepath.Join(root, "source")
	if err := os.Mkdir(source, 0700); err != nil {
		t.Fatal(err)
	}
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
	summary["Environment"] = "Windows synthetic native fixture"
	summary["Changes"] = []string{"Synthetic fixture"}
	for _, check := range summary["Checks"].([]any) {
		check.(map[string]any)["ExitCode"] = 0
	}
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
	summary["Environment"] = "Windows container / Windows synthetic fixture"
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

	if err := export(options{native: nativeDir, container: containerDir, source: source, version: version, commit: sha, run: runURL, attempt: 1, output: out}); err != nil {
		t.Fatal(err)
	}
	archive, err := os.ReadFile(out)
	if err != nil {
		t.Fatal(err)
	}
	digest := sha256.Sum256(archive)
	metadata := map[string]any{"kind": "Synthetic", "version": version, "commit": sha, "run_url": runURL, "run_attempt": 1, "archive": "windows_setup_report_v0.1.0.zip", "source": "source", "sha256": fmt.Sprintf("%x", digest), "size": len(archive)}
	data, err := json.MarshalIndent(metadata, "", "  ")
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "fixture.json"), data, 0600); err != nil {
		t.Fatal(err)
	}
}

func TestConsumerFixtureBoundariesAndVerifier(t *testing.T) {
	base := t.TempDir()
	run := func(value string) error {
		cmd := exec.Command("go", "test", "-count=1", "-run", "^TestExportSyntheticConsumerFixture$", ".")
		env := []string{}
		for _, item := range os.Environ() {
			if !strings.HasPrefix(strings.ToUpper(item), "WINDOWS_SETUP_BUNDLE_FIXTURE_DIR=") {
				env = append(env, item)
			}
		}
		if value != "" {
			env = append(env, "WINDOWS_SETUP_BUNDLE_FIXTURE_DIR="+value)
		}
		cmd.Env = env
		out, err := cmd.CombinedOutput()
		if err != nil {
			t.Logf("generator: %s", out)
		}
		return err
	}
	if err := run(""); err != nil {
		t.Fatal(err)
	}
	if entries, _ := os.ReadDir(base); len(entries) != 0 {
		t.Fatal("unset generator wrote output")
	}
	if err := run("relative-fixture"); err == nil {
		t.Fatal("accepted relative destination")
	}
	if err := run(base); err == nil {
		t.Fatal("accepted existing destination")
	}
	link := filepath.Join(t.TempDir(), "linked")
	if err := os.Symlink(base, link); err != nil {
		t.Logf("symlink unavailable: %v", err)
	} else if err := run(filepath.Join(link, "fixture")); err == nil {
		t.Fatal("accepted linked parent")
	}
	root := filepath.Join(base, "generated")
	if err := run(root); err != nil {
		t.Fatal(err)
	}
	if runtime.GOOS == "windows" {
		reportScript, err := filepath.Abs(filepath.Join("..", "test_report.ps1"))
		if err != nil {
			t.Fatal(err)
		}
		ps := exec.Command("powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", `$ErrorActionPreference='Stop'; . $env:FIXTURE_REPORT_SCRIPT; foreach($name in @('windows-test-reports-1-1','docker-test-reports-1-1')) { $r=Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $env:FIXTURE_ROOT ($name+'/summary.json')) | ConvertFrom-Json; Assert-TestReportSnapshot -Report $r -Release }`)
		ps.Env = append(os.Environ(), "FIXTURE_REPORT_SCRIPT="+reportScript, "FIXTURE_ROOT="+root)
		if out, err := ps.CombinedOutput(); err != nil {
			t.Fatalf("PowerShell report contract: %v\n%s", err, out)
		}
	}
	raw, err := os.ReadFile(filepath.Join(root, "fixture.json"))
	if err != nil {
		t.Fatal(err)
	}
	var m struct {
		Kind    string `json:"kind"`
		Version string `json:"version"`
		Commit  string `json:"commit"`
		Archive string `json:"archive"`
		Source  string `json:"source"`
		SHA256  string `json:"sha256"`
		Size    int    `json:"size"`
	}
	if err := json.Unmarshal(raw, &m); err != nil {
		t.Fatal(err)
	}
	if m.Kind != "Synthetic" || m.Source != "source" || m.Archive != "windows_setup_report_v0.1.0.zip" || strings.Contains(string(raw), root) {
		t.Fatalf("bad metadata: %s", raw)
	}
	binary := filepath.Join(t.TempDir(), "bundle.exe")
	build := exec.Command("go", "build", "-o", binary, ".")
	if out, err := build.CombinedOutput(); err != nil {
		t.Fatalf("build: %v %s", err, out)
	}
	args := []string{"verify", "--historical", "--archive", filepath.Join(root, m.Archive), "--source-root", filepath.Join(root, m.Source), "--version", m.Version, "--commit", m.Commit, "--archive-sha256", m.SHA256, "--archive-size", fmt.Sprint(m.Size)}
	if out, err := exec.Command(binary, args...).CombinedOutput(); err != nil {
		t.Fatalf("verifier rejected fixture: %v %s", err, out)
	}
	args[len(args)-3] = strings.Repeat("0", 64)
	if out, err := exec.Command(binary, args...).CombinedOutput(); err == nil {
		t.Fatalf("verifier accepted bad digest: %s", out)
	}
}
