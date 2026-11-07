package acceptance
import("fmt";"path/filepath";"strings")
func CoverageOutputLocation(source,out string)error{rel,e:=filepath.Rel(source,out);if e!=nil{return e};if rel!=".."&&!strings.HasPrefix(rel,".."+string(filepath.Separator)){return fmt.Errorf("coverage output must be outside read-only source")};return nil}
