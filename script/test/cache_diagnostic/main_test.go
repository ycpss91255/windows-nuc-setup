package main

import (
 "errors"
 "testing"
)

func TestSampleRunsBothFreshTestSetsAndStopsOnFailure(t *testing.T) {
 plan:=samplePlan("native", "report", "fixture", "root", "sha", "url")
 if len(plan)!=4 || plan[0].Args[0]!="test" || plan[1].Args[0]!="test" {t.Fatalf("missing required test sets: %+v",plan)}
 for _,c:=range plan[:2] {found:=false;for _,a:=range c.Args {if a=="-count=1" {found=true}};if !found {t.Fatalf("test result reuse permitted: %+v",c)}}
 if plan[0].Artifact!="native" || plan[1].Artifact!="report" || plan[0].Fixture!="fixture" || plan[1].Fixture!="fixture" {t.Fatalf("fixture provenance mismatch: %+v",plan)}
 calls:=0
 _,err:=runSample(plan,func(c command) error {calls++;if calls==2{return errors.New("failed real test")};return nil})
 if err==nil || calls!=2 {t.Fatalf("failed test did not stop sample: calls=%d err=%v",calls,err)}
}
