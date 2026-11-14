package main

import (
	"archive/zip"
	"bytes"
	"crypto/sha256"
	"flag"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

type fixtureTransport struct {
	target *url.URL
	base   http.RoundTripper
}

func (f fixtureTransport) RoundTrip(r *http.Request) (*http.Response, error) {
	c := r.Clone(r.Context())
	u := *r.URL
	u.Scheme = f.target.Scheme
	u.Host = f.target.Host
	c.URL = &u
	return f.base.RoundTrip(c)
}

func TestRunDownloadsOfficialRedirectWithoutToken(t *testing.T) {
	var b bytes.Buffer
	z := zip.NewWriter(&b)
	w, _ := z.Create("summary.json")
	_, _ = w.Write([]byte(`{}`))
	if err := z.Close(); err != nil {
		t.Fatal(err)
	}
	data := b.Bytes()
	sum := sha256.Sum256(data)
	digest := fmt.Sprintf("sha256:%x", sum)
	calls := 0
	leaked := false
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls++
		switch r.URL.Path {
		case "/repos/example/repo/actions/artifacts/456":
			fmt.Fprintf(w, `{"id":456,"name":"windows-test-reports-123-1","digest":%q,"size_in_bytes":100,"expired":false,"workflow_run":{"id":123}}`, digest)
		case "/repos/example/repo/actions/artifacts/456/zip":
			http.Redirect(w, r, "https://storage.example.test/content", http.StatusFound)
		case "/content":
			leaked = r.Header.Get("Authorization") != ""
			_, _ = w.Write(data)
		default:
			http.NotFound(w, r)
		}
	}))
	defer server.Close()
	u, _ := url.Parse(server.URL)
	oldTransport := http.DefaultTransport
	http.DefaultTransport = fixtureTransport{u, server.Client().Transport}
	defer func() { http.DefaultTransport = oldTransport }()
	oldFlags, oldArgs := flag.CommandLine, os.Args
	defer func() { flag.CommandLine = oldFlags; os.Args = oldArgs }()
	flag.CommandLine = flag.NewFlagSet("test", flag.ContinueOnError)
	flag.CommandLine.SetOutput(io.Discard)
	dest := filepath.Join(t.TempDir(), "result")
	os.Args = []string{"artifact_download", "--repo", "example/repo", "--run", "123", "--attempt", "1", "--id", "456", "--digest", digest, "--dest", dest}
	t.Setenv("GH_TOKEN", "fixture-token")
	if err := run(); err != nil {
		t.Fatalf("production run rejected redirect: %v", err)
	}
	if leaked || calls != 3 {
		t.Fatalf("calls=%d leaked=%v", calls, leaked)
	}
	if got, err := os.ReadFile(filepath.Join(dest, "summary.json")); err != nil || strings.TrimSpace(string(got)) != "{}" {
		t.Fatalf("output invalid: %v", err)
	}
}

func TestRunRejectsOversizeMetadataBeforeDownload(t *testing.T) {
	digest := "sha256:" + strings.Repeat("a", 64)
	zipCalls := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasSuffix(r.URL.Path, "/zip") {
			zipCalls++
			w.WriteHeader(500)
			return
		}
		fmt.Fprintf(w, `{"id":456,"name":"windows-test-reports-123-1","digest":%q,"size_in_bytes":%d,"expired":false,"workflow_run":{"id":123}}`, digest, maxArchive+1)
	}))
	defer server.Close()
	u, _ := url.Parse(server.URL)
	oldTransport := http.DefaultTransport
	http.DefaultTransport = fixtureTransport{u, server.Client().Transport}
	defer func() { http.DefaultTransport = oldTransport }()
	oldFlags, oldArgs := flag.CommandLine, os.Args
	defer func() { flag.CommandLine = oldFlags; os.Args = oldArgs }()
	flag.CommandLine = flag.NewFlagSet("test", flag.ContinueOnError)
	flag.CommandLine.SetOutput(io.Discard)
	os.Args = []string{"artifact_download", "--repo", "example/repo", "--run", "123", "--attempt", "1", "--id", "456", "--digest", digest, "--dest", filepath.Join(t.TempDir(), "result")}
	t.Setenv("GH_TOKEN", "fixture-token")
	err := run()
	if err == nil || zipCalls != 0 {
		t.Fatalf("expected metadata size rejection before download; calls=%d err=%v", zipCalls, err)
	}
}
