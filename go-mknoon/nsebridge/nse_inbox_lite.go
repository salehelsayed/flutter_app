//go:build nse_lite

package bridge

import "encoding/json"

// NSEInboxRetrievePending fails closed in the memory-bounded iOS extension.
// iOS must not advertise opaque_wake_v1 while this build is installed; rich
// ciphertext notifications continue to use the direct/group decrypt exports.
func NSEInboxRetrievePending(paramsJSON string) string {
	var request map[string]interface{}
	if err := json.Unmarshal([]byte(paramsJSON), &request); err != nil || len(request) != 4 {
		return errorJSON("INVALID_INPUT", "invalid NSE inbox request")
	}
	for _, key := range []string{
		"transportPrivateKeyBase64",
		"expectedTransportPeerId",
		"relayMultiaddrs",
		"timeoutMs",
	} {
		if _, exists := request[key]; !exists {
			return errorJSON("INVALID_INPUT", "invalid NSE inbox request")
		}
	}
	return errorJSON("INBOX_UNAVAILABLE", "NSE inbox retrieval unavailable")
}
