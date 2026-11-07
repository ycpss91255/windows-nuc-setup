package acceptance
import "fmt"
type CoverageMeasurement struct{Covered,TotalStatements int;Percent float64;Profile []byte;Packages []string}
func EvaluateCoverage(profiles [][]byte,expectedFiles []string)(CoverageMeasurement,error){return CoverageMeasurement{},fmt.Errorf("coverage measurement not implemented")}
