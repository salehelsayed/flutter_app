package main

import (
	"bytes"
	_ "embed"
	"encoding/json"
	"errors"
	"io"
	"regexp"
)

//go:embed app_diagnostics_schema_v1.json
var appDiagnosticSchemaJSON []byte

var errAppDiagnosticInvalid = errors.New("invalid app diagnostic")
var appDiagnosticHash = regexp.MustCompile("^[0-9a-f]{64}$")

type appDiagnosticSchema struct {
	Required, Optional, UUIDFields                    []string
	Source, Platform, Feature, Stage, Outcome, Reason []string
	BooleanValues, IntegerValues, HashValues          []string
	EnumValues                                        map[string][]string
}

var appDiagnosticRules = func() appDiagnosticSchema {
	var rules appDiagnosticSchema
	if json.Unmarshal(appDiagnosticSchemaJSON, &rules) != nil {
		panic("app diagnostic schema")
	}
	return rules
}()

// Reject duplicate keys as well as unknown fields, including nested values.
// Diagnostics are never a general log or arbitrary error-message transport.
func appDiagnosticDecode(raw []byte, target any) error {
	scanner := json.NewDecoder(bytes.NewReader(raw))
	var scan func(int) error
	scan = func(depth int) error {
		if depth > 12 {
			return errAppDiagnosticInvalid
		}
		tok, err := scanner.Token()
		if err != nil {
			return errAppDiagnosticInvalid
		}
		delim, object := tok.(json.Delim)
		if !object {
			return nil
		}
		switch delim {
		case '{':
			seen := map[string]bool{}
			for scanner.More() {
				k, err := scanner.Token()
				key, ok := k.(string)
				if err != nil || !ok || seen[key] {
					return errAppDiagnosticInvalid
				}
				seen[key] = true
				if scan(depth+1) != nil {
					return errAppDiagnosticInvalid
				}
			}
		case '[':
			for scanner.More() {
				if scan(depth+1) != nil {
					return errAppDiagnosticInvalid
				}
			}
		default:
			return errAppDiagnosticInvalid
		}
		_, err = scanner.Token()
		return err
	}
	if scan(0) != nil {
		return errAppDiagnosticInvalid
	}
	if _, err := scanner.Token(); err != io.EOF {
		return errAppDiagnosticInvalid
	}
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.UseNumber()
	dec.DisallowUnknownFields()
	if dec.Decode(target) != nil {
		return errAppDiagnosticInvalid
	}
	if dec.Decode(new(any)) != io.EOF {
		return errAppDiagnosticInvalid
	}
	return nil
}

func validateAppDiagnosticEvent(raw []byte, server bool) (map[string]any, error) {
	if len(raw) > 4096 {
		return nil, errAppDiagnosticInvalid
	}
	var e map[string]any
	if appDiagnosticDecode(raw, &e) != nil {
		return nil, errAppDiagnosticInvalid
	}
	for _, k := range appDiagnosticRules.Required {
		if _, ok := e[k]; !ok {
			return nil, errAppDiagnosticInvalid
		}
	}
	for k := range e {
		if !diagnosticContains(appDiagnosticRules.Required, k) && !diagnosticContains(appDiagnosticRules.Optional, k) {
			return nil, errAppDiagnosticInvalid
		}
	}
	if e["schemaVersion"] != json.Number("1") {
		return nil, errAppDiagnosticInvalid
	}
	for _, k := range appDiagnosticRules.UUIDFields {
		if v, present := e[k]; present {
			s, ok := v.(string)
			if !ok || !diagnosticUUID.MatchString(s) {
				return nil, errAppDiagnosticInvalid
			}
		}
	}
	for k, allowed := range map[string][]string{
		"source": appDiagnosticRules.Source, "platform": appDiagnosticRules.Platform,
		"feature": appDiagnosticRules.Feature, "stage": appDiagnosticRules.Stage,
		"outcome": appDiagnosticRules.Outcome, "reason": appDiagnosticRules.Reason,
	} {
		s, ok := e[k].(string)
		if !ok || !diagnosticContains(allowed, s) {
			return nil, errAppDiagnosticInvalid
		}
	}
	if !server && e["source"] == "relay" {
		return nil, errAppDiagnosticInvalid
	}
	validNumber := func(v any) bool {
		n, ok := v.(json.Number)
		if !ok {
			return false
		}
		i, err := n.Int64()
		return err == nil && i >= 0 && i <= 9007199254740991
	}
	for _, k := range []string{"sequence", "occurredAtMs", "elapsedMs"} {
		if !validNumber(e[k]) {
			return nil, errAppDiagnosticInvalid
		}
	}
	build, ok := e["build"].(string)
	if !ok || !diagnosticBuild.MatchString(build) {
		return nil, errAppDiagnosticInvalid
	}
	values, ok := e["values"].(map[string]any)
	if !ok || len(values) > 16 {
		return nil, errAppDiagnosticInvalid
	}
	for k, v := range values {
		switch {
		case diagnosticContains(appDiagnosticRules.BooleanValues, k):
			if _, ok := v.(bool); !ok {
				return nil, errAppDiagnosticInvalid
			}
		case diagnosticContains(appDiagnosticRules.IntegerValues, k):
			if !validNumber(v) {
				return nil, errAppDiagnosticInvalid
			}
		case diagnosticContains(appDiagnosticRules.HashValues, k):
			s, ok := v.(string)
			if !ok || !appDiagnosticHash.MatchString(s) {
				return nil, errAppDiagnosticInvalid
			}
		default:
			allowed, ok := appDiagnosticRules.EnumValues[k]
			s, isString := v.(string)
			if !ok || !isString || !diagnosticContains(allowed, s) {
				return nil, errAppDiagnosticInvalid
			}
		}
	}
	return e, nil
}
