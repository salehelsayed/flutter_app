package bridge

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"

	"github.com/mknoon/go-mknoon/node"
)

// Desired publication has no path, root or operation fields and performs only
// the synchronous in-memory fence change in the Node-owned reporter.
func PublishActiveIdentityReporterDesired(paramsJSON string) string {
	n := currentCallBridgeNode()
	if n == nil {
		return errJSON("NOT_INITIALIZED", "call Initialize first")
	}
	fields, ok := activityReporterFields(paramsJSON)
	if !ok || !activityReporterKeys(fields, "version", "revision", "consentEpoch", "profileBinding", "accountPeerId", "enabled", "preservePendingOnUnarm") {
		return activityReporterError(node.ErrActiveIdentityReporterInput)
	}
	var request node.ActiveIdentityReporterDesiredRequest
	if !activityReporterDecodeFence(fields, &request.ActiveIdentityReporterFence) || !activityReporterBool(fields["enabled"], &request.Enabled) || !activityReporterBool(fields["preservePendingOnUnarm"], &request.PreservePendingOnUnarm) {
		return activityReporterError(node.ErrActiveIdentityReporterInput)
	}
	request.Version = 1
	fence, err := n.PublishActiveIdentityReporterDesired(request)
	if err != nil {
		return activityReporterError(err)
	}
	return okJSON(map[string]interface{}{"ok": true, "data": map[string]interface{}{"revision": fence.Revision, "consentEpoch": fence.ConsentEpoch}})
}

func ActiveIdentityReporterV1(paramsJSON string) string {
	n := currentCallBridgeNode()
	if n == nil {
		return errJSON("NOT_INITIALIZED", "call Initialize first")
	}
	fields, ok := activityReporterFields(paramsJSON)
	if !ok {
		return activityReporterError(node.ErrActiveIdentityReporterInput)
	}
	var request node.ActiveIdentityReporterLocalRequest
	if !activityReporterString(fields["op"], &request.Op) || !activityReporterDecodeFence(fields, &request.ActiveIdentityReporterFence) {
		return activityReporterError(node.ErrActiveIdentityReporterInput)
	}
	keys := []string{"version", "revision", "consentEpoch", "profileBinding", "accountPeerId", "op"}
	switch request.Op {
	case "configure":
		keys = append(keys, "enabled", "statePath", "rootPrivateKeyBase64", "preservePendingOnUnarm")
		var enabled bool
		if !activityReporterBool(fields["enabled"], &enabled) || !activityReporterBool(fields["preservePendingOnUnarm"], &request.PreservePendingOnUnarm) || !activityReporterString(fields["statePath"], &request.StatePath) || !activityReporterString(fields["rootPrivateKeyBase64"], &request.RootPrivateKeyBase64) {
			return activityReporterError(node.ErrActiveIdentityReporterInput)
		}
		request.Enabled = &enabled
	case "mark":
		if raw, present := fields["occurredAtUnixMillis"]; present {
			keys = append(keys, "occurredAtUnixMillis")
			var at int64
			if bytes.Equal(bytes.TrimSpace(raw), []byte("null")) || json.Unmarshal(raw, &at) != nil {
				return activityReporterError(node.ErrActiveIdentityReporterInput)
			}
			request.OccurredAtUnixMillis = &at
		}
	case "flush", "weeklyProjection":
	case "markWeekly", "ackWeekly":
		keys = append(keys, "week", "kinds")
		if !activityReporterString(fields["week"], &request.Week) || bytes.Equal(bytes.TrimSpace(fields["kinds"]), []byte("null")) || json.Unmarshal(fields["kinds"], &request.Kinds) != nil {
			return activityReporterError(node.ErrActiveIdentityReporterInput)
		}
		if request.Op == "ackWeekly" {
			keys = append(keys, "relayPeerId")
			if !activityReporterString(fields["relayPeerId"], &request.RelayPeerID) {
				return activityReporterError(node.ErrActiveIdentityReporterInput)
			}
		}
	default:
		return activityReporterError(node.ErrActiveIdentityReporterInput)
	}
	if !activityReporterKeys(fields, keys...) {
		return activityReporterError(node.ErrActiveIdentityReporterInput)
	}
	request.Version = 1
	result, err := n.ActiveIdentityReporterV1(request)
	if err != nil {
		return activityReporterError(err)
	}
	data := map[string]interface{}{"revision": result.Fence.Revision, "consentEpoch": result.Fence.ConsentEpoch}
	switch request.Op {
	case "configure":
		data["configured"] = result.Configured
	case "mark", "markWeekly", "ackWeekly":
		data["accepted"] = result.Accepted
	case "weeklyProjection":
		data["weekly"] = result.Weekly
	case "flush":
		data["queued"] = result.Queued
	}
	return okJSON(map[string]interface{}{"ok": true, "data": data})
}

func activityReporterError(err error) string {
	if errors.Is(err, node.ErrActiveIdentityReporterInput) {
		return errJSON("INVALID_INPUT", "Invalid activity reporter request")
	}
	if errors.Is(err, node.ErrActiveIdentityReporterStale) {
		return errJSON("ACTIVE_IDENTITY_REPORTER_STALE", "Activity reporter owner is not current")
	}
	return errJSON("ACTIVE_IDENTITY_REPORTER_UNAVAILABLE", "Activity reporter unavailable")
}

// Decode members explicitly so duplicate/case-aliased keys, null and missing
// values cannot acquire encoding/json's zero-value or case-folding semantics.
func activityReporterFields(raw string) (map[string]json.RawMessage, bool) {
	if len(raw) > node.ActiveIdentityReporterLocalLimit {
		return nil, false
	}
	decoder := json.NewDecoder(bytes.NewBufferString(raw))
	token, err := decoder.Token()
	if err != nil || token != json.Delim('{') {
		return nil, false
	}
	fields := make(map[string]json.RawMessage)
	for decoder.More() {
		token, err := decoder.Token()
		key, ok := token.(string)
		if err != nil || !ok {
			return nil, false
		}
		if _, exists := fields[key]; exists {
			return nil, false
		}
		var value json.RawMessage
		if decoder.Decode(&value) != nil {
			return nil, false
		}
		fields[key] = value
	}
	token, err = decoder.Token()
	if err != nil || token != json.Delim('}') || decoder.Decode(new(any)) != io.EOF {
		return nil, false
	}
	return fields, true
}

func activityReporterKeys(fields map[string]json.RawMessage, keys ...string) bool {
	if len(fields) != len(keys) {
		return false
	}
	for _, key := range keys {
		if _, ok := fields[key]; !ok {
			return false
		}
	}
	return true
}

func activityReporterString(raw json.RawMessage, out *string) bool {
	return len(raw) != 0 && !bytes.Equal(bytes.TrimSpace(raw), []byte("null")) && json.Unmarshal(raw, out) == nil
}

func activityReporterBool(raw json.RawMessage, out *bool) bool {
	value := bytes.TrimSpace(raw)
	if !bytes.Equal(value, []byte("true")) && !bytes.Equal(value, []byte("false")) {
		return false
	}
	return json.Unmarshal(raw, out) == nil
}

func activityReporterDecodeFence(fields map[string]json.RawMessage, f *node.ActiveIdentityReporterFence) bool {
	if !bytes.Equal(bytes.TrimSpace(fields["version"]), []byte("1")) {
		return false
	}
	if json.Unmarshal(fields["revision"], &f.Revision) != nil || json.Unmarshal(fields["consentEpoch"], &f.ConsentEpoch) != nil || f.Revision <= 0 || f.Revision > 9007199254740991 || f.ConsentEpoch <= 0 || f.ConsentEpoch > 9007199254740991 {
		return false
	}
	return activityReporterString(fields["profileBinding"], &f.ProfileBinding) && activityReporterString(fields["accountPeerId"], &f.AccountPeerID)
}
