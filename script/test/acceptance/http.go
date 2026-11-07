package acceptance

import (
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

func HTTPReader(base string, client *http.Client) (Reader, error) {
	baseURL, e := url.Parse(base)
	if e != nil || baseURL.Scheme != "https" || baseURL.Host == "" || baseURL.User != nil || baseURL.RawQuery != "" || baseURL.Fragment != "" {
		return nil, fmt.Errorf("僅允許有效的 HTTPS 公開驗收來源")
	}
	baseURL.Path = strings.TrimRight(baseURL.Path, "/") + "/"
	allowed := func(u *url.URL) bool {
		if u.Scheme != "https" || !strings.EqualFold(u.Host, baseURL.Host) || u.User != nil || !strings.HasPrefix(u.Path, baseURL.Path) {
			return false
		}
		for _, part := range strings.Split(u.Path, "/") {
			if part == ".." || part == "." || strings.Contains(part, "\\") {
				return false
			}
		}
		return true
	}
	c := http.Client{Timeout: 20 * time.Second}
	if client != nil {
		c = *client
		if c.Timeout == 0 {
			c.Timeout = 20 * time.Second
		}
	}
	c.CheckRedirect = func(req *http.Request, via []*http.Request) error {
		if len(via) >= 10 || !allowed(req.URL) {
			return fmt.Errorf("拒絕離開本站的重導向")
		}
		return nil
	}
	return func(path string) ([]byte, error) {
		ref, e := url.Parse(path)
		if e != nil {
			return nil, e
		}
		u := baseURL.ResolveReference(ref)
		if !allowed(u) {
			return nil, fmt.Errorf("拒絕離開本站的產物路徑")
		}
		request, e := http.NewRequest("GET", u.String(), nil)
		if e != nil {
			return nil, e
		}
		request.Header.Set("User-Agent", "windows-setup-requirements-gate")
		request.Header.Set("Cache-Control", "no-cache")
		response, e := c.Do(request)
		if e != nil {
			return nil, e
		}
		defer response.Body.Close()
		if response.StatusCode != 200 || !allowed(response.Request.URL) {
			return nil, fmt.Errorf("公開網址回應或來源不符：%d", response.StatusCode)
		}
		return io.ReadAll(response.Body)
	}, nil
}
