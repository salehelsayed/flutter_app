package bridge

import (
	"encoding/json"
	"reflect"
	"sync"
	"testing"
	"time"

	libp2p "github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/mknoon/go-mknoon/node"
)

func TestInboxRegisterToken_ThoughtNotificationsBooleanReachesRelay(t *testing.T) {
	withFreshSingletonNode(t)
	relayHost, err := libp2p.New(libp2p.ListenAddrStrings("/ip4/127.0.0.1/tcp/0"))
	if err != nil {
		t.Fatalf("start relay host: %v", err)
	}
	defer relayHost.Close()

	requests := make(chan map[string]interface{}, 1)
	relayHost.SetStreamHandler(node.InboxProtocol, func(s network.Stream) {
		defer s.Close()
		raw := readBridgeTestFrame(t, s)
		var request map[string]interface{}
		if err := json.Unmarshal(raw, &request); err != nil {
			t.Errorf("decode registration frame: %v", err)
			return
		}
		requests <- request
		writeBridgeTestFrame(t, s, []byte(`{"status":"OK"}`))
	})

	relayAddr := relayHost.Addrs()[0].String() + "/p2p/" + relayHost.ID().String()
	startInput, err := json.Marshal(map[string]interface{}{
		"privateKeyHex":  generateTestKeyHex(t),
		"relayAddresses": []string{relayAddr},
		"autoRegister":   false,
	})
	if err != nil {
		t.Fatal(err)
	}
	assertOk(t, parseJSON(t, StartNode(string(startInput))))

	for _, testCase := range []struct {
		name  string
		value *bool
		want  bool
	}{
		{name: "absent defaults ON", want: true},
		{name: "OFF", value: thoughtNotificationsBool(false), want: false},
		{name: "ON", value: thoughtNotificationsBool(true), want: true},
		{name: "OFF again with same token", value: thoughtNotificationsBool(false), want: false},
	} {
		t.Run(testCase.name, func(t *testing.T) {
			input := map[string]interface{}{
				"token":        "same-device-token",
				"platform":     "ios",
				"capabilities": []string{node.DirectReactionPushCapability, "group_reaction_v1"},
			}
			if testCase.value != nil {
				input["thought_notifications_enabled"] = *testCase.value
			}
			encoded, err := json.Marshal(input)
			if err != nil {
				t.Fatal(err)
			}
			assertOk(t, parseJSON(t, InboxRegisterToken(string(encoded))))

			select {
			case request := <-requests:
				if request["action"] != "register_token" || request["token"] != "same-device-token" || request["platform"] != "ios" {
					t.Fatalf("registration lost established fields: %#v", request)
				}
				if !reflect.DeepEqual(request["capabilities"], []interface{}{node.DirectReactionPushCapability, "group_reaction_v1"}) {
					t.Errorf("registration changed capabilities: %#v", request["capabilities"])
				}
				enabled, ok := request["thought_notifications_enabled"].(bool)
				if !ok || enabled != testCase.want {
					t.Errorf("relay thought_notifications_enabled = %#v, want JSON boolean %v", request["thought_notifications_enabled"], testCase.want)
				}
			case <-time.After(2 * time.Second):
				t.Fatal("relay did not receive registration frame")
			}
		})
	}
}

func thoughtNotificationsBool(value bool) *bool { return &value }

func TestInboxRegisterToken_ThoughtPreferencePartialRelayAckRetriesCurrentOff(t *testing.T) {
	withFreshSingletonNode(t)
	var mu sync.Mutex
	rejectSecond := true
	current := map[string]bool{"first": true, "second": true}
	preferenceFrames := map[string][]bool{}
	addresses := make([]string, 0, 2)
	for _, name := range []string{"first", "second"} {
		relayHost, err := libp2p.New(libp2p.ListenAddrStrings("/ip4/127.0.0.1/tcp/0"))
		if err != nil {
			t.Fatalf("start %s relay: %v", name, err)
		}
		defer relayHost.Close()
		relayName := name
		relayHost.SetStreamHandler(node.InboxProtocol, func(s network.Stream) {
			defer s.Close()
			var request map[string]interface{}
			if err := json.Unmarshal(readBridgeTestFrame(t, s), &request); err != nil {
				t.Errorf("decode %s relay frame: %v", relayName, err)
				return
			}
			mu.Lock()
			rejected := relayName == "second" && rejectSecond
			if enabled, present := request["thought_notifications_enabled"].(bool); present {
				preferenceFrames[relayName] = append(preferenceFrames[relayName], enabled)
				if !rejected {
					current[relayName] = enabled
				}
			}
			mu.Unlock()
			if rejected {
				writeBridgeTestFrame(t, s, []byte(`{"status":"ERROR","error":"temporary registration failure"}`))
			} else {
				writeBridgeTestFrame(t, s, []byte(`{"status":"OK"}`))
			}
		})
		addresses = append(addresses, relayHost.Addrs()[0].String()+"/p2p/"+relayHost.ID().String())
	}

	startInput, err := json.Marshal(map[string]interface{}{
		"privateKeyHex": generateTestKeyHex(t),
		// Duplicate addresses for one peer must not become another ACK target.
		"relayAddresses": []string{addresses[0], addresses[0], addresses[1]},
		"autoRegister":   false,
	})
	if err != nil {
		t.Fatal(err)
	}
	assertOk(t, parseJSON(t, StartNode(string(startInput))))
	input := `{"token":"same-device-token","platform":"ios","thought_notifications_enabled":false}`
	partial := parseJSON(t, InboxRegisterToken(input))
	if partial["ok"] != false || partial["errorCode"] != "INBOX_ERROR" {
		t.Errorf("partial preference ACK must remain retryable, got %#v", partial)
	}
	mu.Lock()
	if current["first"] || !current["second"] {
		t.Errorf("fixture must retain OFF on successful relay and stale ON on rejected relay: %#v", current)
	}
	mu.Unlock()

	nodeMu.Lock()
	legacyNode := singletonNode
	nodeMu.Unlock()
	if err := legacyNode.InboxRegisterToken("legacy-token", "ios"); err != nil {
		t.Errorf("legacy at-least-one registration must still succeed: %v", err)
	}

	mu.Lock()
	rejectSecond = false
	mu.Unlock()
	assertOk(t, parseJSON(t, InboxRegisterToken(input)))
	mu.Lock()
	defer mu.Unlock()
	for _, name := range []string{"first", "second"} {
		if current[name] {
			t.Errorf("retry left %s relay ON", name)
		}
		if !reflect.DeepEqual(preferenceFrames[name], []bool{false, false}) {
			t.Errorf("%s relay preference frames = %#v, want current OFF on both attempts", name, preferenceFrames[name])
		}
	}
}
