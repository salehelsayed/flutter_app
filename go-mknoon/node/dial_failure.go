package node

import (
	"context"
	"errors"
	"net"
	"strings"
	"syscall"

	"github.com/libp2p/go-libp2p/core/sec"
	"github.com/libp2p/go-libp2p/p2p/net/swarm"
)

var (
	ErrDialNodeNotStarted = errors.New("node not started")
	ErrDialInvalidPeer    = errors.New("invalid peer ID")
)

// Every class is a fixed literal. Error text, peer IDs and addresses never
// leave this file; the relay status names are libp2p protocol constants.
var dialFailureSentinels = []struct {
	err   error
	class string
}{
	{context.Canceled, "canceled"},
	{swarm.ErrDialBackoff, "backoff"},
	{swarm.ErrDialRefusedBlackHole, "black_hole"},
	{swarm.ErrGaterDisallowedConnection, "gater_denied"},
	{swarm.ErrNoTransport, "no_transport"},
	{swarm.ErrNoAddresses, "no_addresses"},
	{swarm.ErrNoGoodAddresses, "no_good_addresses"},
	{swarm.ErrAddrFiltered, "no_good_addresses"},
	{swarm.ErrDialTimeout, "timeout"},
	{context.DeadlineExceeded, "timeout"},
}

var relayStatusClasses = []struct{ status, class string }{
	{"NO_RESERVATION", "relay_no_reservation"},
	{"RESOURCE_LIMIT_EXCEEDED", "relay_limit"},
	{"PERMISSION_DENIED", "relay_denied"},
	{"CONNECTION_FAILED", "relay_failed"},
}

// A DialError holds one cause per address. The most specific one names the
// failure: a relay verdict, then a socket verdict, then everything weaker.
var dialFailureRank = map[string]int{
	"relay_no_reservation": 0, "relay_limit": 0, "relay_denied": 0, "relay_failed": 0,
	"socket_refused": 1, "socket_unreachable": 1,
	"handshake_failed": 2,
	"black_hole":       3, "gater_denied": 3, "no_transport": 3, "backoff": 3,
	"no_addresses": 4, "no_good_addresses": 4,
	"canceled": 5,
	"timeout":  6,
	"other":    7,
}

// ClassifyDialError maps a libp2p dial error onto a closed, privacy-safe class.
func ClassifyDialError(err error) string {
	if err == nil {
		return ""
	}
	var dial *swarm.DialError
	if errors.As(err, &dial) && dial != nil {
		best := "other"
		for _, attempt := range dial.DialErrors {
			if class := classifyDialCause(attempt.Cause); dialFailureRank[class] < dialFailureRank[best] {
				best = class
			}
		}
		if best != "other" {
			return best
		}
	}
	return classifyDialCause(err)
}

func classifyDialCause(err error) string {
	if err == nil {
		return "other"
	}
	message := err.Error()
	if strings.Contains(strings.ToLower(message), "relay") || strings.Contains(message, "reservation") {
		for _, relay := range relayStatusClasses {
			if strings.Contains(message, relay.status) {
				return relay.class
			}
		}
	}
	var op *net.OpError
	if errors.As(err, &op) && op.Op == "dial" {
		switch {
		case errors.Is(op, syscall.ECONNREFUSED):
			return "socket_refused"
		case errors.Is(op, syscall.ENETUNREACH), errors.Is(op, syscall.EHOSTUNREACH):
			return "socket_unreachable"
		case op.Timeout():
			return "timeout"
		}
	}
	var mismatch sec.ErrPeerIDMismatch
	if errors.As(err, &mismatch) ||
		strings.Contains(message, "failed to negotiate security protocol") ||
		strings.Contains(message, "failed to negotiate stream multiplexer") {
		return "handshake_failed"
	}
	for _, sentinel := range dialFailureSentinels {
		if errors.Is(err, sentinel.err) {
			return sentinel.class
		}
	}
	return "other"
}
