package node

// FDC-15 — 1:1 media over a peer-authenticated libp2p LAN stream.
//
// RED catalog (TL1-TL11, incl. TL5b). Go-unit, host-runnable: TL3/TL5b use the
// FDC-S2 M1 two-host QUIC loopback shape (two real Nodes connected over
// 127.0.0.1/quic-v1 so the receiver's handleIncomingLANMedia + emitEvent fire
// into a testEventCollector). TL5/TL5b's circuit-vs-direct gate is unit-tested
// at the firstNonCircuitConn selector with stub conns (a real /p2p-circuit
// loopback conn is not constructible host-side; see Accepted Differences in the
// plan). The live two-phone transfer is the device-only closure gate (D1).
//
// Run under GOTOOLCHAIN=go1.25.0 (quic-go panics under Go 1.26.x).

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	ma "github.com/multiformats/go-multiaddr"
)

// --- harness ---------------------------------------------------------------

func lanMediaNodeConfig(t *testing.T, key string, mediaFlagOn bool) NodeConfig {
	t.Helper()
	flags := DefaultFeatureFlags()
	flags.EnableLibp2pLANMedia = mediaFlagOn
	return NodeConfig{
		PrivateKeyHex:  key,
		RelayAddresses: []string{},
		AutoRegister:   false,
		FeatureFlags:   &flags,
	}
}

// startLANMediaNode boots a relay-less Node with the FDC-15 media flag set, so
// the MediaLANProtocol handler is (or is not) registered per mediaFlagOn.
func startLANMediaNode(t *testing.T, collector *testEventCollector, mediaFlagOn bool) *Node {
	t.Helper()
	n := New(collector)
	if _, err := n.Start(lanMediaNodeConfig(t, generateTestKey(t), mediaFlagOn)); err != nil {
		t.Fatalf("start LAN-media node: %v", err)
	}
	t.Cleanup(func() { _ = n.Stop() })
	return n
}

// lanLoopbackQUICAddr returns the host's concrete 127.0.0.1 quic-v1 listen addr
// (InterfaceListenAddresses expands the production 0.0.0.0 bind to loopback).
func lanLoopbackQUICAddr(t *testing.T, h host.Host) ma.Multiaddr {
	t.Helper()
	addrs, err := h.Network().InterfaceListenAddresses()
	if err != nil {
		t.Fatalf("interface listen addrs: %v", err)
	}
	for _, a := range addrs {
		s := a.String()
		if strings.Contains(s, "127.0.0.1") && strings.Contains(s, "/quic-v1") {
			return a
		}
	}
	t.Fatalf("no loopback quic addr among %v", addrs)
	return nil
}

// dialDirect connects nodeA -> nodeB over loopback QUIC and returns nodeB's id.
func dialDirect(t *testing.T, nodeA, nodeB *Node) peer.ID {
	t.Helper()
	bid := nodeB.Host().ID()
	addr := lanLoopbackQUICAddr(t, nodeB.Host())
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := nodeA.Host().Connect(ctx, peer.AddrInfo{ID: bid, Addrs: []ma.Multiaddr{addr}}); err != nil {
		t.Fatalf("connect A->B: %v", err)
	}
	if firstNonCircuitConn(nodeA.Host().Network().ConnsToPeer(bid)) == nil {
		t.Fatalf("expected a non-circuit conn A->B after Connect")
	}
	return bid
}

func writeTempBlob(t *testing.T, data []byte) string {
	t.Helper()
	p := filepath.Join(t.TempDir(), "blob.bin")
	if err := os.WriteFile(p, data, 0o600); err != nil {
		t.Fatalf("write temp blob: %v", err)
	}
	return p
}

func sha256Hex(b []byte) string {
	sum := sha256.Sum256(b)
	return hex.EncodeToString(sum[:])
}

func hostHasProtocol(h host.Host, p string) bool {
	for _, pid := range h.Mux().Protocols() {
		if string(pid) == p {
			return true
		}
	}
	return false
}

// --- TL1 -------------------------------------------------------------------

func TestMediaLANProtocol_Id(t *testing.T) {
	if MediaLANProtocol != "/mknoon/media-lan/1.0.0" {
		t.Fatalf("MediaLANProtocol = %q, want /mknoon/media-lan/1.0.0", MediaLANProtocol)
	}
	// Distinctness: the relay-CDN MediaProtocol must NOT have been reused.
	if MediaLANProtocol == MediaProtocol {
		t.Fatalf("MediaLANProtocol must differ from the relay MediaProtocol %q", MediaProtocol)
	}
}

// --- TL2 -------------------------------------------------------------------

func TestStart_RegistersMediaLANHandler_FlagGated(t *testing.T) {
	on := startLANMediaNode(t, &testEventCollector{}, true)
	if !hostHasProtocol(on.Host(), MediaLANProtocol) {
		t.Fatalf("flag ON: host should register %s", MediaLANProtocol)
	}

	off := startLANMediaNode(t, &testEventCollector{}, false)
	if hostHasProtocol(off.Host(), MediaLANProtocol) {
		t.Fatalf("flag OFF: host must NOT register %s", MediaLANProtocol)
	}
	// Baseline preserved: the node otherwise starts normally with chat handler.
	if !hostHasProtocol(off.Host(), ChatProtocol) {
		t.Fatalf("flag OFF node should still register the chat handler")
	}
}

// --- TL3 + TL6 + TL11 ------------------------------------------------------

func TestSendLANMedia_DirectConn_StagesAndVerifies(t *testing.T) {
	collectorB := &testEventCollector{}
	nodeA := startLANMediaNode(t, &testEventCollector{}, true)
	nodeB := startLANMediaNode(t, collectorB, true)
	bid := dialDirect(t, nodeA, nodeB)

	blob := []byte("FDC-15 ciphertext blob — opaque encrypted bytes 0123456789")
	blobPath := writeTempBlob(t, blob)
	shaHex := sha256Hex(blob)

	res, err := nodeA.SendLANMedia(
		bid, blobPath, "media-1",
		nodeA.Host().ID().String(), bid.String(),
		"application/octet-stream", shaHex, "blob-aes-gcm-v1", true, 1500,
	)
	if err != nil {
		t.Fatalf("SendLANMedia: %v", err)
	}
	if !res.Acked || !res.Sha256Verified {
		t.Fatalf("expected acked+verified, got %+v", res)
	}
	if res.Transport != "direct" { // TL6 — label contract on the send side
		t.Fatalf("res.Transport = %q, want direct", res.Transport)
	}

	data := waitForCollectedEvent(t, collectorB, "media:lan_received", 5*time.Second)

	// TL3 discriminator: a staged temp file of exactly len(blob) bytes whose
	// recomputed sha256 == the sent sha256 (not merely "ack returned").
	staged, _ := data["localPath"].(string)
	if staged == "" {
		t.Fatalf("media:lan_received missing localPath: %+v", data)
	}
	got, err := os.ReadFile(staged)
	if err != nil {
		t.Fatalf("read staged file %q: %v", staged, err)
	}
	if len(got) != len(blob) {
		t.Fatalf("staged file size = %d, want %d", len(got), len(blob))
	}
	if sha256Hex(got) != shaHex {
		t.Fatalf("staged file sha256 mismatch")
	}

	// TL11 — full render payload (the receive consumer needs every field).
	if data["id"] != "media-1" {
		t.Fatalf("payload id = %v, want media-1", data["id"])
	}
	if data["from"] != nodeA.Host().ID().String() {
		t.Fatalf("payload from = %v", data["from"])
	}
	if data["sha256"] != shaHex {
		t.Fatalf("payload sha256 = %v", data["sha256"])
	}
	if data["enc"] != true {
		t.Fatalf("payload enc = %v, want true", data["enc"])
	}
	if data["encScheme"] != "blob-aes-gcm-v1" {
		t.Fatalf("payload encScheme = %v", data["encScheme"])
	}
	if data["mime"] != "application/octet-stream" {
		t.Fatalf("payload mime = %v", data["mime"])
	}
	if data["transport"] != "direct" { // TL6 — label on the receive side
		t.Fatalf("payload transport = %v, want direct", data["transport"])
	}
}

// --- TL4 -------------------------------------------------------------------

func TestSendLANMedia_Sha256Mismatch_Rejected(t *testing.T) {
	collectorB := &testEventCollector{}
	nodeA := startLANMediaNode(t, &testEventCollector{}, true)
	nodeB := startLANMediaNode(t, collectorB, true)
	bid := dialDirect(t, nodeA, nodeB)

	blob := []byte("the bytes that will actually be streamed")
	blobPath := writeTempBlob(t, blob)
	wrongSha := sha256Hex([]byte("a different payload — header lies about the hash"))

	res, err := nodeA.SendLANMedia(
		bid, blobPath, "media-bad",
		nodeA.Host().ID().String(), bid.String(),
		"application/octet-stream", wrongSha, "blob-aes-gcm-v1", true, 0,
	)
	if err != nil {
		t.Fatalf("SendLANMedia (mismatch path) returned transport error: %v", err)
	}
	if res.Acked || res.Sha256Verified {
		t.Fatalf("mismatch must NOT be acked/verified, got %+v", res)
	}
	// No media:lan_received for the bad id, and no staged file left behind.
	time.Sleep(300 * time.Millisecond)
	if got := collectorB.collectEvents("media:lan_received"); len(got) != 0 {
		t.Fatalf("expected 0 media:lan_received on mismatch, got %d", len(got))
	}
}

// --- TL5 + TL5b (selector unit) --------------------------------------------

func TestFirstNonCircuitConn_GateSemantics(t *testing.T) {
	circuit := &stubStreamConn{remoteMultiaddr: psCircuitAddr(t)}
	direct := &stubStreamConn{remoteMultiaddr: psQuicAddr(t)}

	// (a) only a circuit conn -> nil (refuse).
	if firstNonCircuitConn([]network.Conn{circuit}) != nil {
		t.Fatalf("(a) circuit-only must yield no direct conn")
	}
	// (b) only a direct conn -> that conn.
	if got := firstNonCircuitConn([]network.Conn{direct}); got != network.Conn(direct) {
		t.Fatalf("(b) direct-only must yield the direct conn, got %v", got)
	}
	// (c) circuit AND direct coexist -> the DIRECT conn (TL5b: NOT a !hasCircuitConn negation).
	if got := firstNonCircuitConn([]network.Conn{circuit, direct}); got != network.Conn(direct) {
		t.Fatalf("(c) coexisting circuit+direct must send over the direct conn, got %v", got)
	}
	// (d) no conns -> nil.
	if firstNonCircuitConn(nil) != nil {
		t.Fatalf("(d) no conns must yield nil")
	}
}

func TestSendLANMedia_RefusesWhenNoDirectConn(t *testing.T) {
	nodeA := startLANMediaNode(t, &testEventCollector{}, true)
	// A peer id we are NOT connected to at all (no non-circuit conn).
	stranger := generatePeerIDStr(t)
	pid, err := peer.Decode(stranger)
	if err != nil {
		t.Fatalf("decode: %v", err)
	}
	blobPath := writeTempBlob(t, []byte("never streamed"))

	_, err = nodeA.SendLANMedia(
		pid, blobPath, "media-x",
		nodeA.Host().ID().String(), stranger,
		"application/octet-stream", sha256Hex([]byte("never streamed")), "", false, 0,
	)
	if err == nil {
		t.Fatalf("expected errMediaLANRequiresDirect when no direct conn exists")
	}
	if !errors.Is(err, errMediaLANRequiresDirect) {
		t.Fatalf("err = %v, want errMediaLANRequiresDirect", err)
	}
}

// --- TL7 (serial dedup) ----------------------------------------------------

func TestHandleIncomingLANMedia_DedupesDuplicateId(t *testing.T) {
	collectorB := &testEventCollector{}
	nodeA := startLANMediaNode(t, &testEventCollector{}, true)
	nodeB := startLANMediaNode(t, collectorB, true)
	bid := dialDirect(t, nodeA, nodeB)

	blob := []byte("dup-id blob")
	blobPath := writeTempBlob(t, blob)
	shaHex := sha256Hex(blob)
	send := func() (LANMediaSendResult, error) {
		return nodeA.SendLANMedia(
			bid, blobPath, "dup-1",
			nodeA.Host().ID().String(), bid.String(),
			"application/octet-stream", shaHex, "blob-aes-gcm-v1", true, 0,
		)
	}

	res1, err := send()
	if err != nil || !res1.Acked {
		t.Fatalf("first delivery should ack: res=%+v err=%v", res1, err)
	}
	waitForCollectedEvent(t, collectorB, "media:lan_received", 5*time.Second)

	res2, _ := send()
	if res2.Acked {
		t.Fatalf("second (duplicate id) delivery must NOT be acked, got %+v", res2)
	}
	time.Sleep(300 * time.Millisecond)
	if got := collectorB.collectEvents("media:lan_received"); len(got) != 1 {
		t.Fatalf("expected exactly 1 media:lan_received for the id, got %d", len(got))
	}
}

// --- TL8 (Stop resets dedup map) -------------------------------------------

func TestStop_ResetsLanMediaSeenIds(t *testing.T) {
	key := generateTestKey(t)
	n := New(&testEventCollector{})
	if _, err := n.Start(lanMediaNodeConfig(t, key, true)); err != nil {
		t.Fatalf("start: %v", err)
	}
	t.Cleanup(func() { _ = n.Stop() })

	if !n.claimLANMediaID("X") {
		t.Fatalf("first claim of X should succeed")
	}
	if n.claimLANMediaID("X") {
		t.Fatalf("second claim of X should fail (seen) before Stop")
	}

	if err := n.Stop(); err != nil {
		t.Fatalf("stop: %v", err)
	}
	if _, err := n.Start(lanMediaNodeConfig(t, key, true)); err != nil {
		t.Fatalf("restart: %v", err)
	}

	if !n.claimLANMediaID("X") {
		t.Fatalf("after Stop/Start, claim of X must succeed again (dedup map reset)")
	}
}

// --- TL9 (concurrent dedup, -race) -----------------------------------------

func TestHandleIncomingLANMedia_ConcurrentDuplicateId_RaceClean(t *testing.T) {
	collectorB := &testEventCollector{}
	nodeA := startLANMediaNode(t, &testEventCollector{}, true)
	nodeB := startLANMediaNode(t, collectorB, true)
	bid := dialDirect(t, nodeA, nodeB)

	blob := []byte("race blob")
	blobPath := writeTempBlob(t, blob)
	shaHex := sha256Hex(blob)

	var wg sync.WaitGroup
	for i := 0; i < 2; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			// Errors are tolerated on the losing goroutine (its stream is reset
			// by the receiver's duplicate-reject); the invariant under test is
			// exactly-one emit + a clean -race on the shared dedup map.
			_, _ = nodeA.SendLANMedia(
				bid, blobPath, "race-1",
				nodeA.Host().ID().String(), bid.String(),
				"application/octet-stream", shaHex, "blob-aes-gcm-v1", true, 0,
			)
		}()
	}
	wg.Wait()

	waitForCollectedEvent(t, collectorB, "media:lan_received", 5*time.Second)
	time.Sleep(300 * time.Millisecond)
	if got := collectorB.collectEvents("media:lan_received"); len(got) != 1 {
		t.Fatalf("expected exactly 1 media:lan_received under concurrency, got %d", len(got))
	}
}

// --- TL10 (oversize header rejected before CopyN) --------------------------

func TestHandleIncomingLANMedia_OversizeHeader_RejectedBeforeCopy(t *testing.T) {
	collectorB := &testEventCollector{}
	nodeA := startLANMediaNode(t, &testEventCollector{}, true)
	nodeB := startLANMediaNode(t, collectorB, true)
	bid := dialDirect(t, nodeA, nodeB)

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	s, err := nodeA.Host().NewStream(ctx, bid, MediaLANProtocol)
	if err != nil {
		t.Fatalf("open media-lan stream: %v", err)
	}
	defer s.Close()

	// A framed header claiming a body larger than MaxLANMediaBytes — the handler
	// must reject BEFORE allocating/streaming the body (no temp file, no CopyN).
	hdr := map[string]interface{}{
		"id":     "oversize-1",
		"from":   nodeA.Host().ID().String(),
		"to":     bid.String(),
		"mime":   "application/octet-stream",
		"size":   MaxLANMediaBytes + 1,
		"sha256": sha256Hex([]byte("x")),
		"enc":    true,
	}
	hdrBytes, _ := json.Marshal(hdr)
	if err := writeFrame(s, hdrBytes); err != nil {
		t.Fatalf("write header: %v", err)
	}

	// Two-phase: the receiver rejects at the PRE-BODY decision frame, so the body
	// is never requested (no os.CreateTemp, no io.CopyN).
	decBytes, err := readFrame(s)
	if err != nil {
		t.Fatalf("read decision: %v", err)
	}
	var dec map[string]interface{}
	if err := json.Unmarshal(decBytes, &dec); err != nil {
		t.Fatalf("bad decision json: %v", err)
	}
	if dec["proceed"] == true {
		t.Fatalf("oversize header must be rejected pre-body, got decision=%+v", dec)
	}
	if dec["reason"] != "size_exceeds_max" {
		t.Fatalf("decision reason = %v, want size_exceeds_max", dec["reason"])
	}
	time.Sleep(200 * time.Millisecond)
	if got := collectorB.collectEvents("media:lan_received"); len(got) != 0 {
		t.Fatalf("oversize header must not emit media:lan_received, got %d", len(got))
	}
}
