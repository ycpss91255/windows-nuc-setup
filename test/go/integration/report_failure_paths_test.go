package integration_test

import (
	"encoding/json"
	"fmt"
	"os"
	"testing"
	a "windows_setup/script/test/acceptance"
)

func TestReportMissingAndMalformedEvidence(t *testing.T) {
	original := files(t, os.Getenv("WINDOWS_SETUP_ARTIFACT_DIR"))
	r := decode(t, original)
	for _, name := range []string{"summary.json", "junit.xml", "index.html", "summary.md", "unit.svg"} {
		t.Run("unreadable_"+name, func(t *testing.T) {
			read := func(n string) ([]byte, error) {
				if n == name {
					return nil, fmt.Errorf("explicit unreadable fixture")
				}
				return reader(original)(n)
			}
			if _, e := a.ValidateReport(read, r.Commit, r.RunUrl, false); e == nil {
				t.Fatal("unreadable evidence accepted")
			}
		})
	}
	for _, kind := range []string{"invalid_json", "checks_not_array", "assertions_not_array", "assertion_name_missing", "assertion_passed_string", "status_missing", "totals_not_object", "negative_total", "null_success", "missing_scope"} {
		t.Run(kind, func(t *testing.T) {
			m := copyFiles(original)
			var q map[string]any
			if e := json.Unmarshal(m["summary.json"], &q); e != nil {
				t.Fatal(e)
			}
			checks := q["Checks"].([]any)
			var checked map[string]any
			for _, v := range checks {
				c := v.(map[string]any)
				if c["Executed"] == true && len(c["Assertions"].([]any)) > 0 {
					checked = c
					break
				}
			}
			if checked == nil {
				t.Fatal("fixture needs real assertions")
			}
			switch kind {
			case "checks_not_array":
				q["Checks"] = true
			case "assertions_not_array":
				checked["Assertions"] = true
			case "assertion_name_missing":
				delete(checked["Assertions"].([]any)[0].(map[string]any), "Name")
			case "assertion_passed_string":
				checked["Assertions"].([]any)[0].(map[string]any)["Passed"] = "true"
			case "status_missing":
				delete(checked, "Status")
			case "totals_not_object":
				q["Totals"] = []any{}
			case "negative_total":
				q["Totals"].(map[string]any)["AssertionsFailed"] = -1
			case "null_success":
				q["Success"] = nil
			case "missing_scope":
				delete(q, "RequestedLayer")
			}
			m["summary.json"], _ = json.Marshal(q)
			if kind == "invalid_json" {
				m["summary.json"] = []byte(`{"broken":`)
			}
			if _, e := a.ValidateReport(reader(m), r.Commit, r.RunUrl, false); e == nil {
				t.Fatal("malformed evidence accepted")
			}
		})
	}
}
