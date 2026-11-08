package integration_test

import (
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"encoding/json"
	"time"
	a "windows_setup/script/test/acceptance"
	rc "windows_setup/script/test/repo_coverage"
)

func TestRepoCoverageCLIValidatesArtifacts(t *testing.T) {
	root, err := filepath.Abs("../../..")
	if err != nil {
		t.Fatal(err)
	}
	bin := filepath.Join(t.TempDir(), "coverage.exe")
	goexe := filepath.Join(runtime.GOROOT(), "bin", "go")
	if runtime.GOOS == "windows" {
		goexe += ".exe"
	}
	build := exec.Command(goexe, "build", "-mod=vendor", "-cover", "-coverpkg=./script/test/...", "-o", bin, "./script/test/repo_coverage_tool")
	build.Dir = root
	if out, err := build.CombinedOutput(); err != nil {
		t.Fatalf("build: %v %s", err, out)
	}
	sha := strings.Repeat("a", 40)
	inv := rc.Inventory{Sources: []rc.Source{{Path: "example.go", Language: "go", SHA256: strings.Repeat("a", 64), ExpectedLines: []int{2}}}}
	artifacts, err := rc.CreateEvidence(inv, []rc.Report{{SchemaVersion: 1, Metric: rc.Metric, Files: map[string]map[int]bool{"example.go": {2: true}}}}, rc.Identity{Commit: sha, MeasuredAt: "2026-01-01T00:00:00Z", SourceState: "Clean"})
	if err != nil {
		t.Fatal(err)
	}
	dir := t.TempDir()
	for name, data := range map[string][]byte{"repo_coverage.json": artifacts.Summary, "coverage_inventory.json": artifacts.Inventory, "coverage.xml": artifacts.XML} {
		if err := os.WriteFile(filepath.Join(dir, name), data, 0600); err != nil {
			t.Fatal(err)
		}
	}
	run := func(ok bool, args ...string) {
		t.Helper()
		cmd := exec.Command(bin, args...)
		cmd.Env = os.Environ()
		if d := os.Getenv("WINDOWS_SETUP_CLI_COVERAGE_DIR"); d != "" {
			cmd.Env = append(cmd.Env, "GOCOVERDIR="+d)
		}
		out, err := cmd.CombinedOutput()
		if (err == nil) != ok {
			t.Fatalf("args %v: %v %s", args, err, out)
		}
	}
	run(true, "verify", "--artifact-dir", dir, "--expected-sha", sha)
	run(true, "verify", "--artifact-dir", dir, "--expected-sha", sha, "--require-complete", "--minimum-percent", "80")
	run(false, "verify", "--artifact-dir", dir, "--expected-sha", sha, "--minimum-percent", "101")
	run(false, "verify", "--artifact-dir", dir, "--expected-sha", sha, "--minimum-percent", "-1")
	run(false, "verify", "--artifact-dir", dir, "--expected-sha", strings.Repeat("b", 40))
	run(false, "verify", "--artifact-dir", dir, "--expected-sha", sha, "--source-root", t.TempDir())
	run(false, "verify", "--artifact-dir", t.TempDir(), "--expected-sha", sha)
	run(false, "verify")
	run(false, "verify", "--unknown")
	run(false, "verify", "--artifact-dir", dir, "--expected-sha", sha, "extra")
	run(false, "unknown")
	run(false)
	for _, tc := range []struct {
		covered, total int
		missing        bool
		ok             bool
	}{{4, 5, false, true}, {7999, 10000, false, false}, {1, 1, true, false}} {
		lines := []int{}
		hits := map[int]bool{}
		for n := 1; n <= tc.total; n++ {
			lines = append(lines, n)
			hits[n] = n <= tc.covered
		}
		check := rc.Inventory{Sources: []rc.Source{{Path: "example.go", Language: "go", SHA256: strings.Repeat("a", 64), ExpectedLines: lines}}}
		if tc.missing {
			check.Sources = append(check.Sources, rc.Source{Path: "missing.ps1", Language: "powershell", SHA256: strings.Repeat("b", 64)})
		}
		a, err := rc.CreateEvidence(check, []rc.Report{{SchemaVersion: 1, Metric: rc.Metric, Files: map[string]map[int]bool{"example.go": hits}}}, rc.Identity{Commit: sha, MeasuredAt: "2026-01-01T00:00:00Z", SourceState: "Clean"})
		if err != nil {
			t.Fatal(err)
		}
		for n, b := range map[string][]byte{"repo_coverage.json": a.Summary, "coverage_inventory.json": a.Inventory, "coverage.xml": a.XML} {
			if err := os.WriteFile(filepath.Join(dir, n), b, 0600); err != nil {
				t.Fatal(err)
			}
		}
		run(tc.ok, "verify", "--artifact-dir", dir, "--expected-sha", sha, "--require-complete", "--minimum-percent", "80")
	}
	if err := os.WriteFile(filepath.Join(dir, "coverage.xml"), []byte("<invalid>"), 0600); err != nil {
		t.Fatal(err)
	}
	run(false, "verify", "--artifact-dir", dir, "--expected-sha", sha)
}

func TestRepoCoverageCLICollectsCleanSources(t *testing.T) {
 repo,_:=filepath.Abs("../../..");fixture:=t.TempDir();external:=t.TempDir()
 source:="package logic\nfunc Value() int { return 1 }\n"
 if err:=os.MkdirAll(filepath.Join(fixture,"script/test/logic"),0700);err!=nil{t.Fatal(err)}
 if err:=os.WriteFile(filepath.Join(fixture,"script/test/logic/logic.go"),[]byte(source),0600);err!=nil{t.Fatal(err)}
 git:=func(args ...string)string{t.Helper();c:=exec.Command("git",append([]string{"-C",fixture},args...)...);out,err:=c.CombinedOutput();if err!=nil{t.Fatalf("git: %v %s",err,out)};return strings.TrimSpace(string(out))}
 git("init");git("config","user.name","Coverage Fixture");git("config","user.email","fixture@example.invalid");git("add",".");git("commit","-m","fixture");sha:=git("rev-parse","HEAD")
 profile:=[]byte("mode: set\nwindows_setup/script/test/logic/logic.go:2.18,2.30 1 1\n")
 evidence,profile,err:=a.CreateCoverageEvidence([][]byte{profile},[]string{"windows_setup/script/test/logic/logic.go"},a.CoverageProvenance{Commit:sha,MeasuredAt:time.Now().UTC().Format(time.RFC3339),SourceState:"Clean",GoVersion:"go1.27.3",Environment:"fixture"});if err!=nil{t.Fatal(err)}
 data,_:=json.Marshal(evidence);ep:=filepath.Join(external,"go.json");pp:=filepath.Join(external,"go.out");os.WriteFile(ep,data,0600);os.WriteFile(pp,profile,0600)
 goexe:=filepath.Join(runtime.GOROOT(),"bin","go");if runtime.GOOS=="windows"{goexe+=".exe"};bin:=filepath.Join(external,"tool.exe")
 build:=exec.Command(goexe,"build","-mod=vendor","-cover","-coverpkg=./script/test/...","-o",bin,"./script/test/repo_coverage_tool");build.Dir=repo;if out,err:=build.CombinedOutput();err!=nil{t.Fatalf("build %v %s",err,out)}
 dest:=filepath.Join(external,"results")
 args:=[]string{"collect","--source-root",fixture,"--output-dir",dest,"--expected-sha",sha,"--go-evidence",ep,"--go-profile",pp}
 run:=func(ok bool,argv ...string){t.Helper();cmd:=exec.Command(bin,argv...);cmd.Env=os.Environ();if d:=os.Getenv("WINDOWS_SETUP_CLI_COVERAGE_DIR");d!=""{cmd.Env=append(cmd.Env,"GOCOVERDIR="+d)};out,err:=cmd.CombinedOutput();if (err==nil)!=ok{t.Fatalf("%v: %v %s",argv,err,out)}}
 run(true,args...)
 run(true,"verify","--artifact-dir",dest,"--expected-sha",sha,"--source-root",fixture,"--require-complete","--minimum-percent","80")
 run(false,args...) // immutable existing output
 os.WriteFile(filepath.Join(fixture,"script/test/logic/logic.go"),[]byte(source+"// changed\n"),0600)
 args[4]=filepath.Join(external,"dirty")
 run(false,args...) // HEAD alone cannot identify modified bytes
}
