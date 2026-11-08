package integration_test

import (
 "encoding/json"
 "fmt"
 "os"
 "strings"
 "testing"
 a "windows_setup/script/test/acceptance"
 c "windows_setup/script/test/repo_coverage"
)
func TestWholeRepoCoverageEvidenceValidated(t *testing.T){
 m:=synthetic(t,files(t,os.Getenv("WINDOWS_SETUP_ARTIFACT_DIR")),true,"Branch")
 r:=decode(t,m); r.SchemaVersion=2
 checks:=[]a.Check{};for _,q:=range r.Checks{if q.Layer=="Unit"||q.Layer=="Integration"||q.Layer=="Static"{checks=append(checks,q)}};r.Checks=checks;save(m,r);m=synthetic(t,m,true,"Branch");r=decode(t,m)
 inventory:=c.Inventory{Sources:[]c.Source{{Path:"core/example.ps1",Language:"powershell",SHA256:strings.Repeat("b",64),ExpectedLines:[]int{1,2}}}}
 artifacts,err:=c.CreateEvidence(inventory,[]c.Report{{SchemaVersion:1,Metric:c.Metric,Files:map[string]map[int]bool{"core/example.ps1":{1:true,2:false}}}},c.Identity{Commit:r.Commit,RunUrl:r.RunUrl,MeasuredAt:r.MeasuredAt,SourceState:r.SourceState});if err!=nil{t.Fatal(err)}
 var raw map[string]any;if err=json.Unmarshal(m["summary.json"],&raw);err!=nil{t.Fatal(err)}
 var evidence any;json.Unmarshal(artifacts.Summary,&evidence);raw["RepoCoverage"]=evidence;raw["Coverage"]="Measured";m["summary.json"],_=json.Marshal(raw)
 m["repo_coverage.json"]=artifacts.Summary;m["coverage_inventory.json"]=artifacts.Inventory;m["coverage.xml"]=artifacts.XML
 label,status:="coverage branch","50.0%";l,q:=len(label)*7+12,len(status)*7+12
 m["coverage.svg"]=[]byte(fmt.Sprintf(`<svg xmlns="http://www.w3.org/2000/svg" height="20" width="%d"><rect width="%d" fill="#555"/><rect width="%d" fill="#007ec6"/><g font-size="11"><text>%s</text><text>%s</text></g></svg>`,l+q,l,q,label,status))
 if _,err=a.ValidateReport(reader(m),r.Commit,r.RunUrl,false);err!=nil{t.Fatalf("valid whole-repo evidence rejected: %v",err)}
 for _,name:=range []string{"repo_coverage.json","coverage_inventory.json","coverage.xml"}{t.Run(name,func(t *testing.T){bad:=copyFiles(m);if name=="repo_coverage.json"{bad[name]=[]byte(strings.Replace(string(bad[name]),"\"Percent\": 50","\"Percent\": 51",1))}else{bad[name]=append(bad[name],' ')};if _,err:=a.ValidateReport(reader(bad),r.Commit,r.RunUrl,false);err==nil{t.Fatal("tampered whole-repo evidence accepted")}})}
}
