package bridge

import "github.com/mknoon/go-mknoon/internal/nsepush"

// Retained for the bridge package's compatibility tests and callers that
// compare the privacy-safe public error contract.
const nseInboxIdentityMismatchMessage = "NSE inbox transport identity mismatch"

// NSEInboxRetrievePending is the app bridge entrypoint for the shared,
// action-local notification-service mailbox read.
func NSEInboxRetrievePending(paramsJSON string) string {
	return nsepush.RetrievePending(paramsJSON)
}
