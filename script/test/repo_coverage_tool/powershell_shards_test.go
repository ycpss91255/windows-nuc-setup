package main

import (
	"bytes"
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

func shardCLIFixture(t *testing.T) (string, string, string) {
	t.Helper()
	root := t.TempDir()
	for name, text := range map[string]string{"core/value.ps1": "function Value { return 1 }\n", "test/powershell/unit/side_0_tests.ps1": "Value\n", "test/powershell/unit/side_1_tests.ps1": "Value\n", "test/powershell/coverage/safe_suite.ps1": "param($SuitePath,$SourceRoot)\n& $SuitePath\n"} {
		p := filepath.Join(root, filepath.FromSlash(name))
		if err := os.MkdirAll(filepath.Dir(p), 0700); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(p, []byte(text), 0600); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.MkdirAll(filepath.Join(root, "test/powershell/integration"), 0700); err != nil {
		t.Fatal(err)
	}
	git := func(args ...string) string {
		t.Helper()
		cmd := exec.Command("git", append([]string{"-C", root}, args...)...)
		b, e := cmd.CombinedOutput()
		if e != nil {
			t.Fatalf("git fixture: %v %s", e, b)
		}
		return strings.TrimSpace(string(b))
	}
	git("init", "-q")
	git("add", ".")
	git("-c", "user.name=CoverageFixture", "-c", "user.email=fixture@example.invalid", "commit", "-qm", "fixture")
	sha := git("rev-parse", "HEAD")
	manifest := filepath.Join(t.TempDir(), "manifest.json")
	b, _ := json.Marshal(map[string]any{"SourceRoot": root, "Sources": []string{"core/value.ps1"}, "Tests": []string{"test/powershell/unit/side_0_tests.ps1", "test/powershell/unit/side_1_tests.ps1"}, "TestEngines": map[string]string{}, "Wrapper": "test/powershell/coverage/safe_suite.ps1"})
	if err := os.WriteFile(manifest, b, 0600); err != nil {
		t.Fatal(err)
	}
	return root, manifest, sha
}

func shardCLIArgs(root, manifest, sha string) []string {
	return []string{"--source-root", root, "--manifest", manifest, "--expected-sha", sha, "--expected-run-url", "https://github.com/example/repo/actions/runs/123", "--run-attempt", "1", "--shard-count", "2"}
}

func TestPowerShellShardPlanPreservesCanonicalScope(t *testing.T) {
	root, manifest, sha := shardCLIFixture(t)
	output := filepath.Join(t.TempDir(), "plan")
	args := append(shardCLIArgs(root, manifest, sha), "--shard-index", "1", "--output-dir", output)
	if err := powershellShardPlan(args, &bytes.Buffer{}); err != nil {
		t.Fatal(err)
	}
	b, err := os.ReadFile(filepath.Join(output, "privatecollection_manifest.json"))
	if err != nil {
		t.Fatal(err)
	}
	var plan struct {
		SourceRoot     string
		Sources, Tests []string
		Wrapper        string
		TestEngines    map[string]string
	}
	if err = json.Unmarshal(b, &plan); err != nil {
		t.Fatal(err)
	}
	if plan.SourceRoot != root || len(plan.Sources) != 1 || len(plan.Tests) != 1 || plan.Tests[0] != "test/powershell/unit/side_1_tests.ps1" || plan.Wrapper != "test/powershell/coverage/safe_suite.ps1" {
		t.Fatalf("scope changed: %#v", plan)
	}
	if err := powershellShardPlan(args, &bytes.Buffer{}); err == nil {
		t.Fatal("existing output accepted")
	}
}

func TestPowerShellShardPlanRejectsMissingCanonicalTest(t *testing.T) {
	root, manifest, sha := shardCLIFixture(t)
	b, _ := os.ReadFile(manifest)
	var m map[string]any
	_ = json.Unmarshal(b, &m)
	m["Tests"] = []string{"test/powershell/unit/side_0_tests.ps1"}
	b, _ = json.Marshal(m)
	_ = os.WriteFile(manifest, b, 0600)
	if err := powershellShardPlan(append(shardCLIArgs(root, manifest, sha), "--shard-index", "0", "--output-dir", filepath.Join(t.TempDir(), "plan")), &bytes.Buffer{}); err == nil {
		t.Fatal("reduced canonical test scope accepted")
	}
}

func TestPowerShellShardCLIRejectsInvalidIdentityAndArguments(t *testing.T) {
	funcs := []func([]string, *bytes.Buffer) error{
		func(a []string, b *bytes.Buffer) error { return powershellShardPlan(a, b) },
		func(a []string, b *bytes.Buffer) error { return powershellShardPack(a, b) },
		func(a []string, b *bytes.Buffer) error { return powershellShardMerge(a, b) },
	}
	for _, f := range funcs {
		for _, args := range [][]string{nil, {"--unknown"}, {"extra"}, {"--source-root", "."}} {
			if f(args, &bytes.Buffer{}) == nil {
				t.Fatal("invalid command accepted")
			}
		}
	}
	root, manifest, sha := shardCLIFixture(t)
	base := shardCLIArgs(root, manifest, sha)
	for _, change := range [][]string{{"--expected-sha", strings.Repeat("A", 40)}, {"--expected-run-url", "http://example.invalid"}, {"--run-attempt", "0"}, {"--shard-count", "0"}, {"--shard-count", "5"}, {"--shard-index", "-1"}, {"--shard-index", "2"}} {
		args := append(append([]string{}, base...), "--shard-index", "0", "--output-dir", filepath.Join(t.TempDir(), "out"))
		args = append(args, change...)
		if powershellShardPlan(args, &bytes.Buffer{}) == nil {
			t.Fatalf("invalid identity accepted %v", change)
		}
	}
}

func TestPowerShellShardPlanRejectsTamperedManifestAndOutput(t *testing.T) {
	for _, kind := range []string{"source", "tests", "wrapper", "engine", "root", "unknown", "duplicate", "trailing", "missing", "dirty", "wrong_commit", "inside_output", "existing_output", "few_tests"} {
		t.Run(kind, func(t *testing.T) {
			root, manifest, sha := shardCLIFixture(t)
			b, _ := os.ReadFile(manifest)
			var m map[string]any
			_ = json.Unmarshal(b, &m)
			output := filepath.Join(t.TempDir(), "plan")
			switch kind {
			case "source":
				m["Sources"] = []string{}
			case "tests":
				m["Tests"] = []string{"test/powershell/unit/side_1_tests.ps1", "test/powershell/unit/side_0_tests.ps1"}
			case "wrapper":
				m["Wrapper"] = "test/powershell/coverage/other.ps1"
			case "engine":
				m["TestEngines"] = map[string]string{"test/powershell/unit/side_0_tests.ps1": "pwsh"}
			case "root":
				m["SourceRoot"] = t.TempDir()
			case "unknown":
				m["Extra"] = true
			case "missing":
				delete(m, "Tests")
			case "dirty":
				_ = os.WriteFile(filepath.Join(root, "untracked.txt"), []byte("not clean"), 0600)
			case "wrong_commit":
				sha = strings.Repeat("a", 40)
			case "inside_output":
				output = filepath.Join(root, "untracked_output")
			case "existing_output":
				output = t.TempDir()
			}
			b, _ = json.Marshal(m)
			if kind == "duplicate" {
				b = append([]byte(`{"SourceRoot":"ignored",`), b[1:]...)
			}
			if kind == "trailing" {
				b = append(b, []byte(` {}`)...)
			}
			_ = os.WriteFile(manifest, b, 0600)
			args := append(shardCLIArgs(root, manifest, sha), "--shard-index", "0", "--output-dir", output)
			if kind == "few_tests" {
				args = append(args, "--shard-count", "3")
			}
			if err := powershellShardPlan(args, &bytes.Buffer{}); err == nil {
				t.Fatalf("invalid %s accepted", kind)
			}
		})
	}
}

// Synthetic typed evidence exercises transport validation only; the parent
// integration suite separately runs actual Pester workers on original files.
func writeShardCLIProof(t *testing.T, root, dir string, pid int, hit bool) {
	t.Helper()
	if err := os.MkdirAll(dir, 0700); err != nil {
		t.Fatal(err)
	}
	text, _ := os.ReadFile(filepath.Join(root, "core/value.ps1"))
	hash := fmt.Sprintf("%x", sha256.Sum256(text))
	engineHash := strings.Repeat("b", 64)
	source := map[string]any{"File": "core/value.ps1", "SHA256": hash, "ExpectedLines": []int{1}}
	worker := map[string]any{"ProcessId": pid, "Engine": "powershell", "EngineVersion": "5.1.0.0", "EngineSHA256": engineHash, "PesterVersion": "6.0.0", "Sources": []any{source}, "Commands": []any{map[string]any{"File": "core/value.ps1", "Line": 1, "Column": 1, "EndLine": 1, "EndColumn": 25, "Hit": hit}}}
	covered := 0
	if hit {
		covered = 1
	}
	proof := map[string]any{"SchemaVersion": 1, "PesterVersion": "6.0.0", "PackageSHA512": "AHIAm7QW11As3sjMayo1rPU4JVIEfBL+ZILAyTyDnMPxMwLFQ3VeAA0prFTx+Y4DgZCUnH2N4+Xb0HDQua2EKA==", "Metric": "FullyCoveredCommandStartLines", "Sources": []any{source}, "Workers": []any{map[string]any{"Index": 0, "ProcessId": pid, "Evidence": "worker_0.json", "Engine": "powershell", "EngineVersion": "5.1.0.0", "EngineSHA256": engineHash}}, "Covered": covered, "Total": 1}
	for name, value := range map[string]any{"worker_0.json": worker, "evidence.json": proof} {
		b, _ := json.Marshal(value)
		if err := os.WriteFile(filepath.Join(dir, name), b, 0600); err != nil {
			t.Fatal(err)
		}
	}
	xml := fmt.Sprintf(`<coverage coverage-schema="1" coverage-metric="complete-executable-lines-v1"><packages><package><classes><class filename="core/value.ps1"><lines><line number="1" hits="%d"/></lines></class></classes></package></packages></coverage>`, covered)
	if err := os.WriteFile(filepath.Join(dir, "coverage.xml"), []byte(xml), 0600); err != nil {
		t.Fatal(err)
	}
}

func TestPowerShellShardPackAndMergePreserveNativeFields(t *testing.T) {
	root, manifest, sha := shardCLIFixture(t)
	parts := t.TempDir()
	for index := 0; index < 2; index++ {
		dir := filepath.Join(parts, fmt.Sprintf("part_%d", index))
		writeShardCLIProof(t, root, dir, 123+index, index == 1)
		args := append(shardCLIArgs(root, manifest, sha), "--shard-index", fmt.Sprint(index), "--evidence-dir", dir)
		if err := powershellShardPack(args, &bytes.Buffer{}); err != nil {
			t.Fatal(err)
		}
		if err := powershellShardPack(args, &bytes.Buffer{}); err == nil {
			t.Fatal("repacked existing envelope")
		}
	}
	output := filepath.Join(t.TempDir(), "merged")
	args := append(shardCLIArgs(root, manifest, sha), "--input-dir", parts, "--output-dir", output)
	if err := powershellShardMerge(args, &bytes.Buffer{}); err != nil {
		t.Fatal(err)
	}
	b, err := os.ReadFile(filepath.Join(output, "evidence.json"))
	if err != nil {
		t.Fatal(err)
	}
	var proof struct {
		Covered, Total int
		Workers        []struct{ Index, ProcessId int }
	}
	if err = json.Unmarshal(b, &proof); err != nil {
		t.Fatal(err)
	}
	if proof.Covered != 1 || proof.Total != 1 || len(proof.Workers) != 2 || proof.Workers[1].Index != 1 || proof.Workers[1].ProcessId != 124 {
		t.Fatalf("evidence identity or actual hit union changed: %#v", proof)
	}
	if err := powershellShardMerge(args, &bytes.Buffer{}); err == nil {
		t.Fatal("existing merge output accepted")
	}
}

func TestPowerShellShardPackAndMergeRejectBadInputs(t *testing.T) {
	root, manifest, sha := shardCLIFixture(t)
	base := shardCLIArgs(root, manifest, sha)
	for _, kind := range []string{"missing", "private_extra", "missing_suite", "invalid_raw"} {
		t.Run("pack_"+kind, func(t *testing.T) {
			dir := filepath.Join(t.TempDir(), "proof")
			writeShardCLIProof(t, root, dir, 123, true)
			args := append(append([]string{}, base...), "--shard-index", "0", "--evidence-dir", dir)
			switch kind {
			case "missing":
				_ = os.Remove(filepath.Join(dir, "evidence.json"))
			case "private_extra":
				_ = os.WriteFile(filepath.Join(dir, "private.log"), []byte("never upload"), 0600)
			case "missing_suite":
				args = append(args, "--shard-count", "1")
			case "invalid_raw":
				_ = os.WriteFile(filepath.Join(dir, "worker_0.json"), []byte(`{}`), 0600)
			}
			if err := powershellShardPack(args, &bytes.Buffer{}); err == nil {
				t.Fatalf("bad %s accepted", kind)
			}
			if _, err := os.Stat(filepath.Join(dir, "shard.json")); err == nil {
				t.Fatal("failed pack wrote success envelope")
			}
		})
	}
	for _, kind := range []string{"missing_part", "file_part", "missing_manifest", "invalid_manifest", "wrong_attempt", "changed_worker"} {
		t.Run("merge_"+kind, func(t *testing.T) {
			parts := t.TempDir()
			for i := 0; i < 2; i++ {
				dir := filepath.Join(parts, fmt.Sprint(i))
				writeShardCLIProof(t, root, dir, 123+i, true)
				if err := powershellShardPack(append(append([]string{}, base...), "--shard-index", fmt.Sprint(i), "--evidence-dir", dir), &bytes.Buffer{}); err != nil {
					t.Fatal(err)
				}
			}
			file := filepath.Join(parts, "1", "shard.json")
			switch kind {
			case "missing_part":
				if err := os.Rename(filepath.Join(parts, "1"), filepath.Join(t.TempDir(), "moved")); err != nil {
					t.Fatal(err)
				}
			case "file_part":
				if err := os.Rename(filepath.Join(parts, "1"), filepath.Join(t.TempDir(), "moved")); err != nil {
					t.Fatal(err)
				}
				_ = os.WriteFile(filepath.Join(parts, "file"), []byte("bad"), 0600)
			case "missing_manifest":
				_ = os.Remove(file)
			case "invalid_manifest":
				_ = os.WriteFile(file, []byte(`{}`), 0600)
			case "wrong_attempt":
				b, _ := os.ReadFile(file)
				var v map[string]any
				_ = json.Unmarshal(b, &v)
				v["RunAttempt"] = 2
				b, _ = json.Marshal(v)
				_ = os.WriteFile(file, b, 0600)
			case "changed_worker":
				_ = os.WriteFile(filepath.Join(parts, "1", "worker_0.json"), []byte(`{}`), 0600)
			}
			output := filepath.Join(t.TempDir(), "merged")
			if err := powershellShardMerge(append(append([]string{}, base...), "--input-dir", parts, "--output-dir", output), &bytes.Buffer{}); err == nil {
				t.Fatalf("bad %s accepted", kind)
			}
			if _, err := os.Stat(output); err == nil {
				t.Fatal("failed validation created output")
			}
		})
	}
}

func TestPowerShellShardInstrumentedCommands(t *testing.T) {
	source, manifest, sha := shardCLIFixture(t)
	repo, err := filepath.Abs("../../..")
	if err != nil {
		t.Fatal(err)
	}
	executable := filepath.Join(t.TempDir(), "shards.exe")
	goexe := filepath.Join(runtime.GOROOT(), "bin", "go")
	if runtime.GOOS == "windows" {
		goexe += ".exe"
	}
	build := exec.Command(goexe, "build", "-mod=vendor", "-cover", "-coverpkg=./script/test/...", "-o", executable, "./script/test/repo_coverage_tool")
	build.Dir = repo
	if b, err := build.CombinedOutput(); err != nil {
		t.Fatalf("instrumented build: %v %s", err, b)
	}
	cover := os.Getenv("WINDOWS_SETUP_CLI_COVERAGE_DIR")
	if cover == "" {
		cover = t.TempDir()
	}
	invoke := func(want bool, args ...string) {
		t.Helper()
		cmd := exec.Command(executable, args...)
		cmd.Env = append(os.Environ(), "GOCOVERDIR="+cover)
		b, e := cmd.CombinedOutput()
		if (e == nil) != want {
			t.Fatalf("real instrumented command %v: %v %s", args, e, b)
		}
	}
	common := shardCLIArgs(source, manifest, sha)
	for _, command := range []string{"powershell-shard-plan", "powershell-shard-pack", "powershell-shard-merge"} {
		invoke(false, command)
		invoke(false, command, "--bad-flag")
	}
	for i := 0; i < 2; i++ {
		invoke(true, append([]string{"powershell-shard-plan"}, append(append([]string{}, common...), "--shard-index", fmt.Sprint(i), "--output-dir", filepath.Join(t.TempDir(), "plan"))...)...)
	}
	parts := t.TempDir()
	for i := 0; i < 2; i++ {
		dir := filepath.Join(parts, fmt.Sprint(i))
		writeShardCLIProof(t, source, dir, 700+i, i == 1)
		args := append([]string{"powershell-shard-pack"}, append(append([]string{}, common...), "--shard-index", fmt.Sprint(i), "--evidence-dir", dir)...)
		invoke(true, args...)
		invoke(false, args...)
	}
	invoke(false, append([]string{"powershell-shard-merge"}, append(append([]string{}, common...), "--input-dir", t.TempDir(), "--output-dir", filepath.Join(t.TempDir(), "incomplete"))...)...)
	invoke(true, append([]string{"powershell-shard-merge"}, append(append([]string{}, common...), "--input-dir", parts, "--output-dir", filepath.Join(t.TempDir(), "merged"))...)...)
	counters, err := filepath.Glob(filepath.Join(cover, "covcounters.*"))
	if err != nil || len(counters) == 0 {
		t.Fatal("real commands did not emit Go runtime counters")
	}
}

func TestPowerShellShardPackRejectsUnboundNativeContext(t *testing.T) {
	root, manifest, sha := shardCLIFixture(t)
	dir := filepath.Join(t.TempDir(), "unbound")
	writeShardCLIProof(t, root, dir, 123, true)
	args := append(shardCLIArgs(root, manifest, sha), "--shard-index", "0", "--evidence-dir", dir)
	if err := powershellShardPack(args, &bytes.Buffer{}); err == nil {
		t.Fatal("native worker without actual case/run context must not be relabelled into a current shard")
	}
}
