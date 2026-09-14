package bridge

import (
	"encoding/json"
	"strings"
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
	const envelope = `{"type":"chat_message","id":"historical-message","encrypted":{"kem":"kem","ciphertext":"immutable-ciphertext","nonce":"nonce"}}`
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
		if action, _ := request["action"].(string); strings.HasPrefix(action, "retrieve") {
			response = map[string]interface{}{
				"status": "OK", "hasMore": false,
				"messages": []node.InboxMessage{
					{ID: "quiet-row", From: relay.ID().String(), Message: envelope, Timestamp: 1700000000000, QuietRecovery: true},
					{ID: "normal-row", From: relay.ID().String(), Message: "normal encrypted bytes", Timestamp: 1700000000001},
				},
			}
			if action == "retrieve_custody_pending_v1" {
				response["custodyContract"] = node.AckOrExpiryCustodyContract
			}
		}
		if request["action"] == "store_custody_v1" || request["action"] == "store_custody_quiet_v1" {
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
	dialInput, _ := json.Marshal(map[string]interface{}{"peerId": relay.ID().String(), "addresses": []string{relay.Addrs()[0].String()}, "timeoutMs": 1000})
	dialResponse := parseJSON(t, DialPeer(string(dialInput)))
	assertOk(t, dialResponse)
	established := dialResponse["connectionDiagnostics"].([]interface{})
	if len(established) == 0 {
		t.Fatal("missing authenticated connection")
	}
	for _, raw := range established {
		r := raw.(map[string]interface{})
		if r["connectionStage"] != "established" || r["observedLeg"] != "endpoint_to_relay" || r["addressFamily"] != "ipv4" {
			t.Fatalf("wrong established evidence: %v", r)
		}
	}
	for _, tc := range []struct {
		name       string
		protected  bool
		suppress   bool
		quiet      bool
		mediaBound bool
	}{
		{name: "legacy_default"},
		{name: "legacy_historical", suppress: true},
		{name: "legacy_quiet", quiet: true},
		{name: "protected_default", protected: true},
		{name: "protected_historical", protected: true, suppress: true},
		{name: "protected_quiet", protected: true, quiet: true},
		{name: "media_quiet", protected: true, quiet: true, mediaBound: true},
		{name: "media_historical", protected: true, suppress: true, mediaBound: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			input := map[string]interface{}{
				"toPeerId": relay.ID().String(), "message": envelope,
				"timeoutMs": 1000, "wakeToken": "recipient-issued-token",
			}
			if tc.quiet {
				input["quietRecovery"] = true
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
			response := parseJSON(t, InboxStore(string(raw)))
			assertOk(t, response)
			observations, ok := response["connectionDiagnostics"].([]interface{})
			if !ok || len(observations) == 0 {
				t.Fatal("missing actual inbox stream diagnostics")
			}
			row := observations[len(observations)-1].(map[string]interface{})
			if row["connectionStage"] != "stream_opened" || row["addressFamily"] != "ipv4" || row["observedLeg"] != "endpoint_to_relay" || row["familyFallback"] != "unknown" {
				t.Fatalf("wrong relay-leg evidence: %v", row)
			}
			if _, exists := response["acked"]; exists {
				t.Fatal("inbox acceptance promoted recipient ACK")
			}
			select {
			case request := <-requests:
				if _, exists := request["connectionDiagnostics"]; exists {
					t.Fatal("local diagnostics leaked onto inbox protocol")
				}
				expectedAction := "store"
				if tc.protected {
					expectedAction = "store_custody_v1"
				}
				if tc.quiet {
					expectedAction = "store_quiet_v1"
					if tc.protected {
						expectedAction = "store_custody_quiet_v1"
					}
				}
				if request["action"] != expectedAction {
					t.Errorf("store capability action = %v, want %s", request["action"], expectedAction)
				}
				if tc.suppress || tc.quiet {
					if request["suppressNotification"] != true {
						t.Errorf("confirmed historical delivery lost notification suppression: %v", request)
					}
				} else if _, exists := request["suppressNotification"]; exists {
					t.Error("ordinary store must omit the additive notification policy")
				}
				if (request["quietRecovery"] == true) != tc.quiet {
					t.Errorf("quiet recovery intent lost: %v", request)
				}
				if !tc.quiet {
					if _, exists := request["quietRecovery"]; exists {
						t.Error("normal store must omit quiet recovery")
					}
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
	for _, tc := range []struct {
		name string
		read func() string
	}{
		{"receive_legacy", InboxRetrieve},
		{"receive_with_timeout", func() string { return InboxRetrieveWithParams(`{"timeoutMs":1000}`) }},
		{"receive_pending", func() string { return InboxRetrievePendingWithParams(`{"timeoutMs":1000}`) }},
		{"receive_protected", func() string {
			return InboxRetrievePendingWithParams(`{"timeoutMs":1000,"custodyContract":"ack_or_expiry_v1"}`)
		}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			response := parseJSON(t, tc.read())
			assertOk(t, response)
			if tc.name == "receive_protected" && response["custodyContract"] != node.AckOrExpiryCustodyContract {
				t.Fatalf("mobile bridge lost protected custody authority: %v", response)
			}
			rows, ok := response["messages"].([]interface{})
			if !ok || len(rows) != 2 {
				t.Fatalf("mobile inbox page lost rows: %v", response)
			}
			quiet, normal := rows[0].(map[string]interface{}), rows[1].(map[string]interface{})
			if quiet["quietRecovery"] != true || quiet["id"] != "quiet-row" || quiet["from"] != relay.ID().String() || quiet["message"] != envelope || quiet["timestamp"] != float64(1700000000000) {
				t.Errorf("mobile bridge lost quiet disposition or immutable identity/bytes: %v", quiet)
			}
			if _, exists := normal["quietRecovery"]; exists || normal["id"] != "normal-row" || normal["message"] != "normal encrypted bytes" {
				t.Errorf("mixed page changed ordinary row policy: %v", normal)
			}
			select {
			case request := <-requests:
				if request["quietRecovery"] != true {
					t.Errorf("receiver did not declare quiet capability: %v", request)
				}
			case <-time.After(2 * time.Second):
				t.Fatal("relay did not receive retrieval request")
			}
		})
	}
}
