package bridge

import (
	"encoding/json"
	"fmt"
	"time"
)

// PeerPing actively PINGS a directly-connected 1:1 peer via the libp2p ping
// protocol. The node is a ping RESPONDER by default (libp2p installs the
// handler); this is the first app-level CALLER. It backs the 183 active-chat
// keepalive: while foreground + in a 1:1 chat the Dart layer pings the open peer
// on a short cadence (~8 s, under the ~30 s QUIC idle) to keep the warm
// connection alive and detect a drop in seconds.
//
// Input JSON:  { "peerId": "...", "timeoutMs": <int> }
// Returns JSON: { "ok": true, "rttMs": <int> } when the peer answered within the
// timeout; { "ok": false, "error": "..." } when the ping failed / timed out.
//
// The probe is best-effort and NEVER load-bearing — an unreachable peer is a
// miss, not an error: only NOT_INITIALIZED / INVALID_INPUT produce an ok:false
// error envelope; the caller treats any non-ok as a miss and never throws.
func PeerPing(paramsJSON string) (result string) {
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
		PeerId    string `json:"peerId"`
		TimeoutMs int64  `json:"timeoutMs"`
	}
	if paramsJSON != "" {
		if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
			return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
		}
	}
	if params.PeerId == "" {
		return errJSON("INVALID_INPUT", "missing peerId")
	}

	timeout := time.Duration(params.TimeoutMs) * time.Millisecond
	if timeout <= 0 {
		timeout = 5 * time.Second
	}

	rtt, err := n.PingPeer(params.PeerId, timeout)
	if err != nil {
		// A failed/timed-out ping is a best-effort miss, not a hard error —
		// surface ok:false with the reason so the Dart layer degrades to a miss.
		return okJSON(map[string]interface{}{"ok": false, "error": err.Error()})
	}

	return okJSON(map[string]interface{}{
		"ok":    true,
		"rttMs": rtt.Milliseconds(),
	})
}
