//go:build integration

package integration_test

import (
	"crypto/rand"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"sync"
	"testing"
	"time"

	"github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p/core/crypto"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/core/record"
	"github.com/libp2p/go-msgio"
	"github.com/mknoon/go-mknoon/node"
	"google.golang.org/protobuf/encoding/protowire"
)

const localRelayFrameLimit = 128 * 1024

type localRelayRegistration struct {
	signedPeerRecord []byte
	expiresAt        time.Time
}

type localRelayInboxMessage struct {
	From      string `json:"from"`
	Message   string `json:"message"`
	Timestamp int64  `json:"timestamp"`
}

type localRelaySharedState struct {
	mu         sync.Mutex
	rendezvous map[string]map[string]localRelayRegistration
	inbox      map[string][]localRelayInboxMessage
}

func newLocalRelaySharedState() *localRelaySharedState {
	return &localRelaySharedState{
		rendezvous: make(map[string]map[string]localRelayRegistration),
		inbox:      make(map[string][]localRelayInboxMessage),
	}
}

func (s *localRelaySharedState) register(namespace, peerID string, signedPeerRecord []byte, ttlSeconds uint64) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if ttlSeconds == 0 {
		ttlSeconds = 7200
	}
	if s.rendezvous[namespace] == nil {
		s.rendezvous[namespace] = make(map[string]localRelayRegistration)
	}
	s.rendezvous[namespace][peerID] = localRelayRegistration{
		signedPeerRecord: append([]byte(nil), signedPeerRecord...),
		expiresAt:        time.Now().Add(time.Duration(ttlSeconds) * time.Second),
	}
}

func (s *localRelaySharedState) unregister(namespace, peerID string) {
	s.mu.Lock()
	defer s.mu.Unlock()

	peers := s.rendezvous[namespace]
	if peers == nil {
		return
	}
	delete(peers, peerID)
	if len(peers) == 0 {
		delete(s.rendezvous, namespace)
	}
}

func (s *localRelaySharedState) discover(namespace, requester string, limit int) [][]byte {
	s.mu.Lock()
	defer s.mu.Unlock()

	now := time.Now()
	var records [][]byte
	peers := s.rendezvous[namespace]
	for peerID, reg := range peers {
		if requester != "" && peerID == requester {
			continue
		}
		if !reg.expiresAt.IsZero() && now.After(reg.expiresAt) {
			delete(peers, peerID)
			continue
		}
		records = append(records, append([]byte(nil), reg.signedPeerRecord...))
		if limit > 0 && len(records) >= limit {
			break
		}
	}
	if len(peers) == 0 {
		delete(s.rendezvous, namespace)
	}
	return records
}

func (s *localRelaySharedState) storeInbox(toPeerID string, message localRelayInboxMessage) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.inbox[toPeerID] = append(s.inbox[toPeerID], message)
}

func (s *localRelaySharedState) retrieveInbox(peerID string, limit int) ([]localRelayInboxMessage, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()

	queue := s.inbox[peerID]
	if len(queue) == 0 {
		return nil, false
	}
	if limit <= 0 || limit > len(queue) {
		limit = len(queue)
	}
	page := append([]localRelayInboxMessage(nil), queue[:limit]...)
	remaining := append([]localRelayInboxMessage(nil), queue[limit:]...)
	if len(remaining) == 0 {
		delete(s.inbox, peerID)
	} else {
		s.inbox[peerID] = remaining
	}
	return page, len(remaining) > 0
}

type localRelayServer struct {
	t         *testing.T
	state     *localRelaySharedState
	privKey   crypto.PrivKey
	peerID    peer.ID
	tcpPort   int
	host      host.Host
	started   bool
	startStop sync.Mutex
}

func newLocalRelayServer(t *testing.T, state *localRelaySharedState) *localRelayServer {
	t.Helper()

	privKey, _, err := crypto.GenerateEd25519Key(rand.Reader)
	if err != nil {
		t.Fatalf("GenerateEd25519Key(): %v", err)
	}
	peerID, err := peer.IDFromPrivateKey(privKey)
	if err != nil {
		t.Fatalf("IDFromPrivateKey(): %v", err)
	}

	return &localRelayServer{
		t:       t,
		state:   state,
		privKey: privKey,
		peerID:  peerID,
		tcpPort: reserveLocalTCPPort(t),
	}
}

func (s *localRelayServer) start() {
	s.t.Helper()

	s.startStop.Lock()
	defer s.startStop.Unlock()

	if s.started {
		return
	}

	h, err := libp2p.New(
		libp2p.Identity(s.privKey),
		libp2p.ListenAddrStrings(fmt.Sprintf("/ip4/127.0.0.1/tcp/%d", s.tcpPort)),
		libp2p.EnableRelayService(),
		libp2p.ForceReachabilityPublic(),
	)
	if err != nil {
		s.t.Fatalf("libp2p.New(relay %s): %v", s.peerID, err)
	}

	h.SetStreamHandler(node.RendezvousProtocol, s.handleRendezvousStream)
	h.SetStreamHandler(node.InboxProtocol, s.handleInboxStream)

	s.host = h
	s.started = true
}

func (s *localRelayServer) stop() {
	s.t.Helper()

	s.startStop.Lock()
	defer s.startStop.Unlock()

	if !s.started || s.host == nil {
		return
	}
	if err := s.host.Close(); err != nil {
		s.t.Fatalf("relay.Close(%s): %v", s.peerID, err)
	}
	s.host = nil
	s.started = false

	// Give the OS and the remote peers a moment to observe the close.
	time.Sleep(300 * time.Millisecond)
}

func (s *localRelayServer) restart() {
	s.stop()
	s.start()
}

func (s *localRelayServer) addr() string {
	return fmt.Sprintf("/ip4/127.0.0.1/tcp/%d/p2p/%s", s.tcpPort, s.peerID)
}

func startLocalRelayPair(t *testing.T) (*localRelayServer, *localRelayServer) {
	t.Helper()

	shared := newLocalRelaySharedState()
	relayA := newLocalRelayServer(t, shared)
	relayB := newLocalRelayServer(t, shared)
	relayA.start()
	relayB.start()

	t.Cleanup(func() {
		relayA.stop()
		relayB.stop()
	})

	return relayA, relayB
}

func startNodeWithRelays(
	t *testing.T,
	relayAddrs []string,
	cb node.EventCallback,
	flags *node.FeatureFlags,
) (*node.Node, string) {
	t.Helper()

	privHex, expectedPeerID := generatePrivateKeyHex(t)

	var n *node.Node
	if cb != nil {
		n = node.New(cb)
	} else {
		n = node.NewNode()
	}

	cfg := node.NodeConfig{
		PrivateKeyHex:  privHex,
		RelayAddresses: append([]string(nil), relayAddrs...),
		ListenPort:     0,
		FeatureFlags:   flags,
	}

	state, err := n.Start(cfg)
	if err != nil {
		t.Fatalf("node.Start(): %v", err)
	}

	if state.PeerId != expectedPeerID {
		t.Fatalf("peerId mismatch: got %s, want %s", state.PeerId, expectedPeerID)
	}

	t.Cleanup(func() {
		if err := n.Stop(); err != nil {
			t.Errorf("node.Stop(): %v", err)
		}
	})

	if err := n.WaitForRelayConnection(20 * time.Second); err != nil {
		t.Fatalf("WaitForRelayConnection(): %v", err)
	}

	return n, state.PeerId
}

func waitForNodeStatus(t *testing.T, n *node.Node, timeout time.Duration, predicate func(map[string]interface{}) bool) map[string]interface{} {
	t.Helper()

	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		status := n.Status()
		if predicate(status) {
			return status
		}
		time.Sleep(250 * time.Millisecond)
	}
	finalStatus := n.Status()
	t.Fatalf("status predicate not satisfied within %v: %+v", timeout, finalStatus)
	return nil
}

func reserveLocalTCPPort(t *testing.T) int {
	t.Helper()

	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("reserveLocalTCPPort(): %v", err)
	}
	defer ln.Close()
	return ln.Addr().(*net.TCPAddr).Port
}

type testRegister struct {
	Namespace        string
	SignedPeerRecord []byte
	TTL              uint64
}

type testDiscover struct {
	Namespace string
	Limit     uint64
}

type testUnregister struct {
	Namespace string
}

type testRzMessage struct {
	Type       uint64
	Register   *testRegister
	Discover   *testDiscover
	Unregister *testUnregister
}

func (s *localRelayServer) handleRendezvousStream(stream network.Stream) {
	defer stream.Close()

	reader := msgio.NewVarintReaderSize(stream, 1<<20)
	msgBytes, err := reader.ReadMsg()
	if err != nil {
		return
	}
	defer reader.ReleaseMsg(msgBytes)

	req, err := unmarshalTestRzMessage(msgBytes)
	if err != nil {
		return
	}

	remotePeer := stream.Conn().RemotePeer().String()

	switch req.Type {
	case 0: // REGISTER
		if req.Register == nil {
			return
		}
		if _, err := record.UnmarshalEnvelope(req.Register.SignedPeerRecord); err != nil {
			_ = writeVarintMessage(stream, marshalRegisterResponseMessage(101, err.Error(), 0))
			return
		}
		s.state.register(remotePeerNamespace(req.Register.Namespace), remotePeer, req.Register.SignedPeerRecord, req.Register.TTL)
		_ = writeVarintMessage(stream, marshalRegisterResponseMessage(0, "OK", req.Register.TTL))
	case 2: // UNREGISTER
		if req.Unregister == nil {
			return
		}
		s.state.unregister(remotePeerNamespace(req.Unregister.Namespace), remotePeer)
	case 3: // DISCOVER
		if req.Discover == nil {
			return
		}
		limit := int(req.Discover.Limit)
		if limit <= 0 {
			limit = 64
		}
		records := s.state.discover(remotePeerNamespace(req.Discover.Namespace), remotePeer, limit)
		_ = writeVarintMessage(stream, marshalDiscoverResponseMessage(records))
	}
}

type localInboxRequest struct {
	Action  string `json:"action"`
	To      string `json:"to,omitempty"`
	From    string `json:"from,omitempty"`
	Message string `json:"message,omitempty"`
	Limit   int    `json:"limit,omitempty"`
}

type localInboxResponse struct {
	Status   string                   `json:"status"`
	Error    string                   `json:"error,omitempty"`
	Messages []localRelayInboxMessage `json:"messages,omitempty"`
	HasMore  bool                     `json:"hasMore,omitempty"`
}

func (s *localRelayServer) handleInboxStream(stream network.Stream) {
	defer stream.Close()

	requestBytes, err := readLocalRelayFrame(stream)
	if err != nil {
		return
	}

	var req localInboxRequest
	if err := json.Unmarshal(requestBytes, &req); err != nil {
		_ = writeLocalRelayResponse(stream, localInboxResponse{Status: "ERROR", Error: "invalid JSON"})
		return
	}

	remotePeer := stream.Conn().RemotePeer().String()

	switch req.Action {
	case "store":
		if req.To == "" || req.Message == "" {
			_ = writeLocalRelayResponse(stream, localInboxResponse{Status: "ERROR", Error: "missing required fields"})
			return
		}
		from := req.From
		if from == "" {
			from = remotePeer
		}
		s.state.storeInbox(req.To, localRelayInboxMessage{
			From:      from,
			Message:   req.Message,
			Timestamp: time.Now().UnixMilli(),
		})
		_ = writeLocalRelayResponse(stream, localInboxResponse{Status: "OK"})
	case "retrieve":
		limit := req.Limit
		if limit <= 0 {
			limit = 50
		}
		messages, hasMore := s.state.retrieveInbox(remotePeer, limit)
		if len(messages) == 0 {
			_ = writeLocalRelayResponse(stream, localInboxResponse{Status: "NO_MESSAGES"})
			return
		}
		_ = writeLocalRelayResponse(stream, localInboxResponse{
			Status:   "OK",
			Messages: messages,
			HasMore:  hasMore,
		})
	default:
		_ = writeLocalRelayResponse(stream, localInboxResponse{Status: "ERROR", Error: "unsupported action"})
	}
}

func remotePeerNamespace(namespace string) string {
	return namespace
}

func readLocalRelayFrame(r io.Reader) ([]byte, error) {
	var lenBuf [4]byte
	if _, err := io.ReadFull(r, lenBuf[:]); err != nil {
		return nil, err
	}
	length := binary.BigEndian.Uint32(lenBuf[:])
	if length > localRelayFrameLimit {
		return nil, fmt.Errorf("frame too large: %d", length)
	}
	data := make([]byte, length)
	if _, err := io.ReadFull(r, data); err != nil {
		return nil, err
	}
	return data, nil
}

func writeLocalRelayFrame(w io.Writer, data []byte) error {
	if len(data) > localRelayFrameLimit {
		return fmt.Errorf("frame too large: %d", len(data))
	}
	var lenBuf [4]byte
	binary.BigEndian.PutUint32(lenBuf[:], uint32(len(data)))
	if _, err := w.Write(lenBuf[:]); err != nil {
		return err
	}
	_, err := w.Write(data)
	return err
}

func writeLocalRelayResponse(stream network.Stream, resp localInboxResponse) error {
	data, err := json.Marshal(resp)
	if err != nil {
		return err
	}
	return writeLocalRelayFrame(stream, data)
}

func writeVarintMessage(stream network.Stream, payload []byte) error {
	writer := msgio.NewVarintWriter(stream)
	return writer.WriteMsg(payload)
}

func marshalRegisterResponseMessage(status uint64, statusText string, ttl uint64) []byte {
	var sub []byte
	sub = protowire.AppendTag(sub, 1, protowire.VarintType)
	sub = protowire.AppendVarint(sub, status)
	if statusText != "" {
		sub = protowire.AppendTag(sub, 2, protowire.BytesType)
		sub = protowire.AppendString(sub, statusText)
	}
	if ttl > 0 {
		sub = protowire.AppendTag(sub, 3, protowire.VarintType)
		sub = protowire.AppendVarint(sub, ttl)
	}

	var msg []byte
	msg = protowire.AppendTag(msg, 1, protowire.VarintType)
	msg = protowire.AppendVarint(msg, 1)
	msg = protowire.AppendTag(msg, 3, protowire.BytesType)
	msg = protowire.AppendBytes(msg, sub)
	return msg
}

func marshalDiscoverResponseMessage(records [][]byte) []byte {
	var sub []byte
	sub = protowire.AppendTag(sub, 1, protowire.VarintType)
	sub = protowire.AppendVarint(sub, 0)
	sub = protowire.AppendTag(sub, 2, protowire.BytesType)
	sub = protowire.AppendString(sub, "OK")
	for _, signedPeerRecord := range records {
		reg := marshalRegistration(signedPeerRecord)
		sub = protowire.AppendTag(sub, 3, protowire.BytesType)
		sub = protowire.AppendBytes(sub, reg)
	}

	var msg []byte
	msg = protowire.AppendTag(msg, 1, protowire.VarintType)
	msg = protowire.AppendVarint(msg, 4)
	msg = protowire.AppendTag(msg, 6, protowire.BytesType)
	msg = protowire.AppendBytes(msg, sub)
	return msg
}

func marshalRegistration(signedPeerRecord []byte) []byte {
	var reg []byte
	reg = protowire.AppendTag(reg, 2, protowire.BytesType)
	reg = protowire.AppendBytes(reg, signedPeerRecord)
	return reg
}

func unmarshalTestRzMessage(data []byte) (*testRzMessage, error) {
	msg := &testRzMessage{}
	for len(data) > 0 {
		num, wtype, n := protowire.ConsumeTag(data)
		if n < 0 {
			return nil, fmt.Errorf("invalid rendezvous tag")
		}
		data = data[n:]
		switch {
		case num == 1 && wtype == protowire.VarintType:
			value, consumed := protowire.ConsumeVarint(data)
			if consumed < 0 {
				return nil, fmt.Errorf("invalid rendezvous type")
			}
			msg.Type = value
			data = data[consumed:]
		case num == 2 && wtype == protowire.BytesType:
			value, consumed := protowire.ConsumeBytes(data)
			if consumed < 0 {
				return nil, fmt.Errorf("invalid register payload")
			}
			register, err := unmarshalTestRegister(value)
			if err != nil {
				return nil, err
			}
			msg.Register = register
			data = data[consumed:]
		case num == 4 && wtype == protowire.BytesType:
			value, consumed := protowire.ConsumeBytes(data)
			if consumed < 0 {
				return nil, fmt.Errorf("invalid unregister payload")
			}
			unregister, err := unmarshalTestUnregister(value)
			if err != nil {
				return nil, err
			}
			msg.Unregister = unregister
			data = data[consumed:]
		case num == 5 && wtype == protowire.BytesType:
			value, consumed := protowire.ConsumeBytes(data)
			if consumed < 0 {
				return nil, fmt.Errorf("invalid discover payload")
			}
			discover, err := unmarshalTestDiscover(value)
			if err != nil {
				return nil, err
			}
			msg.Discover = discover
			data = data[consumed:]
		default:
			consumed := protowire.ConsumeFieldValue(num, wtype, data)
			if consumed < 0 {
				return nil, fmt.Errorf("invalid rendezvous field")
			}
			data = data[consumed:]
		}
	}
	return msg, nil
}

func unmarshalTestRegister(data []byte) (*testRegister, error) {
	register := &testRegister{}
	for len(data) > 0 {
		num, wtype, n := protowire.ConsumeTag(data)
		if n < 0 {
			return nil, fmt.Errorf("invalid register tag")
		}
		data = data[n:]
		switch {
		case num == 1 && wtype == protowire.BytesType:
			value, consumed := protowire.ConsumeString(data)
			if consumed < 0 {
				return nil, fmt.Errorf("invalid register namespace")
			}
			register.Namespace = value
			data = data[consumed:]
		case num == 2 && wtype == protowire.BytesType:
			value, consumed := protowire.ConsumeBytes(data)
			if consumed < 0 {
				return nil, fmt.Errorf("invalid register peer record")
			}
			register.SignedPeerRecord = append([]byte(nil), value...)
			data = data[consumed:]
		case num == 3 && wtype == protowire.VarintType:
			value, consumed := protowire.ConsumeVarint(data)
			if consumed < 0 {
				return nil, fmt.Errorf("invalid register ttl")
			}
			register.TTL = value
			data = data[consumed:]
		default:
			consumed := protowire.ConsumeFieldValue(num, wtype, data)
			if consumed < 0 {
				return nil, fmt.Errorf("invalid register field")
			}
			data = data[consumed:]
		}
	}
	return register, nil
}

func unmarshalTestDiscover(data []byte) (*testDiscover, error) {
	discover := &testDiscover{}
	for len(data) > 0 {
		num, wtype, n := protowire.ConsumeTag(data)
		if n < 0 {
			return nil, fmt.Errorf("invalid discover tag")
		}
		data = data[n:]
		switch {
		case num == 1 && wtype == protowire.BytesType:
			value, consumed := protowire.ConsumeString(data)
			if consumed < 0 {
				return nil, fmt.Errorf("invalid discover namespace")
			}
			discover.Namespace = value
			data = data[consumed:]
		case num == 2 && wtype == protowire.VarintType:
			value, consumed := protowire.ConsumeVarint(data)
			if consumed < 0 {
				return nil, fmt.Errorf("invalid discover limit")
			}
			discover.Limit = value
			data = data[consumed:]
		default:
			consumed := protowire.ConsumeFieldValue(num, wtype, data)
			if consumed < 0 {
				return nil, fmt.Errorf("invalid discover field")
			}
			data = data[consumed:]
		}
	}
	return discover, nil
}

func unmarshalTestUnregister(data []byte) (*testUnregister, error) {
	unregister := &testUnregister{}
	for len(data) > 0 {
		num, wtype, n := protowire.ConsumeTag(data)
		if n < 0 {
			return nil, fmt.Errorf("invalid unregister tag")
		}
		data = data[n:]
		switch {
		case num == 1 && wtype == protowire.BytesType:
			value, consumed := protowire.ConsumeString(data)
			if consumed < 0 {
				return nil, fmt.Errorf("invalid unregister namespace")
			}
			unregister.Namespace = value
			data = data[consumed:]
		default:
			consumed := protowire.ConsumeFieldValue(num, wtype, data)
			if consumed < 0 {
				return nil, fmt.Errorf("invalid unregister field")
			}
			data = data[consumed:]
		}
	}
	return unregister, nil
}
