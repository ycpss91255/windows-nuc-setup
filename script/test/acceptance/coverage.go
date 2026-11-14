package acceptance

import (
	"errors"
	"fmt"
	"math"
	"path"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

var ErrCoverageBelowThreshold = errors.New("Go coverage below exact threshold")

type CoverageMeasurement struct {
	Covered, TotalStatements int
	Percent                  float64
	Profile                  []byte
	Packages                 []string
}

func EvaluateCoverage(profiles [][]byte, expectedFiles []string) (CoverageMeasurement, error) {
	m := CoverageMeasurement{}
	type block struct {
		file              string
		statements, count int
	}
	blocks := map[string]block{}
	files := map[string]bool{}
	allowed := map[string]bool{}
	packages := map[string]bool{}
	for _, f := range expectedFiles {
		if !strings.HasPrefix(f, "windows_setup/script/test/") || strings.HasSuffix(f, "_test.go") || !strings.HasSuffix(f, ".go") {
			return m, fmt.Errorf("coverage scope contains non-maintenance source: %s", f)
		}
		allowed[f] = true
	}
	if len(allowed) == 0 {
		return m, fmt.Errorf("coverage denominator is empty")
	}
	pattern := regexp.MustCompile(`^(windows_setup/script/test/[a-z0-9_/]+\.go):([0-9]+\.[0-9]+,[0-9]+\.[0-9]+) ([0-9]+) ([0-9]+)$`)
	for profileIndex, profile := range profiles {
		lines := strings.Split(strings.TrimSpace(string(profile)), "\n")
		if len(lines) < 2 || !strings.HasPrefix(lines[0], "mode: ") {
			return m, fmt.Errorf("invalid coverage profile")
		}
		mode := strings.TrimSpace(strings.TrimPrefix(lines[0], "mode: "))
		if mode != "set" && mode != "count" && mode != "atomic" {
			return m, fmt.Errorf("unknown coverage mode")
		}
		for _, line := range lines[1:] {
			match := pattern.FindStringSubmatch(strings.TrimSpace(line))
			if match == nil {
				return m, fmt.Errorf("invalid or private coverage block")
			}
			n, e := strconv.Atoi(match[3])
			if e != nil {
				return m, fmt.Errorf("invalid coverage statement count")
			}
			count, e := strconv.Atoi(match[4])
			if e != nil {
				return m, e
			}
			if !allowed[match[1]] {
				return m, fmt.Errorf("unexpected coverage source: %s", match[1])
			}
			id := match[1] + ":" + match[2]
			old, exists := blocks[id]
			if profileIndex > 0 && !exists {
				return m, fmt.Errorf("CLI profile contains a block absent from compiler baseline")
			}
			if exists && old.statements != n {
				return m, fmt.Errorf("contradictory statement denominator")
			}
			if count > 0 || old.count > 0 {
				count = 1
			}
			blocks[id] = block{match[1], n, count}
			if n > 0 {
				files[match[1]] = true
			}
			packages[path.Dir(match[1])] = true
		}
	}
	for f := range allowed {
		if !files[f] {
			return m, fmt.Errorf("coverage omitted owned Go source: %s", f)
		}
	}
	keys := []string{}
	for k := range blocks {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	var out strings.Builder
	out.WriteString("mode: set\n")
	for _, k := range keys {
		b := blocks[k]
		m.TotalStatements += b.statements
		if b.count > 0 {
			m.Covered += b.statements
		}
		fmt.Fprintf(&out, "%s %d %d\n", k, b.statements, b.count)
	}
	for p := range packages {
		m.Packages = append(m.Packages, p)
	}
	sort.Strings(m.Packages)
	m.Profile = []byte(out.String())
	if m.TotalStatements <= 0 {
		return m, fmt.Errorf("empty coverage measurement")
	}
	m.Percent = math.Round(float64(m.Covered)*1000/float64(m.TotalStatements)) / 10
	if int64(m.Covered)*100 < int64(m.TotalStatements)*80 {
		return m, fmt.Errorf("%w: %.1f%% (%d/%d), required 80%%", ErrCoverageBelowThreshold, m.Percent, m.Covered, m.TotalStatements)
	}
	return m, nil
}
