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
		SchemaVersion int
		RefType       string
		GoCoverage    json.RawMessage
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
	svg, e = normalizeFlatBadge(svg)
	if e != nil {
		return e
	}
	var s struct {
		XMLName xml.Name
		Height  string `xml:"height,attr"`
		Width   string `xml:"width,attr"`
		Aria    string `xml:"aria-label,attr"`
		Title   string `xml:"title"`
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
	color := "#4c1" // Historical flat-square evidence keeps its original palette.
	if len(s.Group.Texts) == 2 && s.Group.Texts[0] == "go coverage" {
		label = "go coverage"
		color = coverageColor(float64(c.Covered) * 100 / float64(c.TotalStatements))
		scope := label + " " + strings.ToLower(summary.RefType) + ": " + fmt.Sprintf("%.1f%%", c.Percent)
		if s.Aria != scope || s.Title != scope {
			return fmt.Errorf("Go coverage badge lacks matching source scope")
		}
	}
	value := fmt.Sprintf("%.1f%%", c.Percent)
	if s.XMLName.Local != "svg" || s.Height != "20" || s.Width != fmt.Sprint((len(label)+len(value))*7+24) || s.Group.Font != "11" || len(s.Group.Texts) != 2 || s.Group.Texts[0] != label || s.Group.Texts[1] != value || len(s.Rects) != 2 || s.Rects[0].Fill != "#555" || s.Rects[1].Fill != color || s.Rects[0].Width != fmt.Sprint(len(label)*7+12) || s.Rects[1].Width != fmt.Sprint(len(value)*7+12) {
		return fmt.Errorf("Go coverage badge differs from recomputed statement coverage")
	}
	html, e := read("index.html")
	if e != nil {
		return e
	}
	page, e := parsePage(html, summary.SchemaVersion == 2)
	if e != nil {
		return e
	}
	fraction := fmt.Sprintf("%d/%d", c.Covered, c.TotalStatements)
	htmlScope := []string{"Go 程式敘述覆蓋率", value, fraction + " statements", "全部自有 Go 工具（含 CLI）", "不含 PowerShell 或第三方程式"}
	if summary.SchemaVersion == 2 {
		htmlScope = append(htmlScope, "分項量測明細", "不等於整體覆蓋率")
	} else {
		htmlScope = append(htmlScope, "PowerShell 覆蓋率", "尚未量測")
	}
	for _, text := range htmlScope {
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
	mdScope := []string{"Go 程式敘述覆蓋率：" + value, "Go statements: " + fraction, "全部自有 Go 工具（含 CLI）", "不含 PowerShell 或第三方程式", "PowerShell 覆蓋率未量測"}
	if summary.SchemaVersion == 2 {
		mdScope = []string{"Go 程式敘述覆蓋率（分項）：" + value, fraction + " statements", "全部自有 Go 工具含 CLI", "不含 PowerShell 或第三方程式", "不等於整體覆蓋率"}
	}
	for _, text := range mdScope {
		if !strings.Contains(string(md), text) {
			return fmt.Errorf("Markdown lacks matching Go coverage value or scope: %s", text)
		}
	}
	return nil
}

func coverageColor(p float64) string {
	switch {
	case p >= 90:
		return "#4c1"
	case p >= 80:
		return "#97ca00"
	case p >= 70:
		return "#a4a61d"
	case p >= 60:
		return "#dfb317"
	case p >= 50:
		return "#fe7d37"
	default:
		return "#e05d44"
	}
}

// normalizeFlatBadge validates the portable flat geometry before reusing the
// historical value/scope validator. It never substitutes measured values.
func normalizeFlatBadge(data []byte) ([]byte, error) {
	type rect struct {
		Width  string `xml:"width,attr"`
		Height string `xml:"height,attr"`
		X      string `xml:"x,attr"`
		RX     string `xml:"rx,attr"`
		Fill   string `xml:"fill,attr"`
	}
	type text struct {
		Value   string `xml:",chardata"`
		X       string `xml:"x,attr"`
		Y       string `xml:"y,attr"`
		Fill    string `xml:"fill,attr"`
		Opacity string `xml:"fill-opacity,attr"`
	}
	var s struct {
		Width  string `xml:"width,attr"`
		Height string `xml:"height,attr"`
		Aria   string `xml:"aria-label,attr"`
		Title  string `xml:"title"`
		Defs   struct {
			Clip struct {
				ID   string `xml:"id,attr"`
				Rect rect   `xml:"rect"`
			} `xml:"clipPath"`
			Gradient struct {
				ID    string `xml:"id,attr"`
				X     string `xml:"x2,attr"`
				Y     string `xml:"y2,attr"`
				Stops []struct {
					Offset  string `xml:"offset,attr"`
					Color   string `xml:"stop-color,attr"`
					Opacity string `xml:"stop-opacity,attr"`
				} `xml:"stop"`
			} `xml:"linearGradient"`
		} `xml:"defs"`
		Groups []struct {
			Clip   string `xml:"clip-path,attr"`
			Font   string `xml:"font-size,attr"`
			Family string `xml:"font-family,attr"`
			Anchor string `xml:"text-anchor,attr"`
			Fill   string `xml:"fill,attr"`
			Rects  []rect `xml:"rect"`
			Texts  []text `xml:"text"`
		} `xml:"g"`
	}
	if e := xml.Unmarshal(data, &s); e != nil {
		return nil, e
	}
	if s.Defs.Clip.ID == "" {
		return data, nil
	}
	fail := func() ([]byte, error) {
		return nil, fmt.Errorf("flat coverage badge geometry, gradient or shadow differs")
	}
	if s.Height != "20" || s.Defs.Clip.ID != "r" || s.Defs.Clip.Rect.Width != s.Width || s.Defs.Clip.Rect.Height != "20" || s.Defs.Clip.Rect.RX != "3" || s.Defs.Clip.Rect.Fill != "#fff" || s.Defs.Gradient.ID != "s" || s.Defs.Gradient.X != "0" || s.Defs.Gradient.Y != "100%" || len(s.Defs.Gradient.Stops) != 2 || len(s.Groups) != 2 {
		return fail()
	}
	stops := s.Defs.Gradient.Stops
	if stops[0].Offset != "0" || stops[0].Color != "#bbb" || stops[0].Opacity != ".1" || stops[1].Offset != "1" || stops[1].Color != "" || stops[1].Opacity != ".1" {
		return fail()
	}
	shape, words := s.Groups[0], s.Groups[1]
	if shape.Clip != "url(#r)" || len(shape.Rects) != 3 || len(words.Texts) != 4 || words.Font != "11" || words.Family != "DejaVu Sans,Verdana,Geneva,sans-serif" || words.Anchor != "middle" || words.Fill != "#fff" {
		return fail()
	}
	texts := words.Texts
	label, value := texts[1].Value, texts[3].Value
	left, right := len(label)*7+12, len(value)*7+12
	if s.Width != fmt.Sprint(left+right) || shape.Rects[0].Width != fmt.Sprint(left) || shape.Rects[1].Width != fmt.Sprint(right) || shape.Rects[1].X != fmt.Sprint(left) || shape.Rects[2].Width != s.Width || shape.Rects[2].Fill != "url(#s)" {
		return fail()
	}
	for _, r := range shape.Rects {
		if r.Height != "20" {
			return fail()
		}
	}
	for i, t := range texts {
		x := left / 2
		if i >= 2 {
			x = left + right/2
		}
		y := "14"
		if i%2 == 0 {
			y = "15"
			if t.Fill != "#010101" || t.Opacity != ".3" {
				return fail()
			}
		} else if t.Fill != "" || t.Opacity != "" {
			return fail()
		}
		if t.X != fmt.Sprint(x) || t.Y != y {
			return fail()
		}
	}
	if texts[0].Value != label || texts[2].Value != value {
		return fail()
	}
	return []byte(fmt.Sprintf(`<svg xmlns="http://www.w3.org/2000/svg" width="%s" height="20" aria-label="%s"><title>%s</title><rect width="%d" fill="%s"/><rect width="%d" fill="%s"/><g font-size="11"><text>%s</text><text>%s</text></g></svg>`, s.Width, s.Aria, s.Title, left, shape.Rects[0].Fill, right, shape.Rects[1].Fill, label, value)), nil
}
