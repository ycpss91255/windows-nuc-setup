package unit_test

import (
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func TestRawEvidenceWorkflowRunsAsRunnerUTF8WithoutBOM(t *testing.T) {
	if runtime.GOOS != "windows" {
		t.Skip("requires the actual Windows PowerShell 5.1 runner parser")
	}
	bytes, err := os.ReadFile(filepath.Join("../../..", ".github/workflows/windows_tests.yml"))
	if err != nil {
		t.Fatal(err)
	}
	active, body := false, false
	var code strings.Builder
	for _, line := range strings.Split(string(bytes), "\n") {
		if strings.TrimSpace(line) == "- name: 彙整失敗仍匯出安全 PowerShell 原始證據" {
			active = true
			continue
		}
		if !active {
			continue
		}
		if strings.HasPrefix(line, "      - name:") {
			break
		}
		if strings.TrimSpace(line) == "run: |" {
			body = true
			continue
		}
		if body {
			if strings.TrimSpace(line) != "" && !strings.HasPrefix(line, "          ") {
				t.Fatal("unexpected raw export run indentation")
			}
			code.WriteString(strings.TrimPrefix(line, "          "))
			code.WriteByte('\n')
		}
	}
	if code.Len() == 0 {
		t.Fatal("raw export step body missing")
	}
	directory := t.TempDir()
	script := filepath.Join(directory, "runner_step.ps1")
	// GitHub's powershell runner writes an inline UTF-8 script without a BOM.
	if err := os.WriteFile(script, []byte(code.String()), 0600); err != nil {
		t.Fatal(err)
	}
	shell := filepath.Join(os.Getenv("SystemRoot"), "System32", "WindowsPowerShell", "v1.0", "powershell.exe")
	command := exec.Command(shell, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", script)
	command.Env = append(os.Environ(), "RUNNER_TEMP="+directory)
	if output, err := command.CombinedOutput(); err != nil {
		t.Fatalf("real PS5.1 no-BOM workflow step failed: %v %s", err, output)
	}
}
