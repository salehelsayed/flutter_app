package main

import (
	"bytes"
	_ "embed"
	"encoding/json"
	"errors"
	"io"
	"regexp"
	"strings"
)

//go:embed call_diagnostics_schema_v1.json
var callDiagnosticSchemaJSON []byte
var errCallDiagnosticInvalid = errors.New("invalid diagnostic record")
var diagnosticUUID = regexp.MustCompile(`^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$`)
var diagnosticBuild = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9.+_-]{0,79}$`)

type callDiagnosticSchema struct {
	Required      []string            `json:"required"`
	Optional      []string            `json:"optional"`
	UUIDFields    []string            `json:"uuidFields"`
	Source        []string            `json:"source"`
	Role          []string            `json:"role"`
	Stage         []string            `json:"stage"`
	Action        []string            `json:"action"`
	Outcome       []string            `json:"outcome"`
	Reason        []string            `json:"reason"`
	BooleanValues []string            `json:"booleanValues"`
	IntegerValues []string            `json:"integerValues"`
	EnumValues    map[string][]string `json:"enumValues"`
}

var callDiagnosticRules = func() callDiagnosticSchema {
	var s callDiagnosticSchema
	if json.Unmarshal(callDiagnosticSchemaJSON, &s) != nil {
		panic("diagnostic schema")
	}
	return s
}()

type callDiagnosticContext struct {
	consentEpoch      int64
	TraceID           string `json:"traceId,omitempty"`
	RequestID         string `json:"requestId,omitempty"`
	OperationID       string `json:"operationId,omitempty"`
	ParentOperationID string `json:"parentOperationId,omitempty"`
	Reason            string `json:"cause,omitempty"`
}

func (d *callDiagnosticContext) valid() bool {
	if d == nil {
		return false
	}
	for _, v := range []string{d.TraceID, d.RequestID, d.OperationID, d.ParentOperationID} {
		if v != "" && !diagnosticUUID.MatchString(v) {
			return false
		}
	}
	return (d.TraceID != "" || d.OperationID != "") && (d.Reason == "" || diagnosticContains(callDiagnosticRules.Reason, d.Reason))
}
func diagnosticContains(values []string, v string) bool {
	for _, item := range values {
		if item == v {
			return true
		}
	}
	return false
}
func diagnosticDecode(raw []byte, target any) error {
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.DisallowUnknownFields()
	dec.UseNumber()
	if err := dec.Decode(target); err != nil {
		return errCallDiagnosticInvalid
	}
	if err := dec.Decode(new(any)); err != io.EOF {
		return errCallDiagnosticInvalid
	}
	return nil
}

// Records are closed-schema data, never arbitrary logs. Unknown fields and values
// are rejected before persistence, including server-only sources from clients.
func validateCallDiagnosticEvent(raw []byte, server bool) (map[string]any, error) {
	if len(raw) > 4096 {
		return nil, errCallDiagnosticInvalid
	}
	var event map[string]any
	if diagnosticDecode(raw, &event) != nil {
		return nil, errCallDiagnosticInvalid
	}
	for _, key := range callDiagnosticRules.Required {
		if _, ok := event[key]; !ok {
			return nil, errCallDiagnosticInvalid
		}
	}
	for key := range event {
		if !diagnosticContains(callDiagnosticRules.Required, key) && !diagnosticContains(callDiagnosticRules.Optional, key) {
			return nil, errCallDiagnosticInvalid
		}
	}
	if event["schemaVersion"] != json.Number("1") {
		return nil, errCallDiagnosticInvalid
	}
	for _, key := range callDiagnosticRules.UUIDFields {
		if value, ok := event[key]; ok {
			str, ok := value.(string)
			if !ok || !diagnosticUUID.MatchString(str) {
				return nil, errCallDiagnosticInvalid
			}
		}
	}
	for key, allowed := range map[string][]string{"source": callDiagnosticRules.Source, "role": callDiagnosticRules.Role, "stage": callDiagnosticRules.Stage, "action": callDiagnosticRules.Action, "outcome": callDiagnosticRules.Outcome, "reason": callDiagnosticRules.Reason} {
		str, ok := event[key].(string)
		if !ok || !diagnosticContains(allowed, str) {
			return nil, errCallDiagnosticInvalid
		}
	}
	if !server && (event["source"] == "relay" || event["role"] == "server") {
		return nil, errCallDiagnosticInvalid
	}
	for _, key := range []string{"sequence", "occurredAtMs", "elapsedMs"} {
		n, ok := event[key].(json.Number)
		if !ok {
			return nil, errCallDiagnosticInvalid
		}
		v, err := n.Int64()
		if err != nil || v < 0 || v > 9007199254740991 {
			return nil, errCallDiagnosticInvalid
		}
	}
	if build, ok := event["build"]; ok {
		str, ok := build.(string)
		if !ok || !diagnosticBuild.MatchString(str) {
			return nil, errCallDiagnosticInvalid
		}
	}
	values, ok := event["values"].(map[string]any)
	if !ok || len(values) > 32 {
		return nil, errCallDiagnosticInvalid
	}
	for key, value := range values {
		if diagnosticContains(callDiagnosticRules.BooleanValues, key) {
			if _, ok := value.(bool); !ok {
				return nil, errCallDiagnosticInvalid
			}
			continue
		}
		if diagnosticContains(callDiagnosticRules.IntegerValues, key) {
			n, ok := value.(json.Number)
			if !ok {
				return nil, errCallDiagnosticInvalid
			}
			v, err := n.Int64()
			if err != nil || v < 0 || v > 9007199254740991 {
				return nil, errCallDiagnosticInvalid
			}
			continue
		}
		allowed, ok := callDiagnosticRules.EnumValues[key]
		str, isString := value.(string)
		if !ok || !isString || !diagnosticContains(allowed, str) {
			return nil, errCallDiagnosticInvalid
		}
	}
	return event, nil
}
func diagnosticReason(code string) string {
	switch code {
	case "CALL_UNAUTHORIZED", "TURN_UNAUTHORIZED":
		return "auth_error"
	case "CALL_INVALID_REQUEST":
		return "invalid_request"
	case "CALL_REPLAY":
		return "replay"
	case "CALL_STALE_EPOCH":
		return "stale_epoch"
	case "CALL_EXPIRY_INVALID":
		return "expired"
	case "CALL_RATE_LIMITED":
		return "rate_limited"
	case "CALL_IDENTITY_CONFLICT":
		return "authority_invalid"
	}
	if strings.Contains(code, "CAPACITY") {
		return "quota_exceeded"
	}
	return "backend_unavailable"
}
