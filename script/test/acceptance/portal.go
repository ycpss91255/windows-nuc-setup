package acceptance

import (
	"fmt"
	"net/url"
	"regexp"
	"strings"
	"time"
)

func ValidatePortal(read Reader, readme, sha, run, base string) (Report, error) {
	r, e := ValidateReport(func(n string) ([]byte, error) { return read("main/" + n) }, sha, run, true)
	if e != nil {
		return r, e
	}
	fail := func(s string) (Report, error) { return r, fmt.Errorf("%s", s) }
	b, e := read("index.html")
	if e != nil {
		return r, e
	}
	page, e := ParsePage(b)
	if e != nil {
		return r, e
	}
	manual := false
	for _, l := range page.VisibleLinks {
		u, e := url.Parse(l)
		if e == nil && strings.HasSuffix(u.Path, "/blob/main/readme.md") {
			manual = true
		}
	}
	title := "目前程式檢查通過"
	if !r.Success {
		title = "目前程式檢查未通過"
	}
	if !contains(page.VisibleLinks, "main/index.html") || !manual {
		return fail("R01 首頁缺少報告或使用說明入口")
	}
	if strings.Contains(page.Visible, "Unknown") || !strings.Contains(page.Visible, title) {
		return fail("R02/R06 首頁結論不符")
	}
	stamp, e := time.Parse(time.RFC3339Nano, r.MeasuredAt)
	if e != nil {
		return r, e
	}
	if !strings.Contains(page.Visible, r.Commit[:7]) || !strings.Contains(page.Visible, stamp.UTC().Format("2006-01-02 15:04:05")+" UTC") {
		return fail("R03 首頁提交或時間與本次報告不一致")
	}
	summary, e := read("main/summary.json")
	if e != nil {
		return r, e
	}
	if e = ValidatePortalCoverage(page.Visible, summary); e != nil {
		return r, e
	}
	var versions []struct{ Version, Status, Path string }
	b, e = read("versions.json")
	if e != nil {
		return r, e
	}
	if e = decode(b, &versions); e != nil {
		return r, e
	}
	versionPattern := regexp.MustCompile(`^v\d+\.\d+\.\d+(-rc\d+)?$`)
	missing := regexp.MustCompile(`未保存(可用的)?測試紀錄`)
	for _, v := range versions {
		if !versionPattern.MatchString(v.Version) || v.Path != "versions/"+v.Version+"/index.html" {
			return fail("R04 非法版本路徑")
		}
		b, e = read(v.Path)
		if e != nil {
			return r, e
		}
		p, e := ParsePage(b)
		if e != nil {
			return r, e
		}
		if strings.Contains(p.Visible, "Unknown") {
			return fail("R06 舊版頁顯示未翻譯狀態")
		}
		if v.Status == "Unknown" && !missing.MatchString(p.Visible) {
			return fail("R06 舊版本缺少測試紀錄說明")
		}
	}
	images := regexp.MustCompile(`!\[[^\]]*\]\(([^)]+)\)`).FindAllStringSubmatch(readme, -1)
	for _, n := range []string{"coverage"} {
		found := []string{}
		for _, m := range images {
			if strings.Split(m[1], "?")[0] == base+"main/"+n+".svg" {
				found = append(found, m[1])
			}
		}
		if len(found) != 1 {
			return fail("R05 README 徽章未指向實際公開檔：" + n)
		}
		b, e = read(strings.TrimPrefix(found[0], base))
		if e != nil {
			return r, e
		}
		if e = ValidateSVG(b, r, n); e != nil {
			return r, e
		}
	}
	return r, nil
}

func VerifyWithRetry(read Reader, readme, sha, run, base string, attempts int, sleep func(), extra ...func() error) (Report, error) {
	var r Report
	var e error
	if attempts < 1 {
		return r, fmt.Errorf("重試次數必須大於零")
	}
	for i := 0; i < attempts; i++ {
		r, e = ValidatePortal(read, readme, sha, run, base)
		if e == nil {
			for _, check := range extra {
				if e = check(); e != nil {
					break
				}
			}
		}
		if e == nil {
			return r, nil
		}
		if i+1 < attempts {
			sleep()
		}
	}
	return r, e
}
