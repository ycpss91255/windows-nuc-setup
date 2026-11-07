package acceptance

import (
	"fmt"
	"os/exec"
	"sort"
	"strings"
)

// OwnedGoFiles deliberately inventories all owned tracked Go, not a hand-picked package list.
func OwnedGoFiles(root string) ([]string, error) {
	b, e := exec.Command("git", "-C", root, "-c", "core.quotePath=false", "ls-files").Output()
	if e != nil {
		return nil, e
	}
	files := []string{}
	for _, p := range strings.Split(strings.TrimSpace(string(b)), "\n") {
		p = strings.TrimSpace(p)
		if strings.HasSuffix(p, ".go") && !strings.HasSuffix(p, "_test.go") && !strings.HasPrefix(p, "vendor/") {
			if !strings.HasPrefix(p, "script/test/") {
				return nil, fmt.Errorf("new owned Go source outside measured maintenance scope: %s; expand coverpkg before accepting", p)
			}
			files = append(files, "windows_setup/"+p)
		}
	}
	sort.Strings(files)
	if len(files) == 0 {
		return nil, fmt.Errorf("no owned Go source found")
	}
	return files, nil
}
