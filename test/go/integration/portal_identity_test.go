package integration_test

import (
	"os"
	"strings"
	"testing"
	"time"
	a "windows_setup/script/test/acceptance"
)

func TestPortalOverviewIdentity(t *testing.T) {
	original := files(t, os.Getenv("WINDOWS_SETUP_ARTIFACT_DIR"))
	r := decode(t, original)
	p := portal(t, synthetic(t, original, true, "Branch"))
	stamp, e := time.Parse(time.RFC3339Nano, r.MeasuredAt)
	if e != nil {
		t.Fatal(e)
	}
	identity := "提交 <code>" + r.Commit[:7] + "</code> 檢查時間：" + stamp.UTC().Format("2006-01-02 15:04:05") + " UTC"
	p["index.html"] = append(p["index.html"], []byte(identity)...)
	if _, e := a.ValidatePortal(reader(p), readme(), r.Commit, r.RunUrl, base); e != nil {
		t.Fatal(e)
	}
	for _, kind := range []string{"stale_sha", "stale_time", "hidden_identity"} {
		t.Run(kind, func(t *testing.T) {
			m := copyFiles(p)
			switch kind {
			case "stale_sha":
				m["index.html"] = []byte(strings.ReplaceAll(string(m["index.html"]), r.Commit[:7], "0000000"))
			case "stale_time":
				m["index.html"] = []byte(strings.ReplaceAll(string(m["index.html"]), stamp.UTC().Format("2006-01-02 15:04:05"), "2000-01-01 00:00:00"))
			case "hidden_identity":
				m["index.html"] = []byte(strings.ReplaceAll(string(m["index.html"]), identity, "<details><summary>old</summary>"+identity+"</details>"))
			}
			if _, e := a.ValidatePortal(reader(m), readme(), r.Commit, r.RunUrl, base); e == nil {
				t.Fatal("stale or invisible homepage identity accepted")
			}
		})
	}
}
