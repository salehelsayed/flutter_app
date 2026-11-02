package bridge

import (
	"encoding/json"
	"reflect"
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
