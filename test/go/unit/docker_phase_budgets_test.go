package unit_test

import (
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"testing"
)

func TestDockerBuildAndFullTestHaveIndependentBoundedBudgets(t *testing.T) {
	b, err := os.ReadFile(filepath.Join("../../..", ".github/workflows/windows_tests.yml"))
	if err != nil { t.Fatal(err) }
	w := string(b)
	start := strings.Index(w, "  docker-tests:")
	end := strings.Index(w[start:], "\n  ci-rollup:")
	if start < 0 || end < 0 { t.Fatal("Docker job and required rollup must remain") }
	job := w[start:start+end]
	budget := regexp.MustCompile(`timeout-minutes:\s*([0-9]+)`)
	limits := budget.FindAllStringSubmatch(job, -1)
	if len(limits) < 5 { t.Fatal("build, full tests, native failure probe and evidence each need their own bounded phase") }
	n := func(s string) int { v, e := strconv.Atoi(s); if e != nil { t.Fatal(e) }; return v }
	total := 10 // checkout/tool setup, upload and process cleanup headroom
	for _, m := range limits[1:] { if n(m[1]) <= 0 { t.Fatal("unbounded phase") }; total += n(m[1]) }
	if n(limits[0][1]) < total { t.Fatal("whole-job timeout can cancel normally progressing bounded phases") }
	if !strings.Contains(job, "'-Action','build'") || !strings.Contains(job, "'-Action','test-built'") || strings.Count(job, "windows-container-image.json") != 2 {
		t.Fatal("separate full-test phase must consume the exact build receipt without rebuilding or skipping image identity")
	}
	for _, required := range []string{"Assert-CIDockerFailure", "Assert-CIContainerReport", "requirements_gate", "retention-days: 7"} {
		if !strings.Contains(job, required) { t.Fatalf("original Docker gate removed: %s", required) }
	}
}
