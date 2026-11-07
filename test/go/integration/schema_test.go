package integration_test

import (
 "encoding/json"
 "os"
 "testing"
 a "windows_setup/script/test/acceptance"
)

func TestMissingBooleanEvidenceRejected(t *testing.T){
 original:=files(t,os.Getenv("WINDOWS_SETUP_ARTIFACT_DIR"));r:=decode(t,original)
 for _,field:=range []string{"Executed","Passed"}{t.Run(field,func(t *testing.T){m:=copyFiles(original);var q map[string]any;if e:=json.Unmarshal(m["summary.json"],&q);e!=nil{t.Fatal(e)};for _,item:=range q["Checks"].([]any){c:=item.(map[string]any);if c["Layer"]=="System"{delete(c,field)}};m["summary.json"],_=json.Marshal(q);if _,e:=a.ValidateReport(reader(m),r.Commit,r.RunUrl,false);e==nil{t.Fatalf("missing %s accepted as unexecuted evidence",field)}})}
}
