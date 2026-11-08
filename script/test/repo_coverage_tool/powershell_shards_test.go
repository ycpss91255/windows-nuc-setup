package main

import (
 "bytes"
 "encoding/json"
 "os"
 "os/exec"
 "path/filepath"
 "strings"
 "testing"
)

func shardCLIFixture(t *testing.T) (string,string,string) {
 t.Helper()
 root:=t.TempDir()
 for name,text:=range map[string]string{"core/value.ps1":"function Value { return 1 }\n","test/powershell/unit/side_0_tests.ps1":"Value\n","test/powershell/unit/side_1_tests.ps1":"Value\n","test/powershell/coverage/safe_suite.ps1":"param($SuitePath,$SourceRoot)\n& $SuitePath\n"} {
  p:=filepath.Join(root,filepath.FromSlash(name));if err:=os.MkdirAll(filepath.Dir(p),0700);err!=nil{t.Fatal(err)};if err:=os.WriteFile(p,[]byte(text),0600);err!=nil{t.Fatal(err)}
 }
 if err:=os.MkdirAll(filepath.Join(root,"test/powershell/integration"),0700);err!=nil{t.Fatal(err)}
 git:=func(args ...string)string{t.Helper();cmd:=exec.Command("git",append([]string{"-C",root},args...)...);b,e:=cmd.CombinedOutput();if e!=nil{t.Fatalf("git fixture: %v %s",e,b)};return strings.TrimSpace(string(b))}
 git("init","-q");git("add",".");git("-c","user.name=CoverageFixture","-c","user.email=fixture@example.invalid","commit","-qm","fixture")
 sha:=git("rev-parse","HEAD")
 manifest:=filepath.Join(t.TempDir(),"manifest.json")
 b,_:=json.Marshal(map[string]any{"SourceRoot":root,"Sources":[]string{"core/value.ps1"},"Tests":[]string{"test/powershell/unit/side_0_tests.ps1","test/powershell/unit/side_1_tests.ps1"},"TestEngines":map[string]string{},"Wrapper":"test/powershell/coverage/safe_suite.ps1"})
 if err:=os.WriteFile(manifest,b,0600);err!=nil{t.Fatal(err)}
 return root,manifest,sha
}

func shardCLIArgs(root,manifest,sha string)[]string{return []string{"--source-root",root,"--manifest",manifest,"--expected-sha",sha,"--expected-run-url","https://github.com/example/repo/actions/runs/123","--run-attempt","1","--shard-count","2"}}

func TestPowerShellShardPlanPreservesCanonicalScope(t *testing.T){
 root,manifest,sha:=shardCLIFixture(t)
 output:=filepath.Join(t.TempDir(),"plan")
 args:=append(shardCLIArgs(root,manifest,sha),"--shard-index","1","--output-dir",output)
 if err:=powershellShardPlan(args,&bytes.Buffer{});err!=nil{t.Fatal(err)}
 b,err:=os.ReadFile(filepath.Join(output,"privatecollection_manifest.json"));if err!=nil{t.Fatal(err)}
 var plan struct{SourceRoot string;Sources,Tests []string;Wrapper string;TestEngines map[string]string}
 if err=json.Unmarshal(b,&plan);err!=nil{t.Fatal(err)}
 if plan.SourceRoot!=root || len(plan.Sources)!=1 || len(plan.Tests)!=1 || plan.Tests[0]!="test/powershell/unit/side_1_tests.ps1" || plan.Wrapper!="test/powershell/coverage/safe_suite.ps1" {t.Fatalf("scope changed: %#v",plan)}
 if err:=powershellShardPlan(args,&bytes.Buffer{});err==nil{t.Fatal("existing output accepted")}
}

func TestPowerShellShardPlanRejectsMissingCanonicalTest(t *testing.T){
 root,manifest,sha:=shardCLIFixture(t)
 b,_:=os.ReadFile(manifest);var m map[string]any;_ = json.Unmarshal(b,&m);m["Tests"]=[]string{"test/powershell/unit/side_0_tests.ps1"};b,_=json.Marshal(m);_ = os.WriteFile(manifest,b,0600)
 if err:=powershellShardPlan(append(shardCLIArgs(root,manifest,sha),"--shard-index","0","--output-dir",filepath.Join(t.TempDir(),"plan")),&bytes.Buffer{});err==nil{t.Fatal("reduced canonical test scope accepted")}
}
