package main

import (
	"context"
	"encoding/base64"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func fixtureToken() string {
	return "e30." + base64.RawURLEncoding.EncodeToString([]byte(`{"scp":"Actions.Results:fixture-run:fixture-job"}`)) + ".sig"
}
func TestVisibilityPreflight(t *testing.T) {
	for _, tc := range []struct {
		name, restMode, runtimeMode string
		wantOK                      bool
		wantRuntime                 int
	}{
		{"visible", "valid", "valid", true, 1},
		{"runtime eventually visible", "valid", "later", true, 2},
		{"runtime missing deadline", "valid", "missing", false, 0},
		{"runtime duplicate", "valid", "duplicate", false, 1},
		{"runtime wrong id", "valid", "wrong", false, 1},
		{"rest duplicate", "duplicate", "valid", false, 0},
		{"rest expired", "expired", "valid", false, 0},
		{"rest wrong id", "wrong", "valid", false, 0},
		{"rest wrong digest", "digest", "valid", false, 0},
		{"rest unauthorized", "unauthorized", "valid", false, 0},
	} {
		t.Run(tc.name, func(t *testing.T) {
			var runtimeCalls, restCalls int32
			digest := "sha256:" + strings.Repeat("a", 64)
			name := "github-pages-123-2"
			rest := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				atomic.AddInt32(&restCalls, 1)
				if r.Header.Get("Authorization") != "Bearer rest-fixture" {
					t.Error("wrong REST auth")
				}
				if tc.restMode == "unauthorized" {
					w.WriteHeader(401)
					return
				}
				id, expired, d := 456, false, digest
				if tc.restMode == "wrong" {
					id = 457
				}
				if tc.restMode == "expired" {
					expired = true
				}
				if tc.restMode == "digest" {
					d = "bad"
				}
				row := fmt.Sprintf(`{"id":%d,"name":%q,"digest":%q,"size_in_bytes":100,"expired":%t,"workflow_run":{"id":123}}`, id, name, d, expired)
				rows := row
				if tc.restMode == "duplicate" {
					rows += "," + row
				}
				fmt.Fprintf(w, `{"total_count":%d,"artifacts":[%s]}`, 1, rows)
			}))
			defer rest.Close()
			runtime := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				n := atomic.AddInt32(&runtimeCalls, 1)
				if r.URL.Path != "/twirp/github.actions.results.api.v1.ArtifactService/ListArtifacts" {
					t.Error("wrong runtime path")
				}
				if r.Header.Get("Authorization") != "Bearer "+fixtureToken() {
					t.Error("wrong runtime auth")
				}
				row := fmt.Sprintf(`{"database_id":"456","name":%q,"size":"100"}`, name)
				if tc.runtimeMode == "wrong" {
					row = fmt.Sprintf(`{"database_id":"457","name":%q,"size":"100"}`, name)
				}
				if tc.runtimeMode == "missing" || (tc.runtimeMode == "later" && n == 1) {
					row = ""
				}
				if tc.runtimeMode == "duplicate" {
					row += "," + row
				}
				fmt.Fprintf(w, `{"artifacts":[%s]}`, row)
			}))
			defer runtime.Close()
			ctx, cancel := context.WithTimeout(context.Background(), 80*time.Millisecond)
			defer cancel()
			o := options{client: rest.Client(), restURL: rest.URL, runtimeURL: runtime.URL, token: "rest-fixture", runtimeToken: fixtureToken(), repo: "example/repo", runID: "123", artifactID: "456", name: name, interval: time.Millisecond}
			err := observe(ctx, o)
			calls := int(atomic.LoadInt32(&runtimeCalls))
			if (err == nil) != tc.wantOK {
				t.Errorf("success=%t err=%v", tc.wantOK, err)
			}
			if tc.wantRuntime > 0 && calls != tc.wantRuntime {
				t.Errorf("runtime calls=%d want=%d", calls, tc.wantRuntime)
			}
			if tc.wantRuntime == 0 && tc.runtimeMode != "missing" && calls != 0 {
				t.Errorf("unexpected runtime calls=%d", calls)
			}
			if tc.restMode == "unauthorized" && atomic.LoadInt32(&restCalls) != 1 {
				t.Error("401 retried")
			}
		})
	}
}
