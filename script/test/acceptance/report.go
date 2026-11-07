package acceptance

import (
	"encoding/json"
	"encoding/xml"
	"fmt"
	"regexp"
	"strings"
)

type Reader func(string) ([]byte, error)
type Assertion struct {
	Name   string
	Passed *bool
}
type Check struct {
	Name, Layer, Status string
	Executed            bool
	Passed              *bool
	Assertions          []Assertion
}
type Totals struct{ SuitesExecuted, AssertionsExecuted, AssertionsPassed, AssertionsFailed, UnexecutedSuites int }
type Report struct {
	SchemaVersion                                                                                             int
	RequestedLayer, Commit, RunUrl, SourceState, Coverage, RefType, RefName, Environment, Version, MeasuredAt string
	Success                                                                                                   bool
	Checks                                                                                                    []Check
	Totals                                                                                                    Totals
}

func decode(data []byte, v any) error {
	return json.Unmarshal([]byte(strings.TrimPrefix(string(data), "\ufeff")), v)
}
func BadgeStatus(r Report, name string) string {
	if name == "coverage" {
		return "not measured"
	}
	if name == "system" {
		return "not run"
	}
	status := "not run"
	for _, c := range r.Checks {
		if strings.EqualFold(c.Layer, name) && c.Executed {
			if status == "not run" {
				status = "passed"
			}
			if c.Passed == nil || !*c.Passed {
				status = "failed"
			}
		}
	}
	return status
}
func ValidateSVG(data []byte, r Report, name string) error {
	var s struct {
		XMLName xml.Name
		Height  string `xml:"height,attr"`
		Width   string `xml:"width,attr"`
		Rects   []struct {
			Width string `xml:"width,attr"`
			Fill  string `xml:"fill,attr"`
		} `xml:"rect"`
		Group struct {
			Font  string   `xml:"font-size,attr"`
			Texts []string `xml:"text"`
		} `xml:"g"`
	}
	if e := xml.Unmarshal(data, &s); e != nil {
		return e
	}
	label := name + " " + strings.ToLower(r.RefType)
	status := BadgeStatus(r, name)
	color := "#9f9f9f"
	if status == "passed" {
		color = "#4c1"
	} else if status == "failed" {
		color = "#e05d44"
	}
	if s.XMLName.Space != "http://www.w3.org/2000/svg" || s.XMLName.Local != "svg" || s.Height != "20" || s.Width != fmt.Sprint((len(label)+len(status))*7+24) || s.Group.Font != "11" || len(s.Group.Texts) != 2 || s.Group.Texts[0] != label || s.Group.Texts[1] != status || len(s.Rects) != 2 || s.Rects[0].Fill != "#555" || s.Rects[1].Fill != color || s.Rects[0].Width != fmt.Sprint(len(label)*7+12) || s.Rects[1].Width != fmt.Sprint(len(status)*7+12) {
		return fmt.Errorf("R05 徽章幾何、配色或狀態不符：%s", name)
	}
	return nil
}
func ValidateReport(read Reader, sha, run string, main bool) (Report, error) {
	var r Report
	get := func(n string) ([]byte, error) {
		b, e := read(n)
		if e != nil {
			return nil, fmt.Errorf("R04 %s: %w", n, e)
		}
		return b, nil
	}
	data, e := get("summary.json")
	if e != nil {
		return r, e
	}
	if e = decode(data, &r); e != nil {
		return r, e
	}
	fail := func(s string) (Report, error) { return r, fmt.Errorf("%s", s) }
	if r.SchemaVersion != 1 || r.RequestedLayer != "All" {
		return fail("R02 缺少完整測試範圍")
	}
	if r.Commit != sha || r.RunUrl != run || r.SourceState != "Clean" {
		return fail("R03 提交、執行來源或乾淨版本不符")
	}
	if main && (r.RefType != "Branch" || r.RefName != "main") {
		return fail("R03 部署報表不是 main 分支")
	}
	if r.Coverage != "NotMeasured" || len(r.Checks) == 0 {
		return fail("R02 空測試或冒稱覆蓋率")
	}
	layers := map[string]bool{}
	totals := Totals{}
	success := true
	for _, c := range r.Checks {
		if c.Executed {
			layers[c.Layer] = true
			totals.SuitesExecuted++
			success = success && c.Passed != nil && *c.Passed
			for _, a := range c.Assertions {
				totals.AssertionsExecuted++
				if a.Passed != nil {
					if *a.Passed {
						totals.AssertionsPassed++
					} else {
						totals.AssertionsFailed++
					}
				}
			}
		} else {
			totals.UnexecutedSuites++
		}
		if c.Layer == "System" || c.Layer == "System E2E" {
			if c.Status != "NotRun" || c.Executed || c.Passed != nil || len(c.Assertions) != 0 {
				return fail("R02 未執行實機測試被誤標通過")
			}
			layers[c.Layer] = true
		}
	}
	for _, l := range []string{"Unit", "Integration", "System", "System E2E"} {
		if !layers[l] {
			return fail("R02 缺少必要測試層：" + l)
		}
	}
	if r.Success != success || r.Totals != totals {
		return fail("R02 統計或整體結果與逐項證據不一致")
	}
	var junit struct {
		XMLName xml.Name
		Suites  []struct {
			Name  string `xml:"name,attr"`
			Cases []struct {
				Skipped *struct{} `xml:"skipped"`
				Failure *struct{} `xml:"failure"`
			} `xml:"testcase"`
		} `xml:"testsuite"`
	}
	data, e = get("junit.xml")
	if e != nil {
		return r, e
	}
	if e = xml.Unmarshal(data, &junit); e != nil {
		return r, e
	}
	if junit.XMLName.Local != "testsuites" || len(junit.Suites) != len(r.Checks) {
		return fail("R04 JUnit 套件數不符")
	}
	for i, s := range junit.Suites {
		c := r.Checks[i]
		if s.Name != c.Name || len(s.Cases) == 0 {
			return fail("R04 JUnit 套件與 JSON 不一致")
		}
		failed := false
		for _, tc := range s.Cases {
			failed = failed || tc.Failure != nil
			if !c.Executed && (tc.Skipped == nil || tc.Failure != nil) {
				return fail("R02 JUnit 未執行狀態不一致")
			}
		}
		if c.Executed && (c.Passed == nil || (!failed) != *c.Passed) {
			return fail("R02 JUnit 成敗不一致")
		}
	}
	data, e = get("index.html")
	if e != nil {
		return r, e
	}
	page, e := ParsePage(data)
	if e != nil {
		return r, e
	}
	for _, link := range []string{"summary.json", "summary.md", "junit.xml"} {
		if !contains(page.Links, link) {
			return fail("R04 明細缺少證據連結")
		}
	}
	title := "單元與隔離整合測試通過"
	if !r.Success {
		title = "本次測試未通過"
	}
	if !strings.Contains(page.Visible, title) || strings.Contains(page.Visible, "Unknown") {
		return fail("R02/R06 前台結論不符或包含未翻譯狀態")
	}
	data, e = get("summary.md")
	if e != nil {
		return r, e
	}
	if !strings.Contains(string(data), sha) || r.MeasuredAt == "" || !strings.Contains(string(data), r.MeasuredAt) {
		return fail("R03 摘要來源或時間不一致")
	}
	for _, n := range []string{"unit", "integration", "system", "coverage"} {
		data, e = get(n + ".svg")
		if e != nil {
			return r, e
		}
		if e = ValidateSVG(data, r, n); e != nil {
			return r, e
		}
	}
	private := regexp.MustCompile(`(?i)(^|[^A-Za-z])([A-Za-z]:\\(Users|actions|a|Windows)\\|/home/runner/|/Users/[^/]+/)`)
	for _, n := range []string{"summary.json", "summary.md", "index.html", "junit.xml"} {
		data, e = get(n)
		if e != nil {
			return r, e
		}
		if private.Match(data) {
			return fail("R07 公開產物包含本機或 runner 絕對路徑")
		}
	}
	return r, nil
}
func contains(items []string, v string) bool {
	for _, s := range items {
		if s == v {
			return true
		}
	}
	return false
}
