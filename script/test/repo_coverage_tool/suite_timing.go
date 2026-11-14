package main

import (
	"fmt"
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
