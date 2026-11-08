package repo_coverage

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"regexp"
	"runtime"
	"sort"
	"strconv"
	"strings"
)

type CMDRun struct {
	Arguments                        []string
	Directory                        string
	ExtraArguments                   []string
	ExitCode, ProbeExit, Invocations int
}
type CMDSource struct {
	File, SHA256, CopiedSHA256, AfterSHA256, CopyDirectory string
	Runs                                                   []CMDRun
}
type CMDEvidence struct {
	SchemaVersion       int
	Metric, ProbeSHA256 string
	Sources             []CMDSource
}

func launcherArguments(l CMDLauncher, dir string, extra []string) []string {
	result := []string{}
	for _, arg := range l.Arguments {
		if strings.HasPrefix(arg, "%~dp0") {
			arg = dir + string(filepath.Separator) + strings.TrimPrefix(arg, "%~dp0")
		}
		result = append(result, arg)
	}
	if l.ForwardArguments {
		result = append(result, extra...)
	}
	return result
}

// CollectCMD executes only prevalidated launchers against a caller-built test
// probe. No .ps1 source is copied or invoked. The isolated current directory and
// PATH contain powershell.exe probe, preventing resolution to the real shell.
func CollectCMD(root, probe string) (CMDEvidence, error) {
	e := CMDEvidence{SchemaVersion: 1, Metric: Metric}
	if runtime.GOOS != "windows" {
		return e, fmt.Errorf("CMD collection requires Windows")
	}
	inv, err := ScanInventory(root)
	if err != nil {
		return e, err
	}
	originals := map[string][]byte{}
	launchers := map[string]CMDLauncher{}
	for _, s := range inv.Sources {
		if s.Language != "cmd" {
			continue
		}
		b, err := os.ReadFile(filepath.Join(root, filepath.FromSlash(s.Path)))
		if err != nil {
			return e, err
		}
		l, err := ParseCMDLauncher(b)
		if err != nil {
			return e, fmt.Errorf("%s: %w", s.Path, err)
		}
		originals[s.Path] = b
		launchers[s.Path] = l
	}
	if len(originals) == 0 {
		return e, fmt.Errorf("no CMD sources")
	}
	executable, err := os.ReadFile(probe)
	if err != nil {
		return e, err
	}
	e.ProbeSHA256 = digest(executable)
	temp, err := os.MkdirTemp("", "cmd_coverage_空白 ")
	if err != nil {
		return e, err
	}
	defer os.RemoveAll(temp)
	probeDir := filepath.Join(temp, "probe")
	if err := os.Mkdir(probeDir, 0700); err != nil {
		return e, err
	}
	if err := os.WriteFile(filepath.Join(probeDir, "powershell.exe"), executable, 0700); err != nil {
		return e, err
	}
	cmd := filepath.Join(os.Getenv("SystemRoot"), "System32", "cmd.exe")
	names := []string{}
	for name := range originals {
		names = append(names, name)
	}
	sort.Strings(names)
	for _, name := range names {
		b := originals[name]
		copyPath := filepath.Join(temp, "source", filepath.FromSlash(name))
		if err := os.MkdirAll(filepath.Dir(copyPath), 0700); err != nil {
			return e, err
		}
		if err := os.WriteFile(copyPath, b, 0600); err != nil {
			return e, err
		}
		copied, err := os.ReadFile(copyPath)
		if err != nil || !bytes.Equal(b, copied) {
			return e, fmt.Errorf("CMD copy differs")
		}
		s := CMDSource{File: name, SHA256: digest(b), CopiedSHA256: digest(copied), CopyDirectory: filepath.Dir(copyPath)}
		for _, scenario := range []struct {
			extra []string
			code  int
		}{{[]string{}, 0}, {[]string{"-ProbeArgument", "含 空白 English"}, 37}} {
			record := filepath.Join(temp, "invocation.jsonl")
			os.Remove(record)
			invocation := "\"" + copyPath + "\""
			for _, arg := range scenario.extra {
				invocation += " \"" + arg + "\""
			}
			process := exec.Command(cmd, "/d", "/c", "%CMD_PROBE_COMMAND%")
			process.Dir = probeDir
			process.Env = []string{"SystemRoot=" + os.Getenv("SystemRoot"), "PATH=" + probeDir, "PATHEXT=.EXE", "CMD_PROBE_COMMAND=" + invocation, "CMD_PROBE_OUTPUT=" + record, "CMD_PROBE_EXIT=" + strconv.Itoa(scenario.code)}
			output, runerr := process.CombinedOutput()
			code := 0
			if runerr != nil {
				if exit, ok := runerr.(*exec.ExitError); ok {
					code = exit.ExitCode()
				} else {
					return e, runerr
				}
			}
			raw, err := os.ReadFile(record)
			if err != nil {
				return e, fmt.Errorf("CMD did not invoke probe: %s %s", name, output)
			}
			rows := bytes.Split(bytes.TrimSpace(raw), []byte("\n"))
			if len(rows) != 1 {
				return e, fmt.Errorf("CMD invoked probe more than once")
			}
			var observed struct {
				Arguments []string
				Directory string
			}
			if err := json.Unmarshal(rows[0], &observed); err != nil {
				return e, err
			}
			s.Runs = append(s.Runs, CMDRun{Arguments: observed.Arguments, Directory: observed.Directory, ExtraArguments: scenario.extra, ExitCode: code, ProbeExit: scenario.code, Invocations: len(rows)})
		}
		after, err := os.ReadFile(filepath.Join(root, filepath.FromSlash(name)))
		if err != nil {
			return e, err
		}
		s.AfterSHA256 = digest(after)
		e.Sources = append(e.Sources, s)
	}
	if _, _, err := NormalizeCMD(e, originals); err != nil {
		return e, err
	}
	return e, nil
}

func NormalizeCMD(e CMDEvidence, originals map[string][]byte) (Report, []Catalog, error) {
	r := Report{SchemaVersion: 1, Metric: Metric, Files: map[string]map[int]bool{}}
	catalogs := []Catalog{}
	if e.SchemaVersion != 1 || e.Metric != Metric || !regexp.MustCompile(`^[a-f0-9]{64}$`).MatchString(e.ProbeSHA256) || len(e.Sources) == 0 || len(e.Sources) != len(originals) {
		return r, nil, fmt.Errorf("invalid CMD evidence identity or inventory")
	}
	for _, s := range e.Sources {
		b, ok := originals[s.File]
		if !ok || r.Files[s.File] != nil || s.SHA256 != digest(b) || s.CopiedSHA256 != s.SHA256 || s.AfterSHA256 != s.SHA256 {
			return r, nil, fmt.Errorf("CMD source mismatch")
		}
		l, err := ParseCMDLauncher(b)
		if err != nil {
			return r, nil, err
		}
		if len(s.Runs) != 2 || !filepath.IsAbs(s.CopyDirectory) {
			return r, nil, fmt.Errorf("CMD success and failure runs missing")
		}
		for index, run := range s.Runs {
			expectedExit := 0
			extra := []string{}
			if index == 1 {
				expectedExit = 37
				extra = []string{"-ProbeArgument", "含 空白 English"}
			}
			if run.ProbeExit != expectedExit || run.ExitCode != expectedExit || run.Invocations != 1 || run.Directory == "" || !reflect.DeepEqual(run.ExtraArguments, extra) || !reflect.DeepEqual(run.Arguments, launcherArguments(l, s.CopyDirectory, extra)) {
				return r, nil, fmt.Errorf("CMD argv or exit evidence differs: %s", s.File)
			}
		}
		r.Files[s.File] = map[int]bool{l.Line: true}
		catalogs = append(catalogs, Catalog{Path: s.File, SHA256: s.SHA256, Lines: []int{l.Line}})
	}
	sort.Slice(catalogs, func(i, j int) bool { return catalogs[i].Path < catalogs[j].Path })
	return r, catalogs, nil
}
