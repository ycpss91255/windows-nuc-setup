package integration_test

import (
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"testing"

	rc "windows_setup/script/test/repo_coverage"
)

func TestRepoCoverageUsesRealCompilerCounters(t *testing.T) {
	root := t.TempDir()
	source := []byte("package sample\n// comment is not executable\nfunc Choose(v bool) int { if v { return 1 }; return 2 }\nfunc Empty() {}\n")
	tests := []byte("package sample\nimport \"testing\"\nfunc TestTrue(t *testing.T){if Choose(true)!=1 {t.Fatal(\"true\")}}\nfunc TestFalse(t *testing.T){if Choose(false)!=2 {t.Fatal(\"false\")}}\n")
	for name, data := range map[string][]byte{"go.mod": []byte("module sample\n\ngo 1.27.3\n"), "logic.go": source, "logic_test.go": tests} {
		if err := os.WriteFile(filepath.Join(root, name), data, 0600); err != nil {
			t.Fatal(err)
		}
	}
	goexe := filepath.Join(runtime.GOROOT(), "bin", "go")
	if runtime.GOOS == "windows" {
		goexe += ".exe"
	}
	profiles := [][]byte{}
	for _, name := range []string{"TestTrue", "TestFalse"} {
		file := filepath.Join(root, name+".out")
		cmd := exec.Command(goexe, "test", "-count=1", "-coverprofile="+file, "-run", name, ".")
		cmd.Dir = root
		cmd.Env = append(os.Environ(), "GOWORK=off", "GOPROXY=off", "GOSUMDB=off", "GOTOOLCHAIN=local")
		if output, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("real compiler fixture: %v\n%s", err, output)
		}
		profile, err := os.ReadFile(file)
		if err != nil {
			t.Fatal(err)
		}
		profiles = append(profiles, profile)
	}
	partial, _, err := rc.NormalizeGo(profiles[:1], map[string][]byte{"logic.go": source}, "sample")
	if err != nil {
		t.Fatal(err)
	}
	if partial.Files["logic.go"][3] {
		t.Fatal("one branch made same source line fully covered")
	}
	complete, catalogs, err := rc.NormalizeGo(profiles, map[string][]byte{"logic.go": source}, "sample")
	if err != nil {
		t.Fatal(err)
	}
	if len(complete.Files["logic.go"]) != 1 || !complete.Files["logic.go"][3] {
		t.Fatalf("real counters failed union: %+v", complete)
	}
	inv, err := rc.ScanInventory(root)
	if err != nil {
		t.Fatal(err)
	}
	bound, err := rc.BindCatalogs(inv, catalogs)
	if err != nil {
		t.Fatal(err)
	}
	result, err := bound.Merge(complete)
	if err != nil || !result.Complete || result.Percent == nil || *result.Percent != 100 || result.Executable != 1 {
		t.Fatalf("real source catalog merge failed: %+v %v", result, err)
	}
}
