package node

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"os"
	"strings"
	"syscall"
	"testing"
	"time"

	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/core/protocol"
	"github.com/libp2p/go-libp2p/p2p/net/swarm"
)

type turnDiagnosticFailureHost struct {
	host.Host
	connectErr, streamErr error
}

func (h turnDiagnosticFailureHost) Connect(context.Context, peer.AddrInfo) error { return h.connectErr }
func (h turnDiagnosticFailureHost) NewStream(context.Context, peer.ID, ...protocol.ID) (network.Stream, error) {
	return nil, h.streamErr
}

func TestTurnCredentialsV1_FixedDiagnosticPreservesActualPreStreamStageAndPolicy(t *testing.T) {
	route := &net.OpError{Op: "private-operation", Net: "private-network", Err: &os.SyscallError{Syscall: "private-syscall", Err: syscall.ENETUNREACH}}
	aggregate := &swarm.DialError{Cause: swarm.ErrAllDialsFailed, DialErrors: []swarm.TransportError{{Cause: route}, {Cause: swarm.ErrDialBackoff}}}
	cases := []struct {
		name, stage, kind string
		raw, classified   error
	}{
		{"route", "connect", "network_unreachable", route, ErrTurnCredentialsUnavailable},
		{"backoff", "new_stream", "dial_backoff", swarm.ErrDialBackoff, ErrTurnCredentialsRejected},
		{"mixed", "connect", "dial_aggregate", aggregate, ErrTurnCredentialsRejected},
		{"unknown", "new_stream", "unknown", errors.New("private-identity-and-secret"), ErrTurnCredentialsRejected},
		{"joined", "connect", "joined_errors", errors.Join(route, errors.New("private-trust")), ErrTurnCredentialsRejected},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			h := turnDiagnosticFailureHost{}
			if tc.stage == "connect" {
				h.connectErr = tc.raw
			} else {
				h.streamErr = tc.raw
			}
			_, err := requestTurnCredentialsV1(context.Background(), h, RelayInfo{}, time.Now())
			if !errors.Is(err, tc.classified) {
				t.Fatal("diagnostic changed failure classification")
			}
			detail := TurnCredentialFailureDiagnostics(err)
			if detail["stage"] != tc.stage || detail["kind"] != tc.kind {
				t.Fatal("actual failing stage/kind lost")
			}
			if tc.name == "mixed" {
				if detail["dialAllTransient"] != false || detail["dialComplete"] != true || detail["dialAttemptCount"] != 2 {
					t.Fatal("mixed aggregate diagnostic lost")
				}
				kinds := detail["dialTransportKinds"].([]string)
				if len(kinds) != 2 || kinds[0] != "network_unreachable" || kinds[1] != "dial_backoff" {
					t.Fatal("aggregate fixed kinds lost")
				}
			}
			encoded, _ := json.Marshal(detail)
			if strings.Contains(string(encoded)+err.Error(), "private-") {
				t.Fatal("raw error escaped into diagnostics")
			}
		})
	}
}

func TestTurnCredentialsV1_FixedDiagnosticBoundsAndOwnsItsValues(t *testing.T) {
	dial := &swarm.DialError{Cause: swarm.ErrAllDialsFailed, Skipped: 7}
	for i := 0; i < 100; i++ {
		dial.DialErrors = append(dial.DialErrors, swarm.TransportError{Cause: swarm.ErrDialBackoff})
	}
	err := annotateTurnCredentialFailure(ErrTurnCredentialsRejected, "connect", dial)
	detail := TurnCredentialFailureDiagnostics(err)
	if detail["dialAttemptCount"] != 8 || detail["dialComplete"] != false || detail["dialTruncated"] != true {
		t.Fatal("aggregate output not bounded")
	}
	detail["stage"] = "private-mutated"
	detail["dialTransportKinds"].([]string)[0] = "private-mutated"
	again, _ := json.Marshal(TurnCredentialFailureDiagnostics(err))
	if strings.Contains(string(again), "private-") || len(again) > 512 {
		t.Fatal("diagnostic did not own bounded values")
	}
	var chain error = errors.New("private-root")
	for i := 0; i < 40; i++ {
		chain = fmt.Errorf("private-wrapper: %w", chain)
	}
	kind, _ := turnCredentialDiagnosticKind(chain)
	if kind != "chain_limit" {
		t.Fatal("error traversal not bounded")
	}
}
