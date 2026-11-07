package main

import (
	"encoding/json"
	"encoding/xml"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"regexp"
	"strings"
	"time"
	a "windows_setup/script/test/acceptance"
)

func run() error {
	base := flag.String("base-url", "", "HTTPS Pages root")
	doc := flag.String("readme", "", "README path")
	sha := flag.String("expected-sha", "", "expected commit")
	run := flag.String("expected-run-url", "", "expected run")
	flag.Parse()
	provided := map[string]bool{}
	flag.Visit(func(f *flag.Flag) { provided[f.Name] = true })
	if *base == "" || *doc == "" || *sha == "" || !provided["expected-run-url"] {
		return fmt.Errorf("四個驗收參數皆為必要")
	}
	*base = strings.TrimRight(*base, "/") + "/"
	read, e := a.HTTPReader(*base, nil)
	if e != nil {
		return e
	}
	b, e := os.ReadFile(*doc)
	if e != nil {
		return e
	}
	files, e := a.OwnedGoFiles(".")
	if e != nil {
		return e
	}
	var measured a.GoCoverage
	r, e := a.VerifyWithRetry(read, string(b), *sha, *run, *base, 12, func() {
		fmt.Println("部署驗收尚未符合本次來源，有限等待 CDN 更新。")
		time.Sleep(10 * time.Second)
	}, func() error {
		var captured []byte
		reportReader := func(n string) ([]byte, error) {
			data, err := read("main/" + n)
			if n == "go_coverage.json" {
				captured = data
			}
			return data, err
		}
		if err := a.ValidateGoCoverageReport(reportReader, files, *sha, *run, true); err != nil {
			return err
		}
		return json.Unmarshal(captured, &measured)
	})
	if e != nil {
		return e
	}
	badges := regexp.MustCompile(`https://github\.com/[^/]+/[^/]+/actions/workflows/[^/]+/badge\.svg`).FindAllString(string(b), -1)
	if len(badges) != 1 {
		return fmt.Errorf("R05 缺少唯一 GitHub CI 徽章")
	}
	client := http.Client{Timeout: 20 * time.Second, CheckRedirect: func(req *http.Request, via []*http.Request) error {
		if req.URL.Scheme != "https" || len(via) >= 10 {
			return fmt.Errorf("R05 非法徽章重導向")
		}
		return nil
	}}
	response, e := client.Get(badges[0])
	if e != nil {
		return e
	}
	defer response.Body.Close()
	if response.StatusCode != 200 {
		return fmt.Errorf("R05 GitHub CI 徽章不可讀")
	}
	body, e := io.ReadAll(response.Body)
	if e != nil {
		return e
	}
	if e = a.ValidateXMLNamespace(body, "http://www.w3.org/2000/svg"); e != nil {
		return e
	}
	var svg struct{ XMLName xml.Name }
	if e = xml.Unmarshal(body, &svg); e != nil {
		return e
	}
	if svg.XMLName.Local != "svg" || svg.XMLName.Space != "http://www.w3.org/2000/svg" {
		return fmt.Errorf("R05 GitHub CI 徽章不是SVG")
	}
	summary := fmt.Sprintf("## 公開部署需求驗收通過\n\n- 本次 main 提交：`%s`\n- 報告執行：%s\n- 首頁、報告、JSON／JUnit／Markdown、Go 與分層徽章及歷史頁均可讀取。\n- Go statements：%.1f%%（%d/%d，包含 CLI），精確八成門檻通過。\n- System／E2E 未執行，PowerShell 覆蓋率未量測；人工視覺審查不由此 job 代替。\n", r.Commit, r.RunUrl, measured.Percent, measured.Covered, measured.TotalStatements)
	fmt.Print(summary)
	if p := os.Getenv("GITHUB_STEP_SUMMARY"); p != "" {
		return os.WriteFile(p, []byte(summary), 0600)
	}
	return nil
}
func main() {
	if e := run(); e != nil {
		fmt.Fprintln(os.Stderr, "公開部署驗收失敗：", e)
		os.Exit(1)
	}
}
