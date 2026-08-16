package bridge

import (
	"crypto/rand"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"sync"
	"testing"

	"github.com/libp2p/go-libp2p"
	libp2pcrypto "github.com/libp2p/go-libp2p/core/crypto"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	ma "github.com/multiformats/go-multiaddr"

	"github.com/mknoon/go-mknoon/node"
)

func TestNSEInboxBridgeRejectsIdentityMismatchAndDoesNotUseSingleton(t *testing.T) {
	privateKeyA, _ := nseBridgeTestIdentity(t)
	_, peerB := nseBridgeTestIdentity(t)
	relay := startNSEBridgeTestRelay(t, func(map[string]interface{}, peer.ID) map[string]interface{} {
		return map[string]interface{}{"status": "NO_MESSAGES", "messages": []interface{}{}, "hasMore": false}
	})

	poisonSingleton := node.NewNode()
	nodeMu.Lock()
	previousSingleton := singletonNode
	singletonNode = poisonSingleton
	nodeMu.Unlock()
	t.Cleanup(func() {
		nodeMu.Lock()
		singletonNode = previousSingleton
		nodeMu.Unlock()
	})

	response := decodeWakeOutcomeBridgeTestResponse(t, NSEInboxRetrievePending(nseBridgeParamsJSON(t,
		privateKeyA,
		peerB,
		[]string{relay.addr(t)},
		250,
	)))
	if response["ok"] != false || response["errorCode"] != "IDENTITY_MISMATCH" ||
		response["errorMessage"] != nseInboxIdentityMismatchMessage {
		t.Fatalf("identity-mismatch response = %#v", response)
	}
	nodeMu.Lock()
	gotSingleton := singletonNode
	nodeMu.Unlock()
	if gotSingleton != poisonSingleton {
		t.Fatal("NSE export replaced or mutated the process-global singleton owner")
	}
	if requests := relay.snapshotRequests(); len(requests) != 0 {
		t.Fatalf("identity mismatch reached relay before rejection: %#v", requests)
	}
}

func TestNSEInboxBridgeReturnsStrictBoundedPage(t *testing.T) {
	privateKey, transportPeer := nseBridgeTestIdentity(t)
	relay := startNSEBridgeTestRelay(t, func(request map[string]interface{}, remote peer.ID) map[string]interface{} {
		if remote.String() != transportPeer {
			return map[string]interface{}{"status": "ERROR", "error": "wrong physical mailbox"}
		}
		return map[string]interface{}{
			"status":          "OK",
			"messages":        []map[string]interface{}{{"id": "entry-1", "from": "sender", "message": "cipher", "timestamp": 11}},
			"hasMore":         false,
			"custodyContract": node.AckOrExpiryCustodyContract,
		}
	})

	nodeMu.Lock()
	previousSingleton := singletonNode
	singletonNode = nil
	nodeMu.Unlock()
	t.Cleanup(func() {
		nodeMu.Lock()
		singletonNode = previousSingleton
		nodeMu.Unlock()
	})

	response := decodeWakeOutcomeBridgeTestResponse(t, NSEInboxRetrievePending(nseBridgeParamsJSON(t,
		privateKey,
		transportPeer,
		[]string{relay.addr(t)},
		800,
	)))
	if response["ok"] != true || response["hasMore"] != false ||
		response["custodyContract"] != node.AckOrExpiryCustodyContract {
		t.Fatalf("strict bounded response = %#v", response)
	}
	messages, ok := response["messages"].([]interface{})
	if !ok || len(messages) != 1 {
		t.Fatalf("bounded response messages = %#v", response["messages"])
	}
	requests := relay.snapshotRequests()
	if len(requests) != 1 || requests[0]["action"] != "retrieve_custody_pending_v1" ||
		requests[0]["limit"] != float64(1) ||
		requests[0]["custodyContract"] != node.AckOrExpiryCustodyContract {
		t.Fatalf("strict one-shot request = %#v", requests)
	}
}

type nseBridgeTestRelay struct {
	host host.Host

	mu       sync.Mutex
	requests []map[string]interface{}
}

func startNSEBridgeTestRelay(
	t *testing.T,
	reply func(map[string]interface{}, peer.ID) map[string]interface{},
) *nseBridgeTestRelay {
	t.Helper()
	h, err := libp2p.New(libp2p.ListenAddrStrings("/ip4/127.0.0.1/tcp/0"))
	if err != nil {
		t.Fatalf("libp2p.New: %v", err)
	}
	relay := &nseBridgeTestRelay{host: h}
	h.SetStreamHandler(node.InboxProtocol, func(stream network.Stream) {
		defer stream.Close()
		raw, readErr := nseBridgeReadFrame(stream)
		if readErr != nil {
			return
		}
		var request map[string]interface{}
		if json.Unmarshal(raw, &request) != nil {
			return
		}
		relay.mu.Lock()
		relay.requests = append(relay.requests, request)
		relay.mu.Unlock()
		response, marshalErr := json.Marshal(reply(request, stream.Conn().RemotePeer()))
		if marshalErr == nil {
			_ = nseBridgeWriteFrame(stream, response)
		}
	})
	t.Cleanup(func() {
		if closeErr := h.Close(); closeErr != nil {
			t.Errorf("relay.Close: %v", closeErr)
		}
	})
	return relay
}

func (r *nseBridgeTestRelay) addr(t *testing.T) string {
	t.Helper()
	peerComponent, err := ma.NewMultiaddr(fmt.Sprintf("/p2p/%s", r.host.ID()))
	if err != nil {
		t.Fatalf("relay peer multiaddr: %v", err)
	}
	return r.host.Addrs()[0].Encapsulate(peerComponent).String()
}

func (r *nseBridgeTestRelay) snapshotRequests() []map[string]interface{} {
	r.mu.Lock()
	defer r.mu.Unlock()
	return append([]map[string]interface{}(nil), r.requests...)
}

func nseBridgeTestIdentity(t *testing.T) ([]byte, string) {
	t.Helper()
	privateKey, _, err := libp2pcrypto.GenerateEd25519Key(rand.Reader)
	if err != nil {
		t.Fatalf("GenerateEd25519Key: %v", err)
	}
	raw, err := privateKey.Raw()
	if err != nil {
		t.Fatalf("privateKey.Raw: %v", err)
	}
	transportPeer, err := peer.IDFromPrivateKey(privateKey)
	if err != nil {
		t.Fatalf("IDFromPrivateKey: %v", err)
	}
	return raw, transportPeer.String()
}

func nseBridgeParamsJSON(
	t *testing.T,
	privateKey []byte,
	expectedPeer string,
	relayMultiaddrs []string,
	timeoutMs int,
) string {
	t.Helper()
	raw, err := json.Marshal(map[string]interface{}{
		"transportPrivateKeyBase64": base64.StdEncoding.EncodeToString(privateKey),
		"expectedTransportPeerId":   expectedPeer,
		"relayMultiaddrs":           relayMultiaddrs,
		"timeoutMs":                 timeoutMs,
	})
	if err != nil {
		t.Fatalf("marshal NSE bridge params: %v", err)
	}
	return string(raw)
}

func nseBridgeReadFrame(reader io.Reader) ([]byte, error) {
	var length [4]byte
	if _, err := io.ReadFull(reader, length[:]); err != nil {
		return nil, err
	}
	payload := make([]byte, binary.BigEndian.Uint32(length[:]))
	_, err := io.ReadFull(reader, payload)
	return payload, err
}

func nseBridgeWriteFrame(writer io.Writer, payload []byte) error {
	var length [4]byte
	binary.BigEndian.PutUint32(length[:], uint32(len(payload)))
	if _, err := writer.Write(length[:]); err != nil {
		return err
	}
	_, err := writer.Write(payload)
	return err
}
