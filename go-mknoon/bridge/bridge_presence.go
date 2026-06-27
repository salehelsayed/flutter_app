package bridge

import (
	"encoding/json"
	"fmt"
)

// PresenceGet looks up a peer's coarse relay presence via the additive
// `presence_get` inbox action WITHOUT dialing a circuit (FDC-08). It is the
// cheap up-front "is this peer online-ish?" hint the send path consults to pick
// direct-race-with-lazy-inbox vs inbox-first emphasis, replacing the blind ≤5 s
// circuit dial on the decision path (RelayProbe stays for introductions).
//
// Input JSON:  { "peerId": "..." }
// Returns JSON: { "ok": true, "presence": "reachable"|"unreachable"|"unknown", "ageMs": <int> }
//
// Presence is "online-ish, TTL-lagged" and NEVER a foreground/background claim.
// A relay outage / old relay / garbled reply degrades to presence "unknown"
// inside ok:true — presence is a best-effort HINT and must never throw away a
// send (NET-REL-07). Only NOT_INITIALIZED / INVALID_INPUT produce an ok:false
// error envelope; the caller treats those as `unknown` too.
func PresenceGet(paramsJSON string) (result string) {
	defer func() {
		if r := recover(); r != nil {
			result = errJSON("INTERNAL_ERROR", fmt.Sprintf("panic: %v", r))
		}
	}()

	nodeMu.Lock()
	n := singletonNode
	nodeMu.Unlock()

	if n == nil {
		return errJSON("NOT_INITIALIZED", "call Initialize first")
	}

	var params struct {
		PeerId string `json:"peerId"`
	}
	if paramsJSON != "" {
		if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
			return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
		}
	}
	if params.PeerId == "" {
		return errJSON("INVALID_INPUT", "missing peerId")
	}

	// A relay error leaves res.Presence == "unknown"; surface it as a successful
	// hint envelope so the Dart layer degrades gracefully (it never treats a
	// relay outage as an undeliverable peer).
	res, _ := n.RelayPresenceLookup(params.PeerId)

	return okJSON(map[string]interface{}{
		"ok":       true,
		"presence": string(res.Presence),
		"ageMs":    res.AgeMs,
	})
}

// PresenceSet SELF-PUBLISHES the local peer's coarse foreground/background state
// to the relay via the additive `presence_set` inbox action (FDC-09 §6.3 write
// side, Option C). It is the WRITE twin of PresenceGet: the peer ANNOUNCES fg/bg
// so the read side can pick direct-race-with-lazy-inbox vs inbox-first emphasis
// (the relay provably cannot infer foreground from a TTL-lagged socket). The
// relay derives the subject peer from the authenticated stream identity
// (anti-spoof), so only {state, ttlMs} ride here.
//
// Input JSON:  { "state": "foreground"|"background", "ttlMs": <int> }
// Returns JSON: { "ok": true } on accept; { "ok": false, "error": "..." } when an
// OLD relay answers "Unknown action: presence_set" (the client maps that to
// "unsupported -> skip", NET-REL-07) or the publish could not be delivered.
//
// Presence is a best-effort HINT and NEVER load-bearing — a failed self-publish
// never throws away a send (the inbox + push remain the guarantee). Only
// NOT_INITIALIZED / INVALID_INPUT produce an ok:false error envelope; the caller
// treats those as "unsupported -> skip" too.
func PresenceSet(paramsJSON string) (result string) {
	defer func() {
		if r := recover(); r != nil {
			result = errJSON("INTERNAL_ERROR", fmt.Sprintf("panic: %v", r))
		}
	}()

	nodeMu.Lock()
	n := singletonNode
	nodeMu.Unlock()

	if n == nil {
		return errJSON("NOT_INITIALIZED", "call Initialize first")
	}

	var params struct {
		State string `json:"state"`
		TTLMs int64  `json:"ttlMs"`
	}
	if paramsJSON != "" {
		if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
			return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
		}
	}
	if params.State != "foreground" && params.State != "background" {
		return errJSON("INVALID_INPUT", "state must be foreground or background")
	}

	res, err := n.RelayPresenceSet(params.State, params.TTLMs)
	if err != nil {
		// A relay outage is a best-effort miss, not a hard error — surface ok:false
		// with the reason so the Dart layer degrades silently (presence is a HINT).
		return okJSON(map[string]interface{}{"ok": false, "error": err.Error()})
	}

	out := map[string]interface{}{"ok": res.OK}
	if res.Error != "" {
		out["error"] = res.Error
	}
	return okJSON(out)
}
