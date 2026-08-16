package bridge

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
	nseInboxInvalidInputMessage     = "invalid NSE inbox request"
	nseInboxIdentityMismatchMessage = "NSE inbox transport identity mismatch"
	nseInboxUnavailableMessage      = "NSE inbox retrieval unavailable"
	nseInboxInternalMessage         = "NSE inbox retrieval failed"
)

type nseInboxBridgeParams struct {
	transportPrivateKey     []byte
	expectedTransportPeerID string
	relayMultiaddrs         []string
	timeoutMs               int
}

// NSEInboxRetrievePending is the gomobile-safe Plan-373 entrypoint for one
// action-local, non-destructive NSE mailbox read. It never consults the bridge
// singleton and never returns credential, relay or raw transport errors.
//
// The exact request is:
//
//	{"transportPrivateKeyBase64":"...","expectedTransportPeerId":"...","relayMultiaddrs":["..."],"timeoutMs":250}
func NSEInboxRetrievePending(paramsJSON string) (result string) {
	defer func() {
		if recover() != nil {
			result = errJSON("INTERNAL_ERROR", nseInboxInternalMessage)
		}
	}()

	params, err := parseNSEInboxBridgeParams(paramsJSON)
	if err != nil {
		return errJSON("INVALID_INPUT", nseInboxInvalidInputMessage)
	}
	page, err := node.NSEInboxRetrievePendingOneShot(node.NSEInboxOneShotParams{
		TransportPrivateKey:     params.transportPrivateKey,
		ExpectedTransportPeerID: params.expectedTransportPeerID,
		RelayMultiaddrs:         params.relayMultiaddrs,
		TimeoutMs:               params.timeoutMs,
	})
	if errors.Is(err, node.ErrNSEInboxInvalidInput) {
		return errJSON("INVALID_INPUT", nseInboxInvalidInputMessage)
	}
	if errors.Is(err, node.ErrNSEInboxIdentityMismatch) {
		return errJSON("IDENTITY_MISMATCH", nseInboxIdentityMismatchMessage)
	}
	if err != nil || page == nil || len(page.Messages) > 1 ||
		page.CustodyContract != node.AckOrExpiryCustodyContract {
		return errJSON("INBOX_UNAVAILABLE", nseInboxUnavailableMessage)
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
	return okJSON(map[string]interface{}{
		"ok":              true,
		"messages":        messages,
		"hasMore":         page.HasMore,
		"custodyContract": page.CustodyContract,
	})
}

func parseNSEInboxBridgeParams(raw string) (nseInboxBridgeParams, error) {
	decoder := json.NewDecoder(bytes.NewReader([]byte(raw)))
	start, err := decoder.Token()
	if err != nil {
		return nseInboxBridgeParams{}, err
	}
	if delimiter, ok := start.(json.Delim); !ok || delimiter != '{' {
		return nseInboxBridgeParams{}, errors.New("request is not an object")
	}

	seen := make(map[string]struct{}, 4)
	privateKeyBase64 := ""
	params := nseInboxBridgeParams{}
	for decoder.More() {
		token, err := decoder.Token()
		if err != nil {
			return nseInboxBridgeParams{}, err
		}
		key, ok := token.(string)
		if !ok {
			return nseInboxBridgeParams{}, errors.New("request key is not a string")
		}
		if _, duplicate := seen[key]; duplicate {
			return nseInboxBridgeParams{}, errors.New("duplicate request key")
		}
		seen[key] = struct{}{}
		switch key {
		case "transportPrivateKeyBase64":
			if err := decoder.Decode(&privateKeyBase64); err != nil {
				return nseInboxBridgeParams{}, err
			}
		case "expectedTransportPeerId":
			if err := decoder.Decode(&params.expectedTransportPeerID); err != nil {
				return nseInboxBridgeParams{}, err
			}
		case "relayMultiaddrs":
			if err := decoder.Decode(&params.relayMultiaddrs); err != nil {
				return nseInboxBridgeParams{}, err
			}
		case "timeoutMs":
			if err := decoder.Decode(&params.timeoutMs); err != nil {
				return nseInboxBridgeParams{}, err
			}
		default:
			return nseInboxBridgeParams{}, errors.New("unknown request key")
		}
	}
	if _, err := decoder.Token(); err != nil {
		return nseInboxBridgeParams{}, err
	}
	if err := decoder.Decode(&struct{}{}); err != io.EOF {
		return nseInboxBridgeParams{}, errors.New("request has trailing JSON")
	}
	for _, required := range []string{
		"transportPrivateKeyBase64",
		"expectedTransportPeerId",
		"relayMultiaddrs",
		"timeoutMs",
	} {
		if _, exists := seen[required]; !exists {
			return nseInboxBridgeParams{}, errors.New("request key is missing")
		}
	}

	privateKey, err := base64.StdEncoding.Strict().DecodeString(privateKeyBase64)
	if err != nil || len(privateKey) != ed25519.PrivateKeySize ||
		base64.StdEncoding.EncodeToString(privateKey) != privateKeyBase64 {
		return nseInboxBridgeParams{}, errors.New("private key base64 is not canonical")
	}
	params.transportPrivateKey = privateKey
	return params, nil
}
