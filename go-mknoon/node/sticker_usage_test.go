package node

import (
	"encoding/json"
	"github.com/libp2p/go-libp2p/core/network"
	"testing"
)

func TestStickerUsageTransportAndOldRelay(t *testing.T) {
	for _, supported := range []bool{true, false} {
		relay, _ := startTurnCredentialsRelayFixture(t, "")
		n := turnCredentialsNode(t, relay)
		seen := make(chan map[string]any, 1)
		relay.SetStreamHandler(InboxProtocol, func(s network.Stream) {
			defer s.Close()
			raw, _ := readFrame(s)
			var r map[string]any
			_ = json.Unmarshal(raw, &r)
			seen <- r
			if supported {
				_ = writeFrame(s, []byte(`{"status":"OK","version":1,"data":{"supported":true,"accepted":true}}`))
			} else {
				_ = writeFrame(s, []byte(`{"status":"ERROR","error":"Unknown action: sticker_usage_v1"}`))
			}
		})
		r, err := n.StickerUsageV1(StickerUsageRequest{Day: "2026-11-08", Nonce: "7b719404-d2bb-4d98-b3b6-b7be5d8186f1", Counts: map[string]int{"orbit_crew.planet.hello": 2}})
		if err != nil || r["supported"] != supported {
			t.Fatalf("result %v %v", r, err)
		}
		wire := <-seen
		if len(wire) != 4 || wire["action"] != "sticker_usage_v1" {
			t.Fatalf("identity/diagnostic fields leaked: %v", wire)
		}
	}
}
