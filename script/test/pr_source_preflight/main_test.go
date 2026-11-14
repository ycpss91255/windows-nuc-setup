package main

import (
 "encoding/json"
 "os"
 "os/exec"
 "path/filepath"
 "strings"
 "testing"
)

func TestActualCheckoutSource(t *testing.T) {
 d:=t.TempDir()
 git:=func(args ...string) string { t.Helper(); c:=exec.Command("git",args...); c.Dir=d; c.Env=append(os.Environ(),"GIT_AUTHOR_NAME=Fixture","GIT_AUTHOR_EMAIL=fixture@example.invalid","GIT_COMMITTER_NAME=Fixture","GIT_COMMITTER_EMAIL=fixture@example.invalid"); b,e:=c.CombinedOutput(); if e!=nil {t.Fatalf("git %v: %s: %v",args,b,e)}; return strings.TrimSpace(string(b)) }
 git("init","-q"); git("config","user.name","Fixture"); git("config","user.email","fixture@example.invalid")
 os.WriteFile(filepath.Join(d,"file"),[]byte("base"),0600); git("add","file"); git("commit","-qm","base"); base:=git("rev-parse","HEAD")
 os.WriteFile(filepath.Join(d,"file"),[]byte("head"),0600); git("commit","-qam","head"); head:=git("rev-parse","HEAD"); tree:=git("rev-parse",head+"^{tree}")
 commit:=func(message string, parents ...string) string { args:=[]string{"commit-tree",tree}; for _,p:=range parents {args=append(args,"-p",p)}; args=append(args,"-m",message); return git(args...) }
 actual:=commit("actual",base,head); regenerated:=commit("regenerated",base,head); wrong:=commit("wrong",head,base)
 event:=filepath.Join(d,"event.json")
 writeEvent:=func(b,h string) { t.Helper(); data,_:=json.Marshal(map[string]any{"pull_request":map[string]any{"base":map[string]string{"sha":b},"head":map[string]string{"sha":h}}}); if err:=os.WriteFile(event,data,0600);err!=nil {t.Fatal(err)} }
 cases:=[]struct{name,checkout,eventBase,eventHead,expectedBase,expectedHead string; ok bool}{
  {"actual checkout",actual,base,head,base,head,true},
  {"regenerated is not actual",regenerated,base,head,base,head,false},
  {"changed base",actual,head,head,base,head,false},
  {"changed head",actual,base,base,base,head,false},
  {"parents reversed",wrong,base,head,base,head,false},
  {"missing metadata",actual,"",head,base,head,false},
 }
 for _,tc:=range cases {t.Run(tc.name,func(t *testing.T){ writeEvent(tc.eventBase,tc.eventHead); c:=exec.Command("go","run",".","-repo",d,"-event",event,"-checkout",tc.checkout,"-run-sha",actual,"-base",tc.expectedBase,"-head",tc.expectedHead); b,e:=c.CombinedOutput(); if (e==nil)!=tc.ok {t.Fatalf("want success=%v, got %v: %s",tc.ok,e,b)} })}
}
