package acceptance
import "fmt"
type CoverageProvenance struct{Commit,RunUrl,MeasuredAt,SourceState,GoVersion,Environment string}
type GoCoverage struct{SchemaVersion int;Scope,Metric string;Covered,TotalStatements int;Percent float64;Threshold int;Commit,RunUrl,MeasuredAt,SourceState,GoVersion,Environment,ProfileSHA256 string;Packages []string}
func CreateCoverageEvidence(profiles [][]byte,files []string,p CoverageProvenance)(GoCoverage,[]byte,error){return GoCoverage{},nil,fmt.Errorf("coverage evidence not implemented")}
func ValidateCoverageEvidence(data,profile []byte,files []string,sha,run string)(GoCoverage,error){return GoCoverage{},fmt.Errorf("coverage evidence validation not implemented")}
