package main

import (
	"errors"
 "encoding/json"
 "os"
 "path/filepath"
 "strings"
	"testing"
)

func TestSampleRunsBothFreshTestSetsAndStopsOnFailure(t *testing.T) {
	plan := samplePlan("native", "report", "fixture", "root", "sha", "url")
	if len(plan) != 4 || plan[0].Args[0] != "test" || plan[1].Args[0] != "test" {
		t.Fatalf("missing required test sets: %+v", plan)
	}
	for _, c := range plan[:2] {
		found := false
		for _, a := range c.Args {
			if a == "-count=1" {
				found = true
			}
		}
		if !found {
			t.Fatalf("test result reuse permitted: %+v", c)
		}
	}
	if plan[0].Artifact != "native" || plan[1].Artifact != "report" || plan[0].Fixture != "fixture" || plan[1].Fixture != "fixture" {
		t.Fatalf("fixture provenance mismatch: %+v", plan)
	}
	calls := 0
	_, err := runSample(plan, func(c command) error {
		calls++
		if calls == 2 {
			return errors.New("failed real test")
		}
		return nil
	})
	if err == nil || calls != 2 {
		t.Fatalf("failed test did not stop sample: calls=%d err=%v", calls, err)
	}
}

func TestDiagnosticRequiresCompleteIdentityAndOnlyWritesSuccess(t *testing.T) {
 dir:=t.TempDir();out:=filepath.Join(dir,"sample.json")
 cfg:=configuration{Native:"native",Report:"report",Fixture:"fixture",Root:"root",SHA:strings.Repeat("a",40),RunURL:"https://github.com/example/repo/actions/runs/123",Output:out}
 if err:=runDiagnostic(cfg,func(command) error{return errors.New("failed")});err==nil {t.Fatal("failure accepted")}
 if _,err:=os.Stat(out);!os.IsNotExist(err){t.Fatal("failure published successful sample")}
 cfg.RunURL="";if err:=runDiagnostic(cfg,func(command) error{return nil});err==nil{t.Fatal("missing identity accepted")}
 cfg.RunURL="https://github.com/example/repo/actions/runs/123";if err:=runDiagnostic(cfg,func(command) error{return nil});err!=nil{t.Fatal(err)}
 data,err:=os.ReadFile(out);if err!=nil{t.Fatal(err)}
 var summary struct { Commit,RunURL string; Observations []observation };if err=json.Unmarshal(data,&summary);err!=nil{t.Fatal(err)}
 if summary.Commit!=cfg.SHA || summary.RunURL!=cfg.RunURL || len(summary.Observations)!=4{t.Fatalf("incomplete sample: %s",data)}
 if err:=runDiagnostic(cfg,func(command)error{return nil});err==nil{t.Fatal("overwrote existing sample")}
}
