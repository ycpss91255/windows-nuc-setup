package unit_test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestCacheDiagnosticWorkflowIsOptInAndKeepsEvidenceFresh(t *testing.T) {
	b, err := os.ReadFile(filepath.Join("../../..", ".github/workflows/windows_tests.yml"))
	if err != nil {
		t.Fatal(err)
	}
	workflow := strings.ReplaceAll(string(b), "\r\n", "\n")
	if !strings.Contains(workflow, "cache_diagnostic:") || !strings.Contains(workflow, "default: false") {
		t.Error("missing disabled manual diagnostic input")
	}
	prime := coverageJob(workflow, "cache-diagnostic-prime")
	samples := coverageJob(workflow, "cache-diagnostic-samples")
	for _, job := range []string{prime, samples} {
		if !strings.Contains(job, "github.event_name == 'workflow_dispatch'") || !strings.Contains(job, "inputs.cache_diagnostic") {
			t.Error("diagnostic may run without explicit manual opt-in")
		}
	}
	if !strings.Contains(prime, "needs: [ci-rollup]") || !strings.Contains(samples, "needs: [ci-rollup, cache-diagnostic-prime]") {
		t.Error("diagnostic does not wait for actual quality gates")
	}
	for _, part := range []string{"github.run_id", "github.run_attempt", "github.sha", "hashFiles('go.mod', 'go.sum', 'vendor/**')"} {
		if !strings.Contains(prime, part) || !strings.Contains(samples, part) {
			t.Errorf("cache key missing %s", part)
		}
	}
	for _, name := range []string{"cold_1", "warm_1", "warm_2", "cold_2"} {
		if !strings.Contains(samples, name) {
			t.Errorf("missing sample %s", name)
		}
	}
	if !(strings.Index(samples, "cold_1") < strings.Index(samples, "warm_1") && strings.Index(samples, "warm_1") < strings.Index(samples, "warm_2") && strings.Index(samples, "warm_2") < strings.Index(samples, "cold_2")) {
		t.Error("samples must alternate ABBA")
	}
	if strings.Contains(coverageJob(workflow, "requirements-gate"), "actions/cache") || strings.Contains(coverageJob(workflow, "coverage-aggregation"), "actions/cache") {
		t.Error("formal jobs must not enable cache")
	}
	if !strings.Contains(prime, "go build") || strings.Contains(prime, "go test") || !strings.Contains(samples, "fail-on-cache-miss: true") {
		t.Error("cache must be build-only and warm restores must not silently miss")
	}
}
