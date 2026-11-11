package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	rc "windows_setup/script/test/repo_coverage"
)

func cmdMeasure(args []string, out io.Writer) error {
	f := flag.NewFlagSet("cmd-measure", flag.ContinueOnError)
	f.SetOutput(out)
	root := f.String("source-root", "", "CMD 原始來源")
	probe := f.String("probe-executable", "", "由 test/fixtures/cmd_probe 建立的隔離 probe")
	output := f.String("output", "", "全新私有原始證據檔案")
	if err := f.Parse(args); err != nil {
		return err
	}
	if *root == "" || *probe == "" || *output == "" || f.NArg() != 0 {
		return fmt.Errorf("需指定來源、測試 probe 與全新輸出檔案")
	}
	if _, err := os.Stat(*output); !os.IsNotExist(err) {
		return fmt.Errorf("CMD 原始證據檔案已存在或無法存取")
	}
	evidence, err := rc.CollectCMD(*root, *probe)
	if err != nil {
		return err
	}
	data, err := json.MarshalIndent(evidence, "", "  ")
	if err != nil {
		return err
	}
	file, err := os.OpenFile(*output, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if err != nil {
		return err
	}
	defer file.Close()
	if _, err := file.Write(data); err != nil {
		return err
	}
	fmt.Fprintf(out, "已隔離量測 %d 個 CMD 啟動器，未執行 PowerShell 設定\n", len(evidence.Sources))
	return nil
}
