package bridge

import (
	"errors"

	"github.com/mknoon/go-mknoon/node"
)

var turnCredentialsV1Fetch = func(n *node.Node) (node.TurnCredentialBundle, error) {
	return n.TurnCredentialsV1()
}

// TurnCredentialsV1 obtains a short-lived authenticated TURN bundle. It takes
// no payload: the relay binds issuance to the authenticated libp2p stream.
func TurnCredentialsV1() (result string) {
	defer func() {
		if recover() != nil {
			result = errJSON("INTERNAL_ERROR", "TURN credential bridge failure")
		}
	}()

	nodeMu.Lock()
	n := singletonNode
	nodeMu.Unlock()
	if n == nil {
		return errJSON("NOT_INITIALIZED", "call Initialize first")
	}

	bundle, err := turnCredentialsV1Fetch(n)
	if err != nil {
		return turnCredentialsV1ErrorJSON(err)
	}
	return okJSON(map[string]interface{}{
		"ok":           true,
		"schema":       bundle.Schema,
		"version":      bundle.Version,
		"urls":         bundle.URLs,
		"username":     bundle.Username,
		"password":     bundle.Password,
		"ttlSeconds":   bundle.TTLSeconds,
		"expiresAtMs":  bundle.ExpiresAtMs,
		"serverTimeMs": bundle.ServerTimeMs,
	})
}

func turnCredentialsV1ErrorJSON(err error) string {
	switch {
	case errors.Is(err, node.ErrTurnCredentialsUnsupported):
		return okJSON(map[string]interface{}{
			"ok":           false,
			"unsupported":  true,
			"errorCode":    "TURN_CREDENTIALS_UNSUPPORTED",
			"errorMessage": "Relay does not support credential action",
		})
	case errors.Is(err, node.ErrTurnCredentialsInvalidResponse):
		return errJSON("TURN_CREDENTIALS_INVALID_RESPONSE", "Relay returned an invalid credential response")
	}

	var relayErr *node.TurnCredentialsRelayError
	if errors.As(err, &relayErr) {
		response := map[string]interface{}{
			"ok":           false,
			"unsupported":  false,
			"errorCode":    "TURN_CREDENTIALS_UNAVAILABLE",
			"errorMessage": "Credential mint temporarily unavailable",
		}
		if relayErr.RetryAfter > 0 {
			response["retryAfterMs"] = relayErr.RetryAfter.Milliseconds()
		}
		return okJSON(response)
	}
	return errJSON("TURN_CREDENTIALS_UNAVAILABLE", "Credential mint temporarily unavailable")
}

// TurnCredentialsWithDiagnosticsV1 adds only optional outer diagnostic metadata.
func TurnCredentialsWithDiagnosticsV1(paramsJSON string) (result string) {
	defer callBridgeRecover(&result)
	n := currentCallBridgeNode()
	if n == nil {
		return errJSON("NOT_INITIALIZED", "call Initialize first")
	}
	_, d := splitCallBridgeDiagnostics(paramsJSON)
	bundle, err := n.TurnCredentialsWithDiagnosticsV1(d)
	if err != nil {
		return turnCredentialsV1ErrorJSON(err)
	}
	return okJSON(map[string]interface{}{"ok": true, "schema": bundle.Schema, "version": bundle.Version, "urls": bundle.URLs, "username": bundle.Username, "password": bundle.Password, "ttlSeconds": bundle.TTLSeconds, "expiresAtMs": bundle.ExpiresAtMs, "serverTimeMs": bundle.ServerTimeMs})
}
