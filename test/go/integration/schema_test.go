package integration_test

import (
	"encoding/json"
	"os"
	"strings"
	"testing"
	a "windows_setup/script/test/acceptance"
)

func TestXMLNamespacesAndNullTotals(t *testing.T) {
	original := files(t, os.Getenv("WINDOWS_SETUP_ARTIFACT_DIR"))
	r := decode(t, original)
	for _, kind := range []string{"svg_namespace", "junit_namespace", "null_total"} {
		t.Run(kind, func(t *testing.T) {
			m := copyFiles(original)
			switch kind {
			case "svg_namespace":
				s := strings.ReplaceAll(string(m["unit.svg"]), "<rect ", `<rect xmlns="" `)
				s = strings.ReplaceAll(s, "<g ", `<g xmlns="" `)
				m["unit.svg"] = []byte(s)
			case "junit_namespace":
				m["junit.xml"] = []byte(strings.ReplaceAll(string(m["junit.xml"]), "<testsuite ", `<testsuite xmlns="urn:wrong" `))
			case "null_total":
				var q map[string]any
				json.Unmarshal(m["summary.json"], &q)
				q["Totals"].(map[string]any)["AssertionsFailed"] = nil
				m["summary.json"], _ = json.Marshal(q)
			}
			if _, e := a.ValidateReport(reader(m), r.Commit, r.RunUrl, false); e == nil {
				t.Fatalf("invalid %s accepted", kind)
			}
		})
	}
}

func TestMissingBooleanEvidenceRejected(t *testing.T) {
	original := files(t, os.Getenv("WINDOWS_SETUP_ARTIFACT_DIR"))
	r := decode(t, original)
	for _, field := range []string{"Executed", "Passed"} {
		t.Run(field, func(t *testing.T) {
			m := copyFiles(original)
			var q map[string]any
			if e := json.Unmarshal(m["summary.json"], &q); e != nil {
				t.Fatal(e)
			}
			for _, item := range q["Checks"].([]any) {
				c := item.(map[string]any)
				if c["Layer"] == "System" {
					delete(c, field)
				}
			}
			m["summary.json"], _ = json.Marshal(q)
			if _, e := a.ValidateReport(reader(m), r.Commit, r.RunUrl, false); e == nil {
				t.Fatalf("missing %s accepted as unexecuted evidence", field)
			}
		})
	}
}
