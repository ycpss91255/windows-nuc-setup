package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"strings"
)

var oid = regexp.MustCompile(`^[0-9a-f]{40}$`)

func check(repo, eventPath, checkout, runSHA, base, head string) error {
	for _, v := range []string{checkout, runSHA, base, head} {
		if !oid.MatchString(v) {
			return errors.New("missing or invalid commit identity")
		}
	}
	data, err := os.ReadFile(eventPath)
	if err != nil {
		return err
	}
	var event struct {
		PullRequest *struct {
			Base struct {
				SHA string `json:"sha"`
			} `json:"base"`
			Head struct {
				SHA string `json:"sha"`
			} `json:"head"`
		} `json:"pull_request"`
	}
	if err = json.Unmarshal(data, &event); err != nil {
		return err
	}
	if event.PullRequest == nil || event.PullRequest.Base.SHA != base || event.PullRequest.Head.SHA != head {
		return errors.New("event base/head mismatch")
	}
	git := func(args ...string) (string, error) {
		c := exec.Command("git", args...)
		c.Dir = repo
		b, e := c.Output()
		return strings.TrimSpace(string(b)), e
	}
	if checkout != runSHA {
		return errors.New("checkout differs from run SHA")
	}
	actual, err := git("rev-parse", "--verify", "HEAD^{commit}")
	if err != nil || actual != checkout {
		return errors.New("repository HEAD differs from actual checkout")
	}
	parents, err := git("show", "-s", "--format=%P", checkout)
	if err != nil || parents != base+" "+head {
		return errors.New("merge parents differ from event base/head")
	}
	tree, err := git("rev-parse", checkout+"^{tree}")
	if err != nil {
		return err
	}
	expected, err := git("merge-tree", "--write-tree", base, head)
	if err != nil || expected != tree {
		return errors.New("merge tree differs from expected base/head")
	}
	return nil
}

type prIdentity struct {
	Number int    `json:"number"`
	State  string `json:"state"`
	Base   struct {
		Ref  string `json:"ref"`
		SHA  string `json:"sha"`
		Repo struct {
			FullName string `json:"full_name"`
		} `json:"repo"`
	} `json:"base"`
	Head struct {
		SHA string `json:"sha"`
	} `json:"head"`
}

func authorityCheck(eventPath, authorityPath string) error {
	var ev struct {
		Number      int         `json:"number"`
		PullRequest *prIdentity `json:"pull_request"`
	}
	var live prIdentity
	e, err := os.ReadFile(eventPath)
	if err != nil {
		return err
	}
	if err = json.Unmarshal(e, &ev); err != nil {
		return err
	}
	a, err := os.ReadFile(authorityPath)
	if err != nil {
		return err
	}
	if err = json.Unmarshal(a, &live); err != nil {
		return err
	}
	mainSHA := os.Getenv("PREFLIGHT_MAIN_SHA")
	if !oid.MatchString(mainSHA) || ev.PullRequest == nil || ev.PullRequest.Base.SHA != mainSHA || ev.Number <= 0 || ev.Number != ev.PullRequest.Number || ev.Number != live.Number || live.State != "open" || ev.PullRequest.Base.Ref != "main" || ev.PullRequest.Base.Repo.FullName == "" || ev.PullRequest.Base.Ref != live.Base.Ref || ev.PullRequest.Base.Repo.FullName != live.Base.Repo.FullName || !oid.MatchString(live.Base.SHA) || ev.PullRequest.Base.SHA != live.Base.SHA || !oid.MatchString(live.Head.SHA) || ev.PullRequest.Head.SHA != live.Head.SHA {
		return errors.New("live PR identity differs from event")
	}
	return nil
}
func run(args []string) error {
	f := flag.NewFlagSet("source-preflight", flag.ContinueOnError)
	authority := f.String("authority", "", "live PR API response")
	repo := f.String("repo", ".", "repository")
	event := f.String("event", "", "event JSON")
	checkout := f.String("checkout", "", "actual commit")
	runSHA := f.String("run-sha", "", "event run SHA")
	base := f.String("base", "", "event base")
	head := f.String("head", "", "event head")
	if err := f.Parse(args); err != nil {
		return err
	}
	if f.NArg() != 0 {
		return errors.New("unexpected arguments")
	}
	if err := authorityCheck(*event, *authority); err != nil {
		return err
	}
	return check(*repo, *event, *checkout, *runSHA, *base, *head)
}
func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "source preflight:", err)
		os.Exit(1)
	}
	fmt.Println("source preflight: verified actual checkout")
}
