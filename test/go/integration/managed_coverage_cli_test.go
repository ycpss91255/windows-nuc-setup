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

func TestManagedCoverageCLI(t *testing.T) {
	root := t.TempDir()
	rawDir := t.TempDir()
	repo, _ := filepath.Abs("../../..")
	source := []byte("class X { static int Value() { return 1; } }\n")
	if err := os.WriteFile(filepath.Join(root, "x.cs"), source, 0600); err != nil {
		t.Fatal(err)
	}
	git := func(args ...string) string {
		t.Helper()
		c := exec.Command("git", append([]string{"-C", root}, args...)...)
		b, e := c.CombinedOutput()
		if e != nil {
			t.Fatalf("git %v %s", e, b)
		}
		return strings.TrimSpace(string(b))
	}
	git("init")
	git("config", "user.name", "Fixture")
	git("config", "user.email", "fixture@example.invalid")
	git("add", ".")
	git("commit", "-m", "fixture")
	sha := git("rev-parse", "HEAD")
	hash := func(b []byte) string { return fmt.Sprintf("%x", sha256.Sum256(b)) }
	xml := []byte(fmt.Sprintf(`<results><modules><module id="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"><functions><function token="0x6000001" name="Value()" type_name="X"><ranges><range source_id="1" start_line="1" end_line="1" start_column="31" end_column="40" covered="yes"/></ranges></function></functions><source_files><source_file id="1" path="x.cs" checksum_type="SHA256" checksum="%s"/></source_files></module></modules></results>`, hash(source)))
	files := map[string][]byte{"assembly.dll": []byte("synthetic assembly"), "assembly.pdb": []byte("synthetic pdb"), "shard.coverage": []byte("synthetic raw"), "merged.coverage": []byte("synthetic merged"), "shard.xml": xml, "merged.xml": xml}
	proof := map[string]any{"SchemaVersion": 1, "Metric": "complete-executable-lines-v1", "SourceRoot": root, "Tool": map[string]string{"Id": "Microsoft.dotnet-coverage", "Version": "17.14.1", "PackageSHA512": "hgzaG+c7LtKup6HZixvXtn3l4Pa8VK23bM9vLHveD3Iq2XlzLu7vqMZwtVjQdsof83wx5OzY0tpDh3+YRdOVjA=="}, "Sources": []any{map[string]string{"Path": "x.cs", "SHA256": hash(source)}}, "MergeNative": true}
	for key, name := range map[string]string{"Assembly": "assembly.dll", "PDB": "assembly.pdb", "MergedBinary": "merged.coverage", "MergedXml": "merged.xml"} {
		proof[key+"Path"] = name
		proof[key+"SHA256"] = hash(files[name])
	}
	proof["Shards"] = []any{map[string]string{"BinaryPath": "shard.coverage", "SHA256": hash(files["shard.coverage"]), "XmlPath": "shard.xml", "XmlSHA256": hash(xml)}}
	data, _ := json.Marshal(proof)
	files["evidence.json"] = data
	for name, b := range files {
		if err := os.WriteFile(filepath.Join(rawDir, name), b, 0600); err != nil {
			t.Fatal(err)
		}
	}
	goexe := filepath.Join(runtime.GOROOT(), "bin", "go")
	if runtime.GOOS == "windows" {
		goexe += ".exe"
	}
	bin := filepath.Join(t.TempDir(), "coverage.exe")
	build := exec.Command(goexe, "build", "-cover", "-coverpkg=./script/test/...", "-o", bin, "./script/test/repo_coverage_tool")
	build.Dir = repo
	if b, e := build.CombinedOutput(); e != nil {
		t.Fatalf("build %v %s", e, b)
	}
	run := func(ok bool, args ...string) {
		t.Helper()
		c := exec.Command(bin, args...)
		c.Env = os.Environ()
		if d := os.Getenv("WINDOWS_SETUP_CLI_COVERAGE_DIR"); d != "" {
			c.Env = append(c.Env, "GOCOVERDIR="+d)
		}
		b, e := c.CombinedOutput()
		if (e == nil) != ok {
			t.Fatalf("CLI %v %v %s", args, e, b)
		}
	}
	output := filepath.Join(t.TempDir(), "coverage")
	run(true, "collect", "--source-root", root, "--expected-sha", sha, "--output-dir", output, "--managed-evidence", filepath.Join(rawDir, "evidence.json"))
	run(true, "verify", "--artifact-dir", output, "--expected-sha", sha, "--require-complete", "--minimum-percent", "80")
	if err := os.WriteFile(filepath.Join(rawDir, "merged.coverage"), []byte("tampered"), 0600); err != nil {
		t.Fatal(err)
	}
	run(false, "collect", "--source-root", root, "--expected-sha", sha, "--output-dir", filepath.Join(t.TempDir(), "coverage"), "--managed-evidence", filepath.Join(rawDir, "evidence.json"))
}
