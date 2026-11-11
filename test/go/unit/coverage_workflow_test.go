package unit_test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func coverageJob(text, name string) string {
	lines := strings.Split(text, "\n")
	active := false
	out := []string{}
	for _, line := range lines {
		if strings.TrimSpace(line) == name+":" && strings.HasPrefix(line, "  ") && !strings.HasPrefix(line, "   ") {
			active = true
			continue
		}
		if active && strings.HasPrefix(line, "  ") && !strings.HasPrefix(line, "   ") && strings.HasSuffix(strings.TrimSpace(line), ":") {
			break
		}
		if active {
			out = append(out, line)
		}
	}
	return strings.Join(out, "\n")
}
func TestCIWholeCoverageHasProducerAndStrictConsumers(t *testing.T) {
	b, err := os.ReadFile(filepath.Join("../../..", ".github/workflows/windows_tests.yml"))
	if err != nil {
		t.Fatal(err)
	}
	text := string(b)
	producer := coverageJob(text, "coverage-aggregation")
	for _, required := range []string{"actions/setup-dotnet@", "dotnet-version: '10.0.300'", "DOTNET_INSTALL_DIR:", "managed_coverage.ps1", "run_repo_coverage.ps1", "-GoCoverageDirectory", "-ManagedEvidencePath", "repo-coverage-evidence", "Export-CIPowerShellRawEvidence", "powershell-raw-evidence", "retention-days: 7"} {
		if !strings.Contains(producer, required) {
			t.Fatalf("producer missing %s", required)
		}
	}
	gate := coverageJob(text, "requirements-gate")
	for _, required := range []string{"repo_coverage_tool verify", "--require-complete", "--minimum-percent 80", "--expected-sha", "--expected-run-url"} {
		if !strings.Contains(gate, required) {
			t.Fatalf("strict artifact gate missing %s", required)
		}
	}
	for _, job := range []string{"release", "build-portal"} {
		body := coverageJob(text, job)
		if !strings.Contains(body, "WINDOWS_SETUP_COVERAGE_TOOL:") || !strings.Contains(body, "actions/setup-go@") || !strings.Contains(body, "./script/test/repo_coverage_tool") {
			t.Fatalf("%s cannot execute mandatory coverage verifier", job)
		}
	}
	if !strings.Contains(coverageJob(text, "ci-rollup"), "oobe_payload_inspection") {
		t.Fatal("payload requirement removed")
	}
}
