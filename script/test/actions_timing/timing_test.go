package actions_timing

import (
 "strings"
 "testing"
)
func ptr(s string)*string{return &s}
func fixture() Input {
 sha:=strings.Repeat("a",40)
 return Input{Repository:"example/repo",RunID:123,Attempt:2,HeadSHA:sha,CheckoutSHA:strings.Repeat("b",40),Run:Run{ID:123,RunAttempt:2,HeadSHA:sha,Repository:Repository{FullName:"example/repo"}},Pages:[]Page{{PageNumber:1,PerPage:2,TotalCount:2,Jobs:[]Job{
  {ID:10,RunID:123,RunAttempt:2,Name:"build",Status:"completed",Conclusion:"success",CreatedAt:ptr("2026-11-14T00:00:00Z"),StartedAt:ptr("2026-11-14T00:00:02Z"),CompletedAt:ptr("2026-11-14T00:00:08Z"),Steps:[]Step{{Number:1,Name:"test",Status:"completed",Conclusion:"success",StartedAt:ptr("2026-11-14T00:00:03Z"),CompletedAt:ptr("2026-11-14T00:00:07Z")}}},
  {ID:11,RunID:123,RunAttempt:2,Name:"skipped",Status:"completed",Conclusion:"skipped",StartedAt:ptr("2026-11-14T00:00:04Z"),CompletedAt:ptr("2026-11-14T00:00:03Z")},
 }}}}
}
func TestSameRunTimingPreservesUnknownAndSkipped(t *testing.T){
 out,err:=Analyze(fixture());if err!=nil{t.Fatal(err)}
 if out.CheckoutSHA==out.HeadSHA || out.CheckoutVerified {t.Fatalf("PR checkout evidence overstated: %+v",out)}
 if *out.Jobs[0].PendingMilliseconds!=2000 || *out.Jobs[0].ElapsedMilliseconds!=6000 || *out.Jobs[0].Steps[0].ElapsedMilliseconds!=4000 {t.Fatalf("incorrect timing: %+v",out.Jobs[0])}
 if out.Jobs[1].ElapsedMilliseconds!=nil || out.Jobs[1].PendingMilliseconds!=nil {t.Fatal("skipped timestamps treated as execution")}
 x:=fixture();x.Pages[0].Jobs[0].CreatedAt=nil;x.Pages[0].Jobs[0].Steps[0].CompletedAt=nil
 out,err=Analyze(x);if err!=nil{t.Fatal(err)};if out.Jobs[0].PendingMilliseconds!=nil || out.Jobs[0].Steps[0].ElapsedMilliseconds!=nil {t.Fatal("missing timestamp inferred")}
}
func TestRejectsMixedIdentityIncompletePagesAndBadTime(t *testing.T){
 cases:=map[string]func(*Input){
  "repository":func(x *Input){x.Run.Repository.FullName="other/repo"},"sha":func(x *Input){x.Run.HeadSHA=strings.Repeat("c",40)},
  "run":func(x *Input){x.Pages[0].Jobs[0].RunID=999},"attempt":func(x *Input){x.Pages[0].Jobs[0].RunAttempt=1},
  "incomplete":func(x *Input){x.Pages[0].TotalCount=3},"duplicate_job":func(x *Input){x.Pages[0].Jobs[1].ID=10},
  "duplicate_step":func(x *Input){x.Pages[0].Jobs[0].Steps=append(x.Pages[0].Jobs[0].Steps,x.Pages[0].Jobs[0].Steps[0])},
  "bad_utc":func(x *Input){x.Pages[0].Jobs[0].StartedAt=ptr("2026-11-14T08:00:02+08:00")},
  "backwards":func(x *Input){x.Pages[0].Jobs[0].CompletedAt=ptr("2026-11-13T23:59:59Z")},
 }
 for name,change:=range cases {t.Run(name,func(t *testing.T){x:=fixture();change(&x);if _,err:=Analyze(x);err==nil{t.Fatal("accepted invalid observation")}})}
}
