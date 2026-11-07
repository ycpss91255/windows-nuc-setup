package acceptance

import (
	"fmt"
	"path/filepath"
	"strings"
)

func CoverageOutputLocation(source, out string) error {
	if !filepath.IsAbs(source) || !filepath.IsAbs(out) {
		return fmt.Errorf("coverage paths must be resolved absolute paths")
	}
	if !strings.EqualFold(filepath.VolumeName(source), filepath.VolumeName(out)) {
		return nil
	}
	rel, e := filepath.Rel(source, out)
	if e != nil {
		return e
	}
	if rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
		return fmt.Errorf("coverage output must be outside read-only source")
	}
	return nil
}
