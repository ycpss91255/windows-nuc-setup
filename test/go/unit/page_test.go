package unit_test

import (
 "strings"
 "testing"
 "windows_setup/script/test/acceptance"
)

func TestHTMLVisibility(t *testing.T) {
 p,err:=acceptance.ParsePage([]byte(`<meta charset=utf-8><h1>結果 &amp; next</h1><a href="main/index.html">報告</a><details><summary>技術</summary><p>Unknown hidden</p><a href="secret">hidden</a><details open><summary>nested hidden</summary></details></details><details open><summary>展開</summary><p>visible detail</p></details><script>Unknown script</script><style>Unknown style</style>`))
 if err!=nil { t.Fatal(err) }
 if !strings.Contains(p.Visible,"結果 & next") || !strings.Contains(p.Visible,"visible detail") || strings.Contains(p.Visible,"Unknown") || strings.Contains(p.Visible,"nested hidden") { t.Fatalf("HTML visibility contract failed: %q",p.Visible) }
 if len(p.Links)!=2 || len(p.VisibleLinks)!=1 || p.VisibleLinks[0]!="main/index.html" { t.Fatalf("link visibility differs: %+v",p) }
}

func TestHTMLBooleanOpenAndRawText(t *testing.T) {
 p,err:=acceptance.ParsePage([]byte(`<details open><summary>shown</summary>Unknown visible</details><script>if(a < b) { x="<a href='bad'>" }</script><br><a href='ok?x=1&amp;y=2'>link</a>`))
 if err!=nil || !strings.Contains(p.Visible,"Unknown visible") || len(p.Links)!=1 || p.Links[0]!="ok?x=1&y=2" { t.Fatalf("HTML5 parsing failed: %+v %v",p,err) }
}
