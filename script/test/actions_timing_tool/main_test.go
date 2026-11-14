package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestRunRequiresIndependentIdentityAndNeverPublishesInvalidData(t *testing.T) {
	path := filepath.Join(t.TempDir(), "input.json")
	data := `{"run":{"id":123,"run_attempt":1,"head_sha":"` + strings.Repeat("a", 40) + `","repository":{"full_name":"example/repo"}},"pages":[{"page_number":1,"per_page":100,"total_count":1,"jobs":[{"id":5,"run_id":123,"run_attempt":1,"name":"job","status":"completed","conclusion":"success","created_at":null,"started_at":"2026-01-01T00:00:00Z","completed_at":"2026-01-01T00:00:01Z","steps":[]}]}]}`
	if err := os.WriteFile(path, []byte(data), 0600); err != nil {
		t.Fatal(err)
	}
	args := []string{"--input", path, "--repository", "example/repo", "--run-id", "123", "--attempt", "1", "--head-sha", strings.Repeat("a", 40)}
	var out bytes.Buffer
	if err := run(args, &out); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out.String(), `"elapsed_ms":1000`) || !strings.Contains(out.String(), `"pending_ms":null`) {
		t.Fatalf("incorrect observation: %s", out.String())
	}
	out.Reset()
	bad := append(append([]string{}, args...), "--run-id", "124")
	if err := run(bad, &out); err == nil || out.Len() != 0 {
		t.Fatal("mismatch published observation")
	}
	if err := run([]string{"--input", path}, &bytes.Buffer{}); err == nil {
		t.Fatal("missing expected identity accepted")
	}
}
