package actions_timing

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"strings"
)

type Expected struct {
	Repository           string
	RunID                int64
	Attempt              int
	HeadSHA, CheckoutSHA string
}

func (j *Job) UnmarshalJSON(data []byte) error {
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(data, &fields); err != nil {
		return err
	}
	steps, ok := fields["steps"]
	if !ok || bytes.Equal(bytes.TrimSpace(steps), []byte("null")) {
		return fmt.Errorf("missing job steps inventory")
	}
	for name, raw := range fields {
		if strings.EqualFold(name, "head_sha") && bytes.Equal(bytes.TrimSpace(raw), []byte("null")) {
			return fmt.Errorf("job head cannot be null when supplied")
		}
	}
	type plainJob Job
	var value plainJob
	if err := json.Unmarshal(data, &value); err != nil {
		return err
	}
	*j = Job(value)
	return nil
}

func (p *Page) UnmarshalJSON(data []byte) error {
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(data, &fields); err != nil {
		return err
	}
	for _, name := range []string{"page_number", "per_page", "total_count", "jobs"} {
		raw, ok := fields[name]
		if !ok || bytes.Equal(bytes.TrimSpace(raw), []byte("null")) {
			return fmt.Errorf("missing page field %s", name)
		}
	}
	type plainPage Page
	var value plainPage
	if err := json.Unmarshal(data, &value); err != nil {
		return err
	}
	*p = Page(value)
	return nil
}

// Decode validates shape and internal consistency of caller-supplied data;
// independently obtained Expected values do not authenticate the data origin.
func Decode(data []byte, expected Expected) (Output, error) {
	if len(data) > 16*1024*1024 {
		return Output{}, fmt.Errorf("observation input too large")
	}
	d := json.NewDecoder(bytes.NewReader(data))
	var value func(int) error
	value = func(depth int) error {
		if depth > 100 {
			return fmt.Errorf("JSON nesting too deep")
		}
		token, err := d.Token()
		if err != nil {
			return err
		}
		delim, ok := token.(json.Delim)
		if !ok {
			return nil
		}
		switch delim {
		case '{':
			seen := map[string]bool{}
			for d.More() {
				key, e := d.Token()
				if e != nil {
					return e
				}
				name, ok := key.(string)
				fold := strings.ToLower(name)
				if !ok || seen[fold] {
					return fmt.Errorf("duplicate JSON field")
				}
				seen[fold] = true
				if e = value(depth + 1); e != nil {
					return e
				}
			}
			_, err = d.Token()
			return err
		case '[':
			for d.More() {
				if err = value(depth + 1); err != nil {
					return err
				}
			}
			_, err = d.Token()
			return err
		default:
			return fmt.Errorf("invalid JSON delimiter")
		}
	}
	if err := value(0); err != nil {
		return Output{}, err
	}
	if _, err := d.Token(); err != io.EOF {
		return Output{}, fmt.Errorf("trailing JSON content")
	}
	var wire struct {
		Run   Run    `json:"run"`
		Pages []Page `json:"pages"`
	}
	if err := json.Unmarshal(data, &wire); err != nil {
		return Output{}, err
	}
	return Analyze(Input{Repository: expected.Repository, RunID: expected.RunID, Attempt: expected.Attempt, HeadSHA: expected.HeadSHA, CheckoutSHA: expected.CheckoutSHA, Run: wire.Run, Pages: wire.Pages})
}
