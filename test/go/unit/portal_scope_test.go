package unit_test

import (
 "testing"
 a "windows_setup/script/test/acceptance"
)
func TestSchema2PortalCoverageIsWholeRepoOnly(t *testing.T){
 summary:=[]byte(`{"SchemaVersion":2,"GoCoverage":{"Covered":8,"TotalStatements":10,"Percent":80}}`)
 if err:=a.ValidatePortalCoverage("整體覆蓋率 尚未提供完整量測。",summary);err!=nil{t.Fatalf("Go statements must not replace whole-repo metric: %v",err)}
 for _,bad:=range []string{"整體覆蓋率 80.0%", "整體覆蓋率 尚未提供完整量測。80.0%", "Go 程式敘述覆蓋率：80.0%", "尚未提供完整量測。"}{if err:=a.ValidatePortalCoverage(bad,summary);err==nil{t.Fatalf("misleading overall claim accepted: %s",bad)}}
 measured:=[]byte(`{"SchemaVersion":2,"RepoCoverage":{"Result":{"Complete":true,"Covered":8,"Executable":10,"Percent":80}}}`)
 if err:=a.ValidatePortalCoverage("整體覆蓋率 80.0%（8/10 可執行行）",measured);err!=nil{t.Fatal(err)}
 for _,bad:=range []string{"整體覆蓋率 99.0%（8/10 可執行行）","整體覆蓋率 80.0%（9/10 可執行行）","整體覆蓋率 尚未提供完整量測。","80.0%（8/10 可執行行）"}{if err:=a.ValidatePortalCoverage(bad,measured);err==nil{t.Fatalf("wrong measured overview accepted: %s",bad)}}
}
