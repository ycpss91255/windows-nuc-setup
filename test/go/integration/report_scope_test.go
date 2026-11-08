package integration_test

import (
 "os"
 "testing"
 a "windows_setup/script/test/acceptance"
)

func TestCurrentReportSchemaExcludesSystem(t *testing.T) {
 original := files(t, os.Getenv("WINDOWS_SETUP_ARTIFACT_DIR"))
 r := decode(t, original)
 r.SchemaVersion = 2
 checks := []a.Check{}
 for _, c := range r.Checks { if c.Layer == "Static" || c.Layer == "Unit" || c.Layer == "Integration" { checks = append(checks,c) } }
 r.Checks = checks
 save(original,r)
 current := synthetic(t,original,true,"Branch")
 delete(current,"system.svg")
 if _,err:=a.ValidateReport(reader(current),r.Commit,r.RunUrl,false);err!=nil {t.Fatalf("schema2 requires only actual test evidence: %v",err)}
 injected:=copyFiles(current)
 q:=decode(t,injected)
 q.Checks=append(q.Checks,a.Check{Name:"removed requirement",Layer:"System",Status:"NotRun"})
 q.Totals.UnexecutedSuites++
 save(injected,q)
 if _,err:=a.ValidateReport(reader(injected),q.Commit,q.RunUrl,false);err==nil {t.Fatal("system placeholder accepted in schema2")}
 failed:=synthetic(t,current,false,"Branch")
 if got,err:=a.ValidateReport(reader(failed),r.Commit,r.RunUrl,false);err!=nil || got.Success {t.Fatalf("real failures must remain visible: %v",err)}
}