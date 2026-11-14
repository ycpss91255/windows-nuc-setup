package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

func TestFixedPinMatchesDebloatProfile(t *testing.T) {
	b, e := os.ReadFile("../../../modules/debloat/debloat_profile.json")
	if e != nil {
		t.Fatal(e)
	}
	var p struct{ Source, Commit string }
	if e = json.Unmarshal(bytes.TrimPrefix(b, []byte{0xef, 0xbb, 0xbf}), &p); e != nil {
		t.Fatal(e)
	}
	if p.Source != "https://github.com/Raphire/Win11Debloat" || p.Commit != upstream.commit {
		t.Fatal("profile source differs from fixed upstream pin")
	}
}

func TestReviewedLockPreservesRuntimeAndLicense(t *testing.T) {
	l, e := loadLock("upstream.lock.json", upstream)
	if e != nil {
		t.Fatal(e)
	}
	files := map[string]bool{}
	for _, f := range l.Files {
		files[f.Path] = f.Retain
	}
	for _, name := range []string{"Win11Debloat.ps1", "LICENSE", "README.md", ".gitignore", "Scripts/Get.ps1", "Config/Features.json", "Config/Languages/en-US/Chrome.json", "Config/Languages/zh-TW/Chrome.json", "Assets/Start/start2.bin"} {
		if !files[name] {
			t.Fatalf("required file omitted: %s", name)
		}
	}
}

func TestBundledVendorMatchesReviewedLock(t *testing.T) {
	l, e := loadLock("upstream.lock.json", upstream)
	if e != nil {
		t.Fatal(e)
	}
	if e = verify("../../../modules/debloat/win11debloat", l); e != nil {
		t.Fatal(e)
	}
	mainScript, e := os.ReadFile("../../../modules/debloat/win11debloat/Win11Debloat.ps1")
	if e != nil {
		t.Fatal(e)
	}
	refs := regexp.MustCompile(`(?m)^\.\s+"\$PSScriptRoot/(Scripts/[^"\r\n]+\.ps1)"`).FindAllSubmatch(mainScript, -1)
	if len(refs) != 80 {
		t.Fatalf("unexpected upstream startup script count: %d", len(refs))
	}
	retainedPaths := map[string]bool{}
	for _, f := range l.Files {
		if f.Retain {
			retainedPaths[f.Path] = true
		}
	}
	for _, ref := range refs {
		if !retainedPaths[string(ref[1])] {
			t.Fatalf("startup script omitted: %s", ref[1])
		}
	}
}

func syncFixture(t *testing.T) (string, pin) {
	t.Helper()
	root := t.TempDir()
	for name, content := range map[string]string{"Win11Debloat.ps1": "# fixed upstream\n", "LICENSE": "fixture license\n", ".gitignore": "Backups/*\n", "Tests/example.ps1": "# not runtime\n", "Scripts/Get.ps1": "# retained\n", "Scripts/Build-Release.ps1": "# development\n", "Scripts/Run-Tests.ps1": "# development\n", ".github/workflows/test.yml": "# development\n"} {
		p := filepath.Join(root, filepath.FromSlash(name))
		if e := os.MkdirAll(filepath.Dir(p), 0700); e != nil {
			t.Fatal(e)
		}
		if e := os.WriteFile(p, []byte(content), 0600); e != nil {
			t.Fatal(e)
		}
	}
	git := func(args ...string) string {
		t.Helper()
		cmd := exec.Command("git", append([]string{"-C", root}, args...)...)
		b, e := cmd.CombinedOutput()
		if e != nil {
			t.Fatalf("fixture git: %v %s", e, b)
		}
		return strings.TrimSpace(string(b))
	}
	git("init", "-q")
	git("add", ".")
	git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-qm", "fixture")
	return root, pin{git("rev-parse", "HEAD"), git("rev-parse", "HEAD^{tree}"), 8, 4, ""}
}
func TestSyncStageAndVerify(t *testing.T) {
	source, expected := syncFixture(t)
	root := t.TempDir()
	one := filepath.Join(root, "one")
	two := filepath.Join(root, "two")
	lock := filepath.Join(root, "lock.json")
	call := func(args ...string) error { return run(args, &bytes.Buffer{}, expected) }
	if e := call("lock", "--source", source, "--output", lock); e != nil {
		t.Fatalf("locked snapshot: %v", e)
	}
	lockData, e := os.ReadFile(lock)
	if e != nil {
		t.Fatal(e)
	}
	expected.lockSHA256 = fmt.Sprintf("%x", sha256.Sum256(lockData))
	for _, dest := range []string{one, two} {
		if e := call("stage", "--source", source, "--lock", lock, "--output", dest); e != nil {
			t.Fatalf("stage: %v", e)
		}
		if e := call("verify", "--lock", lock, "--vendor", dest); e != nil {
			t.Fatalf("verify: %v", e)
		}
	}
	if _, e := os.Stat(filepath.Join(one, "Tests/example.ps1")); !os.IsNotExist(e) {
		t.Fatal("development test retained")
	}
	if _, e := os.Stat(filepath.Join(one, "Scripts/Get.ps1")); e != nil {
		t.Fatal("upstream runtime downloader omitted")
	}
	if _, e := os.Stat(filepath.Join(one, ".gitignore")); e != nil {
		t.Fatal("privacy ignore rules omitted")
	}
	for _, name := range []string{"Scripts/Build-Release.ps1", "Scripts/Run-Tests.ps1", ".github/workflows/test.yml"} {
		if _, e := os.Stat(filepath.Join(one, filepath.FromSlash(name))); !os.IsNotExist(e) {
			t.Fatalf("development file retained: %s", name)
		}
	}
	a, _ := os.ReadFile(filepath.Join(one, "Win11Debloat.ps1"))
	b, _ := os.ReadFile(filepath.Join(two, "Win11Debloat.ps1"))
	if !bytes.Equal(a, b) {
		t.Fatal("nonreproducible bytes")
	}
	if e := call("stage", "--source", source, "--lock", lock, "--output", one); e == nil {
		t.Fatal("overwrote existing destination")
	}
	t.Run("matching tampered lock and vendor", func(t *testing.T) {
		dest := filepath.Join(root, "forged-vendor")
		if e := call("stage", "--source", source, "--lock", lock, "--output", dest); e != nil {
			t.Fatal(e)
		}
		changed := []byte("modified license\n")
		if e := os.WriteFile(filepath.Join(dest, "LICENSE"), changed, 0600); e != nil {
			t.Fatal(e)
		}
		l, e := loadLock(lock, expected)
		if e != nil {
			t.Fatal(e)
		}
		for i := range l.Files {
			if l.Files[i].Path == "LICENSE" {
				l.Files[i].SHA256 = fmt.Sprintf("%x", sha256.Sum256(changed))
			}
		}
		data, e := encodeLock(l)
		if e != nil {
			t.Fatal(e)
		}
		forged := filepath.Join(root, "forged.lock")
		if e = os.WriteFile(forged, data, 0600); e != nil {
			t.Fatal(e)
		}
		if e = call("verify", "--lock", forged, "--vendor", dest); e == nil {
			t.Fatal("accepted altered lock matching altered vendor")
		}
	})
	if e := call("stage", "--source", source, "--lock", lock, "--output", filepath.Join(source, "inside")); e == nil {
		t.Fatal("accepted destination inside source")
	}
	t.Run("source alias", func(t *testing.T) {
		alias := filepath.Join(t.TempDir(), "source-link")
		if e := os.Symlink(source, alias); e != nil {
			t.Fatalf("directory symlink fixture: %v", e)
		}
		if e := call("stage", "--source", source, "--lock", lock, "--output", filepath.Join(alias, "inside")); e == nil {
			t.Fatal("accepted destination inside source via symlink")
		}
	})
	for _, kind := range []string{"missing", "changed", "extra"} {
		t.Run(kind, func(t *testing.T) {
			dest := filepath.Join(root, kind)
			if e := call("stage", "--source", source, "--lock", lock, "--output", dest); e != nil {
				t.Fatal(e)
			}
			p := filepath.Join(dest, "LICENSE")
			switch kind {
			case "missing":
				if e := os.Remove(p); e != nil {
					t.Fatal(e)
				}
			case "changed":
				if e := os.WriteFile(p, []byte("changed"), 0600); e != nil {
					t.Fatal(e)
				}
			case "extra":
				if e := os.WriteFile(filepath.Join(dest, "extra"), []byte("extra"), 0600); e != nil {
					t.Fatal(e)
				}
			}
			if e := call("verify", "--lock", lock, "--vendor", dest); e == nil {
				t.Fatalf("accepted %s", kind)
			}
		})
	}
	if e := run([]string{"lock", "--source", source, "--output", filepath.Join(root, "bad.json")}, &bytes.Buffer{}, pin{strings.Repeat("0", 40), expected.tree, expected.files, expected.keep, expected.lockSHA256}); e == nil {
		t.Fatal("accepted wrong commit")
	}
	if e := run([]string{"lock", "--source", source, "--output", filepath.Join(root, "bad-tree.json")}, &bytes.Buffer{}, pin{expected.commit, strings.Repeat("0", 40), expected.files, expected.keep, expected.lockSHA256}); e == nil {
		t.Fatal("accepted wrong tree")
	}
	lockBytes, e := os.ReadFile(lock)
	if e != nil {
		t.Fatal(e)
	}
	badLock := filepath.Join(root, "bad-lock.json")
	if e = os.WriteFile(badLock, bytes.Replace(lockBytes, []byte(`"retain": true`), []byte(`"retain": false`), 1), 0600); e != nil {
		t.Fatal(e)
	}
	if e = call("stage", "--source", source, "--lock", badLock, "--output", filepath.Join(root, "bad-stage")); e == nil {
		t.Fatal("accepted modified exclusion policy")
	}
}
