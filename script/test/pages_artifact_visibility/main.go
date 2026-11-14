package main

import (
	"context"
	"errors"
	"net/http"
	"time"
)

type options struct {
	client                                                                  *http.Client
	restURL, runtimeURL, token, runtimeToken, repo, runID, artifactID, name string
	interval                                                                time.Duration
}

func observe(ctx context.Context, o options) error {
	return errors.New("visibility preflight not implemented")
}
