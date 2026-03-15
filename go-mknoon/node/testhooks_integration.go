//go:build integration

package node

import "time"

// SetWaitForCircuitAddressHookForTests overrides circuit-address readiness in
// integration tests that use the local relay harness.
func (n *Node) SetWaitForCircuitAddressHookForTests(hook func(time.Duration) bool) {
	n.waitForCircuitAddressHook = hook
}
