package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"
	a "windows_setup/script/test/acceptance"
)

func run() error {
	unit := flag.String("unit-profile", "", "compiler test baseline")
	cli := flag.String("cli-profile", "", "instrumented CLI counters")
	root := flag.String("source-root", "", "repository")
	report := flag.String("report-dir", "", "PS public report")
	output := flag.String("output-dir", "", "new external evidence directory")
	flag.Parse()
	if *unit == "" || *cli == "" || *root == "" || *report == "" || *output == "" {
		return fmt.Errorf("five coverage arguments required")
	}
	source, e := filepath.Abs(*root)
	if e != nil {
		return e
	}
	out, e := filepath.Abs(*output)
	if e != nil {
		return e
	}
	if e = a.CoverageOutputLocation(source, out); e != nil {
		return e
	}
	if _, e = os.Stat(out); !os.IsNotExist(e) {
		return fmt.Errorf("coverage output must be a new directory")
	}
	head, e := exec.Command("git", "-C", source, "rev-parse", "HEAD").Output()
	if e != nil {
		return e
	}
	status, e := exec.Command("git", "-C", source, "status", "--porcelain").Output()
	if e != nil {
		return e
	}
	if len(strings.TrimSpace(string(status))) != 0 {
		return fmt.Errorf("coverage requires a clean tracked source checkout")
	}
	b, e := os.ReadFile(filepath.Join(*report, "summary.json"))
	if e != nil {
		return e
	}
	var metadata a.Report
	if e = json.Unmarshal(b, &metadata); e != nil {
		return e
	}
	if metadata.Commit != strings.TrimSpace(string(head)) {
		return fmt.Errorf("PS report and measured source commit differ")
	}
	if _, e = a.ValidateReport(func(n string) ([]byte, error) { return os.ReadFile(filepath.Join(*report, n)) }, metadata.Commit, metadata.RunUrl, false); e != nil {
		return e
	}
	files, e := a.OwnedGoFiles(source)
	if e != nil {
		return e
	}
	first, e := os.ReadFile(*unit)
	if e != nil {
		return e
	}
	second, e := os.ReadFile(*cli)
	if e != nil {
		return e
	}
	evidence, profile, e := a.CreateCoverageEvidence([][]byte{first, second}, files, a.CoverageProvenance{Commit: metadata.Commit, RunUrl: metadata.RunUrl, MeasuredAt: time.Now().UTC().Format(time.RFC3339), SourceState: metadata.SourceState, GoVersion: runtime.Version(), Environment: metadata.Environment + " / " + runtime.Version()})
	if e != nil {
		return e
	}
	data, e := json.MarshalIndent(evidence, "", "  ")
	if e != nil {
		return e
	}
	if e = os.MkdirAll(out, 0700); e != nil {
		return e
	}
	if e = os.WriteFile(filepath.Join(out, "go_coverage.out"), profile, 0600); e != nil {
		return e
	}
	if e = os.WriteFile(filepath.Join(out, "go_coverage.json"), data, 0600); e != nil {
		return e
	}
	fmt.Printf("Go statement coverage %.1f%% (%d/%d), exact threshold 80%% passed\n", evidence.Percent, evidence.Covered, evidence.TotalStatements)
	return nil
}
func main() {
	if e := run(); e != nil {
		fmt.Fprintln(os.Stderr, "Go coverage failed:", e)
		os.Exit(1)
	}
}
