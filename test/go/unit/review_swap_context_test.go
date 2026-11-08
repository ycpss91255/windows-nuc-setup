package unit_test
import (
 "encoding/json"
 "testing"
 rc "windows_setup/script/test/repo_coverage"
)
func TestReviewShardsRejectSwappedNativeCaseWorkers(t *testing.T) {
 f:=newPSShardFixture(t)
 for i:=range f.catalog.Tests { f.catalog.Tests[i].Engine="powershell" }
 for i:=range f.inputs {
  var w map[string]any
  if err:=json.Unmarshal(f.files[i]["worker_0.json"],&w);err!=nil{t.Fatal(err)}
  w["Engine"]="powershell";w["EngineVersion"]="5.1.20348.1"
  f.files[i]["worker_0.json"]=psShardJSON(t,w)
  var p map[string]any
  if err:=json.Unmarshal(f.files[i]["evidence.json"],&p);err!=nil{t.Fatal(err)}
  d:=p["Workers"].([]any)[0].(map[string]any)
  d["Engine"]="powershell";d["EngineVersion"]="5.1.20348.1"
  f.files[i]["evidence.json"]=psShardJSON(t,p)
  f.manifest(t,i,func(m *rc.PowerShellShardManifest){m.Tests=f.catalog.Tests;m.Workers[0].SHA256=psShardHash(f.files[i]["worker_0.json"])})
 }
 if _,err:=rc.MergePowerShellShards(f.identity,f.catalog,f.inputs,f.inventory);err!=nil{t.Fatalf("valid same-engine baseline: %v",err)}
 // Wrong source-case evidence: whole raw bundles move, while the independent
 // envelope keeps its expected case label and hashes the substituted bytes.
 f.files[0]["worker_0.json"],f.files[1]["worker_0.json"]=f.files[1]["worker_0.json"],f.files[0]["worker_0.json"]
 f.files[0]["evidence.json"],f.files[1]["evidence.json"]=f.files[1]["evidence.json"],f.files[0]["evidence.json"]
 for i:=range f.inputs{f.manifest(t,i,func(m *rc.PowerShellShardManifest){m.Workers[0].SHA256=psShardHash(f.files[i]["worker_0.json"])})}
 if _,err:=rc.MergePowerShellShards(f.identity,f.catalog,f.inputs,f.inventory);err==nil{t.Fatal("swapped native workers accepted under unchanged canonical test labels: raw collector does not bind executed suite identity")}
}