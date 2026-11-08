package repo_coverage

import (
	"encoding/base64"
	"fmt"
	"reflect"
	"sort"
)

type psSource struct {
	File, SHA256  string
	ExpectedLines []int
}
type psCommand struct {
	File                             string
	Line, Column, EndLine, EndColumn int
	Hit                              *bool
}
type psWorker struct {
	ProcessId     int
	PesterVersion string
	Sources       []psSource
	Commands      []psCommand
}
type psEvidence struct {
	SchemaVersion                        int
	PesterVersion, PackageSHA512, Metric string
	Sources                              []psSource
	Workers                              []struct {
		Index, ProcessId int
		Evidence         string
	}
	Covered, Total int
}

// NormalizePowerShell verifies normalized lines against the actual per-worker
// Pester command spans. Complementary partial hits are merged before each
// physical line is declared complete; missing spans cannot shrink a denominator.
func NormalizePowerShell(data []byte, read func(string) ([]byte, error), inventory Inventory) (Report, []Catalog, error) {
	r := Report{SchemaVersion: SchemaVersion, Metric: Metric, Files: map[string]map[int]bool{}}
	var evidence psEvidence
	if err := strictJSON(data, &evidence); err != nil {
		return r, nil, err
	}
	packageHash, err := base64.StdEncoding.DecodeString(evidence.PackageSHA512)
	if err != nil || len(packageHash) != 64 || evidence.SchemaVersion != 1 || evidence.PesterVersion == "" || evidence.Metric != "FullyCoveredCommandStartLines" || len(evidence.Sources) == 0 || len(evidence.Workers) == 0 {
		return r, nil, fmt.Errorf("invalid PowerShell collector identity")
	}
	scope := map[string]Source{}
	for _, source := range inventory.Sources {
		scope[source.Path] = source
	}
	expected := map[string]psSource{}
	for _, source := range evidence.Sources {
		name, err := RelativePath(source.File)
		if err != nil {
			return r, nil, err
		}
		original, ok := scope[name]
		if !ok || original.Language != "powershell" || original.SHA256 != source.SHA256 || source.ExpectedLines == nil {
			return r, nil, fmt.Errorf("PowerShell source identity or analysis missing: %s", name)
		}
		if _, exists := expected[name]; exists {
			return r, nil, fmt.Errorf("duplicate PowerShell source")
		}
		expected[name] = source
		r.Files[name] = map[int]bool{}
	}
	merged := map[string]psCommand{}
	baseline := map[string]bool{}
	workers := map[string]bool{}
	for index, descriptor := range evidence.Workers {
		file, err := RelativePath(descriptor.Evidence)
		if err != nil {
			return r, nil, err
		}
		if workers[file] {
			return r, nil, fmt.Errorf("duplicate PowerShell worker")
		}
		workers[file] = true
		bytes, err := read(file)
		if err != nil {
			return r, nil, err
		}
		var worker psWorker
		if err := strictJSON(bytes, &worker); err != nil {
			return r, nil, err
		}
		if worker.PesterVersion != evidence.PesterVersion || worker.ProcessId != descriptor.ProcessId || worker.ProcessId <= 0 || len(worker.Sources) != len(expected) {
			return r, nil, fmt.Errorf("PowerShell worker identity mismatch")
		}
		seenSources := map[string]bool{}
		for _, source := range worker.Sources {
			e, ok := expected[source.File]
			if !ok || seenSources[source.File] || e.SHA256 != source.SHA256 {
				return r, nil, fmt.Errorf("PowerShell worker source mismatch")
			}
			seenSources[source.File] = true
		}
		keys := map[string]bool{}
		for _, command := range worker.Commands {
			if _, ok := expected[command.File]; !ok || command.Line <= 0 || command.Column <= 0 || command.EndLine < command.Line || command.EndColumn <= 0 || command.EndLine == command.Line && command.EndColumn <= command.Column || command.Hit == nil {
				return r, nil, fmt.Errorf("invalid PowerShell command span")
			}
			key := fmt.Sprintf("%s:%d:%d:%d:%d", command.File, command.Line, command.Column, command.EndLine, command.EndColumn)
			if keys[key] {
				return r, nil, fmt.Errorf("duplicate PowerShell command span")
			}
			keys[key] = true
			old, exists := merged[key]
			hit := *command.Hit
			if exists {
				hit = hit || *old.Hit
			}
			command.Hit = &hit
			merged[key] = command
		}
		if index == 0 {
			baseline = keys
		} else if !reflect.DeepEqual(baseline, keys) {
			return r, nil, fmt.Errorf("PowerShell workers disagree on executable denominator")
		}
	}
	for _, command := range merged {
		old, seen := r.Files[command.File][command.Line]
		r.Files[command.File][command.Line] = *command.Hit && (!seen || old)
	}
	catalogs := []Catalog{}
	covered, total := 0, 0
	for name, source := range expected {
		lines := []int{}
		for line, hit := range r.Files[name] {
			lines = append(lines, line)
			total++
			if hit {
				covered++
			}
		}
		sort.Ints(lines)
		if !reflect.DeepEqual(lines, source.ExpectedLines) {
			return r, nil, fmt.Errorf("PowerShell expected line catalog differs from actual command spans")
		}
		catalogs = append(catalogs, Catalog{Path: name, SHA256: source.SHA256, Lines: lines})
	}
	if total != evidence.Total || covered != evidence.Covered {
		return r, nil, fmt.Errorf("PowerShell collector counts disagree with commands")
	}
	xml, err := read("coverage.xml")
	if err != nil {
		return r, nil, err
	}
	normalized, err := ParseCobertura(xml, "")
	if err != nil {
		return r, nil, err
	}
	if !reflect.DeepEqual(normalized, r) {
		return r, nil, fmt.Errorf("PowerShell normalized XML does not match raw command evidence")
	}
	sort.Slice(catalogs, func(i, j int) bool { return catalogs[i].Path < catalogs[j].Path })
	return r, catalogs, nil
}
