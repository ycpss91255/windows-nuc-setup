package unit_test

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

func TestMergeGroupWorkflowContract(t *testing.T) {
	data, err := os.ReadFile(filepath.Join("../../..", ".github/workflows/windows_tests.yml"))
	if err != nil {
		t.Fatal(err)
	}
	workflow := strings.ReplaceAll(string(data), "\r\n", "\n")
	triggers := strings.SplitN(strings.SplitN(workflow, "\non:\n", 2)[1], "\nenv:", 2)[0]
	if !regexp.MustCompile(`(?m)^  merge_group:\s*$`).MatchString(triggers) {
		t.Error("merge queue checks cannot start without merge_group trigger")
	}
	if !strings.Contains(workflow, "group: windows-tests-${{ github.workflow }}-${{ github.ref }}") || !strings.Contains(workflow, "cancel-in-progress: ${{ github.event_name == 'pull_request' }}") {
		t.Error("merge group runs must use their own ref and must not cancel in progress")
	}
	jobs := []string{"isolated-tests", "requirements-gate", "docker-tests", "oobe_payload_inspection", "powershell-coverage", "coverage-aggregation"}
	rollup := coverageJob(workflow, "ci-rollup")
	for _, name := range jobs {
		job := coverageJob(workflow, name)
		if job == "" {
			t.Errorf("missing required job %s", name)
			continue
		}
		if regexp.MustCompile(`(?m)^    if:.*github\.event_name`).MatchString(job) {
			t.Errorf("%s has an event-dependent job condition", name)
		}
		if !strings.Contains(rollup, "needs."+name+".result") {
			t.Errorf("rollup does not check %s", name)
		}
	}
	if !strings.Contains(rollup, "if: always()") {
		t.Error("rollup must report failures and skipped jobs")
	}
	gate := coverageJob(workflow, "requirements-gate")
	for _, required := range []string{"--require-complete", "--minimum-percent 80", "${{ github.run_id }}-${{ github.run_attempt }}", "EXPECTED_SHA: ${{ github.sha }}"} {
		if !strings.Contains(gate, required) {
			t.Errorf("gate missing %s", required)
		}
	}
	for _, name := range []string{"release", "build-portal", "verify-deployment"} {
		job := coverageJob(workflow, name)
		condition := regexp.MustCompile(`(?m)^    if: (.*)$`).FindStringSubmatch(job)
		if len(condition) != 2 || !strings.Contains(condition[1], "github.event_name == 'push'") || strings.Contains(condition[1], "merge_group") {
			t.Errorf("%s publication condition must restrict event", name)
		}
	}
	if !strings.Contains(coverageJob(workflow, "publish-reports"), "needs.build-portal.result == 'success'") {
		t.Error("Pages deployment must depend on gated portal")
	}
}
