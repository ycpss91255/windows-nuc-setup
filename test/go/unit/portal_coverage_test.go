package unit_test

import (
 "strings"
 "testing"
 a "windows_setup/script/test/acceptance"
)

func TestPortalCoverageVisibleContract(t *testing.T) {
 summary:=[]byte(`{"GoCoverage":{"Covered":8,"TotalStatements":10,"Percent":80}}`)
 valid:=`<p>Go 程式敘述覆蓋率：80.0%（8/10 statements）。範圍為全部自有 Go 工具（含 CLI），不含 PowerShell 或第三方程式；PowerShell 覆蓋率尚未量測。</p>`
 page,e:=a.ParsePage([]byte(valid));if e!=nil {t.Fatal(e)}
 if e=a.ValidatePortalCoverage(page.Visible,summary);e!=nil {t.Fatal(e)}
 for _,kind:=range []string{"wrong_percent","wrong_fraction","all_unmeasured","whole_repo_claim","hidden","malformed_summary"}{
  t.Run(kind,func(t *testing.T){
   html:=valid;data:=summary
   switch kind{
   case "wrong_percent":html=strings.ReplaceAll(html,"80.0%","99.0%")
   case "wrong_fraction":html=strings.ReplaceAll(html,"8/10 statements","9/10 statements")
   case "all_unmeasured":html="<p>程式碼覆蓋率也尚未量測。</p>"
   case "whole_repo_claim":html=strings.ReplaceAll(html,"全部自有 Go 工具（含 CLI），不含 PowerShell 或第三方程式","全部儲存庫")
   case "hidden":html="<details><summary>old</summary>"+html+"</details>"
   case "malformed_summary":data=[]byte(`{`)
   }
   page,e:=a.ParsePage([]byte(html));if e!=nil {t.Fatal(e)}
   if e=a.ValidatePortalCoverage(page.Visible,data);e==nil {t.Fatal("misleading homepage coverage accepted")}
  })
 }
 if e=a.ValidatePortalCoverage("程式碼覆蓋率尚未量測。",[]byte(`{}`));e!=nil {t.Fatalf("legacy missing evidence must remain honest: %v",e)}
}