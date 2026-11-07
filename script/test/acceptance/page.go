// Package acceptance checks published maintenance evidence, never Windows settings.
package acceptance

type Page struct { Links, VisibleLinks []string; Visible string }

func ParsePage(data []byte) (Page, error) { return Page{}, nil }
