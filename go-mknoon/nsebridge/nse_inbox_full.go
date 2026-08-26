//go:build !nse_lite

package bridge

import "github.com/mknoon/go-mknoon/internal/nsepush"

// NSEInboxRetrievePending retains the one-shot mailbox capability for host Go
// tests and non-extension consumers. The iOS extension uses the nse_lite build
// because importing libp2p exceeds Apple's notification-extension memory cap.
func NSEInboxRetrievePending(paramsJSON string) string {
	return nsepush.RetrievePending(paramsJSON)
}
