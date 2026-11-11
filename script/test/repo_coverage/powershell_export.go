package repo_coverage

import (
	"encoding/json"
	"fmt"
)

// ExportPowerShellRawEvidence reconstructs only the collector's typed JSON and
// normalized relative-path XML. It never copies arbitrary files, logs, Pester
// XML metadata, or the absolute-path collection manifest into public artifacts.
func ExportPowerShellRawEvidence(data []byte, read func(string) ([]byte, error), inventory Inventory) (map[string][]byte, error) {
	report, catalogs, err := NormalizePowerShell(data, read, inventory)
	if err != nil {
		return nil, err
	}
	var proof psEvidence
	if err := strictJSON(data, &proof); err != nil {
		return nil, err
	}
	output := map[string][]byte{}
	output["evidence.json"], err = json.MarshalIndent(proof, "", "  ")
	if err != nil {
		return nil, err
	}
	for i, descriptor := range proof.Workers {
		if descriptor.Evidence != fmt.Sprintf("worker_%d.json", i) {
			return nil, fmt.Errorf("unexpected public PowerShell evidence name")
		}
		bytes, err := read(descriptor.Evidence)
		if err != nil {
			return nil, err
		}
		var worker psWorker
		if err := strictJSON(bytes, &worker); err != nil {
			return nil, err
		}
		output[descriptor.Evidence], err = json.MarshalIndent(worker, "", "  ")
		if err != nil {
			return nil, err
		}
	}
	bound, err := BindCatalogs(inventory, catalogs)
	if err != nil {
		return nil, err
	}
	output["coverage.xml"], err = normalizedXML(bound, []Report{report})
	if err != nil {
		return nil, err
	}
	return output, nil
}
