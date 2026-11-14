package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"path/filepath"
	rc "windows_setup/script/test/repo_coverage"
)

type timingPhase struct {
	Name         string
	Milliseconds int64
}
type timingReceipt struct {
	SchemaVersion int
	Context       rc.PowerShellWorkerContext
	Phases        []timingPhase
}

// The expected contexts must come from validated actual worker evidence, not the receipt.
func validateTimingRoster(expected []rc.PowerShellWorkerContext, receipts []timingReceipt) error {
	if len(expected) == 0 || len(receipts) != len(expected) {
		return fmt.Errorf("timing roster incomplete")
	}
	byIndex := make(map[int]rc.PowerShellWorkerContext, len(expected))
	for _, c := range expected {
		if _, ok := byIndex[c.GlobalIndex]; ok {
			return fmt.Errorf("duplicate expected worker")
		}
		byIndex[c.GlobalIndex] = c
	}
	seen := make(map[int]bool, len(receipts))
	for _, r := range receipts {
		c, ok := byIndex[r.Context.GlobalIndex]
		if !ok || seen[r.Context.GlobalIndex] || r.SchemaVersion != 1 || r.Context != c {
			return fmt.Errorf("timing worker identity or multiplicity mismatch")
		}
		seen[r.Context.GlobalIndex] = true
		if len(r.Phases) != 3 {
			return fmt.Errorf("timing phase count mismatch")
		}
		names := map[string]bool{"startup": false, "pester_instrumentation_and_test": false, "serialization": false}
		for _, p := range r.Phases {
			used, ok := names[p.Name]
			if !ok || used || p.Milliseconds < 0 {
				return fmt.Errorf("invalid timing phase")
			}
			names[p.Name] = true
		}
	}
	return nil
}

// Worker file names are derived only from the validated local worker order.
func readWorkerTimings(dir string, expected []rc.PowerShellWorkerContext) ([]timingReceipt, error) {
	receipts := make([]timingReceipt, 0, len(expected))
	for i := range expected {
		b, err := readShardRegular(filepath.Join(dir, fmt.Sprintf("worker_%d.timing.json", i)))
		if err != nil {
			return nil, err
		}
		var receipt timingReceipt
		if err := decodeTiming(b, &receipt); err != nil {
			return nil, err
		}
		receipts = append(receipts, receipt)
	}
	if err := validateTimingRoster(expected, receipts); err != nil {
		return nil, err
	}
	return receipts, nil
}

// Reject duplicate object members before decoding to typed values.
func decodeTiming(data []byte, target any) error {
	d := json.NewDecoder(bytes.NewReader(data))
	var value func() error
	value = func() error {
		token, err := d.Token()
		if err != nil {
			return err
		}
		delim, ok := token.(json.Delim)
		if !ok {
			return nil
		}
		switch delim {
		case '{':
			names := map[string]bool{}
			for d.More() {
				k, err := d.Token()
				if err != nil {
					return err
				}
				name, ok := k.(string)
				if !ok || names[name] {
					return fmt.Errorf("duplicate timing field")
				}
				names[name] = true
				if err = value(); err != nil {
					return err
				}
			}
			_, err = d.Token()
			return err
		case '[':
			for d.More() {
				if err = value(); err != nil {
					return err
				}
			}
			_, err = d.Token()
			return err
		default:
			return fmt.Errorf("invalid timing value")
		}
	}
	if err := value(); err != nil {
		return err
	}
	return decodeShardManifest(data, target)
}
