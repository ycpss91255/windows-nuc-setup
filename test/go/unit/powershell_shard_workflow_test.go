package unit_test

import (
 "os"
 "path/filepath"
 "strings"
 "testing"
)

func TestPowerShellCoverageUsesCompleteFourShardMatrix(t *testing.T) {
 b, err := os.ReadFile(filepath.Join("../../..", ".github/workflows/windows_tests.yml"))
 if err != nil { t.Fatal(err) }
 text := string(b)
 shard := coverageJob(text, "powershell-coverage")
 for _, required := range []string{"fail-fast: false", "shard: [0, 1, 2, 3]", "powershell_coverage_shard.ps1", "-ShardCount 4", "GITHUB_RUN_ATTEMPT", "powershell-shard-", "retention-days: 7"} {
  if !strings.Contains(shard, required) { t.Fatalf("complete parallel collection missing %s", required) }
 }
 host := coverageJob(text, "isolated-tests")
 for _, required := range []string{"needs: [powershell-coverage]", "actions/download-artifact@", "powershell-shard-", "-PowerShellShardDirectory", "run_repo_coverage.ps1", "managed_coverage.ps1", "measure_go_coverage.ps1"} {
  if !strings.Contains(host, required) { t.Fatalf("host cannot verify all shards without losing original producers: %s", required) }
 }
 if !strings.Contains(coverageJob(text, "ci-rollup"), "powershell-coverage") { t.Fatal("failed or skipped matrix can bypass rollup") }
}
