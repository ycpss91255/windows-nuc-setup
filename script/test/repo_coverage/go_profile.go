package repo_coverage

import (
	"crypto/sha256"
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

type goBlock struct {
	file       string
	start, end token.Position
	statements int
	hit        bool
}
type goSource struct {
	data  []byte
	file  *ast.File
	set   *token.FileSet
	lines []string
}

var profileBlock = regexp.MustCompile(`^(.+):(\d+)\.(\d+),(\d+)\.(\d+) (\d+) (\d+)$`)

func before(a, b token.Position) bool {
	return a.Line < b.Line || a.Line == b.Line && a.Column < b.Column
}
func positionValid(pos token.Position, lines []string) bool {
	return pos.Line > 0 && pos.Line <= len(lines) && pos.Column > 0 && pos.Column <= len(strings.TrimSuffix(lines[pos.Line-1], "\r"))+1
}

func executableStatement(node ast.Node) bool {
	stmt, ok := node.(ast.Stmt)
	if !ok {
		return false
	}
	switch value := stmt.(type) {
	case *ast.BlockStmt, *ast.EmptyStmt, *ast.CaseClause, *ast.CommClause, *ast.LabeledStmt:
		return false
	case *ast.DeclStmt:
		declaration, ok := value.Decl.(*ast.GenDecl)
		return ok && declaration.Tok == token.VAR
	default:
		return true
	}
}

// NormalizeGo first unions compiler-block counters, then uses original Go AST
// statement positions to select executable lines. All instrumented statement
// positions sharing one physical line must be covered. Comments, blank lines,
// braces and type/constant declarations do not inflate the line denominator.
// Profiles after the first may add hits, never new blocks or changed counts.
func NormalizeGo(profiles [][]byte, sources map[string][]byte, module string) (Report, []Catalog, error) {
	r := Report{SchemaVersion: SchemaVersion, Metric: Metric, Files: map[string]map[int]bool{}}
	var catalogs []Catalog
	if len(profiles) == 0 || len(sources) == 0 || module == "" || strings.HasSuffix(module, "/") {
		return r, nil, fmt.Errorf("Go normalization requires profiles, sources and module identity")
	}
	parsed := map[string]goSource{}
	for raw, data := range sources {
		name, err := RelativePath(raw)
		if err != nil {
			return r, nil, err
		}
		if !strings.HasSuffix(name, ".go") || strings.HasSuffix(name, "_test.go") {
			return r, nil, fmt.Errorf("not a production Go source: %s", name)
		}
		set := token.NewFileSet()
		file, err := parser.ParseFile(set, name, data, 0)
		if err != nil {
			return r, nil, err
		}
		parsed[name] = goSource{data, file, set, strings.Split(string(data), "\n")}
		r.Files[name] = map[int]bool{}
	}
	blocks := map[string]goBlock{}
	for profileIndex, profile := range profiles {
		lines := strings.Split(strings.TrimSpace(string(profile)), "\n")
		if len(lines) == 0 || (lines[0] != "mode: set" && lines[0] != "mode: count" && lines[0] != "mode: atomic") {
			return r, nil, fmt.Errorf("invalid Go coverage mode")
		}
		for _, line := range lines[1:] {
			match := profileBlock.FindStringSubmatch(strings.TrimSpace(line))
			if match == nil {
				return r, nil, fmt.Errorf("malformed Go coverage block")
			}
			if !strings.HasPrefix(match[1], module+"/") {
				return r, nil, fmt.Errorf("foreign Go module in profile")
			}
			name, err := RelativePath(strings.TrimPrefix(match[1], module+"/"))
			if err != nil {
				return r, nil, err
			}
			source, ok := parsed[name]
			if !ok {
				return r, nil, fmt.Errorf("profile contains unknown Go source: %s", name)
			}
			values := make([]int, 6)
			for i := range values {
				n, e := strconv.Atoi(match[i+2])
				if e != nil {
					return r, nil, e
				}
				values[i] = n
			}
			b := goBlock{name, token.Position{Line: values[0], Column: values[1]}, token.Position{Line: values[2], Column: values[3]}, values[4], values[5] > 0}
			if !positionValid(b.start, source.lines) || !positionValid(b.end, source.lines) || before(b.end, b.start) || !before(b.start, b.end) && b.statements > 0 {
				return r, nil, fmt.Errorf("Go coverage block is outside original source: %s", name)
			}
			id := strings.Join(match[1:6], ":")
			old, exists := blocks[id]
			if profileIndex > 0 && !exists {
				return r, nil, fmt.Errorf("additional profile changed compiler block inventory")
			}
			if exists && old.statements != b.statements {
				return r, nil, fmt.Errorf("contradictory Go statement denominator")
			}
			b.hit = b.hit || old.hit
			blocks[id] = b
		}
	}
	for name, source := range parsed {
		var invalid error
		ast.Inspect(source.file, func(node ast.Node) bool {
			if invalid != nil {
				return false
			}
			if !executableStatement(node) {
				return true
			}
			pos := source.set.Position(node.Pos())
			var best *goBlock
			for _, block := range blocks {
				b := block
				if b.file != name || b.statements == 0 || before(pos, b.start) || !before(pos, b.end) {
					continue
				}
				if best == nil || before(best.start, b.start) || best.start.Line == b.start.Line && best.start.Column == b.start.Column && before(b.end, best.end) {
					best = &b
				}
			}
			if best == nil {
				invalid = fmt.Errorf("Go executable point omitted by compiler baseline: %s:%d:%d", name, pos.Line, pos.Column)
				return false
			}
			prior, seen := r.Files[name][pos.Line]
			r.Files[name][pos.Line] = best.hit && (!seen || prior)
			return true
		})
		if invalid != nil {
			return r, nil, invalid
		}
		lines := make([]int, 0, len(r.Files[name]))
		for line := range r.Files[name] {
			lines = append(lines, line)
		}
		sort.Ints(lines)
		catalogs = append(catalogs, Catalog{Path: name, SHA256: fmt.Sprintf("%x", sha256.Sum256(source.data)), Lines: lines})
	}
	sort.Slice(catalogs, func(i, j int) bool { return catalogs[i].Path < catalogs[j].Path })
	return r, catalogs, nil
}
