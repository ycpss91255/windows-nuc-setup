package integration_test
import("os";"path/filepath";"testing"; a "windows_setup/script/test/acceptance")
func TestRepositorySourceGate(t *testing.T){root,e:=os.Getwd();if e!=nil{t.Fatal(e)};root=filepath.Clean(filepath.Join(root,"../../.."));doc,e:=a.ValidateSource(root);if e!=nil||doc==""{t.Fatalf("actual repository naming/entry/vendor source contract: %v",e)}}
