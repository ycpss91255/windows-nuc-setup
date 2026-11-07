package acceptance

import "errors"

type Reader func(string)([]byte,error)
type Assertion struct {Name string; Passed *bool}
type Check struct {Name,Layer,Status string; Executed bool; Passed *bool; Assertions []Assertion}
type Totals struct {SuitesExecuted,AssertionsExecuted,AssertionsPassed,AssertionsFailed,UnexecutedSuites int}
type Report struct {SchemaVersion int; RequestedLayer,Commit,RunUrl,SourceState,Coverage,RefType,RefName,Environment,Version,MeasuredAt string; Success bool; Checks []Check; Totals Totals}

func ValidateReport(read Reader,sha,run string,main bool)(Report,error){return Report{},errors.New("report validation not implemented")}
func ValidatePortal(read Reader,readme,sha,run,base string)(Report,error){return Report{},errors.New("portal validation not implemented")}
func VerifyWithRetry(read Reader,readme,sha,run,base string,attempts int,sleep func())(Report,error){return Report{},errors.New("retry not implemented")}
