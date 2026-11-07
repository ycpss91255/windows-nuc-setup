package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	a "windows_setup/script/test/acceptance"
)

func run() error {
	dir := flag.String("artifact-dir", "", "report directory")
	root := flag.String("source-root", "", "repository")
	sha := flag.String("expected-sha", "", "expected commit")
	run := flag.String("expected-run-url", "", "expected run")
	flag.Parse()
	provided := map[string]bool{}
	flag.Visit(func(f *flag.Flag) { provided[f.Name] = true })
	if *dir == "" || *root == "" || *sha == "" || !provided["expected-run-url"] {
		return fmt.Errorf("四個驗收參數皆為必要")
	}
	if _, e := a.ValidateSource(*root); e != nil {
		return e
	}
	_, e := a.ValidateReport(func(n string) ([]byte, error) { return os.ReadFile(filepath.Join(*dir, n)) }, *sha, *run, false)
	return e
}
func main() {
	if e := run(); e != nil {
		fmt.Fprintln(os.Stderr, "需求驗收失敗：", e)
		os.Exit(1)
	}
	fmt.Println("需求驗收通過：來源命名／入口、真實測試產物、證據連結與 base 徽章；實機與人工視覺驗收未冒稱完成。")
}
