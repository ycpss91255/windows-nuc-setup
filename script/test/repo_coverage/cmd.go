package repo_coverage

import (
	"fmt"
	"regexp"
	"strings"
)

type CMDLauncher struct {
	Line             int
	Arguments        []string
	ForwardArguments bool
}

var cmdToken = regexp.MustCompile(`"[^"\r\n]*"|[^ \t"]+`)
var cmdLiteral = regexp.MustCompile(`^[A-Za-z0-9_./\\ -]+$`)

// ParseCMDLauncher intentionally supports only the repository's simple native
// PowerShell launchers. Unknown syntax has no trustworthy executable catalog.
// @echo off is a shell display directive, not an executable setup statement.
func ParseCMDLauncher(data []byte) (CMDLauncher, error) {
	result := CMDLauncher{}
	directive := false
	for index, line := range strings.Split(strings.TrimPrefix(string(data), "\ufeff"), "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		if !directive {
			if !strings.EqualFold(line, "@echo off") {
				return result, fmt.Errorf("CMD requires explicit echo directive")
			}
			directive = true
			continue
		}
		if result.Line != 0 || strings.ContainsAny(line, "&|<>^!()\r") {
			return result, fmt.Errorf("unsupported CMD control flow")
		}
		tokens := cmdToken.FindAllString(line, -1)
		if len(tokens) < 3 || !strings.EqualFold(tokens[0], "powershell.exe") {
			return result, fmt.Errorf("unsupported CMD command")
		}
		if strings.Join(tokens, " ") != line {
			return result, fmt.Errorf("CMD launcher spacing or quoting is unsupported")
		}
		hasFile := false
		for n, token := range tokens[1:] {
			if token == "%*" {
				if n != len(tokens)-2 {
					return result, fmt.Errorf("CMD forwarding must be final")
				}
				result.ForwardArguments = true
				continue
			}
			value := strings.Trim(token, "\"")
			if strings.HasPrefix(value, "%~dp0") {
				if !strings.HasPrefix(token, "\"") {
					return result, fmt.Errorf("CMD dynamic path must be quoted")
				}
				value = strings.TrimPrefix(value, "%~dp0")
			}
			if !cmdLiteral.MatchString(value) {
				return result, fmt.Errorf("unsupported CMD argument")
			}
			original := strings.Trim(token, "\"")
			if strings.EqualFold(original, "-Command") || strings.EqualFold(original, "-EncodedCommand") {
				return result, fmt.Errorf("CMD must launch a file")
			}
			if strings.EqualFold(original, "-File") {
				if n+2 >= len(tokens) || !strings.HasPrefix(tokens[n+2], "\"%~dp0") || !strings.HasSuffix(strings.ToLower(tokens[n+2]), ".ps1\"") {
					return result, fmt.Errorf("CMD script must be source-relative")
				}
				hasFile = true
			}
			result.Arguments = append(result.Arguments, original)
		}
		if !hasFile {
			return result, fmt.Errorf("CMD has no script file")
		}
		result.Line = index + 1
	}
	if result.Line == 0 {
		return result, fmt.Errorf("CMD has no executable launcher")
	}
	return result, nil
}
