package node

import (
	"context"
	"encoding/json"
	"regexp"
	"strings"
	"testing"
	"time"

	libp2p "github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/core/protocol"
)

func TestGroupProtocolIDs_AreVersionedCurrentContracts(t *testing.T) {
	versionedProtocol := regexp.MustCompile(`^/[a-z0-9-]+/[a-z0-9-]+/\d+\.\d+\.\d+$`)

	protocols := map[string]protocol.ID{
		"chat":       ChatProtocol,
		"inbox":      InboxProtocol,
		"rendezvous": RendezvousProtocol,
		"media":      MediaProtocol,
	}

	for name, id := range protocols {
		if !versionedProtocol.MatchString(string(id)) {
			t.Fatalf("%s protocol %q is not a versioned /namespace/name/semver id", name, id)
		}
	}

	if ChatProtocol != "/mknoon/chat/1.0.0" {
		t.Fatalf("ChatProtocol = %q, want /mknoon/chat/1.0.0", ChatProtocol)
	}
	if InboxProtocol != "/mknoon/inbox/1.0.0" {
		t.Fatalf("InboxProtocol = %q, want /mknoon/inbox/1.0.0", InboxProtocol)
	}
	if RendezvousProtocol != "/canvas/rendezvous/1.0.0" {
		t.Fatalf("RendezvousProtocol = %q, want /canvas/rendezvous/1.0.0", RendezvousProtocol)
	}
	if MediaProtocol != "/mknoon/media/1.0.0" {
		t.Fatalf("MediaProtocol = %q, want /mknoon/media/1.0.0", MediaProtocol)
	}
}

func TestGroupProtocolChatStreamNegotiatesCurrentVersionOnly(t *testing.T) {
	nodeA := startLocalNodeForMultiRelayTest(t)
	nodeB := startLocalNodeForMultiRelayTest(t)

	var nodeBAddrStrs []string
	for _, addr := range nodeB.Host().Addrs() {
		nodeBAddrStrs = append(nodeBAddrStrs, addr.String())
	}
	if err := nodeA.DialPeer(nodeB.PeerId(), nodeBAddrStrs); err != nil {
		t.Fatalf("DialPeer: %v", err)
	}

	targetID, err := peer.Decode(nodeB.PeerId())
	if err != nil {
		t.Fatalf("decode target peer: %v", err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()

	current, err := nodeA.Host().NewStream(ctx, targetID, ChatProtocol)
	if err != nil {
		t.Fatalf("NewStream current chat protocol: %v", err)
	}
	if current.Protocol() != ChatProtocol {
		t.Fatalf("negotiated protocol = %q, want %q", current.Protocol(), ChatProtocol)
	}
	_ = current.Reset()

	unsupported, err := nodeA.Host().NewStream(ctx, targetID, protocol.ID("/mknoon/chat/0.9.0"))
	if err == nil {
		_ = unsupported.Reset()
		t.Fatal("unsupported chat protocol opened a stream")
	}
}

func TestSecureLibp2pChannelRequiredBeforeMknoonProtocols(t *testing.T) {
	secureNode := startLocalNodeForMultiRelayTest(t)

	insecureHost, err := libp2p.New(
		libp2p.NoSecurity,
		libp2p.ListenAddrStrings("/ip4/127.0.0.1/tcp/0"),
	)
	if err != nil {
		t.Fatalf("start insecure host: %v", err)
	}
	defer insecureHost.Close()

	targetID, err := peer.Decode(secureNode.PeerId())
	if err != nil {
		t.Fatalf("decode target peer: %v", err)
	}

	rawTCPAddrs := secureNode.Host().Addrs()[:0]
	for _, addr := range secureNode.Host().Addrs() {
		addrString := addr.String()
		if strings.Contains(addrString, "/tcp/") && !strings.Contains(addrString, "/ws") {
			rawTCPAddrs = append(rawTCPAddrs, addr)
		}
	}
	if len(rawTCPAddrs) == 0 {
		t.Fatal("secure mknoon node did not expose a raw TCP address for security negotiation proof")
	}
	addrInfo := peer.AddrInfo{
		ID:    targetID,
		Addrs: rawTCPAddrs,
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	if err := insecureHost.Connect(ctx, addrInfo); err == nil {
		t.Fatal("insecure libp2p host connected to secure mknoon node")
	}
	if got := insecureHost.Network().Connectedness(targetID); got == network.Connected {
		t.Fatal("insecure libp2p host stayed connected to secure mknoon node")
	}
	if got := secureNode.Host().Network().Connectedness(insecureHost.ID()); got == network.Connected {
		t.Fatal("secure mknoon node retained an insecure peer connection")
	}

	stream, err := insecureHost.NewStream(ctx, targetID, ChatProtocol)
	if err == nil {
		_ = stream.Reset()
		t.Fatal("insecure libp2p host opened mknoon chat protocol stream")
	}
}

func TestGroupProtocolInboxStoreUsesVersionedInboxProtocol(t *testing.T) {
	relayHost, err := libp2p.New(libp2p.ListenAddrStrings("/ip4/127.0.0.1/tcp/0"))
	if err != nil {
		t.Fatalf("start relay host: %v", err)
	}
	defer relayHost.Close()

	requestSeen := make(chan groupInboxRequest, 1)
	protocolSeen := make(chan protocol.ID, 1)
	relayHost.SetStreamHandler(InboxProtocol, func(s network.Stream) {
		defer s.Close()
		protocolSeen <- s.Protocol()

		reqBytes, err := readFrame(s)
		if err != nil {
			return
		}
		var req groupInboxRequest
		if err := json.Unmarshal(reqBytes, &req); err != nil {
			return
		}
		requestSeen <- req

		_ = writeFrame(s, []byte(`{"status":"OK"}`))
	})

	relayAddr := relayHost.Addrs()[0].String() + "/p2p/" + relayHost.ID().String()
	n := startLocalNodeForMultiRelayTest(t)
	n.relayAddresses = []string{relayAddr}

	if err := n.GroupInboxStore(
		"group-protocol-inbox",
		`{"version":"3","encrypted":{"ciphertext":"ct","nonce":"nonce"}}`,
		[]string{"peer-reader"},
		"Safe preview title",
		"Safe preview body",
	); err != nil {
		t.Fatalf("GroupInboxStore: %v", err)
	}

	select {
	case got := <-protocolSeen:
		if got != InboxProtocol {
			t.Fatalf("stream protocol = %q, want %q", got, InboxProtocol)
		}
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for inbox protocol stream")
	}

	select {
	case req := <-requestSeen:
		if req.Action != "group_store" {
			t.Fatalf("action = %q, want group_store", req.Action)
		}
		if req.GroupId != "group-protocol-inbox" {
			t.Fatalf("groupId = %q, want group-protocol-inbox", req.GroupId)
		}
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for group inbox request")
	}
}
