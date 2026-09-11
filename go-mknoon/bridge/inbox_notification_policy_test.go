package bridge

import (
	"encoding/json"
	"testing"
	"time"

	"github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/mknoon/go-mknoon/node"
)

// Exercise the exported mobile JSON boundary through the actual node and a
// framed local relay. A Dart-only flag must not vanish before reaching STORE.
func TestInboxStoreNotificationPolicyReachesRelay(t *testing.T) {
	withFreshSingletonNode(t)
	relay, err := libp2p.New(libp2p.ListenAddrStrings("/ip4/127.0.0.1/tcp/0"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = relay.Close() })
	requests := make(chan map[string]interface{}, 8)
	relay.SetStreamHandler(node.InboxProtocol, func(stream network.Stream) {
		defer stream.Close()
		_ = stream.SetDeadline(time.Now().Add(5 * time.Second))
		var request map[string]interface{}
		if err := json.Unmarshal(readBridgeTestFrame(t, stream), &request); err != nil {
			t.Error(err)
			return
		}
		requests <- request
		response := map[string]interface{}{"status": "OK", "storeStatus": "stored"}
		if request["action"] == "store_custody_v1" {
			response["custodyContract"] = node.AckOrExpiryCustodyContract
			if expiry, exists := request["custodyExpiresAtOrBeforeMs"]; exists {
				response["expiresAtMs"] = expiry
			}
		}
		raw, _ := json.Marshal(response)
		writeBridgeTestFrame(t, stream, raw)
	})
	start, _ := json.Marshal(map[string]interface{}{
		"privateKeyHex":  generateTestKeyHex(t),
		"relayAddresses": []string{relay.Addrs()[0].String() + "/p2p/" + relay.ID().String()},
		"autoRegister":   false,
	})
	assertOk(t, parseJSON(t, StartNode(string(start))))
	const envelope = `{"type":"chat_message","id":"historical-message","encrypted":{"kem":"kem","ciphertext":"immutable-ciphertext","nonce":"nonce"}}`
	for _, tc := range []struct {
		name       string
		protected  bool
		suppress   bool
		mediaBound bool
	}{
		{name: "legacy_default"},
		{name: "legacy_historical", suppress: true},
		{name: "protected_default", protected: true},
		{name: "protected_historical", protected: true, suppress: true},
		{name: "media_historical", protected: true, suppress: true, mediaBound: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			input := map[string]interface{}{
				"toPeerId": relay.ID().String(), "message": envelope,
				"timeoutMs": 1000, "wakeToken": "recipient-issued-token",
			}
			if tc.suppress {
				input["suppressNotification"] = true
			}
			if tc.protected {
				input["custodyContract"] = node.AckOrExpiryCustodyContract
				input["custodyKind"] = node.CustodyKindDirectTextV108
			}
			if tc.mediaBound {
				input["custodyExpiresAtOrBeforeMs"] = int64(2_000_000_123_456)
			}
			raw, _ := json.Marshal(input)
			assertOk(t, parseJSON(t, InboxStore(string(raw))))
			select {
			case request := <-requests:
				if tc.suppress {
					if request["suppressNotification"] != true {
						t.Errorf("confirmed historical delivery lost notification suppression: %v", request)
					}
				} else if _, exists := request["suppressNotification"]; exists {
					t.Error("ordinary store must omit the additive notification policy")
				}
				if request["message"] != envelope || request["to"] != relay.ID().String() || request["wakeToken"] != "recipient-issued-token" {
					t.Errorf("notification policy changed immutable custody or wake authorization: %v", request)
				}
				if tc.protected && (request["custodyContract"] != node.AckOrExpiryCustodyContract || request["custodyKind"] != node.CustodyKindDirectTextV108) {
					t.Errorf("protected custody contract changed: %v", request)
				}
			case <-time.After(2 * time.Second):
				t.Fatal("relay did not receive STORE")
			}
		})
	}
}
