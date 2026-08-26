package nsepush

import (
	"bytes"
	"crypto/ed25519"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"

	"github.com/mknoon/go-mknoon/node"
)

const (
	invalidInputMessage     = "invalid NSE inbox request"
	identityMismatchMessage = "NSE inbox transport identity mismatch"
	inboxUnavailableMessage = "NSE inbox retrieval unavailable"
	internalMessage         = "NSE inbox retrieval failed"
)

type bridgeParams struct {
	transportPrivateKey     []byte
	expectedTransportPeerID string
	relayMultiaddrs         []string
	timeoutMs               int
}

// RetrievePending owns the full one-shot mailbox implementation used by the
// app bridge and host tests. The memory-bounded iOS extension build replaces
// this path with a fail-closed stub so it does not link the libp2p graph.
func RetrievePending(paramsJSON string) (result string) {
	defer func() {
		if recover() != nil {
			result = errorJSON("INTERNAL_ERROR", internalMessage)
		}
	}()

	params, err := parseBridgeParams(paramsJSON)
	if err != nil {
		return errorJSON("INVALID_INPUT", invalidInputMessage)
	}
	page, err := node.NSEInboxRetrievePendingOneShot(node.NSEInboxOneShotParams{
		TransportPrivateKey:     params.transportPrivateKey,
		ExpectedTransportPeerID: params.expectedTransportPeerID,
		RelayMultiaddrs:         params.relayMultiaddrs,
		TimeoutMs:               params.timeoutMs,
	})
	if errors.Is(err, node.ErrNSEInboxInvalidInput) {
		return errorJSON("INVALID_INPUT", invalidInputMessage)
	}
	if errors.Is(err, node.ErrNSEInboxIdentityMismatch) {
		return errorJSON("IDENTITY_MISMATCH", identityMismatchMessage)
	}
	if err != nil || page == nil || len(page.Messages) > 1 ||
		page.CustodyContract != node.AckOrExpiryCustodyContract {
		return errorJSON("INBOX_UNAVAILABLE", inboxUnavailableMessage)
	}

	messages := make([]map[string]interface{}, len(page.Messages))
	for index, message := range page.Messages {
		messages[index] = map[string]interface{}{
			"id":        message.ID,
			"from":      message.From,
			"message":   message.Message,
			"timestamp": message.Timestamp,
		}
	}
	return successJSON(map[string]interface{}{
		"ok":              true,
		"messages":        messages,
		"hasMore":         page.HasMore,
		"custodyContract": page.CustodyContract,
	})
}

func parseBridgeParams(raw string) (bridgeParams, error) {
	decoder := json.NewDecoder(bytes.NewReader([]byte(raw)))
	start, err := decoder.Token()
	if err != nil {
		return bridgeParams{}, err
	}
	if delimiter, ok := start.(json.Delim); !ok || delimiter != '{' {
		return bridgeParams{}, errors.New("request is not an object")
	}

	seen := make(map[string]struct{}, 4)
	privateKeyBase64 := ""
	params := bridgeParams{}
	for decoder.More() {
		token, err := decoder.Token()
		if err != nil {
			return bridgeParams{}, err
		}
		key, ok := token.(string)
		if !ok {
			return bridgeParams{}, errors.New("request key is not a string")
		}
		if _, duplicate := seen[key]; duplicate {
			return bridgeParams{}, errors.New("duplicate request key")
		}
		seen[key] = struct{}{}
		switch key {
		case "transportPrivateKeyBase64":
			if err := decoder.Decode(&privateKeyBase64); err != nil {
				return bridgeParams{}, err
			}
		case "expectedTransportPeerId":
			if err := decoder.Decode(&params.expectedTransportPeerID); err != nil {
				return bridgeParams{}, err
			}
		case "relayMultiaddrs":
			if err := decoder.Decode(&params.relayMultiaddrs); err != nil {
				return bridgeParams{}, err
			}
		case "timeoutMs":
			if err := decoder.Decode(&params.timeoutMs); err != nil {
				return bridgeParams{}, err
			}
		default:
			return bridgeParams{}, errors.New("unknown request key")
		}
	}
	if _, err := decoder.Token(); err != nil {
		return bridgeParams{}, err
	}
	if err := decoder.Decode(&struct{}{}); err != io.EOF {
		return bridgeParams{}, errors.New("request has trailing JSON")
	}
	for _, required := range []string{
		"transportPrivateKeyBase64",
		"expectedTransportPeerId",
		"relayMultiaddrs",
		"timeoutMs",
	} {
		if _, exists := seen[required]; !exists {
			return bridgeParams{}, errors.New("request key is missing")
		}
	}

	privateKey, err := base64.StdEncoding.Strict().DecodeString(privateKeyBase64)
	if err != nil || len(privateKey) != ed25519.PrivateKeySize ||
		base64.StdEncoding.EncodeToString(privateKey) != privateKeyBase64 {
		return bridgeParams{}, errors.New("private key base64 is not canonical")
	}
	params.transportPrivateKey = privateKey
	return params, nil
}

func successJSON(value map[string]interface{}) string {
	encoded, err := json.Marshal(value)
	if err != nil {
		return errorJSON("INTERNAL_ERROR", internalMessage)
	}
	return string(encoded)
}

func errorJSON(code, message string) string {
	encoded, _ := json.Marshal(map[string]interface{}{
		"ok":           false,
		"errorCode":    code,
		"errorMessage": message,
	})
	return string(encoded)
}
