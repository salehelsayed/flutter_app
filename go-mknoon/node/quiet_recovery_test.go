package node

import (
	"encoding/json"
	"strings"
	"testing"
	"time"
)

type quietRecoveryCallback struct {
	node          *Node
	received      chan map[string]interface{}
	beforeConfirm func()
}

func (c *quietRecoveryCallback) OnEvent(raw string) {
	var event struct {
		Event string                 `json:"event"`
		Data  map[string]interface{} `json:"data"`
	}
	if json.Unmarshal([]byte(raw), &event) != nil || event.Event != "message:received" {
		return
	}
	c.received <- event.Data
	if nonce, ok := event.Data["confirmNonce"].(string); ok {
		if c.beforeConfirm != nil {
			c.beforeConfirm()
		}
		c.node.ResolveDirectConfirm(nonce, true)
	}
}

func TestQuietRecoveryNegotiatesWithoutChangingEncryptedBytesOrCommittedACK(t *testing.T) {
	sender := NewNode()
	if _, err := sender.Start(NodeConfig{PrivateKeyHex: generateTestKey(t), RelayAddresses: []string{}, AutoRegister: false}); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { sender.Stop() })
	callback := &quietRecoveryCallback{received: make(chan map[string]interface{}, 4)}
	receiver := New(callback)
	callback.node = receiver
	if _, err := receiver.Start(NodeConfig{PrivateKeyHex: generateTestKey(t), RelayAddresses: []string{}, AutoRegister: false}); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { receiver.Stop() })
	addresses := []string{}
	for _, address := range receiver.Host().Addrs() {
		if strings.Contains(address.String(), "/tcp/") {
			addresses = append(addresses, address.String())
		}
	}
	if err := sender.DialPeerWithTimeout(receiver.PeerId(), addresses, 10000); err != nil {
		t.Fatal(err)
	}
	const wire = `{"type":"chat_message","version":"2","id":"original","senderPeerId":"sender","encrypted":{"kem":"k","ciphertext":"immutable","nonce":"n"}}`
	for _, quiet := range []bool{true, false} {
		result, err := sender.SendMessageWithNotificationPolicy(receiver.PeerId(), wire, 5000, quiet)
		if err != nil || !result.Acked {
			t.Fatalf("quiet=%v result=%+v err=%v", quiet, result, err)
		}
		select {
		case event := <-callback.received:
			if event["content"] != wire || event["from"] != sender.PeerId() {
				t.Fatalf("immutable/authenticated event changed: %v", event)
			}
			if (event["quietRecovery"] == true) != quiet {
				t.Fatalf("quiet metadata lost: %v", event)
			}
			if !quiet {
				if _, present := event["quietRecovery"]; present {
					t.Fatal("normal direct send added policy")
				}
			}
		case <-time.After(time.Second):
			t.Fatal("missing incoming event")
		}
	}
	receiver.Host().RemoveStreamHandler(QuietRecoveryChatProtocol)
	if result, err := sender.SendMessageWithNotificationPolicy(receiver.PeerId(), wire, 5000, true); result.Acked {
		t.Fatalf("unsupported quiet protocol fell back: %+v %v", result, err)
	}
	select {
	case event := <-callback.received:
		t.Fatalf("unsupported receiver got alertable message: %v", event)
	default:
	}
}

func TestQuietRecoveryInboxMetadataSurvivesJSONAndReplicaCoalescing(t *testing.T) {
	const raw = `[{"id":"original","from":"sender","message":"immutable","timestamp":9,"quietRecovery":true},{"id":"original","from":"sender","message":"immutable","timestamp":8}]`
	var rows []InboxMessage
	if err := json.Unmarshal([]byte(raw), &rows); err != nil {
		t.Fatal(err)
	}
	for _, input := range [][]InboxMessage{rows, {rows[1], rows[0]}} {
		merged, err := coalesceAndSortInboxCustodyMessages(input)
		if err != nil || len(merged) != 1 || !merged[0].QuietRecovery || merged[0].Timestamp != 8 {
			t.Fatalf("lost quiet disposition: %+v %v", merged, err)
		}
		encoded, err := json.Marshal(merged)
		if err != nil || !strings.Contains(string(encoded), `"quietRecovery":true`) {
			t.Fatalf("mobile/NSE retrieval dropped metadata: %s %v", encoded, err)
		}
	}
}
