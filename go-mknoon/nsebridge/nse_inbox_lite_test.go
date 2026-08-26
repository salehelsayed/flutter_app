//go:build nse_lite

package bridge

import (
	"encoding/base64"
	"encoding/json"
	"strings"
	"testing"
)

func TestNSEInboxRetrievePendingLiteFailsClosed(t *testing.T) {
	request, err := json.Marshal(map[string]interface{}{
		"transportPrivateKeyBase64": base64.StdEncoding.EncodeToString(make([]byte, 64)),
		"expectedTransportPeerId":   "12D3KooWExpectedTransport",
		"relayMultiaddrs":           []string{"/dns4/relay.example/tcp/4001"},
		"timeoutMs":                 1000,
	})
	if err != nil {
		t.Fatal(err)
	}

	result := NSEInboxRetrievePending(string(request))
	if !strings.Contains(result, `"errorCode":"INBOX_UNAVAILABLE"`) {
		t.Fatalf("lite bridge must fail fixed inbox wakes closed: %s", result)
	}
	if strings.Contains(result, "transportPrivateKeyBase64") ||
		strings.Contains(result, "12D3KooWExpectedTransport") {
		t.Fatalf("error disclosed private request material: %s", result)
	}
}
