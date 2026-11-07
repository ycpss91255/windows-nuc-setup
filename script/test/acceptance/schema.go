package acceptance

import (
	"encoding/json"
	"fmt"
)

func requiredFields(m map[string]json.RawMessage, names ...string) error {
	for _, n := range names {
		if _, ok := m[n]; !ok {
			return fmt.Errorf("R02 缺少證據欄位：%s", n)
		}
	}
	return nil
}
func booleanField(m map[string]json.RawMessage, name string, nullable bool) error {
	v, ok := m[name]
	if !ok {
		return fmt.Errorf("R02 缺少布林證據：%s", name)
	}
	s := string(v)
	if s != "true" && s != "false" && !(nullable && s == "null") {
		return fmt.Errorf("R02 非法布林證據：%s", name)
	}
	return nil
}
func validateSchema(data []byte) error {
	var m map[string]json.RawMessage
	if e := decode(data, &m); e != nil {
		return e
	}
	if e := requiredFields(m, "SchemaVersion", "RequestedLayer", "Commit", "RunUrl", "SourceState", "Coverage", "RefType", "RefName", "MeasuredAt", "Checks", "Totals"); e != nil {
		return e
	}
	if e := booleanField(m, "Success", false); e != nil {
		return e
	}
	var checks []map[string]json.RawMessage
	if e := json.Unmarshal(m["Checks"], &checks); e != nil {
		return e
	}
	for _, c := range checks {
		if e := requiredFields(c, "Name", "Layer", "Status", "Assertions"); e != nil {
			return e
		}
		if e := booleanField(c, "Executed", false); e != nil {
			return e
		}
		if e := booleanField(c, "Passed", true); e != nil {
			return e
		}
		var assertions []map[string]json.RawMessage
		if e := json.Unmarshal(c["Assertions"], &assertions); e != nil {
			return e
		}
		for _, a := range assertions {
			if e := requiredFields(a, "Name"); e != nil {
				return e
			}
			if e := booleanField(a, "Passed", false); e != nil {
				return e
			}
		}
	}
	var totals map[string]json.RawMessage
	if e := json.Unmarshal(m["Totals"], &totals); e != nil {
		return e
	}
	return requiredFields(totals, "SuitesExecuted", "AssertionsExecuted", "AssertionsPassed", "AssertionsFailed", "UnexecutedSuites")
}
