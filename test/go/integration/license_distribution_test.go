package integration_test

import (
	"crypto/sha256"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

func TestSourceDistributionContainsApprovedApacheLicense(t *testing.T) {
	root, err := filepath.Abs("../../..")
	if err != nil {
		t.Fatal(err)
	}
	b, err := os.ReadFile(filepath.Join(root, "license"))
	if err != nil {
		t.Fatalf("source distribution must include the approved license: %v", err)
	}
	// Apache's complete official text, including the appendix; normalize only
	// platform line endings so Git checkout settings cannot change this contract.
	canonical := strings.ReplaceAll(string(b), "\r\n", "\n")
	if got := fmt.Sprintf("%x", sha256.Sum256([]byte(canonical))); got != "cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30" {
		t.Fatal("license must retain the complete official Apache-2.0 text")
	}
}

func TestSourceDistributionLicenseReferencesResolve(t *testing.T) {
	root, err := filepath.Abs("../../..")
	if err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"readme.md", "doc/third_party.md"} {
		b, err := os.ReadFile(filepath.Join(root, name))
		if err != nil {
			t.Fatal(err)
		}
		refs := regexp.MustCompile(`\]\(([^)]+)\)`).FindAllStringSubmatch(string(b), -1)
		found := false
		for _, ref := range refs {
			if ref[1] != "./license" && ref[1] != "../license" {
				continue
			}
			path := filepath.Clean(filepath.Join(root, filepath.Dir(name), ref[1]))
			if path != filepath.Join(root, "license") {
				t.Fatalf("%s license link resolves outside the approved root license", name)
			}
			if _, err := os.ReadFile(path); err != nil {
				t.Fatal(err)
			}
			found = true
		}
		if !found {
			t.Errorf("%s must link to the locally shipped license", name)
		}
	}
}
