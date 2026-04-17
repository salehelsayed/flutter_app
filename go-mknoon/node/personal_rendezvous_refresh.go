package node

import (
	"context"
	"errors"
	"fmt"
	"log"
	"time"
)

var errPersonalRendezvousRegisterInFlight = errors.New("personal rendezvous registration already in flight")

func (n *Node) autoRegisterPersonalNamespaceForStart() {
	totalStart := time.Now()

	circuitStart := time.Now()
	circuitOk := n.waitForCircuitAddressForStart(10 * time.Second)
	circuitAddressMs := time.Since(circuitStart).Milliseconds()
	circuitOutcome := "found"
	if !circuitOk {
		circuitOutcome = "timeout"
	}

	if !circuitOk {
		n.emitEvent("node:startup_timing", map[string]interface{}{
			"phase":                 "discoverable",
			"circuitAddressMs":      circuitAddressMs,
			"circuitAddressOutcome": circuitOutcome,
			"totalToDiscoverableMs": time.Since(totalStart).Milliseconds(),
		})
		log.Printf("[NODE] auto-register skipped: no circuit address ready")
		return
	}

	n.mu.RLock()
	namespace := n.namespace
	n.mu.RUnlock()
	if namespace == "" {
		log.Printf("[NODE] auto-register skipped: no personal namespace configured")
		return
	}

	regStart := time.Now()
	err := n.registerPersonalRendezvousNamespace(namespace, nil)
	rendezvousRegisterMs := time.Since(regStart).Milliseconds()

	n.emitEvent("node:startup_timing", map[string]interface{}{
		"phase":                 "discoverable",
		"circuitAddressMs":      circuitAddressMs,
		"circuitAddressOutcome": circuitOutcome,
		"rendezvousRegisterMs":  rendezvousRegisterMs,
		"totalToDiscoverableMs": time.Since(totalStart).Milliseconds(),
	})

	if err != nil {
		if errors.Is(err, errPersonalRendezvousRegisterInFlight) {
			log.Printf("[NODE] auto-register skipped: personal registration already in flight")
			return
		}
		log.Printf("[NODE] auto-register failed: %v", err)
		return
	}
}

func (n *Node) maybeStartPersonalRendezvousRefreshLoopAfterRegister(namespace string) {
	n.mu.RLock()
	started := n.isStarted
	ctx := n.ctx
	personalNamespace := n.namespace
	cfg := n.lastConfig
	n.mu.RUnlock()

	if !started || ctx == nil || ctx.Err() != nil || cfg == nil || !cfg.AutoRegister {
		return
	}
	if namespace == "" || namespace != personalNamespace {
		return
	}

	n.startPersonalRendezvousRefreshLoop(cfg.PersonalRendezvousRefreshEvery())
}

func (n *Node) registerPersonalRendezvousNamespace(namespace string, serverAddresses []string) error {
	if namespace == "" {
		return fmt.Errorf("personal namespace not set")
	}
	if !n.personalRendezvousRegistering.CompareAndSwap(false, true) {
		return errPersonalRendezvousRegisterInFlight
	}
	defer n.personalRendezvousRegistering.Store(false)

	if err := n.rendezvousRegisterForStart(namespace, serverAddresses); err != nil {
		return err
	}

	n.maybeStartPersonalRendezvousRefreshLoopAfterRegister(namespace)
	return nil
}

func (n *Node) recoverPersonalRendezvousRegistration(trigger string) (int64, error) {
	start := time.Now()

	n.mu.RLock()
	started := n.isStarted
	ctx := n.ctx
	cfg := n.lastConfig
	namespace := n.namespace
	n.mu.RUnlock()

	if !started || ctx == nil || ctx.Err() != nil || cfg == nil || !cfg.AutoRegister || namespace == "" {
		return 0, nil
	}

	if err := n.registerPersonalRendezvousNamespace(namespace, nil); err != nil {
		if errors.Is(err, errPersonalRendezvousRegisterInFlight) {
			log.Printf("[NODE] %s personal re-register coalesced: registration already in flight", trigger)
			return 0, nil
		}
		return 0, err
	}

	log.Printf("[NODE] %s personal namespace re-registered: ns=%s", trigger, namespace)
	return time.Since(start).Milliseconds(), nil
}

func (n *Node) finalizeRelayRecoveryResult(result *RecoveryResult, trigger string) *RecoveryResult {
	if result == nil {
		result = &RecoveryResult{
			RecoveryMode: "in_place",
			Success:      false,
			ErrorCode:    "RECOVERY_NIL",
			Reason:       "recovery returned nil result",
		}
	}
	if result.ForegroundRecoveryPath == "" {
		result.ForegroundRecoveryPath = "background_fallback"
	}
	if result.ForegroundRelayDialTimeoutMs == 0 {
		result.ForegroundRelayDialTimeoutMs = ForegroundRelayDialTimeout.Milliseconds()
	}
	if result.AutorelayRetryCadenceMs == 0 {
		result.AutorelayRetryCadenceMs = ForegroundAutoRelayRetryCadence.Milliseconds()
	}
	if !result.Success {
		return result
	}

	personalReregisterMs, err := n.recoverPersonalRendezvousRegistration(trigger)
	result.PersonalReregisterMs = personalReregisterMs
	if err != nil {
		result.Success = false
		result.ErrorCode = "PERSONAL_REREGISTER_FAILED"
		result.Reason = err.Error()
	}
	return result
}

func (n *Node) startPersonalRendezvousRefreshLoop(interval time.Duration) {
	if interval <= 0 {
		interval = DefaultPersonalRendezvousRefreshEvery
	}

	n.mu.Lock()
	if !n.isStarted || n.ctx == nil || n.ctx.Err() != nil || n.lastConfig == nil || !n.lastConfig.AutoRegister || n.namespace == "" {
		n.mu.Unlock()
		return
	}
	if n.personalRendezvousRefreshCancel != nil {
		n.mu.Unlock()
		return
	}

	namespace := n.namespace
	loopCtx, cancel := context.WithCancel(n.ctx)
	n.personalRendezvousRefreshLoopID++
	loopID := n.personalRendezvousRefreshLoopID
	n.personalRendezvousRefreshCancel = cancel
	n.mu.Unlock()

	log.Printf("[NODE] personal rendezvous refresh started: ns=%s interval=%v", namespace, interval)

	go func() {
		ticker := time.NewTicker(interval)
		defer ticker.Stop()
		defer func() {
			n.mu.Lock()
			if n.personalRendezvousRefreshLoopID == loopID {
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
				autoRegister := n.lastConfig != nil && n.lastConfig.AutoRegister
				started := n.isStarted
				n.mu.RUnlock()
				if !started || !autoRegister {
					continue
				}

				if err := n.registerPersonalRendezvousNamespace(namespace, nil); err != nil && !errors.Is(err, errPersonalRendezvousRegisterInFlight) {
					log.Printf("[NODE] personal rendezvous refresh failed: %v", err)
				}
			}
		}
	}()
}

func (n *Node) stopPersonalRendezvousRefreshLoopLocked() {
	if n.personalRendezvousRefreshCancel != nil {
		n.personalRendezvousRefreshCancel()
		n.personalRendezvousRefreshCancel = nil
	}
}
