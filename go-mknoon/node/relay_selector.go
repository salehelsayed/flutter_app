package node

import (
	"fmt"
	"log"
	"sync"

	"github.com/libp2p/go-libp2p/core/peer"
	ma "github.com/multiformats/go-multiaddr"
)

// RelayInfo holds a relay's peer ID and all known multiaddrs for it.
type RelayInfo struct {
	ID    peer.ID
	Addrs []ma.Multiaddr
}

// RelaySelector groups relay multiaddrs by peer ID and provides
// try-each-relay-in-order helpers for failover.
type RelaySelector struct {
	mu     sync.RWMutex
	relays []RelayInfo
}

// NewRelaySelector builds a RelaySelector from raw multiaddr strings.
// Addresses for the same peer ID are merged. Invalid addresses are skipped.
func NewRelaySelector(rawAddrs []string) *RelaySelector {
	infoMap := make(map[peer.ID]*RelayInfo)
	var order []peer.ID // preserve insertion order

	for _, addr := range rawAddrs {
		maddr, err := ma.NewMultiaddr(addr)
		if err != nil {
			log.Printf("[RELAY_SELECTOR] Skip invalid address %s: %v", addr, err)
			continue
		}
		info, err := peer.AddrInfoFromP2pAddr(maddr)
		if err != nil {
			log.Printf("[RELAY_SELECTOR] Skip unparseable address %s: %v", addr, err)
			continue
		}
		if existing, ok := infoMap[info.ID]; ok {
			existing.Addrs = append(existing.Addrs, info.Addrs...)
		} else {
			infoMap[info.ID] = &RelayInfo{ID: info.ID, Addrs: info.Addrs}
			order = append(order, info.ID)
		}
	}

	relays := make([]RelayInfo, 0, len(order))
	for _, id := range order {
		relays = append(relays, *infoMap[id])
	}

	return &RelaySelector{relays: relays}
}

// Relays returns a copy of the relay list in priority order.
func (rs *RelaySelector) Relays() []RelayInfo {
	rs.mu.RLock()
	defer rs.mu.RUnlock()
	out := make([]RelayInfo, len(rs.relays))
	copy(out, rs.relays)
	return out
}

// Len returns the number of distinct relay peers.
func (rs *RelaySelector) Len() int {
	rs.mu.RLock()
	defer rs.mu.RUnlock()
	return len(rs.relays)
}

// First returns the first relay, or an error if there are none.
func (rs *RelaySelector) First() (RelayInfo, error) {
	rs.mu.RLock()
	defer rs.mu.RUnlock()
	if len(rs.relays) == 0 {
		return RelayInfo{}, fmt.Errorf("no relays configured")
	}
	return rs.relays[0], nil
}

// ForEach calls fn for each relay peer in configured order, with all of that
// peer's addresses available for libp2p's Happy Eyeballs dialing. If fn returns
// nil, iteration stops and ForEach returns nil. If
// all relays fail, the last error is returned with context about the number of
// relays tried.
func (rs *RelaySelector) ForEach(fn func(relay RelayInfo) error) error {
	rs.mu.RLock()
	relays := make([]RelayInfo, len(rs.relays))
	copy(relays, rs.relays)
	rs.mu.RUnlock()

	if len(relays) == 0 {
		return fmt.Errorf("no relays configured")
	}

	var lastErr error
	for i, relay := range relays {
		candidates := relayInfoAttemptCandidates(relay)
		for j, candidate := range candidates {
			err := fn(candidate)
			if err == nil {
				return nil
			}
			lastErr = err
			log.Printf("[RELAY_SELECTOR] Relay %d/%d addr %d/%d (%s) failed: %v",
				i+1, len(relays), j+1, len(candidates), relay.ID.String()[:min(20, len(relay.ID.String()))], err)
		}
	}

	return fmt.Errorf("all %d relays failed, last error: %w", len(relays), lastErr)
}

// FanOut calls fn for every relay with its complete address set.
// Returns nil if at least one relay succeeds, otherwise returns the last error.
func (rs *RelaySelector) FanOut(fn func(relay RelayInfo) error) error {
	rs.mu.RLock()
	relays := make([]RelayInfo, len(rs.relays))
	copy(relays, rs.relays)
	rs.mu.RUnlock()

	if len(relays) == 0 {
		return fmt.Errorf("no relays configured")
	}

	type relayJob struct {
		index int
		relay RelayInfo
	}
	workers := min(len(relays), 3)
	jobs := make(chan relayJob)
	var wg sync.WaitGroup
	var mu sync.Mutex
	var lastErr error
	successCount := 0
	for i := 0; i < workers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for job := range jobs {
				if err := fanOutRelay(job.relay, job.index, len(relays), fn); err != nil {
					mu.Lock()
					lastErr = err
					mu.Unlock()
					continue
				}
				mu.Lock()
				successCount++
				mu.Unlock()
			}
		}()
	}
	for i, relay := range relays {
		jobs <- relayJob{index: i, relay: relay}
	}
	close(jobs)
	wg.Wait()

	if successCount > 0 {
		return nil
	}

	return fmt.Errorf("all %d relays failed, last error: %w", len(relays), lastErr)
}

func fanOutRelay(relay RelayInfo, index int, relayCount int, fn func(relay RelayInfo) error) error {
	candidates := relayInfoAttemptCandidates(relay)
	var lastErr error
	for j, candidate := range candidates {
		err := fn(candidate)
		if err == nil {
			return nil
		}
		lastErr = err
		log.Printf("[RELAY_SELECTOR] Relay %d/%d addr %d/%d (%s) failed: %v",
			index+1, relayCount, j+1, len(candidates), relay.ID.String()[:min(20, len(relay.ID.String()))], err)
	}
	return lastErr
}

// ForEachWithResult calls fn for each relay peer in configured order. If fn
// returns a non-nil result and nil error, iteration stops and the result is
// returned. If all relays fail, the last error is returned.
func ForEachWithResult[T any](rs *RelaySelector, fn func(relay RelayInfo) (T, error)) (T, error) {
	rs.mu.RLock()
	relays := make([]RelayInfo, len(rs.relays))
	copy(relays, rs.relays)
	rs.mu.RUnlock()

	var zero T
	if len(relays) == 0 {
		return zero, fmt.Errorf("no relays configured")
	}

	var lastErr error
	for i, relay := range relays {
		candidates := relayInfoAttemptCandidates(relay)
		for j, candidate := range candidates {
			result, err := fn(candidate)
			if err == nil {
				return result, nil
			}
			lastErr = err
			log.Printf("[RELAY_SELECTOR] Relay %d/%d addr %d/%d (%s) failed: %v",
				i+1, len(relays), j+1, len(candidates), relay.ID.String()[:min(20, len(relay.ID.String()))], err)
		}
	}

	return zero, fmt.Errorf("all %d relays failed, last error: %w", len(relays), lastErr)
}

func relayInfoAttemptCandidates(relay RelayInfo) []RelayInfo {
	// Address fallback belongs to the swarm, which can race families and
	// transports under one deadline. Retrying the operation per address would
	// serialize dials and could repeat a request after a protocol-level error.
	return []RelayInfo{relay}
}

// buildRelaySelector creates a RelaySelector from the provided addresses,
// falling back to the node's configured relayAddresses, then to defaults.
func (n *Node) buildRelaySelector(serverAddresses []string) *RelaySelector {
	addrs := serverAddresses
	if len(addrs) == 0 {
		n.mu.RLock()
		addrs = n.relayAddresses
		n.mu.RUnlock()
	}
	if len(addrs) == 0 {
		addrs = DefaultRelayAddresses()
	}
	addrs = limitRelayAddresses(addrs, n.currentFeatureFlags())
	return NewRelaySelector(addrs)
}
