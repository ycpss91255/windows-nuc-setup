package integration_test

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func TestPowerShellRawExportCLI(t *testing.T) {
	repo, _ := filepath.Abs("../../..")
	bin := filepath.Join(t.TempDir(), "raw_export.exe")
	goexe := filepath.Join(runtime.GOROOT(), "bin", "go")
	if runtime.GOOS == "windows" {
		goexe += ".exe"
	}
	build := exec.Command(goexe, "build", "-mod=vendor", "-cover", "-coverpkg=./script/test/...", "-o", bin, "./script/test/repo_coverage_tool")
	build.Dir = repo
	if out, err := build.CombinedOutput(); err != nil {
		t.Fatalf("build: %v %s", err, out)
	}
	source := t.TempDir()
	input := t.TempDir()
	destination := filepath.Join(t.TempDir(), "safe")
	code := []byte("Write-Host fixture\n")
	name := "logic.ps1"
	hash := fmt.Sprintf("%x", sha256.Sum256(code))
	os.WriteFile(filepath.Join(source, name), code, 0600)
	sources := []any{map[string]any{"File": name, "SHA256": hash}}
	worker := map[string]any{"ProcessId": 100, "PesterVersion": "6.0.0", "Engine": "powershell", "EngineVersion": "5.1.20348.1", "EngineSHA256": strings.Repeat("a", 64), "Sources": sources, "Commands": []any{map[string]any{"File": name, "Line": 1, "Column": 1, "EndLine": 1, "EndColumn": 19, "Hit": true}}}
	proof := map[string]any{"SchemaVersion": 1, "PesterVersion": "6.0.0", "PackageSHA512": "AHIAm7QW11As3sjMayo1rPU4JVIEfBL+ZILAyTyDnMPxMwLFQ3VeAA0prFTx+Y4DgZCUnH2N4+Xb0HDQua2EKA==", "Metric": "FullyCoveredCommandStartLines", "Covered": 1, "Total": 1, "Sources": []any{map[string]any{"File": name, "SHA256": hash, "ExpectedLines": []int{1}}}, "Workers": []any{map[string]any{"Index": 0, "ProcessId": 100, "Engine": "powershell", "EngineVersion": "5.1.20348.1", "EngineSHA256": strings.Repeat("a", 64), "Evidence": "worker_0.json"}}}
	wb, _ := json.Marshal(worker)
	pb, _ := json.Marshal(proof)
	os.WriteFile(filepath.Join(input, "worker_0.json"), wb, 0600)
	os.WriteFile(filepath.Join(input, "evidence.json"), pb, 0600)
	os.WriteFile(filepath.Join(input, "coverage.xml"), []byte(`<coverage coverage-schema="1" coverage-metric="complete-executable-lines-v1"><!-- private metadata --><packages><package><classes><class filename="logic.ps1"><lines><line number="1" hits="1"/></lines></class></classes></package></packages></coverage>`), 0600)
	os.WriteFile(filepath.Join(input, "worker_0.xml"), []byte("PRIVATE-PESTER-ABSOLUTE-PATH"), 0600)
	os.WriteFile(filepath.Join(input, "stdout.log"), []byte("PRIVATE-STDOUT"), 0600)
	run := func(ok bool, arguments ...string) {
		t.Helper()
		cmd := exec.Command(bin, arguments...)
		cmd.Env = os.Environ()
		if d := os.Getenv("WINDOWS_SETUP_CLI_COVERAGE_DIR"); d != "" {
			cmd.Env = append(cmd.Env, "GOCOVERDIR="+d)
		}
		out, err := cmd.CombinedOutput()
		if (err == nil) != ok {
			t.Fatalf("export result: %v %s", err, out)
		}
	}
	args := []string{"export-powershell", "--source-root", source, "--evidence-dir", input, "--output-dir", destination}
	run(true, args...)
	files, _ := os.ReadDir(destination)
	if len(files) != 3 {
		t.Fatal("unexpected public file set", len(files))
	}
	for _, file := range files {
		bytes, _ := os.ReadFile(filepath.Join(destination, file.Name()))
		if strings.Contains(string(bytes), "PRIVATE") || strings.Contains(string(bytes), "private metadata") || strings.Contains(string(bytes), source) {
			t.Fatal("private metadata leaked")
		}
	}
	run(false, args...)
	run(false, "export-powershell")
	run(false, "export-powershell", "--unknown")
	run(false, "export-powershell", "--source-root", source, "--evidence-dir", input, "--output-dir", filepath.Join(source, "bad"))
	os.WriteFile(filepath.Join(source, name), []byte("tampered"), 0600)
	args[len(args)-1] = filepath.Join(t.TempDir(), "bad")
	run(false, args...)
}
