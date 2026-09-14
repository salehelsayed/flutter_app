package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"testing"
	"time"

	"github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/core/record"
	"github.com/libp2p/go-libp2p/p2p/protocol/circuitv2/client"
	"github.com/libp2p/go-msgio"
	ma "github.com/multiformats/go-multiaddr"
)

// Real sockets and production handlers complement the mock protocol suites.
// Each endpoint gets exactly one relay address; IPv4, another transport, LAN,
// cellular and USB cannot silently satisfy a requested IPv6 leg. Loopback is
// deliberately not evidence of a public IPv6-only or DNS64/NAT64 network.
func TestRelayDualStackApplicationContracts(t *testing.T) {
	for _, transport := range []string{"tcp/0", "tcp/0/ws", "udp/0/quic-v1"} {
		for _, families := range [][2]string{{"ip4", "ip4"}, {"ip6", "ip6"}, {"ip4", "ip6"}, {"ip6", "ip4"}} {
			t.Run(fmt.Sprintf("%s/%s-to-%s", transport, families[0], families[1]), func(t *testing.T) {
				ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
				t.Cleanup(cancel)
				relay, err := libp2p.New(
					libp2p.ListenAddrStrings("/ip4/127.0.0.1/"+transport, "/ip6/::1/"+transport),
					libp2p.EnableRelayService(), libp2p.ForceReachabilityPublic(),
				)
				if err != nil {
					t.Fatal(err)
				}
				t.Cleanup(func() { _ = relay.Close() })
				addresses := make(map[string]ma.Multiaddr)
				for _, address := range relay.Network().ListenAddresses() {
					for _, family := range []string{"ip4", "ip6"} {
						code := ma.P_IP4
						if family == "ip6" {
							code = ma.P_IP6
						}
						if _, err := address.ValueForProtocol(code); err == nil {
							addresses[family] = address
						}
					}
				}
				if len(addresses) != 2 {
					t.Fatal("both requested loopback families must bind; no alternate-family pass")
				}
				connect := func(family string) host.Host {
					t.Helper()
					h, err := libp2p.New(libp2p.NoListenAddrs)
					if err != nil {
						t.Fatal(err)
					}
					t.Cleanup(func() { _ = h.Close() })
					if err := h.Connect(ctx, peer.AddrInfo{ID: relay.ID(), Addrs: []ma.Multiaddr{addresses[family]}}); err != nil {
						t.Fatal(err)
					}
					return h
				}
				sender, recipient := connect(families[0]), connect(families[1])
				assertRoute := func(h host.Host, family string) {
					t.Helper()
					connections := h.Network().ConnsToPeer(relay.ID())
					if len(connections) != 1 || connections[0].RemotePeer() != relay.ID() || !connections[0].RemoteMultiaddr().Equal(addresses[family]) {
						t.Fatal("authenticated connection did not retain its exact requested family and transport")
					}
				}
				assertRoute(sender, families[0])
				assertRoute(recipient, families[1])
				if _, err := client.Reserve(ctx, recipient, peer.AddrInfo{ID: relay.ID(), Addrs: []ma.Multiaddr{addresses[families[1]]}}); err != nil {
					t.Fatal(err)
				}

				rendezvous := NewRendezvousStore()
				relay.SetStreamHandler(RendezvousProtocol, func(s network.Stream) { HandleRendezvousStream(s, rendezvous) })
				rzRequest := func(h host.Host, request *RzMessage) []byte {
					t.Helper()
					s, err := h.NewStream(ctx, relay.ID(), RendezvousProtocol)
					if err != nil {
						t.Fatal(err)
					}
					defer s.Close()
					_ = s.SetDeadline(time.Now().Add(5 * time.Second))
					if err := msgio.NewVarintWriter(s).WriteMsg(request.Marshal()); err != nil {
						t.Fatal(err)
					}
					reader := msgio.NewVarintReaderSize(s, 1<<20)
					raw, err := reader.ReadMsg()
					if err != nil {
						t.Fatal(err)
					}
					defer reader.ReleaseMsg(raw)
					return append([]byte(nil), raw...)
				}
				envelope, err := record.Seal(&peer.PeerRecord{PeerID: sender.ID(), Addrs: []ma.Multiaddr{addresses[families[0]]}, Seq: 1}, sender.Peerstore().PrivKey(sender.ID()))
				if err != nil {
					t.Fatal(err)
				}
				signed, err := envelope.Marshal()
				if err != nil {
					t.Fatal(err)
				}
				registered := rzRequest(sender, &RzMessage{Type: MessageType_REGISTER, Register: &Register{Ns: "dual-stack-fixture", SignedPeerRecord: signed, TTL: 60}})
				wantRegistered := (&RzMessage{Type: MessageType_REGISTER_RESPONSE, RegisterResponse: &RegisterResponse{Status: ResponseStatus_OK, StatusText: "OK", TTL: 60}}).Marshal()
				if !bytes.Equal(registered, wantRegistered) {
					t.Fatal("rendezvous registration failed")
				}
				discovered := rzRequest(recipient, &RzMessage{Type: MessageType_DISCOVER, Discover: &Discover{Ns: "dual-stack-fixture", Limit: 10}})
				wantDiscovered := (&RzMessage{Type: MessageType_DISCOVER_RESPONSE, DiscoverResponse: &DiscoverResponse{Status: ResponseStatus_OK, StatusText: "OK", Registrations: []Registration{{Ns: "dual-stack-fixture", SignedPeerRecord: signed}}}}).Marshal()
				if !bytes.Equal(discovered, wantDiscovered) {
					t.Fatal("rendezvous did not preserve the signed peer record")
				}

				now := time.Now()
				calls, redis := callTestService(t, now, nil)
				inbox := NewInboxStoreWithBackendAndCapacity(newRedisInboxBackend(newTestRedisClient(t, redis), "dual-stack:", 10), NewPushServiceWithBackend(newMemoryPushTokenStore()), 10)
				inbox.SetAckCustodyAdmissionEnabled(true)
				groups, presence := NewGroupInboxStore(8, time.Hour), NewPresenceStore()
				relay.SetStreamHandler(InboxProtocol, func(s network.Stream) { HandleInboxStream(s, inbox, groups, relay, presence, nil, calls) })
				roundTrip := func(h host.Host, request any, response any) {
					t.Helper()
					s, err := h.NewStream(ctx, relay.ID(), InboxProtocol)
					if err != nil {
						t.Fatal(err)
					}
					defer s.Close()
					_ = s.SetDeadline(time.Now().Add(5 * time.Second))
					raw, err := json.Marshal(request)
					if err != nil {
						t.Fatal(err)
					}
					if err := writeFrame(s, raw); err != nil {
						t.Fatal(err)
					}
					raw, err = readFrame(s)
					if err != nil {
						t.Fatal(err)
					}
					if err := json.Unmarshal(raw, response); err != nil {
						t.Fatal(err)
					}
				}
				message := ackCustodyTextEnvelope("dual-stack-quiet", sender.ID().String(), "synthetic-encrypted-bytes")
				var stored inboxResponse
				roundTrip(sender, inboxRequest{Action: "store_custody_quiet_v1", To: recipient.ID().String(), From: "forged", Message: message, CustodyKind: ackCustodyDirectTextKind, CustodyContract: ackCustodyContract}, &stored)
				if stored.Status != "OK" || stored.CustodyContract != ackCustodyContract {
					t.Fatalf("custody rejected: %#v", stored)
				}
				var legacy, pending inboxResponse
				roundTrip(recipient, inboxRequest{Action: "retrieve_pending", Limit: 10}, &legacy)
				if legacy.Status != "NO_MESSAGES" || len(legacy.Messages) != 0 {
					t.Fatal("legacy recipient consumed a quiet row")
				}
				roundTrip(recipient, inboxRequest{Action: ackCustodyRetrievePendingAction, CustodyContract: ackCustodyContract, Limit: 10, QuietRecovery: true}, &pending)
				if pending.Status != "OK" || len(pending.Messages) != 1 || !pending.Messages[0].QuietRecovery || pending.Messages[0].From != sender.ID().String() || pending.Messages[0].Message != message {
					t.Fatalf("quiet bytes/attribution lost: %#v", pending)
				}
				var ack inboxResponse
				roundTrip(recipient, inboxRequest{Action: ackCustodyAckAction, CustodyContract: ackCustodyContract, EntryIds: []string{pending.Messages[0].ID}}, &ack)
				if ack.Status != "OK" || ack.Acked != 1 {
					t.Fatalf("custody ACK failed: %#v", ack)
				}
				var drained inboxResponse
				roundTrip(recipient, inboxRequest{Action: ackCustodyRetrievePendingAction, CustodyContract: ackCustodyContract, QuietRecovery: true}, &drained)
				if drained.Status != "NO_MESSAGES" || len(drained.Messages) != 0 {
					t.Fatal("ACK did not drain custody")
				}

				callRequest := func(h host.Host, request map[string]any) map[string]any {
					t.Helper()
					var response map[string]any
					roundTrip(h, request, &response)
					if response["status"] != "OK" {
						t.Fatalf("call action %s failed: %#v", request["action"], response)
					}
					return response
				}
				callRequest(recipient, map[string]any{"action": "call_wake_handle_set_v1", "authorizedSenderPeerId": sender.ID().String(), "wakeHandle": callTestWake, "expiresAtMs": now.Add(time.Hour).UnixMilli()})
				callRequest(sender, map[string]any{"action": "call_store_v1", "to": recipient.ID().String(), "callHandle": callTestHandleA, "messageId": callTestMessageA, "envelope": "synthetic-call-control", "expiresAtMs": now.Add(45 * time.Second).UnixMilli(), "wakeHandle": callTestWake})
				fetched := callRequest(recipient, map[string]any{"action": "call_retrieve_v1", "callHandle": callTestHandleA, "limit": 10})
				events, ok := fetched["events"].([]any)
				if !ok || len(events) != 1 {
					t.Fatal("call-control event missing")
				}
				event := events[0].(map[string]any)
				if event["senderPeerId"] != sender.ID().String() || event["envelope"] != "synthetic-call-control" {
					t.Fatal("call-control bytes/attribution lost")
				}
				callAck := callRequest(recipient, map[string]any{"action": "call_ack_v1", "callHandle": callTestHandleA, "messageIds": []string{callTestMessageA}})
				if callAck["acked"] != float64(1) {
					t.Fatal("call-control ACK failed")
				}
				assertRoute(sender, families[0])
				assertRoute(recipient, families[1])
			})
		}
	}
}
