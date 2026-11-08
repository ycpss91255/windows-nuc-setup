package acceptance

import (
	"encoding/json"
	"fmt"
	"reflect"
	c "windows_setup/script/test/repo_coverage"
)

// ValidateRepoCoverageReport recalculates the public total from its exact source
// inventory and normalized executable-line evidence, including missing sources.
func ValidateRepoCoverageReport(read Reader, summary []byte, sha, run string, required bool) (*c.Evidence, error) {
	var raw struct{ RepoCoverage json.RawMessage }
	if err := decode(summary, &raw); err != nil {
		return nil, err
	}
	if len(raw.RepoCoverage) == 0 || string(raw.RepoCoverage) == "null" {
		if required {
			return nil, fmt.Errorf("缺少完整儲存庫覆蓋率證據")
		}
		return nil, nil
	}
	inventory, err := read("coverage_inventory.json")
	if err != nil {
		return nil, err
	}
	normalized, err := read("coverage.xml")
	if err != nil {
		return nil, err
	}
	published, err := read("repo_coverage.json")
	if err != nil {
		return nil, err
	}
	embedded, err := c.ValidateEvidence(raw.RepoCoverage, inventory, normalized, sha, run)
	if err != nil {
		return nil, err
	}
	sidecar, err := c.ValidateEvidence(published, inventory, normalized, sha, run)
	if err != nil {
		return nil, err
	}
	if !reflect.DeepEqual(embedded, sidecar) {
		return nil, fmt.Errorf("報告與公開整體覆蓋率證據不一致")
	}
	if required && !embedded.Result.Complete {
		return nil, fmt.Errorf("整體覆蓋率來源量測不完整")
	}
	return &embedded, nil
}
