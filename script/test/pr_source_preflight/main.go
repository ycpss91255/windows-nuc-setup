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
func main() {
	repo := flag.String("repo", ".", "repository containing actual checkout")
	event := flag.String("event", "", "event JSON")
	checkout := flag.String("checkout", "", "actual checked out commit")
	run := flag.String("run-sha", "", "event run SHA")
	base := flag.String("base", "", "expected base commit")
	head := flag.String("head", "", "expected head commit")
	flag.Parse()
	if flag.NArg() != 0 {
		fmt.Fprintln(os.Stderr, "unexpected arguments")
		os.Exit(1)
	}
	if err := check(*repo, *event, *checkout, *run, *base, *head); err != nil {
		fmt.Fprintln(os.Stderr, "source preflight:", err)
		os.Exit(1)
	}
	fmt.Println("source preflight: verified actual checkout")
}
