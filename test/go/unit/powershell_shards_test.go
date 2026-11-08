package unit_test

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"strings"
	"testing"

	rc "windows_setup/script/test/repo_coverage"
)

func psShardJSON(t *testing.T, value any) []byte {
	t.Helper()
	b, err := json.Marshal(value)
	if err != nil {
		t.Fatal(err)
	}
	return b
}

func psShardHash(b []byte) string { return fmt.Sprintf("%x", sha256.Sum256(b)) }

type psShardFixture struct {
	identity  rc.PowerShellShardIdentity
	catalog   rc.PowerShellShardCatalog
	inventory rc.Inventory
	inputs    []rc.PowerShellShardInput
	files     []map[string][]byte
}

// Synthetic command evidence tests merging semantics; the CI integration test
// separately runs real Pester workers and must not infer measurement from this.
func newPSShardFixture(t *testing.T) psShardFixture {
	t.Helper()
	source := rc.PowerShellShardSource{File: "core/logic.ps1", SHA256: strings.Repeat("a", 64)}
	f := psShardFixture{
		identity: rc.PowerShellShardIdentity{Commit: strings.Repeat("b", 40), RunUrl: "https://github.com/example/repo/actions/runs/123", RunAttempt: 2, ShardCount: 2},
		catalog: rc.PowerShellShardCatalog{Sources: []rc.PowerShellShardSource{source}, Tests: []rc.PowerShellShardTest{
			{File: "test/powershell/unit/first_tests.ps1", SHA256: strings.Repeat("c", 64), Engine: "powershell"},
			{File: "test/powershell/unit/second_tests.ps1", SHA256: strings.Repeat("d", 64), Engine: "pwsh"},
		}, Wrapper: rc.PowerShellShardSource{File: "test/powershell/coverage/safe_suite.ps1", SHA256: strings.Repeat("e", 64)}},
		inventory: rc.Inventory{Sources: []rc.Source{{Path: source.File, Language: "powershell", SHA256: source.SHA256}}},
	}
	for i, test := range f.catalog.Tests {
		engineVersion := "5.1.20348.1"
		if test.Engine == "pwsh" {
			engineVersion = "7.6.1"
		}
		engineHash := strings.Repeat(fmt.Sprint(i+1), 64)
		commands := []map[string]any{}
		for col := 1; col <= 2; col++ {
			commands = append(commands, map[string]any{"File": source.File, "Line": 2, "Column": col, "EndLine": 2, "EndColumn": col + 1, "Hit": col == i+1})
		}
		context := rc.PowerShellWorkerContext{Commit: f.identity.Commit, RunUrl: f.identity.RunUrl, RunAttempt: f.identity.RunAttempt, ShardIndex: i, ShardCount: 2, GlobalIndex: i, ProcessId: 100 + i, TestFile: test.File, TestSHA256: test.SHA256, WrapperFile: f.catalog.Wrapper.File, WrapperSHA256: f.catalog.Wrapper.SHA256}
		worker := map[string]any{"ProcessId": 100 + i, "Engine": test.Engine, "EngineVersion": engineVersion, "EngineSHA256": engineHash, "PesterVersion": "6.0.0", "Sources": []any{map[string]any{"File": source.File, "SHA256": source.SHA256}}, "Commands": commands, "Context": context}
		proof := map[string]any{"SchemaVersion": 1, "PesterVersion": "6.0.0", "PackageSHA512": "AHIAm7QW11As3sjMayo1rPU4JVIEfBL+ZILAyTyDnMPxMwLFQ3VeAA0prFTx+Y4DgZCUnH2N4+Xb0HDQua2EKA==", "Metric": "FullyCoveredCommandStartLines", "Sources": []any{map[string]any{"File": source.File, "SHA256": source.SHA256, "ExpectedLines": []int{2}}}, "Workers": []any{map[string]any{"Index": 0, "ProcessId": 100 + i, "Evidence": "worker_0.json", "Engine": test.Engine, "EngineVersion": engineVersion, "EngineSHA256": engineHash}}, "Covered": 0, "Total": 1}
		files := map[string][]byte{"worker_0.json": psShardJSON(t, worker), "evidence.json": psShardJSON(t, proof), "coverage.xml": cobertura(`<class filename="core/logic.ps1"><lines><line number="2" hits="0"/></lines></class>`)}
		manifest := rc.PowerShellShardManifest{SchemaVersion: 1, Commit: f.identity.Commit, RunUrl: f.identity.RunUrl, RunAttempt: f.identity.RunAttempt, ShardCount: 2, ShardIndex: i, Sources: f.catalog.Sources, Tests: f.catalog.Tests, Wrapper: f.catalog.Wrapper,
			Workers: []rc.PowerShellShardWorker{{GlobalIndex: i, TestFile: test.File, TestSHA256: test.SHA256, Evidence: "worker_0.json", SHA256: psShardHash(files["worker_0.json"])}}}
		f.files = append(f.files, files)
		f.inputs = append(f.inputs, rc.PowerShellShardInput{Manifest: psShardJSON(t, manifest), Read: func(name string) ([]byte, error) {
			b, ok := files[name]
			if !ok {
				return nil, fmt.Errorf("missing %s", name)
			}
			return b, nil
		}})
	}
	return f
}

func (f *psShardFixture) manifest(t *testing.T, shard int, mutate func(*rc.PowerShellShardManifest)) {
	t.Helper()
	var m rc.PowerShellShardManifest
	if err := json.Unmarshal(f.inputs[shard].Manifest, &m); err != nil {
		t.Fatal(err)
	}
	mutate(&m)
	f.inputs[shard].Manifest = psShardJSON(t, m)
}

func (f *psShardFixture) worker(t *testing.T, shard int, mutate func(map[string]any)) {
	t.Helper()
	var w map[string]any
	if err := json.Unmarshal(f.files[shard]["worker_0.json"], &w); err != nil {
		t.Fatal(err)
	}
	mutate(w)
	f.files[shard]["worker_0.json"] = psShardJSON(t, w)
	f.manifest(t, shard, func(m *rc.PowerShellShardManifest) {
		m.Workers[0].SHA256 = psShardHash(f.files[shard]["worker_0.json"])
	})
}

func TestPowerShellShardsMergeComplementaryCommandsAndPreserveRawWorkers(t *testing.T) {
	f := newPSShardFixture(t)
	// Artifact download order does not determine the canonical worker order.
	f.inputs[0], f.inputs[1] = f.inputs[1], f.inputs[0]
	files, err := rc.MergePowerShellShards(f.identity, f.catalog, f.inputs, f.inventory)
	if err != nil {
		t.Fatal(err)
	}
	if len(files) != 4 || string(files["worker_0.json"]) != string(f.files[0]["worker_0.json"]) || string(files["worker_1.json"]) != string(f.files[1]["worker_0.json"]) {
		t.Fatal("raw worker bytes or canonical identity changed")
	}
	r, catalogs, err := rc.NormalizePowerShell(files["evidence.json"], func(name string) ([]byte, error) { return files[name], nil }, f.inventory)
	if err != nil || !r.Files["core/logic.ps1"][2] || len(catalogs) != 1 {
		t.Fatalf("complementary command union lost: %+v %v", r, err)
	}
	for name, data := range files {
		if strings.Contains(string(data), `C:\Users\`) {
			t.Fatalf("private path in %s", name)
		}
	}
}

func TestPowerShellShardsSnapshotEachRawInputOnce(t *testing.T) {
	f := newPSShardFixture(t)
	for i := range f.inputs {
		read := f.inputs[i].Read
		seen := map[string]bool{}
		f.inputs[i].Read = func(name string) ([]byte, error) {
			if seen[name] {
				return nil, fmt.Errorf("raw input changed after first observation")
			}
			seen[name] = true
			return read(name)
		}
	}
	if _, err := rc.MergePowerShellShards(f.identity, f.catalog, f.inputs, f.inventory); err != nil {
		t.Fatal("verified raw input was read again instead of using its captured bytes", err)
	}
}

func TestPowerShellShardsSingleShardRetainsEverySuite(t *testing.T) {
	f := newPSShardFixture(t)
	f.identity.ShardCount = 1
	for i := range f.inputs {
		f.worker(t, i, func(w map[string]any) { c := w["Context"].(map[string]any); c["ShardCount"] = 1; c["ShardIndex"] = 0 })
	}
	var proof, other map[string]any
	if err := json.Unmarshal(f.files[0]["evidence.json"], &proof); err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(f.files[1]["evidence.json"], &other); err != nil {
		t.Fatal(err)
	}
	descriptor := other["Workers"].([]any)[0].(map[string]any)
	descriptor["Index"], descriptor["Evidence"] = 1, "worker_1.json"
	proof["Workers"] = append(proof["Workers"].([]any), descriptor)
	proof["Covered"] = 1
	f.files[0]["evidence.json"] = psShardJSON(t, proof)
	f.files[0]["coverage.xml"] = cobertura(`<class filename="core/logic.ps1"><lines><line number="2" hits="1"/></lines></class>`)
	f.files[0]["worker_1.json"] = f.files[1]["worker_0.json"]
	f.manifest(t, 0, func(m *rc.PowerShellShardManifest) {
		m.ShardCount = 1
		m.Workers = append(m.Workers, rc.PowerShellShardWorker{GlobalIndex: 1, TestFile: f.catalog.Tests[1].File, TestSHA256: f.catalog.Tests[1].SHA256, Evidence: "worker_1.json", SHA256: psShardHash(f.files[0]["worker_1.json"])})
	})
	f.inputs = f.inputs[:1]
	files, err := rc.MergePowerShellShards(f.identity, f.catalog, f.inputs, f.inventory)
	if err != nil || len(files) != 4 {
		t.Fatal("single shard lost a canonical suite", err)
	}
}

func TestPowerShellShardsRejectIncompleteOrForeignProvenance(t *testing.T) {
	cases := map[string]func(*psShardFixture){
		"missing shard":   func(f *psShardFixture) { f.inputs = f.inputs[:1] },
		"extra shard":     func(f *psShardFixture) { f.inputs = append(f.inputs, f.inputs[0]) },
		"duplicate index": func(f *psShardFixture) { f.manifest(t, 1, func(m *rc.PowerShellShardManifest) { m.ShardIndex = 0 }) },
		"foreign commit": func(f *psShardFixture) {
			f.manifest(t, 1, func(m *rc.PowerShellShardManifest) { m.Commit = strings.Repeat("f", 40) })
		},
		"foreign run":     func(f *psShardFixture) { f.manifest(t, 1, func(m *rc.PowerShellShardManifest) { m.RunUrl += "9" }) },
		"foreign attempt": func(f *psShardFixture) { f.manifest(t, 1, func(m *rc.PowerShellShardManifest) { m.RunAttempt++ }) },
		"foreign count":   func(f *psShardFixture) { f.manifest(t, 1, func(m *rc.PowerShellShardManifest) { m.ShardCount++ }) },
		"invalid index":   func(f *psShardFixture) { f.manifest(t, 1, func(m *rc.PowerShellShardManifest) { m.ShardIndex = -1 }) },
		"schema":          func(f *psShardFixture) { f.manifest(t, 1, func(m *rc.PowerShellShardManifest) { m.SchemaVersion = 2 }) },
		"source omission": func(f *psShardFixture) { f.manifest(t, 1, func(m *rc.PowerShellShardManifest) { m.Sources = nil }) },
		"source digest": func(f *psShardFixture) {
			f.manifest(t, 1, func(m *rc.PowerShellShardManifest) { m.Sources[0].SHA256 = strings.Repeat("f", 64) })
		},
		"test omission": func(f *psShardFixture) {
			f.manifest(t, 1, func(m *rc.PowerShellShardManifest) { m.Tests = m.Tests[:1] })
		},
		"test digest": func(f *psShardFixture) {
			f.manifest(t, 1, func(m *rc.PowerShellShardManifest) { m.Tests[0].SHA256 = strings.Repeat("f", 64) })
		},
		"test engine": func(f *psShardFixture) {
			f.manifest(t, 1, func(m *rc.PowerShellShardManifest) { m.Tests[0].Engine = "pwsh" })
		},
		"wrapper digest": func(f *psShardFixture) {
			f.manifest(t, 1, func(m *rc.PowerShellShardManifest) { m.Wrapper.SHA256 = strings.Repeat("f", 64) })
		},
		"missing suite": func(f *psShardFixture) { f.manifest(t, 1, func(m *rc.PowerShellShardManifest) { m.Workers = nil }) },
		"duplicate suite": func(f *psShardFixture) {
			f.manifest(t, 1, func(m *rc.PowerShellShardManifest) { m.Workers = append(m.Workers, m.Workers[0]) })
		},
		"wrong global suite": func(f *psShardFixture) {
			f.manifest(t, 1, func(m *rc.PowerShellShardManifest) { m.Workers[0].GlobalIndex = 0 })
		},
		"wrong test context": func(f *psShardFixture) {
			f.manifest(t, 1, func(m *rc.PowerShellShardManifest) { m.Workers[0].TestFile = m.Tests[0].File })
		},
		"wrong test context digest": func(f *psShardFixture) {
			f.manifest(t, 1, func(m *rc.PowerShellShardManifest) { m.Workers[0].TestSHA256 = strings.Repeat("f", 64) })
		},
		"raw digest": func(f *psShardFixture) {
			f.manifest(t, 1, func(m *rc.PowerShellShardManifest) { m.Workers[0].SHA256 = strings.Repeat("f", 64) })
		},
		"evidence traversal": func(f *psShardFixture) {
			f.manifest(t, 1, func(m *rc.PowerShellShardManifest) { m.Workers[0].Evidence = "../worker_0.json" })
		},
		"worker missing": func(f *psShardFixture) { delete(f.files[1], "worker_0.json") },
		"proof missing":  func(f *psShardFixture) { delete(f.files[1], "evidence.json") },
		"xml missing":    func(f *psShardFixture) { delete(f.files[1], "coverage.xml") },
		"worker unknown field": func(f *psShardFixture) {
			f.worker(t, 1, func(w map[string]any) { w["PrivatePath"] = `C:\Users\secret` })
		},
		"worker hidden case alias": func(f *psShardFixture) {
			f.worker(t, 1, func(w map[string]any) {
				w["sources"] = w["Sources"]
				w["Sources"] = []any{map[string]any{"File": `C:\Users\secret`, "SHA256": strings.Repeat("a", 64)}}
			})
		},
		"worker engine mismatch": func(f *psShardFixture) { f.worker(t, 1, func(w map[string]any) { w["Engine"] = "powershell" }) },
		"cross shard span mismatch": func(f *psShardFixture) {
			f.worker(t, 1, func(w map[string]any) { w["Commands"].([]any)[0].(map[string]any)["EndColumn"] = 9 })
		},
		"inventory omitted source": func(f *psShardFixture) {
			f.inventory.Sources = append(f.inventory.Sources, rc.Source{Path: "core/new.ps1", Language: "powershell", SHA256: strings.Repeat("f", 64)})
		},
		"unknown envelope field": func(f *psShardFixture) {
			f.inputs[1].Manifest = append(f.inputs[1].Manifest[:len(f.inputs[1].Manifest)-1], []byte(`,"extra":true}`)...)
		},
		"envelope case alias": func(f *psShardFixture) {
			f.inputs[1].Manifest = []byte(strings.Replace(string(f.inputs[1].Manifest), `"ShardIndex":`, `"shardindex":`, 1))
		},
		"nested case alias": func(f *psShardFixture) {
			f.inputs[1].Manifest = []byte(strings.Replace(string(f.inputs[1].Manifest), `"TestFile":`, `"testfile":`, 1))
		},
		"duplicate envelope key": func(f *psShardFixture) {
			f.inputs[1].Manifest = append(f.inputs[1].Manifest[:len(f.inputs[1].Manifest)-1], []byte(`,"ShardIndex":1}`)...)
		},
	}
	for name, mutate := range cases {
		t.Run(name, func(t *testing.T) {
			f := newPSShardFixture(t)
			mutate(&f)
			if _, err := rc.MergePowerShellShards(f.identity, f.catalog, f.inputs, f.inventory); err == nil {
				t.Fatal("invalid shard collection was accepted")
			}
		})
	}
}

func TestPowerShellShardsRejectInvalidTrustedPlan(t *testing.T) {
	for _, kind := range []string{"zero count", "too many shards", "invalid commit", "invalid run", "invalid attempt", "empty sources", "source path", "duplicate source", "source order", "empty tests", "test path", "duplicate test", "test order", "unknown test engine", "wrapper path", "wrapper digest", "nil reader"} {
		t.Run(kind, func(t *testing.T) {
			f := newPSShardFixture(t)
			switch kind {
			case "zero count":
				f.identity.ShardCount = 0
			case "too many shards":
				f.identity.ShardCount = 5
			case "invalid commit":
				f.identity.Commit = "dirty"
			case "invalid run":
				f.identity.RunUrl = "https://example.invalid/run/1"
			case "invalid attempt":
				f.identity.RunAttempt = 0
			case "empty sources":
				f.catalog.Sources = nil
			case "source path":
				f.catalog.Sources[0].File = "../core/logic.ps1"
			case "duplicate source":
				f.catalog.Sources = append(f.catalog.Sources, f.catalog.Sources[0])
			case "source order":
				f.catalog.Sources = append(f.catalog.Sources, rc.PowerShellShardSource{File: "core/aaa.ps1", SHA256: strings.Repeat("a", 64)})
			case "empty tests":
				f.catalog.Tests = nil
			case "test path":
				f.catalog.Tests[0].File = `C:\Users\secret.ps1`
			case "duplicate test":
				f.catalog.Tests = append(f.catalog.Tests, f.catalog.Tests[0])
			case "test order":
				f.catalog.Tests[0], f.catalog.Tests[1] = f.catalog.Tests[1], f.catalog.Tests[0]
			case "unknown test engine":
				f.catalog.Tests[0].Engine = "bash"
			case "wrapper path":
				f.catalog.Wrapper.File = "./test/wrapper.ps1"
			case "wrapper digest":
				f.catalog.Wrapper.SHA256 = "unknown"
			case "nil reader":
				f.inputs[0].Read = nil
			}
			if _, err := rc.MergePowerShellShards(f.identity, f.catalog, f.inputs, f.inventory); err == nil {
				t.Fatal("invalid trusted plan was accepted")
			}
		})
	}
}

func TestPowerShellShardsRequireNativeExecutionContext(t *testing.T) {
	cases := map[string]func(map[string]any){
		"missing":      func(w map[string]any) { delete(w, "Context") },
		"null":         func(w map[string]any) { w["Context"] = nil },
		"stale commit": func(w map[string]any) { w["Context"].(map[string]any)["Commit"] = strings.Repeat("f", 40) },
		"stale run": func(w map[string]any) {
			w["Context"].(map[string]any)["RunUrl"] = "https://github.com/example/repo/actions/runs/999"
		},
		"stale attempt":      func(w map[string]any) { w["Context"].(map[string]any)["RunAttempt"] = 3 },
		"other global suite": func(w map[string]any) { w["Context"].(map[string]any)["GlobalIndex"] = 3 },
		"other shard":        func(w map[string]any) { w["Context"].(map[string]any)["ShardIndex"] = 0 },
		"other shard count":  func(w map[string]any) { c := w["Context"].(map[string]any); c["ShardCount"] = 1; c["ShardIndex"] = 0 },
		"other test": func(w map[string]any) {
			w["Context"].(map[string]any)["TestFile"] = "test/powershell/unit/other_tests.ps1"
		},
		"other test bytes": func(w map[string]any) { w["Context"].(map[string]any)["TestSHA256"] = strings.Repeat("f", 64) },
		"other wrapper": func(w map[string]any) {
			w["Context"].(map[string]any)["WrapperFile"] = "test/powershell/coverage/other.ps1"
		},
		"other wrapper bytes":   func(w map[string]any) { w["Context"].(map[string]any)["WrapperSHA256"] = strings.Repeat("f", 64) },
		"wrong native pid":      func(w map[string]any) { w["Context"].(map[string]any)["ProcessId"] = 999 },
		"missing native field":  func(w map[string]any) { delete(w["Context"].(map[string]any), "ShardIndex") },
		"context unknown field": func(w map[string]any) { w["Context"].(map[string]any)["PrivateRoot"] = `C:\Users\secret` },
		"context hidden case alias": func(w map[string]any) {
			c := w["Context"].(map[string]any)
			c["runurl"] = c["RunUrl"]
			c["RunUrl"] = `C:\Users\secret`
		},
		"context case spelling": func(w map[string]any) {
			c := w["Context"].(map[string]any)
			c["runurl"] = c["RunUrl"]
			delete(c, "RunUrl")
		},
		"invalid attempt":     func(w map[string]any) { w["Context"].(map[string]any)["RunAttempt"] = 0 },
		"invalid source path": func(w map[string]any) { w["Context"].(map[string]any)["TestFile"] = "../private.ps1" },
	}
	for name, mutate := range cases {
		t.Run(name, func(t *testing.T) {
			f := newPSShardFixture(t)
			f.worker(t, 1, mutate)
			if _, err := rc.MergePowerShellShards(f.identity, f.catalog, f.inputs, f.inventory); err == nil {
				t.Fatal("untrusted native execution context accepted")
			}
		})
	}
	t.Run("same case relabeled PID", func(t *testing.T) {
		f := newPSShardFixture(t)
		f.worker(t, 1, func(w map[string]any) { w["ProcessId"] = 999 })
		var proof map[string]any
		if err := json.Unmarshal(f.files[1]["evidence.json"], &proof); err != nil {
			t.Fatal(err)
		}
		proof["Workers"].([]any)[0].(map[string]any)["ProcessId"] = 999
		f.files[1]["evidence.json"] = psShardJSON(t, proof)
		if _, err := rc.MergePowerShellShards(f.identity, f.catalog, f.inputs, f.inventory); err == nil {
			t.Fatal("outer re-signing bypassed the collector's observed PID")
		}
	})
}

func TestPowerShellShardsKeepContextOptionalOnlyForLegacyNormalizer(t *testing.T) {
	f := newPSShardFixture(t)
	f.worker(t, 0, func(w map[string]any) { delete(w, "Context") })
	if _, _, err := rc.NormalizePowerShell(f.files[0]["evidence.json"], f.inputs[0].Read, f.inventory); err != nil {
		t.Fatal("legacy raw proof no longer readable", err)
	}
	files, err := rc.ExportPowerShellRawEvidence(f.files[0]["evidence.json"], f.inputs[0].Read, f.inventory)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(files["worker_0.json"]), `"Context"`) {
		t.Fatal("legacy export invented a native execution context")
	}
	if _, err := rc.MergePowerShellShards(f.identity, f.catalog, f.inputs, f.inventory); err == nil {
		t.Fatal("legacy raw proof was silently promoted to native shard execution")
	}
}
