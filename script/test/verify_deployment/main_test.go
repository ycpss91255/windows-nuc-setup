package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"testing"

	c "windows_setup/script/test/repo_coverage"
)

// The command's own behavior cases must cover its real executable lines. The
// compiler generates this profile; no fixture coverage is counted here.
func TestDeploymentExecutableLineCoverage(t *testing.T) {
	root, err := filepath.Abs("../../..")
	if err != nil {
		t.Fatal(err)
	}
	profile := filepath.Join(t.TempDir(), "command.out")
	goexe := filepath.Join(runtime.GOROOT(), "bin", "go")
	if runtime.GOOS == "windows" {
		goexe += ".exe"
	}
	cmd := exec.Command(goexe, "test", "-mod=vendor", "-count=1", "-run", "^TestDeploymentCases$", "-coverprofile="+profile, "./script/test/verify_deployment")
	cmd.Dir = root
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("actual deployment cases: %v\n%s", err, out)
	}
	data, err := os.ReadFile(profile)
	if err != nil {
		t.Fatal(err)
	}
	source, err := os.ReadFile(filepath.Join(root, "script/test/verify_deployment/main.go"))
	if err != nil {
		t.Fatal(err)
	}
	report, _, err := c.NormalizeGo([][]byte{data}, map[string][]byte{"script/test/verify_deployment/main.go": source}, "windows_setup")
	if err != nil {
		t.Fatal(err)
	}
	hit := 0
	for _, covered := range report.Files["script/test/verify_deployment/main.go"] {
		if covered {
			hit++
		}
	}
	t.Logf("actual deployment cases: %d/%d complete executable lines", hit, len(report.Files["script/test/verify_deployment/main.go"]))
	if hit < 60 {
		t.Fatalf("deployment command behavior cases cover %d real complete executable lines; require at least 60", hit)
	}
}
