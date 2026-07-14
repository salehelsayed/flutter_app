package node

import (
	"encoding/json"
	"reflect"
	"strings"
	"testing"
	"time"

	libp2p "github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p/core/network"
)

func TestInboxRegisterToken_DirectReactionCapabilityIsOptionalAndExact(t *testing.T) {
	const groupReactionPushCapability = "group_reaction_v1"
	relayHost, err := libp2p.New(libp2p.ListenAddrStrings("/ip4/127.0.0.1/tcp/0"))
	if err != nil {
		t.Fatalf("start relay host: %v", err)
	}
	defer relayHost.Close()

	rawSeen := make(chan []byte, 2)
	relayHost.SetStreamHandler(InboxProtocol, func(s network.Stream) {
		defer s.Close()
		raw, err := readFrame(s)
		if err != nil {
			return
		}
		rawSeen <- raw
		_ = writeFrame(s, []byte(`{"status":"OK"}`))
	})

	n := startLocalNodeForMultiRelayTest(t)
	relayAddr := relayHost.Addrs()[0].String() + "/p2p/" + relayHost.ID().String()
	n.mu.Lock()
	n.relayAddresses = []string{relayAddr}
	n.mu.Unlock()

	if err := n.InboxRegisterToken(
		"capable-token",
		"android",
		DirectReactionPushCapability,
		groupReactionPushCapability,
	); err != nil {
		t.Fatalf("capable InboxRegisterToken: %v", err)
	}
	if err := n.InboxRegisterToken("legacy-token", "ios"); err != nil {
		t.Fatalf("legacy InboxRegisterToken: %v", err)
	}

	for index, wantCapabilities := range [][]string{{DirectReactionPushCapability, groupReactionPushCapability}, nil} {
		select {
		case raw := <-rawSeen:
			var req inboxRequest
			if err := json.Unmarshal(raw, &req); err != nil {
				t.Fatalf("decode request %d: %v", index, err)
			}
			if req.Action != "register_token" {
				t.Fatalf("request %d action = %q", index, req.Action)
			}
			if len(req.Capabilities) != len(wantCapabilities) {
				t.Fatalf("request %d capabilities = %#v, want %#v", index, req.Capabilities, wantCapabilities)
			}
			if len(wantCapabilities) > 0 && !reflect.DeepEqual(req.Capabilities, wantCapabilities) {
				t.Fatalf("capabilities = %#v, want exact %#v", req.Capabilities, wantCapabilities)
			}
			// Frozen pre-capability relay reader: additive JSON must still decode
			// the upgraded registration's established fields.
			var legacyReader struct {
				Action   string `json:"action"`
				Token    string `json:"token"`
				Platform string `json:"platform"`
			}
			if err := json.Unmarshal(raw, &legacyReader); err != nil {
				t.Fatalf("legacy reader rejected request %d: %v", index, err)
			}
			if legacyReader.Action != "register_token" || legacyReader.Token == "" || legacyReader.Platform == "" {
				t.Fatalf("legacy reader lost established fields: %#v", legacyReader)
			}
			if len(wantCapabilities) == 0 && strings.Contains(string(raw), "capabilities") {
				t.Fatalf("legacy registration must omit capabilities key: %s", raw)
			}
		case <-time.After(2 * time.Second):
			t.Fatalf("timed out waiting for request %d", index)
		}
	}
}
