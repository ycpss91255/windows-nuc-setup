package integration_test

import (
	"os"
	"testing"
	a "windows_setup/script/test/acceptance"
)

func TestSimplePortalDoesNotRequireComparisonArtifacts(t *testing.T) {
	report := synthetic(t, files(t, os.Getenv("WINDOWS_SETUP_ARTIFACT_DIR")), true, "Branch")
	r := decode(t, report)
	m := portal(t, report)
	m["versions.json"] = []byte(`[{"Version":"v1.0.0","Status":"Unknown","Path":"versions/v1.0.0/index.html"}]`)
	m["versions/v1.0.0/index.html"] = []byte(`<html><body>未保存測試紀錄</body></html>`)
	if _, err := a.ValidatePortal(reader(m), readme(), r.Commit, r.RunUrl, base); err != nil {
		t.Fatalf("simple portal must not require removed comparison artifacts: %v", err)
	}
}
