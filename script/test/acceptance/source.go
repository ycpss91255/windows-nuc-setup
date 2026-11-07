package acceptance

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
)

func ValidateSource(root string) (string, error) {
	output, e := exec.Command("git", "-C", root, "-c", "core.quotePath=false", "ls-files").Output()
	if e != nil {
		return "", e
	}
	paths := strings.Split(strings.TrimSpace(string(output)), "\n")
	for i := range paths {
		paths[i] = strings.TrimSpace(paths[i])
	}
	legal := regexp.MustCompile(`^[a-z0-9_.]+$`)
	for _, p := range paths {
		thirdparty := strings.HasPrefix(p, "modules/debloat/win11debloat/") || strings.HasPrefix(p, "vendor/golang.org/x/net/")
		if !thirdparty && !legal.MatchString(filepath.Base(p)) {
			return "", fmt.Errorf("R08 自有檔名不是小寫底線：%s", p)
		}
	}
	b, e := os.ReadFile(filepath.Join(root, "readme.md"))
	if e != nil {
		return "", e
	}
	doc := string(b)
	for _, m := range regexp.MustCompile(`\]\(([^)]+)\)`).FindAllStringSubmatch(doc, -1) {
		s := m[1]
		if strings.HasPrefix(s, "http:") || strings.HasPrefix(s, "https:") || strings.HasPrefix(s, "#") {
			continue
		}
		s = strings.Split(s, "#")[0]
		if !contains(paths, s) {
			return "", fmt.Errorf("R01 README 相對連結不存在或大小寫不符：%s", s)
		}
	}
	badges := regexp.MustCompile(`https://github\.com/[^/]+/[^/]+/actions/workflows/([^/]+)/badge\.svg`).FindAllStringSubmatch(doc, -1)
	if len(badges) != 1 || !contains(paths, ".github/workflows/"+badges[0][1]) {
		return "", fmt.Errorf("R05 README CI 徽章沒有對應 workflow")
	}
	for _, s := range []string{"init.cmd", "windows.cmd"} {
		if !contains(paths, s) || !strings.Contains(doc, s) {
			return "", fmt.Errorf("R01 缺少使用者入口：%s", s)
		}
	}
	for _, s := range []string{"Ctrl+Shift+F3", "-AfterRestart", "-VerifyOnly"} {
		if !strings.Contains(doc, s) {
			return "", fmt.Errorf("R01 操作說明缺少：%s", s)
		}
	}
	return doc, nil
}
