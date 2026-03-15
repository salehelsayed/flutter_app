package node

import (
	"context"
	"time"
)

// startPersonalRendezvousRefreshLoop is Phase 0 scaffolding for the future
// personal rendezvous refresh loop. It is intentionally not wired into
// Start() yet; tests call it directly to lock the loop semantics before the
// production rollout begins.
func (n *Node) startPersonalRendezvousRefreshLoop(interval time.Duration) {
	if interval <= 0 {
		return
	}

	n.mu.Lock()
	if !n.isStarted || n.ctx == nil || n.lastConfig == nil || !n.lastConfig.AutoRegister {
		n.mu.Unlock()
		return
	}
	if n.personalRendezvousRefreshCancel != nil {
		n.mu.Unlock()
		return
	}

	loopCtx, cancel := context.WithCancel(n.ctx)
	n.personalRendezvousRefreshCancel = cancel
	n.mu.Unlock()

	go func() {
		ticker := time.NewTicker(interval)
		defer ticker.Stop()
		defer func() {
			n.mu.Lock()
			if n.personalRendezvousRefreshCancel != nil {
				n.personalRendezvousRefreshCancel = nil
			}
			n.mu.Unlock()
		}()

		for {
			select {
			case <-loopCtx.Done():
				return
			case <-ticker.C:
				n.mu.RLock()
				namespace := n.namespace
				n.mu.RUnlock()
				if namespace == "" {
					continue
				}
				_ = n.rendezvousRegisterForStart(namespace, nil)
			}
		}
	}()
}
