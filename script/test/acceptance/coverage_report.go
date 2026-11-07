package acceptance

import (
	"encoding/json"
	"encoding/xml"
	"fmt"
	"reflect"
	"regexp"
	"sort"
	"strings"
)

func GoCoverageBadgePath(doc, base string) (string, error) {
	found := []string{}
	for _, m := range regexp.MustCompile(`!\[[^\]]*\]\(([^)]+)\)`).FindAllStringSubmatch(doc, -1) {
		if strings.Split(m[1], "?")[0] == base+"main/go_coverage.svg" {
			found = append(found, m[1])
		}
	}
	if len(found) != 1 {
		return "", fmt.Errorf("README must reference exactly one same-site Go coverage badge")
	}
	return strings.TrimPrefix(found[0], base+"main/"), nil
}

func ValidateGoCoverageReport(read Reader, files []string, sha, run string, required bool) error {
	b, e := read("summary.json")
	if e != nil {
		return e
	}
	var summary struct {
		RefType    string
		GoCoverage json.RawMessage
	}
	if e = decode(b, &summary); e != nil {
		return e
	}
	if len(summary.GoCoverage) == 0 || string(summary.GoCoverage) == "null" {
		if required {
			return fmt.Errorf("current main requires measured Go coverage")
		}
		return nil
	}
	if summary.RefType != "Branch" {
		return fmt.Errorf("Go sidecar is branch evidence, not historical release evidence")
	}
	data, e := read("go_coverage.json")
	if e != nil {
		return e
	}
	profile, e := read("go_coverage.out")
	if e != nil {
		return e
	}
	if files == nil {
		seen := map[string]bool{}
		for _, line := range strings.Split(string(profile), "\n") {
			if i := strings.Index(line, ":"); i > 0 && strings.HasPrefix(line, "windows_setup/") {
				seen[line[:i]] = true
			}
		}
		for f := range seen {
			files = append(files, f)
		}
		sort.Strings(files)
	}
	c, e := ValidateCoverageEvidence(data, profile, files, sha, run)
	if e != nil {
		return e
	}
	embedded, e := ValidateCoverageEvidence(summary.GoCoverage, profile, files, sha, run)
	if e != nil {
		return e
	}
	if !reflect.DeepEqual(c, embedded) {
		return fmt.Errorf("summary and Go coverage sidecar disagree")
	}
	svg, e := read("go_coverage.svg")
	if e != nil {
		return e
	}
	if e = ValidateXMLNamespace(svg, "http://www.w3.org/2000/svg"); e != nil {
		return e
	}
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
	if e = xml.Unmarshal(svg, &s); e != nil {
		return e
	}
	label := "go coverage " + strings.ToLower(summary.RefType)
	value := fmt.Sprintf("%.1f%%", c.Percent)
	if s.XMLName.Local != "svg" || s.Height != "20" || s.Width != fmt.Sprint((len(label)+len(value))*7+24) || s.Group.Font != "11" || len(s.Group.Texts) != 2 || s.Group.Texts[0] != label || s.Group.Texts[1] != value || len(s.Rects) != 2 || s.Rects[0].Fill != "#555" || s.Rects[1].Fill != "#4c1" || s.Rects[0].Width != fmt.Sprint(len(label)*7+12) || s.Rects[1].Width != fmt.Sprint(len(value)*7+12) {
		return fmt.Errorf("Go coverage badge differs from recomputed statement coverage")
	}
	html, e := read("index.html")
	if e != nil {
		return e
	}
	page, e := ParsePage(html)
	if e != nil {
		return e
	}
	fraction := fmt.Sprintf("%d/%d", c.Covered, c.TotalStatements)
	for _, text := range []string{"Go 程式敘述覆蓋率", value, fraction + " statements", "全部自有 Go 工具（含 CLI）", "不含 PowerShell 或第三方程式", "PowerShell 覆蓋率", "尚未量測"} {
		if !strings.Contains(page.Visible, text) {
			return fmt.Errorf("visible HTML lacks matching Go coverage value or scope: %s", text)
		}
	}
	if !contains(page.VisibleLinks, "go_coverage.json") || !contains(page.VisibleLinks, "go_coverage.out") {
		return fmt.Errorf("visible HTML lacks exact Go evidence download links")
	}
	md, e := read("summary.md")
	if e != nil {
		return e
	}
	for _, text := range []string{"Go 程式敘述覆蓋率：" + value, "Go statements: " + fraction, "全部自有 Go 工具（含 CLI）", "不含 PowerShell 或第三方程式", "PowerShell 覆蓋率未量測"} {
		if !strings.Contains(string(md), text) {
			return fmt.Errorf("Markdown lacks matching Go coverage value or scope: %s", text)
		}
	}
	return nil
}
