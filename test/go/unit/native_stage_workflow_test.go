package unit_test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestNativeProducerAndStrictCoverageAggregatorAreParallel(t *testing.T) {
	data, err := os.ReadFile(filepath.Join("../../..", ".github/workflows/windows_tests.yml"))
	if err != nil {
		t.Fatal(err)
	}
	text := string(data)
	native := coverageJob(text, "isolated-tests")
	if strings.Contains(native, "needs:") || strings.Contains(native, "run_repo_coverage.ps1") {
		t.Fatal("native producer still waits for PowerShell or claims whole coverage")
	}
	for _, required := range []string{"run_ci.ps1", "measure_go_coverage.ps1", "native-stage-pack", "--run-attempt", "native-stage-${{ github.run_id }}-${{ github.run_attempt }}"} {
		if !strings.Contains(native, required) {
			t.Fatalf("complete native producer missing %s", required)
		}
	}
	if strings.Contains(native, "name: windows-test-reports-") {
		t.Fatal("partial native stage must not publish final report artifact")
	}
	aggregate := coverageJob(text, "coverage-aggregation")
	for _, required := range []string{"needs: [isolated-tests, powershell-coverage]", "native-stage-restore", "native-stage-${{ github.run_id }}-${{ github.run_attempt }}", "managed_coverage.ps1", "run_repo_coverage.ps1", "-PowerShellShardDirectory", "-RunAttempt", "PreparingRelease", "name: windows-test-reports-"} {
		if !strings.Contains(aggregate, required) {
			t.Fatalf("strict aggregator missing %s", required)
		}
	}
	if strings.Contains(aggregate, "run_ci.ps1") || strings.Contains(aggregate, "measure_go_coverage.ps1") {
		t.Fatal("aggregator reruns native producer rather than consuming its verified bytes")
	}
	if strings.Count(text, "name: windows-test-reports-") != 4 {
		t.Fatal("only one final artifact upload, its two existing consumers and the opted-in diagnostic are expected")
	}
	diagnostic := coverageJob(text, "cache-diagnostic-samples")
	if !strings.Contains(diagnostic, "github.event_name == 'workflow_dispatch'") || !strings.Contains(diagnostic, "inputs.cache_diagnostic") || !strings.Contains(diagnostic, "needs: [ci-rollup, cache-diagnostic-prime]") || !strings.Contains(diagnostic, "name: windows-test-reports-${{ github.run_id }}-${{ github.run_attempt }}") {
		t.Fatal("additional report consumer must be manual-only and use same-run final evidence after all gates")
	}
	for _, job := range []string{"requirements-gate", "ci-rollup", "build-portal"} {
		if !strings.Contains(coverageJob(text, job), "coverage-aggregation") {
			t.Fatalf("%s can bypass complete coverage aggregator", job)
		}
	}
	rollup := coverageJob(text, "ci-rollup")
	if !strings.Contains(rollup, "needs.coverage-aggregation.result") || !strings.Contains(rollup, "Coverage=$env:COVERAGE_RESULT") {
		t.Fatal("failed/cancelled/skipped aggregation can bypass rollup")
	}
}
