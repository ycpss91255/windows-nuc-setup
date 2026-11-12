package main

import (
	"archive/zip"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"html"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
	a "windows_setup/script/test/acceptance"
	c "windows_setup/script/test/repo_coverage"
)

var nativeNames = []string{"index.html", "summary.json", "summary.md", "junit.xml", "unit.svg", "integration.svg", "coverage.svg", "repo_coverage.json", "coverage_inventory.json", "coverage.xml", "go_coverage.json", "go_coverage.out", "go_coverage.svg"}
var containerNames = []string{"index.html", "summary.json", "summary.md", "junit.xml", "unit.svg", "integration.svg", "coverage.svg"}

const provenanceNote = "CI selects exact run and attempt artifacts; this manifest records supplied context and is not an independent provenance attestation."
const maxFile = 64 << 20
const maxArchive = 256 << 20

type fileRecord struct {
	Path   string `json:"path"`
	Size   int64  `json:"size"`
	SHA256 string `json:"sha256"`
}
type bundleManifest struct {
	SchemaVersion int          `json:"schema_version"`
	Version       string       `json:"version"`
	Commit        string       `json:"commit"`
	RunURL        string       `json:"run_url"`
	RunAttempt    int          `json:"run_attempt"`
	Provenance    string       `json:"provenance"`
	Files         []fileRecord `json:"files"`
}
type options struct {
	native, container, source, version, commit, run, output string
	attempt                                                 int
}

func parseOptions(args []string) (options, error) {
	var o options
	f := flag.NewFlagSet("export", flag.ContinueOnError)
	f.SetOutput(io.Discard)
	f.StringVar(&o.native, "native-dir", "", "")
	f.StringVar(&o.container, "container-dir", "", "")
	f.StringVar(&o.source, "source-root", "", "")
	f.StringVar(&o.version, "version", "", "")
	f.StringVar(&o.commit, "commit", "", "")
	f.StringVar(&o.run, "run-url", "", "")
	f.IntVar(&o.attempt, "run-attempt", 0, "")
	f.StringVar(&o.output, "output", "", "")
	if err := f.Parse(args); err != nil {
		return o, err
	}
	if f.NArg() != 0 {
		return o, errors.New("unexpected argument")
	}
	return o, nil
}
func validateIdentity(o options) (string, error) {
	if !regexp.MustCompile(`^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-rc[1-9][0-9]*)?$`).MatchString(o.version) || !regexp.MustCompile(`^[a-f0-9]{40}$`).MatchString(o.commit) || o.attempt < 1 {
		return "", errors.New("invalid version, commit or attempt")
	}
	m := regexp.MustCompile(`^https://github\.com/[^/]+/[^/]+/actions/runs/([1-9][0-9]*)$`).FindStringSubmatch(o.run)
	if len(m) != 2 {
		return "", errors.New("invalid run URL")
	}
	return m[1], nil
}
func loadReport(dir string, names []string) (map[string][]byte, error) {
	info, e := os.Lstat(dir)
	if e != nil {
		return nil, e
	}
	if !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
		return nil, errors.New("report directory must be a real directory")
	}
	entries, e := os.ReadDir(dir)
	if e != nil {
		return nil, e
	}
	if len(entries) != len(names) {
		return nil, errors.New("report file set mismatch")
	}
	allowed := map[string]bool{}
	for _, n := range names {
		allowed[n] = true
	}
	out := map[string][]byte{}
	for _, entry := range entries {
		if !allowed[entry.Name()] {
			return nil, fmt.Errorf("unexpected report file: %s", entry.Name())
		}
		p := filepath.Join(dir, entry.Name())
		st, e := os.Lstat(p)
		if e != nil {
			return nil, e
		}
		if !st.Mode().IsRegular() || st.Size() < 0 || st.Size() > maxFile {
			return nil, errors.New("invalid report file type or size")
		}
		data, e := os.ReadFile(p)
		if e != nil {
			return nil, e
		}
		if int64(len(data)) != st.Size() {
			return nil, errors.New("report changed during read")
		}
		out[entry.Name()] = data
	}
	return out, nil
}
func reportReader(m map[string][]byte) a.Reader {
	return func(name string) ([]byte, error) {
		b, ok := m[name]
		if !ok {
			return nil, fmt.Errorf("missing report %s", name)
		}
		return b, nil
	}
}
func validateReports(o options, native, container map[string][]byte) error {
	for i, m := range []map[string][]byte{native, container} {
		r, e := a.ValidateReport(reportReader(m), o.commit, o.run, false)
		if e != nil {
			return e
		}
		if r.SchemaVersion != 2 || r.RefType != "Release" || r.RefName != o.version || r.Version != o.version || r.RequestedLayer != "All" || !r.Success || r.Totals.UnexecutedSuites != 0 {
			return errors.New("report release identity or execution state mismatch")
		}
		isContainer := strings.HasPrefix(r.Environment, "Windows container / ")
		if (i == 1) != isContainer {
			return errors.New("report environment mismatch")
		}
		for _, check := range r.Checks {
			if check.Layer != "Static" && check.Layer != "Unit" && check.Layer != "Integration" {
				return errors.New("unexpected report scope")
			}
		}
		if i == 1 && (r.Coverage != "NotMeasured" || r.RepoCoverage != nil) {
			return errors.New("container coverage must remain unmeasured")
		}
	}
	r := reportReader(native)
	if _, e := a.ValidateRepoCoverageReport(r, native["summary.json"], o.commit, o.run, true); e != nil {
		return e
	}
	if e := c.ValidateInventory(o.source, native["coverage_inventory.json"]); e != nil {
		return e
	}
	files, e := a.OwnedGoFiles(o.source)
	if e != nil {
		return e
	}
	if e = a.ValidateGoCoverageReport(r, files, o.commit, o.run, true); e != nil {
		return e
	}
	return nil
}
func sourceClean(o options) error {
	head, e := exec.Command("git", "-C", o.source, "rev-parse", "HEAD").Output()
	if e != nil || strings.TrimSpace(string(head)) != o.commit {
		return errors.New("source commit mismatch")
	}
	status, e := exec.Command("git", "-C", o.source, "status", "--porcelain").Output()
	if e != nil || len(strings.TrimSpace(string(status))) != 0 {
		return errors.New("source must be clean")
	}
	return nil
}
func export(o options) error {
	runID, e := validateIdentity(o)
	if e != nil {
		return e
	}
	if o.native == "" || o.container == "" || o.source == "" || o.output == "" {
		return errors.New("missing export input")
	}
	if filepath.Base(filepath.Clean(o.native)) != "windows-test-reports-"+runID+"-"+strconv.Itoa(o.attempt) || filepath.Base(filepath.Clean(o.container)) != "docker-test-reports-"+runID+"-"+strconv.Itoa(o.attempt) {
		return errors.New("artifact selection context mismatch")
	}
	source, e := filepath.Abs(o.source)
	if e != nil {
		return e
	}
	out, e := filepath.Abs(o.output)
	if e != nil {
		return e
	}
	rel, e := filepath.Rel(source, out)
	if e != nil {
		return e
	}
	if rel == "." || (rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator))) {
		return errors.New("output must be outside source")
	}
	if filepath.Base(out) != "windows_setup_report_"+o.version+".zip" {
		return errors.New("invalid archive name")
	}
	o.source = source
	if e = sourceClean(o); e != nil {
		return e
	}
	native, e := loadReport(o.native, nativeNames)
	if e != nil {
		return e
	}
	container, e := loadReport(o.container, containerNames)
	if e != nil {
		return e
	}
	if e = validateReports(o, native, container); e != nil {
		return e
	}
	files := map[string][]byte{}
	for n, b := range native {
		files["native/"+n] = b
	}
	for n, b := range container {
		files["windows_container/"+n] = b
	}
	files["index.html"] = []byte("<!doctype html><html lang=\"zh-Hant\"><meta charset=\"utf-8\"><title>版本測試報表</title><h1>" + html.EscapeString(o.version) + " 測試報表</h1><p>包含實際執行的單元與隔離整合測試。</p><a href=\"native/index.html\">Windows 原生報表</a> · <a href=\"windows_container/index.html\">Windows 容器報表</a> · <a href=\"report_scope.md\">測試說明</a></html>\n")
	files["report_scope.md"] = []byte("# 版本測試報表\n\n本報表包含同次 Windows 原生與 Windows 容器實際執行的單元及隔離整合測試。原生報表含完整整體及 Go 覆蓋率原始證據；容器報表維持其原始未量測狀態。\n\nCI 依執行及重試次數選取工件；此封裝記錄輸入脈絡，不是獨立來源認證。\n")
	names := make([]string, 0, len(files))
	for n := range files {
		names = append(names, n)
	}
	sort.Strings(names)
	m := bundleManifest{SchemaVersion: 1, Version: o.version, Commit: o.commit, RunURL: o.run, RunAttempt: o.attempt, Provenance: provenanceNote}
	for _, n := range names {
		sum := sha256.Sum256(files[n])
		m.Files = append(m.Files, fileRecord{Path: n, Size: int64(len(files[n])), SHA256: hex.EncodeToString(sum[:])})
	}
	manifest, e := json.MarshalIndent(m, "", "  ")
	if e != nil {
		return e
	}
	files["manifest.json"] = append(manifest, '\n')
	names = append(names, "manifest.json")
	sort.Strings(names)
	f, e := os.OpenFile(out, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if e != nil {
		return e
	}
	ok := false
	defer func() {
		f.Close()
		if !ok {
			os.Remove(out)
		}
	}()
	z := zip.NewWriter(f)
	for _, n := range names {
		h := &zip.FileHeader{Name: n, Method: zip.Deflate}
		h.SetModTime(time.Date(2000, 1, 1, 0, 0, 0, 0, time.UTC))
		w, e := z.CreateHeader(h)
		if e != nil {
			z.Close()
			return e
		}
		if _, e = w.Write(files[n]); e != nil {
			z.Close()
			return e
		}
	}
	if e = z.Close(); e != nil {
		return e
	}
	if e = f.Close(); e != nil {
		return e
	}
	ok = true
	return nil
}
func run() error {
	if len(os.Args) < 2 || os.Args[1] != "export" {
		return errors.New("expected export command")
	}
	o, e := parseOptions(os.Args[2:])
	if e != nil {
		return e
	}
	return export(o)
}
func main() {
	if e := run(); e != nil {
		fmt.Fprintln(os.Stderr, "report bundle:", e)
		os.Exit(1)
	}
}
