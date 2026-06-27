package bridge

// FDC-11 — bonsoir-fed libp2p LAN-direct dial bridge entrypoint.
//
// A NEW file in package bridge (precedent: events.go). gomobile binds the whole
// package (Makefile BIND_PKG), so the exported HandleLANPeerFound below is bound
// and dispatchable from Dart via the lan:peer_found command. It freely uses the
// package-level singletonNode / nodeMu / okJSON / errJSON declared in bridge.go.

import (
	"encoding/json"
	"fmt"
)

// HandleLANPeerFound is the gomobile-bound entrypoint for the lan:peer_found
// command. Dart forwards a bonsoir-discovered same-WiFi peer carrying the
// remote's libp2p QUIC (+TCP) multiaddrs; the node seeds the peerstore and
// issues a LAN-direct dial gated by EnableLibp2pLANDial.
//
// Input JSON:   { "peerId": "...", "addresses": ["/ip4/<lan>/udp/<p>/quic-v1", ...] }
// Returns JSON: { "ok": true }
//
// The dial runs on a background goroutine inside the node, off the single
// Dart→Go bridge channel, so it never head-of-line-blocks the user's send.
func HandleLANPeerFound(paramsJSON string) (result string) {
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
		PeerId    string   `json:"peerId"`
		Addresses []string `json:"addresses"`
	}
	if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
		return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
	}
	if params.PeerId == "" {
		return errJSON("INVALID_INPUT", "missing peerId")
	}

	// Fire-and-forget: the node gates on EnableLibp2pLANDial and runs the dial on
	// its own goroutine (off the bridge channel).
	go n.HandleLANPeerFoundAddrs(params.PeerId, params.Addresses)

	return okJSON(map[string]interface{}{"ok": true})
}

// MediaLANSend is the gomobile-bound entrypoint for the media:lan_send command
// (FDC-15). Dart forwards a 1:1 media ciphertext blob — the SAME
// EncryptedMediaArtifact it uploads to the relay-CDN — to be streamed over the
// FDC-11 LAN-direct conn (MediaLANProtocol). The node refuses unless a
// non-circuit conn exists; the SHA-256 of the ciphertext file is computed
// node-side and verified by the receiver. This is best-effort acceleration only —
// the relay-CDN upload stays UNCONDITIONAL on the Dart side.
//
// Input JSON:   { "id","to","from","mime","filePath","enc","encScheme","durationMs" }
// Returns JSON: { "ok": true, "acked": bool, "sha256Verified": bool, "transport": "direct" }
//
// Unlike HandleLANPeerFound this runs SYNCHRONOUSLY (Dart awaits the ack via a
// stall watchdog), mirroring the relay-CDN MediaUpload bridge call.
func MediaLANSend(paramsJSON string) (result string) {
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
		ID         string `json:"id"`
		To         string `json:"to"`
		From       string `json:"from"`
		Mime       string `json:"mime"`
		FilePath   string `json:"filePath"`
		Enc        bool   `json:"enc"`
		EncScheme  string `json:"encScheme"`
		DurationMs int    `json:"durationMs"`
	}
	if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
		return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
	}
	if params.ID == "" || params.To == "" || params.FilePath == "" {
		return errJSON("INVALID_INPUT", "missing id, to, or filePath")
	}

	res, err := n.SendLANMediaToPeer(
		params.To, params.FilePath, params.ID, params.From, params.Mime, params.EncScheme, params.Enc, params.DurationMs,
	)
	if err != nil {
		return errJSON("MEDIA_LAN_ERROR", err.Error())
	}

	return okJSON(map[string]interface{}{
		"ok":             true,
		"acked":          res.Acked,
		"sha256Verified": res.Sha256Verified,
		"transport":      res.Transport,
	})
}
