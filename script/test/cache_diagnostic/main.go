// cache_diagnostic runs fresh requirement checks with a caller-provided isolated build cache.
package main

import (
	"fmt"
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
func main() {}
