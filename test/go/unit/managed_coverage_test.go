package unit_test

import (
	"crypto/sha256"
	"fmt"
	"strings"
	"testing"
	"encoding/json"
	rc "windows_setup/script/test/repo_coverage"
)

func TestManagedRangesRequireNativeMergeAndCompleteLines(t *testing.T) {
	source := []byte("class Sample {\n static int Value(bool b) { return b ? 1 : 2; }\n}\n")
	hash := fmt.Sprintf("%x", sha256.Sum256(source))
	raw := fmt.Sprintf(`<results><modules><module id="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"><functions><function token="0x6000001" name="Value(bool)" type_name="Sample"><ranges><range source_id="1" start_line="2" end_line="2" start_column="2" end_column="25" covered="yes"/><range source_id="1" start_line="2" end_line="2" start_column="26" end_column="43" covered="partial"/></ranges></function></functions><source_files><source_file id="1" path="native/sample.cs" checksum_type="SHA256" checksum="%s"/></source_files></module></modules></results>`, hash)
	originals := map[string][]byte{"native/sample.cs": source}
	partial, catalogs, err := rc.ParseManagedCoverage([]byte(raw), "", originals)
	if err != nil || partial.Files["native/sample.cs"][2] || len(catalogs) != 1 {
		t.Fatalf("partial credited: %+v %v", partial, err)
	}
	full := strings.ReplaceAll(raw, `covered="partial"`, `covered="yes"`)
	report, _, err := rc.ParseManagedCoverage([]byte(full), "", originals)
	if err != nil || !report.Files["native/sample.cs"][2] {
		t.Fatalf("complete missed: %+v %v", report, err)
	}
	for _, bad := range []string{strings.ReplaceAll(raw, hash, strings.Repeat("0", 64)), strings.ReplaceAll(raw, `covered="partial"`, `covered="unknown"`), strings.ReplaceAll(raw, `source_id="1"`, `source_id="2"`), strings.ReplaceAll(raw, `end_column="43"`, `end_column="999"`), strings.ReplaceAll(raw, `native/sample.cs`, `../outside.cs`), strings.ReplaceAll(raw, `start_line="2"`, `start_line="0"`), strings.ReplaceAll(raw, `<ranges>`, `<ranges><range source_id="1" start_line="2" end_line="2" start_column="2" end_column="25" covered="yes"/>`)} {
		if _, _, err := rc.ParseManagedCoverage([]byte(bad), "", originals); err == nil {
			t.Fatal("invalid managed counter accepted")
		}
	}
	originals["native/missing.cs"] = source
	if _, _, err := rc.ParseManagedCoverage([]byte(raw), "", originals); err == nil {
		t.Fatal("omitted managed source accepted")
	}
}

func TestManagedEvidenceRequiresNativeBinaryRosterAndHashes(t *testing.T){
 source:=[]byte("class X { static int Value() { return 1; } }\n");hash:=fmt.Sprintf("%x",sha256.Sum256(source))
 raw:=fmt.Sprintf(`<results><modules><module id="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"><functions><function token="0x6000001" name="Value()" type_name="X"><ranges><range source_id="1" start_line="1" end_line="1" start_column="31" end_column="40" covered="partial"/></ranges></function></functions><source_files><source_file id="1" path="native/x.cs" checksum_type="SHA256" checksum="%s"/></source_files></module></modules></results>`,hash)
 files:=map[string][]byte{"assembly.dll":[]byte("assembly"),"assembly.pdb":[]byte("pdb"),"worker.coverage":[]byte("raw"),"worker.xml":[]byte(raw),"merged.coverage":[]byte("native merged"),"merged.xml":[]byte(strings.ReplaceAll(raw,`covered="partial"`,`covered="yes"`))}
 digest:=func(name string)string{return fmt.Sprintf("%x",sha256.Sum256(files[name]))}
 proof:=map[string]any{"SchemaVersion":1,"Metric":rc.Metric,"Tool":map[string]any{"Id":"Microsoft.dotnet-coverage","Version":"17.14.1","PackageSHA512":"hgzaG+c7LtKup6HZixvXtn3l4Pa8VK23bM9vLHveD3Iq2XlzLu7vqMZwtVjQdsof83wx5OzY0tpDh3+YRdOVjA=="},"SourceRoot":"","Sources":[]any{map[string]any{"Path":"native/x.cs","SHA256":hash}},"AssemblyPath":"assembly.dll","AssemblySHA256":digest("assembly.dll"),"PDBPath":"assembly.pdb","PDBSHA256":digest("assembly.pdb"),"Shards":[]any{map[string]any{"BinaryPath":"worker.coverage","SHA256":digest("worker.coverage"),"XmlPath":"worker.xml","XmlSHA256":digest("worker.xml")}},"MergedBinaryPath":"merged.coverage","MergedBinarySHA256":digest("merged.coverage"),"MergedXmlPath":"merged.xml","MergedXmlSHA256":digest("merged.xml"),"MergeNative":true}
 read:=func(name string)([]byte,error){data,ok:=files[name];if !ok{return nil,fmt.Errorf("missing")};return data,nil}
 originals:=map[string][]byte{"native/x.cs":source}
 data,_:=json.Marshal(proof);r,_,err:=rc.NormalizeManaged(data,read,originals)
 if err!=nil || !r.Files["native/x.cs"][1]{t.Fatalf("native merged rejected: %+v %v",r,err)}
 for _,field:=range []string{"MergeNative","Metric","MergedXmlSHA256","AssemblySHA256","PDBSHA256"}{
  var p map[string]any;json.Unmarshal(data,&p);if field=="MergeNative"{p[field]=false}else{p[field]="invalid"};b,_:=json.Marshal(p);if _,_,err:=rc.NormalizeManaged(b,read,originals);err==nil{t.Fatalf("invalid %s accepted",field)}
 }
 files["worker.xml"]=[]byte(strings.ReplaceAll(raw,`start_column="31"`,`start_column="32"`));proof["Shards"]=[]any{map[string]any{"BinaryPath":"worker.coverage","SHA256":digest("worker.coverage"),"XmlPath":"worker.xml","XmlSHA256":digest("worker.xml")}}
 data,_=json.Marshal(proof);if _,_,err:=rc.NormalizeManaged(data,read,originals);err==nil{t.Fatal("changed native counter roster accepted")}
}
