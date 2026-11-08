package unit_test

import (
	"strings"
	"encoding/json"
	"testing"
	rc "windows_setup/script/test/repo_coverage"
)

func TestCMDLauncherCatalogAndUnsupportedSyntax(t *testing.T) {
	source := []byte("@echo off\r\npowershell.exe -NoProfile -File \"%~dp0core\\run.ps1\" %*\r\n")
	launcher, err := rc.ParseCMDLauncher(source)
	if err != nil || launcher.Line != 2 || !launcher.ForwardArguments {
		t.Fatalf("%+v %v", launcher, err)
	}
	for _, bad := range []string{string(source) + "echo extra\n", strings.ReplaceAll(string(source), " %*", " & echo bad"), strings.ReplaceAll(string(source), "%~dp0", "%USERPROFILE%"), "@echo off\nif 1==1 echo no\n", strings.ReplaceAll(string(source), "-File", "-Command"), strings.ReplaceAll(string(source), "run.ps1", "run.ps1\" & evil \"")} {
		if _, err := rc.ParseCMDLauncher([]byte(bad)); err == nil {
			t.Fatalf("accepted unsupported %q", bad)
		}
	}
}

func TestCMDRejectsAmbiguousRawJSON(t *testing.T){
 for _,bad:=range []string{`{"SchemaVersion":1,"SchemaVersion":2}`,`{"Unexpected":1}`,`{} {}`} {if _,err:=rc.DecodeCMDEvidence([]byte(bad));err==nil{t.Fatal("ambiguous evidence accepted")}}
 data,_:=json.Marshal(rc.CMDEvidence{SchemaVersion:1});if _,err:=rc.DecodeCMDEvidence(data);err!=nil{t.Fatal(err)}
}
