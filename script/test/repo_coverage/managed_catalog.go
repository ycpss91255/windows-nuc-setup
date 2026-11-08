package repo_coverage

import (
	"encoding/xml"
	"fmt"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

type pdbPoint struct {
	Path                                               string
	StartLine, StartColumn, EndLine, EndColumn, Offset int
}
type pdbMethod struct {
	Token        string
	HasBody      *bool
	HiddenPoints int
	Points       []pdbPoint
}
type pdbCatalog struct {
	SchemaVersion                                                         int
	AssemblySHA256, PDBSHA256, AssemblyMVID, PDBContentID, PEPDBContentID string
	Documents                                                             []struct{ Path, SHA256 string }
	Methods                                                               []pdbMethod
}
type nativeSpan struct {
	path       string
	start, end uint64
}

func spanPosition(line, column int) uint64 { return uint64(line)<<32 | uint64(column) }
func methodToken(token string) (uint64, error) {
	if !strings.HasPrefix(token, "0x") {
		return 0, fmt.Errorf("invalid method token")
	}
	value, err := strconv.ParseUint(token[2:], 16, 32)
	if err != nil || value>>24 != 6 || value&0xffffff == 0 {
		return 0, fmt.Errorf("invalid method definition token")
	}
	return value, nil
}

// The independent PDB supplies every method and visible point. Native ranges
// may subdivide each point, but their union must span it without omissions.
func validateManagedCatalog(data []byte, proof managedEvidence, merged []byte, originals map[string][]byte) error {
	var catalog pdbCatalog
	if err := strictJSON(data, &catalog); err != nil {
		return err
	}
	if catalog.SchemaVersion != 1 || catalog.AssemblySHA256 != proof.AssemblySHA256 || catalog.PDBSHA256 != proof.PDBSHA256 || !regexp.MustCompile(`(?i)^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$`).MatchString(catalog.AssemblyMVID) || catalog.PDBContentID == "" || catalog.PDBContentID != catalog.PEPDBContentID || len(catalog.Documents) != len(originals) || len(catalog.Methods) == 0 {
		return fmt.Errorf("independent PDB identity is incomplete")
	}
	docs := map[string]bool{}
	for _, doc := range catalog.Documents {
		b, ok := originals[doc.Path]
		if !ok || docs[doc.Path] || digest(b) != doc.SHA256 {
			return fmt.Errorf("PDB document checksum differs")
		}
		docs[doc.Path] = true
	}
	var document managedXML
	if err := xml.Unmarshal(merged, &document); err != nil {
		return err
	}
	if len(document.Modules) != 1 {
		return fmt.Errorf("PDB catalog must identify one owned assembly")
	}
	ranges := map[uint64][]nativeSpan{}
	module := document.Modules[0]
	sourceIDs := map[string]string{}
	for _, s := range module.Sources {
		name, err := sourcePath(proof.SourceRoot, s.Path, nil)
		if err != nil {
			return err
		}
		sourceIDs[s.ID] = name
	}
	for _, f := range module.Functions {
		token, err := methodToken(f.Token)
		if err != nil {
			return err
		}
		for _, r := range f.Ranges {
			ranges[token] = append(ranges[token], nativeSpan{sourceIDs[r.SourceID], spanPosition(r.StartLine, r.StartColumn), spanPosition(r.EndLine, r.EndColumn)})
		}
	}
	seen := map[uint64]bool{}
	for _, method := range catalog.Methods {
		token, err := methodToken(method.Token)
		if err != nil {
			return err
		}
		if seen[token] || method.HasBody == nil || method.HiddenPoints < 0 || method.Points == nil || !*method.HasBody && len(method.Points) > 0 {
			return fmt.Errorf("PDB method roster malformed")
		}
		seen[token] = true
		points := []nativeSpan{}
		offsets := map[int]bool{}
		for _, p := range method.Points {
			if !docs[p.Path] || p.StartLine <= 0 || p.StartColumn <= 0 || p.EndLine <= 0 || p.EndColumn <= 0 || p.Offset < 0 || offsets[p.Offset] {
				return fmt.Errorf("PDB visible point malformed")
			}
			offsets[p.Offset] = true
			point := nativeSpan{p.Path, spanPosition(p.StartLine, p.StartColumn), spanPosition(p.EndLine, p.EndColumn)}
			if point.end <= point.start {
				return fmt.Errorf("PDB point extent malformed")
			}
			points = append(points, point)
			matching := []nativeSpan{}
			for _, r := range ranges[token] {
				if r.path == point.path && r.start < point.end && r.end > point.start {
					matching = append(matching, r)
				}
			}
			sort.Slice(matching, func(i, j int) bool { return matching[i].start < matching[j].start })
			cursor := point.start
			for _, r := range matching {
				if r.start > cursor {
					break
				}
				if r.end > cursor {
					cursor = r.end
				}
			}
			if cursor < point.end {
				return fmt.Errorf("native counters omit PDB visible point: %s %s", method.Token, p.Path)
			}
		}
		for _, r := range ranges[token] {
			matched := false
			for _, p := range points {
				if p.path == r.path && r.start < p.end && r.end > p.start {
					matched = true
					break
				}
			}
			if !matched {
				return fmt.Errorf("native counter has no independent PDB point")
			}
		}
	}
	for token := range ranges {
		if !seen[token] {
			return fmt.Errorf("native method missing from independent PDB catalog")
		}
	}
	return nil
}
