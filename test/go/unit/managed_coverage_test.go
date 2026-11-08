package unit_test

import("crypto/sha256";"fmt";"strings";"testing";rc "windows_setup/script/test/repo_coverage")

func TestManagedRangesRequireNativeMergeAndCompleteLines(t *testing.T){
 source:=[]byte("class Sample {\n static int Value(bool b) { return b ? 1 : 2; }\n}\n")
 hash:=fmt.Sprintf("%x",sha256.Sum256(source))
 raw:=fmt.Sprintf(`<results><modules><module id="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"><functions><function token="0x6000001" name="Value(bool)" type_name="Sample"><ranges><range source_id="1" start_line="2" end_line="2" start_column="2" end_column="25" covered="yes"/><range source_id="1" start_line="2" end_line="2" start_column="26" end_column="43" covered="partial"/></ranges></function></functions><source_files><source_file id="1" path="native/sample.cs" checksum_type="SHA256" checksum="%s"/></source_files></module></modules></results>`,hash)
 originals:=map[string][]byte{"native/sample.cs":source}
 partial,catalogs,err:=rc.ParseManagedCoverage([]byte(raw),"",originals)
 if err!=nil || partial.Files["native/sample.cs"][2] || len(catalogs)!=1{t.Fatalf("partial credited: %+v %v",partial,err)}
 full:=strings.ReplaceAll(raw,`covered="partial"`,`covered="yes"`)
 report,_,err:=rc.ParseManagedCoverage([]byte(full),"",originals)
 if err!=nil || !report.Files["native/sample.cs"][2]{t.Fatalf("complete missed: %+v %v",report,err)}
 for _,bad:=range []string{strings.ReplaceAll(raw,hash,strings.Repeat("0",64)),strings.ReplaceAll(raw,`covered="partial"`,`covered="unknown"`),strings.ReplaceAll(raw,`source_id="1"`,`source_id="2"`),strings.ReplaceAll(raw,`end_column="43"`,`end_column="999"`),strings.ReplaceAll(raw,`native/sample.cs`,`../outside.cs`),strings.ReplaceAll(raw,`start_line="2"`,`start_line="0"`),strings.ReplaceAll(raw,`<ranges>`,`<ranges><range source_id="1" start_line="2" end_line="2" start_column="2" end_column="25" covered="yes"/>`)}{
  if _,_,err:=rc.ParseManagedCoverage([]byte(bad),"",originals);err==nil{t.Fatal("invalid managed counter accepted")}
 }
 originals["native/missing.cs"]=source
 if _,_,err:=rc.ParseManagedCoverage([]byte(raw),"",originals);err==nil{t.Fatal("omitted managed source accepted")}
}
