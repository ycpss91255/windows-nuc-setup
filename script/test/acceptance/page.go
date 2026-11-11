// Package acceptance checks published maintenance evidence, never Windows settings.
package acceptance

import (
	"bytes"
	"golang.org/x/net/html"
	"strings"
)

type Page struct {
	Links, VisibleLinks []string
	Visible             string
}

func ParsePage(data []byte) (Page, error) { return parsePage(data, false) }

// parsePage optionally exposes the named user-expandable coverage detail, while
// keeping unrelated closed details and hidden content excluded.
func parsePage(data []byte, coverageDetails bool) (Page, error) {
	root, err := html.Parse(bytes.NewReader(data))
	if err != nil {
		return Page{}, err
	}
	p := Page{}
	var text []string
	var walk func(*html.Node, bool)
	walk = func(n *html.Node, visible bool) {
		if n.Type == html.ElementNode && (n.Data == "script" || n.Data == "style") {
			return
		}
		closed := false
		if n.Type == html.ElementNode {
			for _, attr := range n.Attr {
				if attr.Key == "hidden" || (attr.Key == "aria-hidden" && attr.Val == "true") {
					visible = false
				}
				if attr.Key == "style" {
					style := strings.ReplaceAll(strings.ToLower(attr.Val), " ", "")
					if strings.Contains(style, "display:none") || strings.Contains(style, "visibility:hidden") {
						visible = false
					}
				}
			}
			if n.Data == "details" {
				closed = true
				for _, a := range n.Attr {
					if a.Key == "open" {
						closed = false
					}
				}
			}
			if coverageDetails && closed {
				for child := n.FirstChild; child != nil; child = child.NextSibling {
					if child.Type == html.ElementNode && child.Data == "summary" {
						if child.FirstChild != nil && child.FirstChild.Type == html.TextNode && strings.TrimSpace(child.FirstChild.Data) == "分項量測明細" {
							closed = false
						}
						break
					}
				}
			}
			if n.Data == "a" {
				for _, a := range n.Attr {
					if a.Key == "href" && a.Val != "" {
						p.Links = append(p.Links, a.Val)
						if visible {
							p.VisibleLinks = append(p.VisibleLinks, a.Val)
						}
					}
				}
			}
		}
		if n.Type == html.TextNode && visible {
			text = append(text, n.Data)
		}
		summarySeen := false
		for c := n.FirstChild; c != nil; c = c.NextSibling {
			childVisible := visible
			if closed {
				isSummary := c.Type == html.ElementNode && c.Data == "summary" && !summarySeen
				childVisible = visible && isSummary
				if isSummary {
					summarySeen = true
				}
			}
			walk(c, childVisible)
		}
	}
	walk(root, true)
	p.Visible = strings.Join(text, " ")
	return p, nil
}
