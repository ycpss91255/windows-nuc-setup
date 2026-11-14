// cache_diagnostic runs fresh requirement checks with a caller-provided isolated build cache.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"time"
)

type command struct {
	Name              string
	Args              []string
	Artifact, Fixture string
}
type observation struct {
	Name         string `json:"name"`
	Milliseconds int64  `json:"milliseconds"`
}

func samplePlan(native, report, fixture, root, sha, url string) []command {
	return []command{
		{"native_cli", []string{"test", "-count=1", "./test/go/integration", "-run", "^TestCLICommands$"}, native, fixture},
		{"all_go_tests", []string{"test", "-count=1", "./..."}, report, fixture},
		{"requirements", []string{"run", "./script/test/requirements_gate", "--artifact-dir", report, "--source-root", root, "--expected-sha", sha, "--expected-run-url", url}, report, fixture},
		{"coverage_verify", []string{"run", "./script/test/repo_coverage_tool", "verify", "--artifact-dir", report, "--source-root", root, "--expected-sha", sha, "--expected-run-url", url, "--require-complete", "--minimum-percent", "80"}, report, fixture},
	}
}
func runSample(plan []command, run func(command) error) ([]observation, error) {
	result := make([]observation, 0, len(plan))
	for _, c := range plan {
		start := time.Now()
		err := run(c)
		elapsed := time.Since(start).Milliseconds()
		if err != nil {
			return nil, fmt.Errorf("%s failed: %w", c.Name, err)
		}
		result = append(result, observation{c.Name, elapsed})
	}
	return result, nil
}

type configuration struct {
	Native, Report, Fixture, Root, SHA, RunURL, Output, Sample string
	Attempt                                                    int
}

func runDiagnostic(c configuration, execute func(command) error) error {
	if c.Native == "" || c.Report == "" || c.Fixture == "" || c.Root == "" || c.Output == "" || c.Attempt < 1 || !regexp.MustCompile(`^[a-f0-9]{40}$`).MatchString(c.SHA) || !regexp.MustCompile(`^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/actions/runs/[1-9][0-9]*$`).MatchString(c.RunURL) || !regexp.MustCompile(`^(cold|warm)_[1-9][0-9]*$`).MatchString(c.Sample) {
		return fmt.Errorf("complete diagnostic identity is required")
	}
	observations, err := runSample(samplePlan(c.Native, c.Report, c.Fixture, c.Root, c.SHA, c.RunURL), execute)
	if err != nil {
		return err
	}
	value := struct {
		Commit, RunURL, Sample string
		Attempt                int
		Observations           []observation
	}{c.SHA, c.RunURL, c.Sample, c.Attempt, observations}
	data, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		return err
	}
	f, err := os.OpenFile(c.Output, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if err != nil {
		return err
	}
	defer f.Close()
	if _, err = f.Write(data); err != nil {
		return err
	}
	return f.Close()
}
func main() {
	var c configuration
	flag.StringVar(&c.Native, "native", "", "native stage report")
	flag.StringVar(&c.Report, "report", "", "complete report")
	flag.StringVar(&c.Fixture, "fixture", "", "synthetic portal fixture")
	flag.StringVar(&c.Root, "root", "", "same source root")
	flag.StringVar(&c.SHA, "sha", "", "same source commit")
	flag.StringVar(&c.RunURL, "run-url", "", "same run URL")
	flag.StringVar(&c.Output, "output", "", "new timing output")
	flag.StringVar(&c.Sample, "sample", "", "sample label")
	flag.IntVar(&c.Attempt, "attempt", 0, "same run attempt")
	flag.Parse()
	if flag.NArg() != 0 {
		fmt.Fprintln(os.Stderr, "unexpected arguments")
		os.Exit(2)
	}
	err := runDiagnostic(c, func(cmd command) error {
		p := exec.Command("go", cmd.Args...)
		p.Dir = c.Root
		p.Env = append(os.Environ(), "WINDOWS_SETUP_ARTIFACT_DIR="+cmd.Artifact, "WINDOWS_SETUP_PORTAL_FIXTURE_DIR="+cmd.Fixture)
		p.Stdout = os.Stdout
		p.Stderr = os.Stderr
		return p.Run()
	})
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
