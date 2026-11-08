// repo_coverage_tool verifies repository-owned coverage artifacts without a
// hosted coverage service. It is a maintenance tool, not a Windows dependency.
package main

import (
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	rc "windows_setup/script/test/repo_coverage"
)

func run(args []string, out io.Writer) error {
	if len(args) == 0 || args[0] != "verify" {
		return fmt.Errorf("用法：repo_coverage_tool verify --artifact-dir 路徑 --expected-sha 提交 [--expected-run-url URL] [--source-root 原始碼]")
	}
	flags := flag.NewFlagSet("verify", flag.ContinueOnError)
	flags.SetOutput(out)
	dir := flags.String("artifact-dir", "", "三檔證據目錄")
	sha := flags.String("expected-sha", "", "預期提交")
	runURL := flags.String("expected-run-url", "", "預期 Actions 執行 URL")
	source := flags.String("source-root", "", "選用：核對實際來源清單與雜湊")
	if err := flags.Parse(args[1:]); err != nil {
		return err
	}
	if *dir == "" || *sha == "" || flags.NArg() != 0 {
		return fmt.Errorf("必須指定證據目錄與提交，不能帶額外位置參數")
	}
	files := make([][]byte, 3)
	for index, name := range []string{"repo_coverage.json", "coverage_inventory.json", "coverage.xml"} {
		data, err := os.ReadFile(filepath.Join(*dir, name))
		if err != nil {
			return fmt.Errorf("讀取 %s：%w", name, err)
		}
		files[index] = data
	}
	evidence, err := rc.ValidateEvidence(files[0], files[1], files[2], *sha, *runURL)
	if err != nil {
		return err
	}
	if *source != "" {
		if err := rc.ValidateInventory(*source, files[1]); err != nil {
			return err
		}
	}
	fmt.Fprintf(out, "整體覆蓋率證據驗證通過：%s，完整=%t，命中=%d，可執行=%d\n", evidence.Commit, evidence.Result.Complete, evidence.Result.Covered, evidence.Result.Executable)
	return nil
}
func main() {
	if err := run(os.Args[1:], os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
