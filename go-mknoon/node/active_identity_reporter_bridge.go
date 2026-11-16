package node

import (
	"context"
	"encoding/binary"
	"io"
	"time"

	"github.com/libp2p/go-libp2p/core/peer"
)

const ActiveIdentityReporterLocalLimit = 16 << 10

// These aliases let the local JSON adapter map fixed engine failures without
// exposing underlying parser, filesystem, or private-input error text.
var (
	ErrActiveIdentityReporterInput       = errActiveIdentityReporterInput
	ErrActiveIdentityReporterStale       = errActiveIdentityReporterStale
	ErrActiveIdentityReporterStorage     = errActiveIdentityReporterStorage
	ErrActiveIdentityReporterUnavailable = errActiveIdentityReporterUnavailable
)

type ActiveIdentityReporterDesiredRequest struct {
	Version int `json:"version"`
	ActiveIdentityReporterFence
	Enabled                bool `json:"enabled"`
	PreservePendingOnUnarm bool `json:"preservePendingOnUnarm"`
}

// The local request is flat. Root/path/consent fields are configure-only; they
// never become fields in the independent active_identity_v1 relay request.
type ActiveIdentityReporterLocalRequest struct {
	Version int    `json:"version"`
	Op      string `json:"op"`
	ActiveIdentityReporterFence
	Enabled                *bool  `json:"enabled,omitempty"`
	StatePath              string `json:"statePath,omitempty"`
	RootPrivateKeyBase64   string `json:"rootPrivateKeyBase64,omitempty"`
	PreservePendingOnUnarm bool   `json:"preservePendingOnUnarm,omitempty"`
}

type ActiveIdentityReporterLocalResult struct {
	Configured bool
	Accepted   bool
	Queued     bool
	Fence      ActiveIdentityReporterFence
}

// Node ownership is independent of host lifetime: Stop cancels the captured
// transport, while hostless configure/mark continue to use the same reporter.
func (n *Node) activeIdentityReporterInstance() *activeIdentityReporter {
	n.mu.Lock()
	defer n.mu.Unlock()
	if n.activeIdentityReporter == nil {
		n.activeIdentityReporter = newActiveIdentityReporter(activeIdentityReporterDeps{transportSnapshot: n.activeIdentityReporterSnapshot})
	}
	return n.activeIdentityReporter
}

func (n *Node) PublishActiveIdentityReporterDesired(request ActiveIdentityReporterDesiredRequest) (ActiveIdentityReporterFence, error) {
	if request.Version != 1 {
		return ActiveIdentityReporterFence{}, ErrActiveIdentityReporterInput
	}
	return n.activeIdentityReporterInstance().publishDesired(request.ActiveIdentityReporterFence, request.Enabled, request.PreservePendingOnUnarm)
}

func (n *Node) ActiveIdentityReporterV1(request ActiveIdentityReporterLocalRequest) (ActiveIdentityReporterLocalResult, error) {
	result := ActiveIdentityReporterLocalResult{Fence: request.ActiveIdentityReporterFence}
	if request.Version != 1 || !activeIdentityReporterFenceValid(result.Fence) {
		return result, ErrActiveIdentityReporterInput
	}
	reporter := n.activeIdentityReporterInstance()
	switch request.Op {
	case "configure":
		if request.Enabled == nil {
			return result, ErrActiveIdentityReporterInput
		}
		reporter.stateMu.Lock()
		matches := reporter.desiredLocked(result.Fence)
		enabledMatches := reporter.enabled == *request.Enabled
		reporter.stateMu.Unlock()
		if !matches {
			return result, ErrActiveIdentityReporterStale
		}
		if !enabledMatches {
			return result, ErrActiveIdentityReporterInput
		}
		err := reporter.configure(ActiveIdentityReporterConfig{Fence: result.Fence, StatePath: request.StatePath, RootPrivateKeyBase64: request.RootPrivateKeyBase64, PreservePendingOnUnarm: request.PreservePendingOnUnarm})
		result.Configured = *request.Enabled && result.Fence.AccountPeerID != "" && !request.PreservePendingOnUnarm
		return result, err
	case "mark", "flush":
		if request.Enabled != nil || request.StatePath != "" || request.RootPrivateKeyBase64 != "" || request.PreservePendingOnUnarm {
			return result, ErrActiveIdentityReporterInput
		}
		if request.Op == "mark" {
			err := reporter.mark(result.Fence)
			result.Accepted = err == nil
			return result, err
		}
		reporter.stateMu.Lock()
		armed := reporter.armedLocked(result.Fence)
		reporter.stateMu.Unlock()
		if !armed {
			return result, ErrActiveIdentityReporterStale
		}
		// This is a local queue receipt, never a claim about a relay ACK.
		go func() { _ = reporter.flush(result.Fence) }()
		result.Queued = true
		return result, nil
	default:
		return result, ErrActiveIdentityReporterInput
	}
}

func (n *Node) activeIdentityReporterSnapshot() (activeIdentityReporterTransport, bool) {
	n.mu.RLock()
	h, ctx, generation := n.host, n.ctx, n.hostGeneration
	if !n.isStarted || h == nil || ctx == nil || ctx.Err() != nil {
		n.mu.RUnlock()
		return activeIdentityReporterTransport{}, false
	}
	var addresses []string
	if n.lastConfig != nil && n.lastConfig.RelayAddresses != nil {
		addresses = append([]string{}, n.lastConfig.RelayAddresses...)
	}
	n.mu.RUnlock()
	current := func() bool {
		n.mu.RLock()
		defer n.mu.RUnlock()
		return n.isStarted && n.host == h && n.hostGeneration == generation && ctx.Err() == nil
	}
	return activeIdentityReporterTransport{
		peerID: h.ID().String(), generation: generation, ctx: ctx, relayAddresses: addresses, current: current,
		exchange: func(attempt context.Context, relay RelayInfo, raw []byte) ([]byte, error) {
			if !current() || attempt.Err() != nil {
				return nil, errActiveIdentityReporterUnavailable
			}
			if err := h.Connect(attempt, peer.AddrInfo{ID: relay.ID, Addrs: relay.Addrs}); err != nil {
				return nil, errActiveIdentityReporterUnavailable
			}
			stream, err := h.NewStream(attempt, relay.ID, InboxProtocol)
			if err != nil {
				return nil, errActiveIdentityReporterUnavailable
			}
			ok := false
			defer finishStream(stream, &ok)
			deadline, bounded := attempt.Deadline()
			if !bounded || time.Until(deadline) > activeIdentityReporterFlushBudget || stream.SetDeadline(deadline) != nil {
				return nil, errActiveIdentityReporterUnavailable
			}
			stop := context.AfterFunc(attempt, func() { _ = stream.Reset() })
			defer stop()
			if stream.Conn().RemotePeer() != relay.ID || !current() || writeFrame(stream, raw) != nil {
				return nil, errActiveIdentityReporterUnavailable
			}
			var header [4]byte
			if _, err := io.ReadFull(stream, header[:]); err != nil {
				return nil, errActiveIdentityReporterUnavailable
			}
			size := binary.BigEndian.Uint32(header[:])
			if size > activeIdentityProtocolLimit {
				return nil, errActiveIdentityReporterUnavailable
			}
			response := make([]byte, int(size))
			if _, err := io.ReadFull(stream, response); err != nil || !current() {
				return nil, errActiveIdentityReporterUnavailable
			}
			ok = true
			return response, nil
		},
	}, true
}
