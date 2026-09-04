package bridge

import (
	"encoding/json"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/mknoon/go-mknoon/node"
)

func TestTurnCredentialsV1Bridge_NoPayloadAndExactSuccessJSON(t *testing.T) {
	withSingletonNode(t)
	previous := turnCredentialsV1Fetch
	turnCredentialsV1Fetch = func(*node.Node) (node.TurnCredentialBundle, error) {
		return node.TurnCredentialBundle{
			Schema:       "turn_credentials",
			Version:      1,
			URLs:         []string{"turn:relay.invalid:3478?transport=udp", "turns:relay.invalid:443?transport=tcp"},
			Username:     "synthetic-user-never-log",
			Password:     "synthetic-password-never-log",
			TTLSeconds:   600,
			ExpiresAtMs:  1_800_000_600_000,
			ServerTimeMs: 1_800_000_000_000,
		}, nil
	}
	t.Cleanup(func() { turnCredentialsV1Fetch = previous })

	// The zero-argument signature is load-bearing: this action derives identity
	// from the authenticated relay stream and accepts no caller payload.
	result := TurnCredentialsV1()
	var got map[string]any
	if json.Unmarshal([]byte(result), &got) != nil || got["ok"] != true {
		t.Fatal("TURN credential bridge did not return a valid success envelope")
	}
	if got["schema"] != "turn_credentials" || got["version"] != float64(1) ||
		got["username"] != "synthetic-user-never-log" ||
		got["password"] != "synthetic-password-never-log" ||
		got["ttlSeconds"] != float64(600) ||
		got["expiresAtMs"] != float64(1_800_000_600_000) ||
		got["serverTimeMs"] != float64(1_800_000_000_000) {
		t.Fatal("TURN credential bridge changed the canonical JSON schema")
	}
	urls, ok := got["urls"].([]any)
	if !ok || len(urls) != 2 ||
		urls[0] != "turn:relay.invalid:3478?transport=udp" ||
		urls[1] != "turns:relay.invalid:443?transport=tcp" {
		t.Fatal("TURN credential bridge did not preserve URL order")
	}
	for _, forbidden := range []string{"peerId", "from", "to", "staticPassword", "sharedSecret"} {
		if _, present := got[forbidden]; present {
			t.Fatal("TURN credential bridge exposed forbidden identity/static material")
		}
	}
}

func TestTurnCredentialsV1Bridge_TypedSafeFailures(t *testing.T) {
	t.Run("not initialized", func(t *testing.T) {
		withNilSingleton(t)
		got := parseJSON(t, TurnCredentialsV1())
		assertNotOk(t, got, "NOT_INITIALIZED")
	})

	tests := []struct {
		name      string
		err       error
		wantCode  string
		wantRetry float64
	}{
		{name: "old relay", err: node.ErrTurnCredentialsUnsupported, wantCode: "TURN_CREDENTIALS_UNSUPPORTED"},
		{name: "invalid response", err: node.ErrTurnCredentialsInvalidResponse, wantCode: "TURN_CREDENTIALS_INVALID_RESPONSE"},
		{name: "finite relay failure", err: &node.TurnCredentialsRelayError{Code: "RATE_LIMITED", RetryAfter: 2500 * time.Millisecond}, wantCode: "TURN_CREDENTIALS_UNAVAILABLE", wantRetry: 2500},
	}
	for _, testCase := range tests {
		t.Run(testCase.name, func(t *testing.T) {
			withSingletonNode(t)
			previous := turnCredentialsV1Fetch
			turnCredentialsV1Fetch = func(*node.Node) (node.TurnCredentialBundle, error) {
				return node.TurnCredentialBundle{}, testCase.err
			}
			t.Cleanup(func() { turnCredentialsV1Fetch = previous })

			result := TurnCredentialsV1()
			got := parseJSON(t, result)
			assertNotOk(t, got, testCase.wantCode)
			if testCase.wantRetry != 0 && got["retryAfterMs"] != testCase.wantRetry {
				t.Fatal("finite TURN failure lost its bounded retry interval")
			}
			for _, forbidden := range []string{
				"synthetic-user-never-log",
				"synthetic-password-never-log",
				"sharedSecret",
				"rawResponse",
			} {
				if strings.Contains(result, forbidden) {
					t.Fatal("TURN bridge failure echoed sensitive material")
				}
			}
			if errors.Is(testCase.err, node.ErrTurnCredentialsUnsupported) && got["unsupported"] != true {
				t.Fatal("old-relay failure was not explicitly typed unsupported")
			}
		})
	}
}
