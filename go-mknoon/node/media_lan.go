package node

// FDC-15 — 1:1 media over a peer-authenticated libp2p LAN stream.
//
// The chat envelope already rides a Noise-authenticated libp2p conn; FDC-15
// lifts the 1:1 media BYTE leg onto the SAME direct conn instead of the legacy
// plaintext ws://+HTTP-PUT LAN server. The bytes are the unchanged, app-encrypted
// EncryptedMediaArtifact ciphertext (confidentiality is unchanged — we
// re-TRANSPORT, never re-encrypt); the win is peer auth (the remote proves it
// holds the peerId's key), metadata protection (the offer header rides the
// encrypted stream), and one LAN stack.
//
// Invariants (locked by media_lan_test.go):
//   - NEW protocol id, distinct from the relay-CDN MediaProtocol (TL1).
//   - handler is flag-gated by EnableLibp2pLANMedia (TL2; registered in Start).
//   - a send streams the ciphertext + the receiver verifies SHA-256 (TL3/TL4)
//     and labels the stream "direct" (TL6).
//   - media NEVER rides a circuit/relay conn — SendLANMedia refuses unless a
//     non-circuit conn exists (TL5); a peer holding BOTH a circuit reservation
//     and a direct conn still sends over the direct (TL5b).
//   - duplicate / concurrent same-id deliveries dedup to a single render (TL7/TL9).
//   - an oversize framed header is rejected before any disk write / CopyN (TL10).
//   - the media:lan_received event carries the full LocalMediaReady render
//     payload incl. the Go-staged temp path (TL11).
//
// The relay-CDN upload stays UNCONDITIONAL on the Dart side — this lane is
// best-effort acceleration only (the durable recovery copy is the relay-CDN one).

import (
	"context"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"os"

	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
)

// errMediaLANRequiresDirect is returned by SendLANMedia when the peer has no
// non-circuit (direct) conn to stream over. Media must never ride the live relay
// socket (proposal §6.2: circuit-v2 is 2 min / 128 KB), so the send is REFUSED
// rather than downgraded onto a circuit; the relay-CDN copy + WS LAN leg backstop.
var errMediaLANRequiresDirect = fmt.Errorf("media-lan: no direct (non-circuit) conn to peer")

// lanMediaHeader is the framed JSON offer that precedes the raw ciphertext body
// on a MediaLANProtocol stream. It carries exactly the fields the Dart receive
// consumer needs to reconstruct a LocalMediaReady and stage the <canonical>.enc
// blob (metadata-minimized: opaque mime, no cleartext waveform/filename).
type lanMediaHeader struct {
	ID         string `json:"id"`
	From       string `json:"from"`
	To         string `json:"to"`
	Mime       string `json:"mime"`
	Size       int64  `json:"size"`
	Sha256     string `json:"sha256"`
	Enc        bool   `json:"enc"`
	EncScheme  string `json:"encScheme,omitempty"`
	DurationMs int    `json:"durationMs,omitempty"`
}

// lanMediaDecision is the framed JSON reply the receiver writes IMMEDIATELY
// after the header, BEFORE the body is streamed: it accepts (proceed) or rejects
// (oversize / duplicate / bad header) the offer. A pre-body reject means the
// sender never streams the (potentially multi-GB) body, so a rejected transfer
// cannot stall the sender against the QUIC flow-control window (the failure mode
// a header→body→ack single-phase protocol has).
type lanMediaDecision struct {
	Proceed bool   `json:"proceed"`
	Reason  string `json:"reason,omitempty"`
}

// lanMediaAck is the framed JSON reply the receiver writes AFTER streaming and
// verifying the body (sha256 match / transfer complete).
type lanMediaAck struct {
	OK             bool   `json:"ok"`
	Sha256Verified bool   `json:"sha256Verified"`
	Reason         string `json:"reason,omitempty"`
}

// LANMediaSendResult reports the outcome of a SendLANMedia call for the bridge
// envelope / telemetry.
type LANMediaSendResult struct {
	// Acked is true when the receiver replied ok (staged + sha256-verified).
	Acked bool
	// Sha256Verified mirrors the receiver's ack — the streamed bytes hashed to
	// the offered sha256.
	Sha256Verified bool
	// Transport is the classifyStreamTransport label of the media stream — always
	// "direct" for this lane (the send is refused over a circuit).
	Transport string
}

// firstNonCircuitConn returns the first non-circuit, non-limited (direct) conn
// in conns, or nil. The MediaLANProtocol gate is "has >= 1 non-circuit conn" —
// NOT "has no circuit conn": a peer can simultaneously hold a relay circuit
// reservation AND a fresh FDC-11 LAN-direct conn, and that case MUST send over
// the direct conn (TL5b). Mirrors the firstDirectConn test helper, promoted to
// production for the send gate.
func firstNonCircuitConn(conns []network.Conn) network.Conn {
	for _, c := range conns {
		if c.Stat().Limited {
			continue
		}
		if a := c.RemoteMultiaddr(); a != nil && isCircuitAddr(a) {
			continue
		}
		return c
	}
	return nil
}

// claimLANMediaID atomically marks a media id as in-flight/seen and reports
// whether the caller is the FIRST to claim it. Lazily creates the set; reset by
// Stop(). Guarded by lanMediaSeenIdsMu so concurrent inbound streams race-clean
// (TL9) and resolve to a single render (TL7).
func (n *Node) claimLANMediaID(id string) bool {
	n.lanMediaSeenIdsMu.Lock()
	defer n.lanMediaSeenIdsMu.Unlock()
	if n.lanMediaSeenIds == nil {
		n.lanMediaSeenIds = make(map[string]bool)
	}
	if n.lanMediaSeenIds[id] {
		return false
	}
	n.lanMediaSeenIds[id] = true
	return true
}

// releaseLANMediaID drops a claim so a FAILED transfer (oversize / sha mismatch /
// truncation) does not permanently suppress a legitimate retry of the same id. A
// SUCCESSFUL transfer keeps the claim until Stop() (dedup vs the WS / relay copy).
func (n *Node) releaseLANMediaID(id string) {
	n.lanMediaSeenIdsMu.Lock()
	defer n.lanMediaSeenIdsMu.Unlock()
	delete(n.lanMediaSeenIds, id)
}

// handleIncomingLANMedia is the MediaLANProtocol stream handler (registered in
// Start only when EnableLibp2pLANMedia is on). It reads a framed lanMediaHeader,
// rejects an oversize or duplicate offer, streams the raw ciphertext body to a
// temp file while verifying SHA-256 incrementally, writes a framed lanMediaAck,
// and on success emits a media:lan_received event carrying the staged temp path
// (the Dart side cannot guess a Go temp dir). The bytes are opaque ciphertext.
func (n *Node) handleIncomingLANMedia(s network.Stream) {
	defer s.Close()
	setStreamDeadline(s, MediaTimeout)

	headerBytes, err := readFrame(s)
	if err != nil {
		log.Printf("[NODE] media-lan: read header: %v", err)
		return
	}
	var hdr lanMediaHeader
	if err := json.Unmarshal(headerBytes, &hdr); err != nil {
		log.Printf("[NODE] media-lan: bad header: %v", err)
		return
	}
	// --- Phase 1: pre-body decision (reject BEFORE the body is streamed) ---
	if hdr.ID == "" {
		_ = writeLANMediaDecision(s, lanMediaDecision{Proceed: false, Reason: "missing_id"})
		return
	}

	// Size guard BEFORE any disk write / CopyN — a malicious header must not be
	// able to drive an unbounded disk write / OOM (TL10). Mirrors the WS
	// LocalMediaServer.acceptOffer pre-stream size reject.
	if hdr.Size <= 0 || hdr.Size > MaxLANMediaBytes {
		_ = writeLANMediaDecision(s, lanMediaDecision{Proceed: false, Reason: "size_exceeds_max"})
		return
	}

	// Dedup: claim the id atomically. A duplicate (WS leg already delivered, or a
	// retransmit / concurrent stream) is rejected without re-staging or re-emitting.
	if !n.claimLANMediaID(hdr.ID) {
		_ = writeLANMediaDecision(s, lanMediaDecision{Proceed: false, Reason: "duplicate"})
		return
	}

	tmp, err := os.CreateTemp("", "mknoon-lanmedia-*")
	if err != nil {
		n.releaseLANMediaID(hdr.ID)
		_ = writeLANMediaDecision(s, lanMediaDecision{Proceed: false, Reason: "stage_failed"})
		return
	}
	tmpPath := tmp.Name()

	// Accepted: tell the sender to stream the body now.
	if err := writeLANMediaDecision(s, lanMediaDecision{Proceed: true}); err != nil {
		os.Remove(tmpPath)
		n.releaseLANMediaID(hdr.ID)
		log.Printf("[NODE] media-lan: write proceed: %v", err)
		return
	}

	// --- Phase 2: stream the body to disk while teeing into a SHA-256 sink.
	// io.CopyN bounds the read to exactly hdr.Size; the idle reader fails a
	// stalled transfer. ---
	hasher := sha256.New()
	idle := newIdleTimeoutReader(s, MediaIdleTimeout)
	tee := io.TeeReader(idle, hasher)
	written, copyErr := io.CopyN(tmp, tee, hdr.Size)
	closeErr := tmp.Close()
	if copyErr == nil {
		copyErr = closeErr
	}
	if copyErr != nil || written != hdr.Size {
		os.Remove(tmpPath)
		n.releaseLANMediaID(hdr.ID)
		_ = writeLANMediaAck(s, lanMediaAck{OK: false, Reason: "transfer_incomplete"})
		return
	}

	computedHex := hex.EncodeToString(hasher.Sum(nil))
	if subtle.ConstantTimeCompare([]byte(computedHex), []byte(hdr.Sha256)) != 1 {
		os.Remove(tmpPath)
		n.releaseLANMediaID(hdr.ID)
		_ = writeLANMediaAck(s, lanMediaAck{OK: false, Sha256Verified: false, Reason: "sha256_mismatch"})
		return
	}

	if err := writeLANMediaAck(s, lanMediaAck{OK: true, Sha256Verified: true}); err != nil {
		// Verified + staged, but the ack write failed (peer gone). Keep the staged
		// blob + emit so the local render still proceeds; the id stays claimed.
		log.Printf("[NODE] media-lan: ack write failed for %s: %v", hdr.ID, err)
	}

	// Attribute the sender from the AUTHENTICATED libp2p peer (Noise-proven),
	// NOT the attacker-controllable wire header — and the recipient is this node,
	// not a wire value. Mirrors handleIncomingMessage's identity contract; the
	// header's From/To are advisory only. (`from` is load-bearing downstream: the
	// Dart consumer keys the staged blob + dedup on it.)
	n.emitEvent("media:lan_received", map[string]interface{}{
		"id":         hdr.ID,
		"from":       s.Conn().RemotePeer().String(),
		"to":         n.peerId,
		"mime":       hdr.Mime,
		"size":       hdr.Size,
		"localPath":  tmpPath,
		"sha256":     hdr.Sha256,
		"enc":        hdr.Enc,
		"encScheme":  hdr.EncScheme,
		"durationMs": hdr.DurationMs,
		"transport":  classifyStreamTransport(s),
	})
}

// SendLANMedia streams a single 1:1 media ciphertext blob to peer pid over a
// peer-authenticated libp2p LAN-direct conn (MediaLANProtocol). It REFUSES with
// errMediaLANRequiresDirect when no non-circuit conn exists (media never rides
// the live relay socket). It writes a framed lanMediaHeader, streams the raw
// ciphertext body, and reads the receiver's framed ack. sha256Hex is the hash of
// the ciphertext file (computed by the bridge / caller); the receiver verifies
// the streamed bytes against it. Best-effort acceleration only — the
// unconditional relay-CDN upload remains the durable copy.
func (n *Node) SendLANMedia(
	pid peer.ID,
	filePath, mediaID, fromPeerID, toPeerID, mime, sha256Hex, encScheme string,
	enc bool,
	durationMs int,
) (LANMediaSendResult, error) {
	n.mu.RLock()
	h := n.host
	baseCtx := n.ctx
	n.mu.RUnlock()
	if h == nil {
		return LANMediaSendResult{}, fmt.Errorf("media-lan: node not started")
	}

	// Gate: "has >= 1 non-circuit conn" — refuse (no stream opened) otherwise.
	if firstNonCircuitConn(h.Network().ConnsToPeer(pid)) == nil {
		return LANMediaSendResult{}, errMediaLANRequiresDirect
	}

	fi, err := os.Stat(filePath)
	if err != nil {
		return LANMediaSendResult{}, fmt.Errorf("media-lan: stat file: %w", err)
	}
	size := fi.Size()
	if size <= 0 || size > MaxLANMediaBytes {
		return LANMediaSendResult{}, fmt.Errorf("media-lan: file size %d out of bounds", size)
	}

	f, err := os.Open(filePath)
	if err != nil {
		return LANMediaSendResult{}, fmt.Errorf("media-lan: open file: %w", err)
	}
	defer f.Close()

	// Derive the stream context from n.ctx so Stop() cancels any in-flight dial
	// (mirror openChatStream's context lineage).
	if baseCtx == nil {
		baseCtx = context.Background()
	}
	streamCtx, cancel := context.WithTimeout(baseCtx, MediaTimeout)
	defer cancel()

	s, err := h.NewStream(streamCtx, pid, MediaLANProtocol)
	if err != nil {
		return LANMediaSendResult{}, fmt.Errorf("media-lan: open stream: %w", err)
	}
	defer s.Close()
	setStreamDeadline(s, MediaTimeout)

	hdrBytes, err := json.Marshal(lanMediaHeader{
		ID: mediaID, From: fromPeerID, To: toPeerID, Mime: mime,
		Size: size, Sha256: sha256Hex, Enc: enc, EncScheme: encScheme, DurationMs: durationMs,
	})
	if err != nil {
		return LANMediaSendResult{}, fmt.Errorf("media-lan: marshal header: %w", err)
	}
	if err := writeFrame(s, hdrBytes); err != nil {
		return LANMediaSendResult{}, fmt.Errorf("media-lan: write header: %w", err)
	}

	// Phase 1: read the receiver's pre-body decision. A reject (oversize /
	// duplicate / bad header) means we NEVER stream the body — no wasted transfer,
	// no stall against the flow-control window. A clean reject is not an error: the
	// relay-CDN copy backstops, so we return a non-acked result.
	decBytes, err := readFrame(s)
	if err != nil {
		return LANMediaSendResult{}, fmt.Errorf("media-lan: read decision: %w", err)
	}
	var dec lanMediaDecision
	if err := json.Unmarshal(decBytes, &dec); err != nil {
		return LANMediaSendResult{}, fmt.Errorf("media-lan: bad decision: %w", err)
	}
	if !dec.Proceed {
		return LANMediaSendResult{
			Acked:     false,
			Transport: classifyStreamTransport(s),
		}, nil
	}

	// Phase 2: stream the body, then read the final ack (sha256 verify / complete).
	if _, err := io.CopyN(s, f, size); err != nil {
		return LANMediaSendResult{}, fmt.Errorf("media-lan: stream body: %w", err)
	}

	ackBytes, err := readFrame(s)
	if err != nil {
		return LANMediaSendResult{}, fmt.Errorf("media-lan: read ack: %w", err)
	}
	var ack lanMediaAck
	if err := json.Unmarshal(ackBytes, &ack); err != nil {
		return LANMediaSendResult{}, fmt.Errorf("media-lan: bad ack: %w", err)
	}

	return LANMediaSendResult{
		Acked:          ack.OK,
		Sha256Verified: ack.Sha256Verified,
		Transport:      classifyStreamTransport(s),
	}, nil
}

// SendLANMediaToPeer is the string-keyed production entrypoint (called by the
// bridge): it decodes the peer id, computes the SHA-256 of the ciphertext file
// (the single source of truth for the offer header — mirrors the WS
// LocalMediaSender computing its own hash over the file), and delegates to
// SendLANMedia.
func (n *Node) SendLANMediaToPeer(
	peerIDStr, filePath, mediaID, fromPeerID, mime, encScheme string,
	enc bool,
	durationMs int,
) (LANMediaSendResult, error) {
	pid, err := peer.Decode(peerIDStr)
	if err != nil {
		return LANMediaSendResult{}, fmt.Errorf("media-lan: invalid peer id %q: %w", peerIDStr, err)
	}
	shaHex, _, err := fileSha256AndSize(filePath)
	if err != nil {
		return LANMediaSendResult{}, err
	}
	return n.SendLANMedia(pid, filePath, mediaID, fromPeerID, peerIDStr, mime, shaHex, encScheme, enc, durationMs)
}

// writeLANMediaDecision marshals + frame-writes a lanMediaDecision reply.
func writeLANMediaDecision(s network.Stream, dec lanMediaDecision) error {
	b, err := json.Marshal(dec)
	if err != nil {
		return err
	}
	return writeFrame(s, b)
}

// writeLANMediaAck marshals + frame-writes a lanMediaAck reply.
func writeLANMediaAck(s network.Stream, ack lanMediaAck) error {
	b, err := json.Marshal(ack)
	if err != nil {
		return err
	}
	return writeFrame(s, b)
}

// fileSha256AndSize returns the hex SHA-256 and byte size of a file (the offer
// header's content hash for the libp2p-LAN leg).
func fileSha256AndSize(path string) (string, int64, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", 0, fmt.Errorf("media-lan: open %q: %w", path, err)
	}
	defer f.Close()
	h := sha256.New()
	size, err := io.Copy(h, f)
	if err != nil {
		return "", 0, fmt.Errorf("media-lan: hash %q: %w", path, err)
	}
	return hex.EncodeToString(h.Sum(nil)), size, nil
}
