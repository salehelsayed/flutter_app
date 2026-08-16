package node

import (
	"context"
	"crypto/ed25519"
	"encoding/json"
	"errors"
	"fmt"
	"time"
	"unicode/utf8"

	"github.com/libp2p/go-libp2p"
	libp2pcrypto "github.com/libp2p/go-libp2p/core/crypto"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/peer"
	ma "github.com/multiformats/go-multiaddr"
)

const (
	nseInboxMinTimeoutMs     = 250
	nseInboxMaxTimeoutMs     = 3000
	nseInboxMaxRelayAddrs    = 8
	nseInboxMaxRelayAddrSize = 512
	nseInboxMaxRelayBytes    = 8 * 1024
	nseInboxPageLimit        = 1
)

// ErrNSEInboxInvalidInput reports a rejected action-local credential or relay
// shape. Callers must not include the wrapped detail in user-visible output.
var ErrNSEInboxInvalidInput = errors.New("invalid NSE inbox input")

// ErrNSEInboxIdentityMismatch is returned before networking when the supplied
// transport private key does not derive the exact expected physical peer.
var ErrNSEInboxIdentityMismatch = errors.New("NSE inbox transport identity mismatch")

// NSEInboxOneShotParams contains the complete action-local authority for one
// bounded, non-destructive NSE mailbox read.
type NSEInboxOneShotParams struct {
	TransportPrivateKey     []byte
	ExpectedTransportPeerID string
	RelayMultiaddrs         []string
	TimeoutMs               int
}

// NSEInboxRetrievePendingOneShot creates and closes an ephemeral no-listen host
// without consulting a process-global Node. It reuses the incumbent custody
// negotiation but never ACKs or starts any long-lived Node service.
func NSEInboxRetrievePendingOneShot(
	params NSEInboxOneShotParams,
) (*InboxRetrievePendingResult, error) {
	privateKey, relays, err := validateNSEInboxOneShotParams(params)
	if err != nil {
		return nil, err
	}

	timeoutMs := max(nseInboxMinTimeoutMs, min(nseInboxMaxTimeoutMs, params.TimeoutMs))
	deadline := time.Now().Add(time.Duration(timeoutMs) * time.Millisecond)
	ctx, cancel := context.WithDeadline(context.Background(), deadline)
	defer cancel()

	ephemeralHost, err := libp2p.New(
		libp2p.Identity(privateKey),
		libp2p.NoListenAddrs,
	)
	if err != nil {
		return nil, fmt.Errorf("create NSE inbox host: %w", err)
	}
	defer ephemeralHost.Close()
	if len(ephemeralHost.Addrs()) != 0 {
		return nil, fmt.Errorf("NSE inbox host unexpectedly has listen addresses")
	}

	return retrieveNSEInboxPage(ctx, ephemeralHost, relays, deadline)
}

func validateNSEInboxOneShotParams(
	params NSEInboxOneShotParams,
) (libp2pcrypto.PrivKey, []RelayInfo, error) {
	if len(params.TransportPrivateKey) != ed25519.PrivateKeySize {
		return nil, nil, fmt.Errorf("%w: private key must be %d bytes",
			ErrNSEInboxInvalidInput, ed25519.PrivateKeySize)
	}
	privateKey, err := libp2pcrypto.UnmarshalEd25519PrivateKey(params.TransportPrivateKey)
	if err != nil {
		return nil, nil, fmt.Errorf("%w: invalid Ed25519 private key", ErrNSEInboxInvalidInput)
	}
	derivedPeer, err := peer.IDFromPrivateKey(privateKey)
	if err != nil {
		return nil, nil, fmt.Errorf("%w: derive transport peer", ErrNSEInboxInvalidInput)
	}
	expectedPeer, err := peer.Decode(params.ExpectedTransportPeerID)
	if err != nil || expectedPeer.String() != params.ExpectedTransportPeerID {
		return nil, nil, fmt.Errorf("%w: expected peer is not canonical", ErrNSEInboxInvalidInput)
	}
	if derivedPeer != expectedPeer {
		return nil, nil, ErrNSEInboxIdentityMismatch
	}

	relays, err := parseNSEInboxRelayMultiaddrs(params.RelayMultiaddrs)
	if err != nil {
		return nil, nil, err
	}
	return privateKey, relays, nil
}

func parseNSEInboxRelayMultiaddrs(rawAddrs []string) ([]RelayInfo, error) {
	if len(rawAddrs) == 0 || len(rawAddrs) > nseInboxMaxRelayAddrs {
		return nil, fmt.Errorf("%w: relay address count out of bounds", ErrNSEInboxInvalidInput)
	}
	totalBytes := 0
	seenAddrs := make(map[string]struct{}, len(rawAddrs))
	relayIndex := make(map[peer.ID]int, len(rawAddrs))
	relays := make([]RelayInfo, 0, len(rawAddrs))
	for _, raw := range rawAddrs {
		if !utf8.ValidString(raw) || len(raw) == 0 || len(raw) > nseInboxMaxRelayAddrSize {
			return nil, fmt.Errorf("%w: relay address size out of bounds", ErrNSEInboxInvalidInput)
		}
		totalBytes += len(raw)
		if totalBytes > nseInboxMaxRelayBytes {
			return nil, fmt.Errorf("%w: aggregate relay address bytes out of bounds", ErrNSEInboxInvalidInput)
		}
		if _, duplicate := seenAddrs[raw]; duplicate {
			return nil, fmt.Errorf("%w: duplicate relay address", ErrNSEInboxInvalidInput)
		}
		seenAddrs[raw] = struct{}{}

		multiaddr, err := ma.NewMultiaddr(raw)
		if err != nil || multiaddr.String() != raw {
			return nil, fmt.Errorf("%w: relay address is not canonical", ErrNSEInboxInvalidInput)
		}
		info, err := peer.AddrInfoFromP2pAddr(multiaddr)
		if err != nil || info.ID.String() == "" || len(info.Addrs) != 1 {
			return nil, fmt.Errorf("%w: relay address lacks one canonical peer route", ErrNSEInboxInvalidInput)
		}
		if index, exists := relayIndex[info.ID]; exists {
			relays[index].Addrs = append(relays[index].Addrs, info.Addrs[0])
			continue
		}
		relayIndex[info.ID] = len(relays)
		relays = append(relays, RelayInfo{ID: info.ID, Addrs: []ma.Multiaddr{info.Addrs[0]}})
	}
	return relays, nil
}

func retrieveNSEInboxPage(
	ctx context.Context,
	ephemeralHost host.Host,
	relays []RelayInfo,
	deadline time.Time,
) (*InboxRetrievePendingResult, error) {
	allMessages := make([]InboxMessage, 0, len(relays))
	sourceHasMore := false
	validPeers := 0
	failedPeers := 0
	var lastErr error
	for index, relay := range relays {
		if ctx.Err() != nil {
			failedPeers += len(relays) - index
			lastErr = ctx.Err()
			break
		}
		leg, err := retrieveAckCustodyRelayWithExchange(
			relay,
			nseInboxPageLimit,
			func(candidate RelayInfo, request inboxRequest) ([]byte, error) {
				return exchangeNSEInboxRequest(ctx, ephemeralHost, candidate, request, deadline)
			},
		)
		if err != nil {
			failedPeers++
			lastErr = err
			continue
		}
		validPeers++
		allMessages = append(allMessages, leg.Messages...)
		sourceHasMore = sourceHasMore || leg.HasMore
	}

	merged, err := coalesceAndSortInboxCustodyMessages(allMessages)
	if err != nil {
		return nil, err
	}
	if validPeers == 0 || (len(merged) == 0 && failedPeers != 0) {
		if lastErr == nil {
			lastErr = ErrInboxCustodyPartial
		}
		return nil, fmt.Errorf("%w: incomplete NSE inbox scan: %v", ErrInboxCustodyPartial, lastErr)
	}
	page, hasMore, err := fitNSEInboxPage(
		merged,
		sourceHasMore || failedPeers != 0,
	)
	if err != nil {
		return nil, err
	}
	return &InboxRetrievePendingResult{
		Messages:        page,
		HasMore:         hasMore,
		CustodyContract: AckOrExpiryCustodyContract,
	}, nil
}

func exchangeNSEInboxRequest(
	ctx context.Context,
	ephemeralHost host.Host,
	relay RelayInfo,
	request inboxRequest,
	deadline time.Time,
) ([]byte, error) {
	if !time.Now().Before(deadline) {
		return nil, context.DeadlineExceeded
	}
	if err := ephemeralHost.Connect(ctx, peer.AddrInfo{ID: relay.ID, Addrs: relay.Addrs}); err != nil {
		return nil, fmt.Errorf("connect to NSE relay: %w", err)
	}
	stream, err := ephemeralHost.NewStream(ctx, relay.ID, InboxProtocol)
	if err != nil {
		return nil, fmt.Errorf("open NSE inbox stream: %w", err)
	}
	streamOK := false
	defer finishStream(stream, &streamOK)
	if err := stream.SetDeadline(deadline); err != nil {
		return nil, fmt.Errorf("set NSE inbox stream deadline: %w", err)
	}
	rawRequest, err := json.Marshal(request)
	if err != nil {
		return nil, fmt.Errorf("marshal NSE inbox request: %w", err)
	}
	if err := writeFrame(stream, rawRequest); err != nil {
		return nil, fmt.Errorf("write NSE inbox request: %w", err)
	}
	rawResponse, err := readFrame(stream)
	if err != nil {
		return nil, fmt.Errorf("read NSE inbox response: %w", err)
	}
	streamOK = true
	return rawResponse, nil
}

func fitNSEInboxPage(
	messages []InboxMessage,
	sourceHasMore bool,
) ([]InboxMessage, bool, error) {
	limit := min(len(messages), nseInboxPageLimit)
	page := append([]InboxMessage(nil), messages[:limit]...)
	hasMore := sourceHasMore || len(messages) > limit
	encoded, err := json.Marshal(inboxResponse{
		Status:          "OK",
		Messages:        page,
		HasMore:         hasMore,
		CustodyContract: AckOrExpiryCustodyContract,
	})
	if err != nil {
		return nil, false, fmt.Errorf("marshal NSE inbox page: %w", err)
	}
	if len(encoded) > MaxFrameLen {
		return nil, false, fmt.Errorf("%w: first NSE inbox entry exceeds frame limit", ErrInboxCustodyInvalidReceipt)
	}
	return page, hasMore, nil
}
