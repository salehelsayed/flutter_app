package bridge

import "testing"

// 183 (TC-183-31) — PeerPing param-parse + error path. The real ping.Ping
// round-trip is device-proven (TC-183-50); here we lock the bridge envelope:
// NOT_INITIALIZED when there is no node, and INVALID_INPUT for a missing peerId
// / malformed JSON. Mutation: break the param parse / drop the peerId check → red.

func TestPeerPing_NodeNotInitialized(t *testing.T) {
	result := PeerPing(`{"peerId": "12D3KooWTest", "timeoutMs": 4000}`)
	m := parseJSON(t, result)
	assertNotOk(t, m, "NOT_INITIALIZED")
}

func TestPeerPing_MissingPeerId(t *testing.T) {
	withSingletonNode(t)
	result := PeerPing(`{"timeoutMs": 4000}`)
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}

func TestPeerPing_InvalidJSON(t *testing.T) {
	withSingletonNode(t)
	result := PeerPing(`not json`)
	m := parseJSON(t, result)
	assertNotOk(t, m, "INVALID_INPUT")
}
