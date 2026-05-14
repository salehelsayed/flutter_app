package node

import (
	"context"
	"fmt"
	"log"
	"time"

	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/core/peerstore"
	"github.com/libp2p/go-libp2p/core/record"
	"github.com/libp2p/go-msgio"
	ma "github.com/multiformats/go-multiaddr"
	"google.golang.org/protobuf/encoding/protowire"
)

// RendezvousRegister registers this node on a rendezvous namespace.
// Tries each configured relay in order until one succeeds.
func (n *Node) RendezvousRegister(namespace string, serverAddresses []string) error {
	if n.rendezvousRegisterHook != nil {
		return n.rendezvousRegisterHook(namespace, serverAddresses)
	}

	n.mu.RLock()
	h := n.host
	n.mu.RUnlock()

	if h == nil {
		return fmt.Errorf("node not started")
	}

	rs := n.buildRelaySelector(serverAddresses)

	registerStart := time.Now()
	if err := rs.ForEach(func(relay RelayInfo) error {
		timeout := DiscoverTimeout
		ctx, cancel := context.WithTimeout(n.ctx, timeout)
		defer cancel()

		s, err := h.NewStream(ctx, relay.ID, RendezvousProtocol)
		if err != nil {
			return fmt.Errorf("open rendezvous stream: %w", err)
		}
		streamOK := false
		defer finishStream(s, &streamOK)
		setStreamDeadline(s, timeout)

		// Build signed peer record
		cab, ok := h.Peerstore().(peerstore.CertifiedAddrBook)
		if !ok {
			return fmt.Errorf("peerstore does not support certified addresses")
		}

		signedRecord := cab.GetPeerRecord(h.ID())
		var signedRecordBytes []byte
		if signedRecord != nil {
			signedRecordBytes, err = signedRecord.Marshal()
			if err != nil {
				return fmt.Errorf("marshal signed peer record: %w", err)
			}
		}

		// Build Register message
		regBytes := marshalRegister(namespace, signedRecordBytes, uint64(PersonalRendezvousRegistrationTTL/time.Second))
		msgBytes := marshalRzMessage(0, regBytes) // MessageType_REGISTER = 0

		// Write varint-prefixed message
		writer := msgio.NewVarintWriter(s)
		if err := writer.WriteMsg(msgBytes); err != nil {
			return fmt.Errorf("write register: %w", err)
		}

		// Read varint-prefixed response
		reader := msgio.NewVarintReaderSize(s, 1<<20)
		respBytes, err := reader.ReadMsg()
		if err != nil {
			return fmt.Errorf("read register response: %w", err)
		}
		defer reader.ReleaseMsg(respBytes)

		// Parse response to check status
		status, statusText, err := parseRegisterResponse(respBytes)
		if err != nil {
			return fmt.Errorf("parse register response: %w", err)
		}

		if status != 0 { // 0 = OK
			return fmt.Errorf("register failed: status=%d text=%s", status, statusText)
		}

		log.Printf("[RENDEZVOUS] Registered ns=%s", namespace)
		streamOK = true
		return nil
	}); err != nil {
		n.emitEvent("rendezvous:register_timing", map[string]interface{}{
			"elapsedMs": time.Since(registerStart).Milliseconds(),
			"outcome":   "failed",
		})
		return err
	}

	n.emitEvent("rendezvous:register_timing", map[string]interface{}{
		"elapsedMs": time.Since(registerStart).Milliseconds(),
		"outcome":   "success",
	})
	n.maybeStartPersonalRendezvousRefreshLoopAfterRegister(namespace)
	return nil
}

// RendezvousDiscoverWithTimeout discovers peers on a namespace using a
// caller-supplied timeout override. If timeoutMs <= 0, the default
// DiscoverTimeout is used.
// Tries each configured relay in order until one succeeds.
func (n *Node) RendezvousDiscoverWithTimeout(namespace string, serverAddresses []string, timeoutMs int) ([]peer.AddrInfo, error) {
	if n.rendezvousDiscoverHook != nil {
		return n.rendezvousDiscoverHook(namespace, serverAddresses)
	}

	n.mu.RLock()
	h := n.host
	n.mu.RUnlock()

	if h == nil {
		return nil, fmt.Errorf("node not started")
	}

	timeout := DiscoverTimeout
	if timeoutMs > 0 {
		timeout = time.Duration(timeoutMs) * time.Millisecond
	}

	rs := n.buildRelaySelector(serverAddresses)

	discoverStart := time.Now()
	result, err := ForEachWithResult(rs, func(relay RelayInfo) ([]peer.AddrInfo, error) {
		ctx, cancel := context.WithTimeout(n.ctx, timeout)
		defer cancel()

		s, err := h.NewStream(ctx, relay.ID, RendezvousProtocol)
		if err != nil {
			return nil, fmt.Errorf("open rendezvous stream: %w", err)
		}
		streamOK := false
		defer finishStream(s, &streamOK)
		setStreamDeadline(s, timeout)

		// Build Discover message
		discBytes := marshalDiscover(namespace, 64)
		msgBytes := marshalRzMessage(3, discBytes) // MessageType_DISCOVER = 3

		writer := msgio.NewVarintWriter(s)
		if err := writer.WriteMsg(msgBytes); err != nil {
			return nil, fmt.Errorf("write discover: %w", err)
		}

		reader := msgio.NewVarintReaderSize(s, 1<<20)
		respBytes, err := reader.ReadMsg()
		if err != nil {
			return nil, fmt.Errorf("read discover response: %w", err)
		}
		defer reader.ReleaseMsg(respBytes)

		// Parse discover response
		peers, err := parseDiscoverResponse(respBytes)
		if err != nil {
			return nil, fmt.Errorf("parse discover response: %w", err)
		}

		log.Printf("[RENDEZVOUS] Discovered %d peers on ns=%s (timeout=%v)", len(peers), namespace, timeout)
		streamOK = true
		return peers, nil
	})
	outcome := "success"
	if err != nil {
		outcome = "failed"
	}
	n.emitEvent("rendezvous:discover_timing", map[string]interface{}{
		"elapsedMs": time.Since(discoverStart).Milliseconds(),
		"outcome":   outcome,
		"peerCount": len(result),
	})
	return result, err
}

// RendezvousDiscover discovers peers on a namespace.
// Tries each configured relay in order until one succeeds.
func (n *Node) RendezvousDiscover(namespace string, serverAddresses []string) ([]peer.AddrInfo, error) {
	return n.RendezvousDiscoverWithTimeout(namespace, serverAddresses, 0)
}

// RendezvousUnregister removes this node from a namespace.
// Tries each configured relay in order until one succeeds.
func (n *Node) RendezvousUnregister(namespace string, serverAddresses []string) error {
	if n.rendezvousUnregisterHook != nil {
		return n.rendezvousUnregisterHook(namespace, serverAddresses)
	}

	n.mu.RLock()
	h := n.host
	n.mu.RUnlock()

	if h == nil {
		return fmt.Errorf("node not started")
	}

	rs := n.buildRelaySelector(serverAddresses)

	return rs.ForEach(func(relay RelayInfo) error {
		timeout := DiscoverTimeout
		ctx, cancel := context.WithTimeout(n.ctx, timeout)
		defer cancel()

		s, err := h.NewStream(ctx, relay.ID, RendezvousProtocol)
		if err != nil {
			return fmt.Errorf("open rendezvous stream: %w", err)
		}
		streamOK := false
		defer finishStream(s, &streamOK)
		setStreamDeadline(s, timeout)

		// Build Unregister message
		unregBytes := marshalUnregister(namespace)
		msgBytes := marshalRzMessage(2, unregBytes) // MessageType_UNREGISTER = 2

		writer := msgio.NewVarintWriter(s)
		if err := writer.WriteMsg(msgBytes); err != nil {
			return fmt.Errorf("write unregister: %w", err)
		}

		// Unregister has no response
		log.Printf("[RENDEZVOUS] Unregistered ns=%s", namespace)
		streamOK = true
		return nil
	})
}

// getRelayPeerID parses the relay peer ID from addresses.
// Deprecated: use buildRelaySelector instead for multi-relay support.
// Kept for backward compatibility with any callers not yet migrated.
func (n *Node) getRelayPeerID(serverAddresses []string) (peer.ID, error) {
	rs := n.buildRelaySelector(serverAddresses)
	first, err := rs.First()
	if err != nil {
		return "", err
	}
	return first.ID, nil
}

// --- Protobuf encoding helpers (matching relay server's pb.go) ---

func marshalRegister(ns string, signedPeerRecord []byte, ttl uint64) []byte {
	var b []byte
	if ns != "" {
		b = protowire.AppendTag(b, 1, protowire.BytesType)
		b = protowire.AppendString(b, ns)
	}
	if len(signedPeerRecord) > 0 {
		b = protowire.AppendTag(b, 2, protowire.BytesType)
		b = protowire.AppendBytes(b, signedPeerRecord)
	}
	if ttl > 0 {
		b = protowire.AppendTag(b, 3, protowire.VarintType)
		b = protowire.AppendVarint(b, ttl)
	}
	return b
}

func marshalDiscover(ns string, limit uint64) []byte {
	var b []byte
	if ns != "" {
		b = protowire.AppendTag(b, 1, protowire.BytesType)
		b = protowire.AppendString(b, ns)
	}
	if limit > 0 {
		b = protowire.AppendTag(b, 2, protowire.VarintType)
		b = protowire.AppendVarint(b, limit)
	}
	return b
}

func marshalUnregister(ns string) []byte {
	var b []byte
	if ns != "" {
		b = protowire.AppendTag(b, 1, protowire.BytesType)
		b = protowire.AppendString(b, ns)
	}
	return b
}

// marshalRzMessage wraps a sub-message into the top-level RzMessage.
// fieldNum: 2=register, 4=unregister, 5=discover
func marshalRzMessage(msgType uint64, submsg []byte) []byte {
	var b []byte
	// Field 1: type (varint)
	b = protowire.AppendTag(b, 1, protowire.VarintType)
	b = protowire.AppendVarint(b, msgType)

	// Field for the sub-message: register=2, unregister=4, discover=5
	var fieldNum protowire.Number
	switch msgType {
	case 0: // REGISTER
		fieldNum = 2
	case 2: // UNREGISTER
		fieldNum = 4
	case 3: // DISCOVER
		fieldNum = 5
	default:
		return b
	}

	b = protowire.AppendTag(b, fieldNum, protowire.BytesType)
	b = protowire.AppendBytes(b, submsg)
	return b
}

// parseRegisterResponse extracts status and statusText from a REGISTER_RESPONSE.
func parseRegisterResponse(data []byte) (int64, string, error) {
	// Top-level RzMessage: field 3 is registerResponse
	var respBytes []byte
	raw := data
	for len(raw) > 0 {
		num, wtype, n := protowire.ConsumeTag(raw)
		if n < 0 {
			return -1, "", fmt.Errorf("invalid tag")
		}
		raw = raw[n:]
		if num == 3 && wtype == protowire.BytesType {
			val, vn := protowire.ConsumeBytes(raw)
			if vn < 0 {
				return -1, "", fmt.Errorf("invalid registerResponse bytes")
			}
			respBytes = append([]byte(nil), val...)
			raw = raw[vn:]
		} else {
			vn := protowire.ConsumeFieldValue(num, wtype, raw)
			if vn < 0 {
				return -1, "", fmt.Errorf("invalid field")
			}
			raw = raw[vn:]
		}
	}

	if respBytes == nil {
		return -1, "", fmt.Errorf("no registerResponse in message")
	}

	// Parse RegisterResponse: field 1=status, field 2=statusText
	var status int64
	var statusText string
	raw = respBytes
	for len(raw) > 0 {
		num, wtype, n := protowire.ConsumeTag(raw)
		if n < 0 {
			return -1, "", fmt.Errorf("invalid tag in registerResponse")
		}
		raw = raw[n:]
		switch num {
		case 1:
			val, vn := protowire.ConsumeVarint(raw)
			if vn < 0 {
				return -1, "", fmt.Errorf("invalid status")
			}
			status = int64(val)
			raw = raw[vn:]
		case 2:
			val, vn := protowire.ConsumeString(raw)
			if vn < 0 {
				return -1, "", fmt.Errorf("invalid statusText")
			}
			statusText = val
			raw = raw[vn:]
		default:
			vn := protowire.ConsumeFieldValue(num, wtype, raw)
			if vn < 0 {
				return -1, "", fmt.Errorf("invalid field in registerResponse")
			}
			raw = raw[vn:]
		}
	}

	return status, statusText, nil
}

// parseDiscoverResponse extracts peer registrations from a DISCOVER_RESPONSE.
func parseDiscoverResponse(data []byte) ([]peer.AddrInfo, error) {
	// Top-level RzMessage: field 6 is discoverResponse
	var discRespBytes []byte
	raw := data
	for len(raw) > 0 {
		num, wtype, n := protowire.ConsumeTag(raw)
		if n < 0 {
			return nil, fmt.Errorf("invalid tag")
		}
		raw = raw[n:]
		if num == 6 && wtype == protowire.BytesType {
			val, vn := protowire.ConsumeBytes(raw)
			if vn < 0 {
				return nil, fmt.Errorf("invalid discoverResponse bytes")
			}
			discRespBytes = append([]byte(nil), val...)
			raw = raw[vn:]
		} else {
			vn := protowire.ConsumeFieldValue(num, wtype, raw)
			if vn < 0 {
				return nil, fmt.Errorf("invalid field")
			}
			raw = raw[vn:]
		}
	}

	if discRespBytes == nil {
		return nil, fmt.Errorf("no discoverResponse in message")
	}

	// Parse DiscoverResponse: field 3 (repeated) = registrations
	var results []peer.AddrInfo
	raw = discRespBytes
	for len(raw) > 0 {
		num, wtype, n := protowire.ConsumeTag(raw)
		if n < 0 {
			return nil, fmt.Errorf("invalid tag in discoverResponse")
		}
		raw = raw[n:]
		if num == 3 && wtype == protowire.BytesType {
			val, vn := protowire.ConsumeBytes(raw)
			if vn < 0 {
				return nil, fmt.Errorf("invalid registration bytes")
			}
			raw = raw[vn:]

			// Parse Registration: field 2 = signedPeerRecord
			regRaw := val
			for len(regRaw) > 0 {
				rNum, rType, rn := protowire.ConsumeTag(regRaw)
				if rn < 0 {
					break
				}
				regRaw = regRaw[rn:]
				if rNum == 2 && rType == protowire.BytesType {
					sprBytes, sprN := protowire.ConsumeBytes(regRaw)
					if sprN < 0 {
						break
					}
					regRaw = regRaw[sprN:]

					// Unmarshal signed peer record → AddrInfo
					env, err := record.UnmarshalEnvelope(sprBytes)
					if err != nil {
						log.Printf("[RENDEZVOUS] Skip invalid peer record: %v", err)
						continue
					}
					var peerRec peer.PeerRecord
					if err := peerRec.UnmarshalRecord(env.RawPayload); err != nil {
						log.Printf("[RENDEZVOUS] Skip peer record unmarshal: %v", err)
						continue
					}
					addrs := make([]ma.Multiaddr, len(peerRec.Addrs))
					copy(addrs, peerRec.Addrs)
					results = append(results, peer.AddrInfo{
						ID:    peerRec.PeerID,
						Addrs: addrs,
					})
				} else {
					vn := protowire.ConsumeFieldValue(rNum, rType, regRaw)
					if vn < 0 {
						break
					}
					regRaw = regRaw[vn:]
				}
			}
		} else {
			vn := protowire.ConsumeFieldValue(num, wtype, raw)
			if vn < 0 {
				return nil, fmt.Errorf("invalid field in discoverResponse")
			}
			raw = raw[vn:]
		}
	}

	return results, nil
}
