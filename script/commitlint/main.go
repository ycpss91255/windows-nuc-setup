package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
	"unicode"
)

var privatePath = regexp.MustCompile(`(?i)(?:[a-z]:[\\/](?:users|documents and settings)[\\/][^\\/\s]+|/(?:home|Users)/[^/\s]+)`)
var credential = regexp.MustCompile(`(?i)(?:password|passwd|token|api[_-]?key|secret)\s*[:=]\s*[^\s]{8,}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----`)

func lint(path string) error {
	b, err := os.ReadFile(path)
	if err != nil {
		return fmt.Errorf("無法讀取提交訊息")
	}
	msg := string(b)
	lines := strings.Split(msg, "\n")
	subject := strings.TrimSpace(strings.TrimPrefix(lines[0], "\ufeff"))
	if !strings.ContainsFunc(subject, func(r rune) bool { return unicode.Is(unicode.Han, r) }) {
		return fmt.Errorf("提交標題須包含中文")
	}
	if privatePath.MatchString(msg) {
		return fmt.Errorf("訊息可能包含私人家目錄路徑")
	}
	if credential.MatchString(msg) {
		return fmt.Errorf("訊息可能包含機密資料")
	}
	return nil
}
func install(repo string) error {
	abs, err := filepath.Abs(repo)
	if err != nil {
		return err
	}
	cmd := exec.Command("git", "-C", abs, "rev-parse", "--path-format=absolute", "--git-path", "hooks")
	out, err := cmd.Output()
	if err != nil {
		return fmt.Errorf("無法取得 Git hooks 目錄")
	}
	dir := strings.TrimSpace(string(out))
	if err := os.MkdirAll(dir, 0755); err != nil {
		return err
	}
	target := filepath.Join(dir, "commit-msg")
	f, err := os.OpenFile(target, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0755)
	if err != nil {
		return fmt.Errorf("無法建立 hook；既有檔案不會覆蓋：%w", err)
	}
	_, source, _, ok := runtime.Caller(0)
	if !ok {
		f.Close()
		os.Remove(target)
		return fmt.Errorf("無法定位工具來源")
	}
	quoted := "'" + strings.ReplaceAll(filepath.ToSlash(source), "'", "'\\''") + "'"
	_, err = fmt.Fprintf(f, "#!/bin/sh\nexec go run %s lint \"$1\"\n", quoted)
	closeErr := f.Close()
	if err != nil {
		os.Remove(target)
		return err
	}
	return closeErr
}
func main() {
	if len(os.Args) != 3 {
		fmt.Fprintln(os.Stderr, "用法：commitlint lint <訊息檔> | install <儲存庫>")
		os.Exit(2)
	}
	var err error
	switch os.Args[1] {
	case "lint":
		err = lint(os.Args[2])
	case "install":
		err = install(os.Args[2])
	default:
		err = fmt.Errorf("未知命令")
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
