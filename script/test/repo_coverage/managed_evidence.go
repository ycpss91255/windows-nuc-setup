package repo_coverage

import (
	"fmt"
	"reflect"
	"sort"
)

const managedPackageHash = "hgzaG+c7LtKup6HZixvXtn3l4Pa8VK23bM9vLHveD3Iq2XlzLu7vqMZwtVjQdsof83wx5OzY0tpDh3+YRdOVjA=="

type managedEvidence struct {
	SchemaVersion                                                        int
	Metric, SourceRoot                                                   string
	Tool                                                                 struct{ Id, Version, PackageSHA512 string }
	Sources                                                              []struct{ Path, SHA256 string }
	AssemblyPath, AssemblySHA256, PDBPath, PDBSHA256                     string
	Shards                                                               []struct{ BinaryPath, SHA256, XmlPath, XmlSHA256 string }
	MergedBinaryPath, MergedBinarySHA256, MergedXmlPath, MergedXmlSHA256 string
	MergeNative                                                          bool
}

// NormalizeManaged verifies private native collector artifacts. Only the native
// binary-merged XML supplies hits; shard XML is solely denominator evidence.
func NormalizeManaged(data []byte, read func(string) ([]byte, error), originals map[string][]byte) (Report, []Catalog, error) {
	empty := Report{}
	var proof managedEvidence
	if err := strictJSON(data, &proof); err != nil {
		return empty, nil, err
	}
	if proof.SchemaVersion != 1 || proof.Metric != Metric || !proof.MergeNative || proof.Tool.Id != "Microsoft.dotnet-coverage" || proof.Tool.Version != "17.14.1" || proof.Tool.PackageSHA512 != managedPackageHash || len(proof.Shards) == 0 || len(proof.Sources) != len(originals) {
		return empty, nil, fmt.Errorf("managed native collector identity invalid")
	}
	seen := map[string]bool{}
	for _, source := range proof.Sources {
		original, ok := originals[source.Path]
		if !ok || seen[source.Path] || digest(original) != source.SHA256 {
			return empty, nil, fmt.Errorf("managed source hash inventory differs")
		}
		seen[source.Path] = true
	}
	consumed := map[string]bool{}
	checked := func(name, hash string) ([]byte, error) {
		canonical, err := RelativePath(name)
		if err != nil {
			return nil, err
		}
		if canonical != name || consumed[name] {
			return nil, fmt.Errorf("duplicate or noncanonical managed artifact")
		}
		consumed[name] = true
		b, err := read(name)
		if err != nil {
			return nil, err
		}
		if len(b) == 0 || digest(b) != hash {
			return nil, fmt.Errorf("managed artifact hash differs: %s", name)
		}
		return b, nil
	}
	for _, artifact := range [][2]string{{proof.AssemblyPath, proof.AssemblySHA256}, {proof.PDBPath, proof.PDBSHA256}, {proof.MergedBinaryPath, proof.MergedBinarySHA256}} {
		if _, err := checked(artifact[0], artifact[1]); err != nil {
			return empty, nil, err
		}
	}
	merged, err := checked(proof.MergedXmlPath, proof.MergedXmlSHA256)
	if err != nil {
		return empty, nil, err
	}
	result, catalogs, roster, err := parseManaged(merged, proof.SourceRoot, originals)
	if err != nil {
		return empty, nil, err
	}
	keys := func(counters map[string]string) []string {
		result := []string{}
		for key := range counters {
			result = append(result, key)
		}
		sort.Strings(result)
		return result
	}
	expected := keys(roster)
	for _, shard := range proof.Shards {
		if _, err := checked(shard.BinaryPath, shard.SHA256); err != nil {
			return empty, nil, err
		}
		xml, err := checked(shard.XmlPath, shard.XmlSHA256)
		if err != nil {
			return empty, nil, err
		}
		_, _, counters, err := parseManaged(xml, proof.SourceRoot, originals)
		if err != nil {
			return empty, nil, err
		}
		if !reflect.DeepEqual(expected, keys(counters)) {
			return empty, nil, fmt.Errorf("native shard and merged counter rosters differ")
		}
	}
	return result, catalogs, nil
}
