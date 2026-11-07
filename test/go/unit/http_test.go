package unit_test

import (
	"net/http"
	"net/http/httptest"
	"testing"
	a "windows_setup/script/test/acceptance"
)

func TestHTTPSOriginBoundary(t *testing.T) {
	outsideHits := 0
	outside := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { outsideHits++; w.Write([]byte("outside")) }))
	defer outside.Close()
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/site/redirect" {
			http.Redirect(w, r, outside.URL+"/evil", http.StatusFound)
			return
		}
		w.Write([]byte("same-origin"))
	}))
	defer server.Close()
	read, e := a.HTTPReader(server.URL+"/site/", server.Client())
	if e != nil {
		t.Fatal(e)
	}
	if b, e := read("index.html"); e != nil || string(b) != "same-origin" {
		t.Fatalf("same-origin HTTPS rejected: %s %v", b, e)
	}
	for _, path := range []string{"../outside", outside.URL + "/evil", "redirect", "%2e%2e/outside"} {
		if _, e := read(path); e == nil {
			t.Fatalf("unsafe path accepted: %s", path)
		}
	}
	if outsideHits != 0 {
		t.Fatalf("off-origin redirect fetched %d times", outsideHits)
	}
	if _, e := a.HTTPReader("http://example.com/", server.Client()); e == nil {
		t.Fatal("HTTP accepted")
	}
}
