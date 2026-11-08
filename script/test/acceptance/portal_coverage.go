package acceptance

import (
	"fmt"
	"strings"
)

// ValidatePortalCoverage checks the visible overview against already verified report evidence.
func ValidatePortalCoverage(visible string, summary []byte) error {
	var metadata struct{ GoCoverage *GoCoverage }
	if e := decode(summary, &metadata); e != nil {
		return e
	}
	c := metadata.GoCoverage
	if c == nil {
		return nil
	}
	expected := []string{
		fmt.Sprintf("Go 程式敘述覆蓋率：%.1f%%", c.Percent),
		fmt.Sprintf("%d/%d statements", c.Covered, c.TotalStatements),
		"全部自有 Go 工具（含 CLI）", "不含 PowerShell 或第三方程式", "PowerShell 覆蓋率尚未量測",
	}
	for _, text := range expected {
		if !strings.Contains(visible, text) {
			return fmt.Errorf("首頁缺少正確可見 Go 覆蓋率或範圍：%s", text)
		}
	}
	return nil
}
