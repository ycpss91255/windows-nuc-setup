package repo_coverage

import (
	"path"
	"sort"
	"strings"
)

// ScanRuntimeInventory leaves the historical all-owned inventory unchanged.
// Only approved PowerShell and managed native sources contribute to runtime coverage.
func ScanRuntimeInventory(root string) (Inventory, error) {
	all, err := ScanInventory(root)
	if err != nil {
		return Inventory{}, err
	}
	inv := Inventory{Excluded: append([]Exclusion(nil), all.Excluded...)}
	isRuntime := func(name string) bool { return strings.HasPrefix(name, "core/") || strings.HasPrefix(name, "modules/") }
	for _, b := range all.Blockers {
		name, _, _ := strings.Cut(b, ":")
		if isRuntime(name) && !strings.Contains(b, "unsupported CMD executable syntax") {
			inv.Blockers = append(inv.Blockers, b)
		}
	}
	for _, s := range all.Sources {
		parts := strings.Split(s.Path, "/")
		native := len(parts) == 4 && parts[0] == "modules" && parts[2] == "native" && s.Language == "csharp"
		approved := isRuntime(s.Path) && (s.Language == "powershell" || native)
		if approved {
			inv.Sources = append(inv.Sources, s)
			continue
		}
		inv.Excluded = append(inv.Excluded, Exclusion{s.Path, "outside runtime PowerShell and native C# coverage scope"})
		if isRuntime(s.Path) && s.Language != "cmd" {
			inv.Blockers = append(inv.Blockers, s.Path+": runtime executable requires explicit scope decision")
		}
	}
	for _, e := range all.Excluded {
		if e.Reason != "non-executable data, documentation, or dependency artifact" || !isRuntime(e.Path) {
			continue
		}
		ext := strings.ToLower(path.Ext(e.Path))
		if (ext == ".exe" || ext == ".dll" || ext == ".com") && !strings.EqualFold(e.Path, "modules/accounts/Autologon64.exe") {
			inv.Blockers = append(inv.Blockers, e.Path+": runtime executable requires explicit scope decision")
		}
	}
	sort.Slice(inv.Sources, func(i, j int) bool { return inv.Sources[i].Path < inv.Sources[j].Path })
	sort.Strings(inv.Blockers)
	return inv, nil
}
