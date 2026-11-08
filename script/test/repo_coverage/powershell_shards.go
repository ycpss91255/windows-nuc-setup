package repo_coverage

import (
	"encoding/json"
	"fmt"
	"reflect"
	"regexp"
	"strings"
)

// The canonical catalog is independently built from the trusted checkout; it
// never comes from an artifact's own claim about which tests or sources exist.
type PowerShellShardSource struct{ File, SHA256 string }
type PowerShellShardTest struct{ File, SHA256, Engine string }
type PowerShellShardCatalog struct {
	Sources []PowerShellShardSource
	Tests   []PowerShellShardTest
	Wrapper PowerShellShardSource
}
type PowerShellShardIdentity struct {
	Commit, RunUrl         string
	RunAttempt, ShardCount int
}
type PowerShellShardWorker struct {
	GlobalIndex                            int
	TestFile, TestSHA256, Evidence, SHA256 string
}
type PowerShellShardManifest struct {
	SchemaVersion                      int
	Commit, RunUrl                     string
	RunAttempt, ShardIndex, ShardCount int
	Sources                            []PowerShellShardSource
	Tests                              []PowerShellShardTest
	Wrapper                            PowerShellShardSource
	Workers                            []PowerShellShardWorker
}
type PowerShellShardInput struct {
	Manifest []byte
	Read     func(string) ([]byte, error)
}

// Context is written by the actual collector child, using its own PID and the
// suite/wrapper bytes it executed. Outer artifact packaging cannot add it later.
// Legacy non-sharded evidence may omit it; new shard aggregation requires it.
type PowerShellWorkerContext struct {
	Commit, RunUrl                                             string
	RunAttempt, ShardIndex, ShardCount, GlobalIndex, ProcessId int
	TestFile, TestSHA256, WrapperFile, WrapperSHA256           string
}

func validNativePowerShellContext(context *PowerShellWorkerContext, pid int) bool {
	if context == nil || pid <= 0 || context.ProcessId != pid {
		return false
	}
	if !regexp.MustCompile(`^[a-f0-9]{40}$`).MatchString(context.Commit) || !regexp.MustCompile(`^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/actions/runs/[0-9]+$`).MatchString(context.RunUrl) || context.RunAttempt < 1 {
		return false
	}
	if context.ShardCount < 1 || context.ShardCount > 4 || context.ShardIndex < 0 || context.ShardIndex >= context.ShardCount || context.GlobalIndex < 0 || context.GlobalIndex%context.ShardCount != context.ShardIndex {
		return false
	}
	return validShardFile(context.TestFile, context.TestSHA256) && validShardFile(context.WrapperFile, context.WrapperSHA256) && context.TestFile != context.WrapperFile
}

func validShardFile(file, hash string) bool {
	canonical, err := RelativePath(file)
	return err == nil && canonical == file && !strings.ContainsAny(file, "\r\n\t\\") && strings.HasSuffix(file, ".ps1") && regexp.MustCompile(`^[a-f0-9]{64}$`).MatchString(hash)
}

func validateShardCatalog(catalog PowerShellShardCatalog, inventory Inventory) error {
	if len(catalog.Sources) == 0 || len(catalog.Tests) == 0 || !validShardFile(catalog.Wrapper.File, catalog.Wrapper.SHA256) {
		return fmt.Errorf("PowerShell shard canonical catalog is incomplete")
	}
	sources, names := map[string]string{}, map[string]bool{}
	for _, source := range inventory.Sources {
		if source.Language != "powershell" {
			continue
		}
		if !validShardFile(source.Path, source.SHA256) || sources[source.Path] != "" {
			return fmt.Errorf("invalid PowerShell inventory for shards")
		}
		sources[source.Path] = source.SHA256
	}
	if len(sources) != len(catalog.Sources) {
		return fmt.Errorf("PowerShell shard catalog omits inventory sources")
	}
	last := ""
	for _, source := range catalog.Sources {
		key := strings.ToLower(source.File)
		if !validShardFile(source.File, source.SHA256) || source.File <= last || names[key] || sources[source.File] != source.SHA256 {
			return fmt.Errorf("PowerShell shard source catalog mismatch")
		}
		names[key], last = true, source.File
	}
	last = ""
	for _, test := range catalog.Tests {
		key := strings.ToLower(test.File)
		if !validShardFile(test.File, test.SHA256) || test.File <= last || names[key] || test.Engine != "powershell" && test.Engine != "pwsh" {
			return fmt.Errorf("PowerShell shard test catalog mismatch")
		}
		names[key], last = true, test.File
	}
	if names[strings.ToLower(catalog.Wrapper.File)] {
		return fmt.Errorf("PowerShell shard wrapper overlaps source or test")
	}
	return nil
}

// Go's decoder is case-insensitive. Keep canonical field spelling as well as
// strictJSON's duplicate/unknown-key checks, so a hidden case alias cannot carry
// unrelated strings into otherwise validated raw files that we preserve.
func exactShardFields(data []byte, shape reflect.Type, required bool) error {
	switch shape.Kind() {
	case reflect.Pointer:
		if strings.TrimSpace(string(data)) != "null" {
			return exactShardFields(data, shape.Elem(), true)
		}
	case reflect.Struct:
		var object map[string]json.RawMessage
		if err := json.Unmarshal(data, &object); err != nil {
			return err
		}
		if required && len(object) != shape.NumField() {
			return fmt.Errorf("missing PowerShell shard fields")
		}
		for name, value := range object {
			field, ok := shape.FieldByName(name)
			if !ok || field.Name != name {
				return fmt.Errorf("noncanonical PowerShell shard field")
			}
			if err := exactShardFields(value, field.Type, required); err != nil {
				return err
			}
		}
	case reflect.Slice:
		var values []json.RawMessage
		if err := json.Unmarshal(data, &values); err != nil {
			return err
		}
		for _, value := range values {
			if err := exactShardFields(value, shape.Elem(), required); err != nil {
				return err
			}
		}
	}
	return nil
}

// MergePowerShellShards accepts only the complete deterministic shard set for
// one clean checkout/run/attempt. Original raw workers keep their real process,
// engine and command records; only their file names/descriptor indices become
// canonical global indices. Command hits are unioned before complete lines.
func MergePowerShellShards(identity PowerShellShardIdentity, catalog PowerShellShardCatalog, inputs []PowerShellShardInput, inventory Inventory) (map[string][]byte, error) {
	if !regexp.MustCompile(`^[a-f0-9]{40}$`).MatchString(identity.Commit) || !regexp.MustCompile(`^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/actions/runs/[0-9]+$`).MatchString(identity.RunUrl) || identity.RunAttempt < 1 || identity.ShardCount < 1 || identity.ShardCount > 4 || identity.ShardCount > len(catalog.Tests) || len(inputs) != identity.ShardCount {
		return nil, fmt.Errorf("invalid PowerShell shard collection identity or count")
	}
	if err := validateShardCatalog(catalog, inventory); err != nil {
		return nil, err
	}
	output := map[string][]byte{}
	var merged psEvidence
	seenShards, seenTests := map[int]bool{}, map[int]bool{}
	commandHits := map[string]psCommand{}
	var expectedSpans map[string]bool
	for _, input := range inputs {
		if input.Read == nil {
			return nil, fmt.Errorf("missing PowerShell shard reader")
		}
		var manifest PowerShellShardManifest
		if err := strictJSON(input.Manifest, &manifest); err != nil {
			return nil, err
		}
		if err := exactShardFields(input.Manifest, reflect.TypeOf(manifest), true); err != nil {
			return nil, err
		}
		if manifest.SchemaVersion != 1 || manifest.Commit != identity.Commit || manifest.RunUrl != identity.RunUrl || manifest.RunAttempt != identity.RunAttempt || manifest.ShardCount != identity.ShardCount || manifest.ShardIndex < 0 || manifest.ShardIndex >= identity.ShardCount || seenShards[manifest.ShardIndex] || !reflect.DeepEqual(manifest.Sources, catalog.Sources) || !reflect.DeepEqual(manifest.Tests, catalog.Tests) || manifest.Wrapper != catalog.Wrapper {
			return nil, fmt.Errorf("PowerShell shard manifest provenance mismatch")
		}
		seenShards[manifest.ShardIndex] = true
		selected := []int{}
		for global := range catalog.Tests {
			if global%identity.ShardCount == manifest.ShardIndex {
				selected = append(selected, global)
			}
		}
		if len(manifest.Workers) != len(selected) {
			return nil, fmt.Errorf("PowerShell shard is missing or duplicates test execution")
		}
		// Capture every approved file exactly once. Normalization and hash checks
		// must refer to the same bytes even if a reader's backing files change.
		raw := map[string][]byte{}
		files := []string{"evidence.json", "coverage.xml"}
		for local := range selected {
			files = append(files, fmt.Sprintf("worker_%d.json", local))
		}
		for _, name := range files {
			data, err := input.Read(name)
			if err != nil {
				return nil, err
			}
			raw[name] = append([]byte(nil), data...)
		}
		read := func(name string) ([]byte, error) {
			data, ok := raw[name]
			if !ok {
				return nil, fmt.Errorf("unapproved PowerShell shard evidence name")
			}
			return data, nil
		}
		proof := raw["evidence.json"]
		if _, _, err := NormalizePowerShell(proof, read, inventory); err != nil {
			return nil, err
		}
		var evidence psEvidence
		if err := strictJSON(proof, &evidence); err != nil {
			return nil, err
		}
		if len(evidence.Workers) != len(selected) || len(evidence.Sources) != len(catalog.Sources) {
			return nil, fmt.Errorf("PowerShell shard raw source or worker count mismatch")
		}
		for i, source := range evidence.Sources {
			if source.File != catalog.Sources[i].File || source.SHA256 != catalog.Sources[i].SHA256 {
				return nil, fmt.Errorf("PowerShell shard raw sources disagree with canonical catalog")
			}
		}
		if merged.Sources == nil {
			merged = evidence
			merged.Workers = make([]struct {
				Index, ProcessId                    int
				Evidence                            string
				Engine, EngineVersion, EngineSHA256 string
			}, len(catalog.Tests))
		} else if !reflect.DeepEqual(merged.Sources, evidence.Sources) {
			return nil, fmt.Errorf("PowerShell shard source command catalogs disagree")
		}
		for local, context := range manifest.Workers {
			global := selected[local]
			test, descriptor := catalog.Tests[global], evidence.Workers[local]
			name := fmt.Sprintf("worker_%d.json", local)
			if context.GlobalIndex != global || context.TestFile != test.File || context.TestSHA256 != test.SHA256 || context.Evidence != name || descriptor.Evidence != name || descriptor.Engine != test.Engine || seenTests[global] {
				return nil, fmt.Errorf("PowerShell shard suite/worker binding mismatch")
			}
			data := raw[name]
			if digest(data) != context.SHA256 {
				return nil, fmt.Errorf("PowerShell shard worker digest mismatch")
			}
			var worker psWorker
			if err := strictJSON(data, &worker); err != nil {
				return nil, err
			}
			if err := exactShardFields(data, reflect.TypeOf(worker), false); err != nil {
				return nil, err
			}
			actualContext := PowerShellWorkerContext{Commit: identity.Commit, RunUrl: identity.RunUrl, RunAttempt: identity.RunAttempt, ShardIndex: manifest.ShardIndex, ShardCount: identity.ShardCount, GlobalIndex: global, ProcessId: worker.ProcessId, TestFile: test.File, TestSHA256: test.SHA256, WrapperFile: catalog.Wrapper.File, WrapperSHA256: catalog.Wrapper.SHA256}
			if worker.Context == nil || *worker.Context != actualContext {
				return nil, fmt.Errorf("native PowerShell execution context does not match canonical suite or run")
			}
			spans := map[string]bool{}
			for _, command := range worker.Commands {
				key := fmt.Sprintf("%s:%d:%d:%d:%d", command.File, command.Line, command.Column, command.EndLine, command.EndColumn)
				spans[key] = true
				hit := *command.Hit
				if previous, ok := commandHits[key]; ok {
					hit = hit || *previous.Hit
				}
				command.Hit = &hit
				commandHits[key] = command
			}
			if expectedSpans == nil {
				expectedSpans = spans
			} else if !reflect.DeepEqual(expectedSpans, spans) {
				return nil, fmt.Errorf("PowerShell shards disagree on full command denominator")
			}
			seenTests[global] = true
			descriptor.Index, descriptor.Evidence = global, fmt.Sprintf("worker_%d.json", global)
			merged.Workers[global] = descriptor
			output[descriptor.Evidence] = append([]byte(nil), data...)
		}
	}
	if len(seenTests) != len(catalog.Tests) {
		return nil, fmt.Errorf("PowerShell shard test union is incomplete")
	}
	report := Report{SchemaVersion: SchemaVersion, Metric: Metric, Files: map[string]map[int]bool{}}
	catalogs := []Catalog{}
	for _, source := range merged.Sources {
		report.Files[source.File] = map[int]bool{}
		catalogs = append(catalogs, Catalog{Path: source.File, SHA256: source.SHA256, Lines: source.ExpectedLines})
	}
	for _, command := range commandHits {
		old, seen := report.Files[command.File][command.Line]
		report.Files[command.File][command.Line] = *command.Hit && (!seen || old)
	}
	merged.Covered, merged.Total = 0, 0
	for _, lines := range report.Files {
		for _, hit := range lines {
			merged.Total++
			if hit {
				merged.Covered++
			}
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
	output["evidence.json"], err = json.MarshalIndent(merged, "", "  ")
	if err != nil {
		return nil, err
	}
	if _, _, err := NormalizePowerShell(output["evidence.json"], func(name string) ([]byte, error) { return output[name], nil }, inventory); err != nil {
		return nil, err
	}
	return output, nil
}
