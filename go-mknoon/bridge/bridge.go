// Package bridge provides the gomobile-exported API for Flutter integration.
//
// ALL functions take and return JSON strings (gomobile constraint -- no complex
// types across FFI). Each function recovers panics and returns a JSON error
// envelope so the caller never sees an unhandled crash.
//
// JSON protocol:
//
//	Success: { "ok": true, ... }
//	Error:   { "ok": false, "errorCode": "...", "errorMessage": "..." }
package bridge

import (
	"encoding/json"
	"fmt"
	"strings"
	"sync"

	mcrypto "github.com/mknoon/go-mknoon/crypto"
	"github.com/mknoon/go-mknoon/identity"
	"github.com/mknoon/go-mknoon/node"
)

var (
	singletonNode *node.Node
	nodeMu        sync.Mutex
)

// nodeCallbackAdapter adapts bridge.EventCallback to node.EventCallback.
type nodeCallbackAdapter struct {
	cb EventCallback
}

func (a *nodeCallbackAdapter) OnEvent(jsonString string) {
	a.cb.OnEvent(jsonString)
}

// --- Identity ---

// GenerateIdentity creates a new identity with BIP39 mnemonic + Ed25519 keypair.
// Returns JSON: { "ok": true, "identity": { "peerId", "publicKey", "privateKey", "mnemonic12", "createdAt", "updatedAt" } }
// Or: { "ok": false, "errorCode": "INTERNAL_ERROR", "errorMessage": "..." }
func GenerateIdentity() (result string) {
	defer func() {
		if r := recover(); r != nil {
			result = errJSON("INTERNAL_ERROR", fmt.Sprintf("panic: %v", r))
		}
	}()

	id, err := identity.GenerateIdentity()
	if err != nil {
		return errJSON("INTERNAL_ERROR", err.Error())
	}

	return okJSON(map[string]interface{}{
		"ok":       true,
		"identity": identityMap(id),
	})
}

// RestoreIdentity restores identity from mnemonic.
// Input JSON: { "mnemonic12": "word1 word2 ... word12" }
// Returns same format as GenerateIdentity.
func RestoreIdentity(paramsJSON string) (result string) {
	defer func() {
		if r := recover(); r != nil {
			result = errJSON("INTERNAL_ERROR", fmt.Sprintf("panic: %v", r))
		}
	}()

	var params struct {
		Mnemonic12 string `json:"mnemonic12"`
	}
	if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
		return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
	}

	if params.Mnemonic12 == "" {
		return errJSON("INVALID_INPUT", "missing mnemonic12")
	}

	id, err := identity.RestoreIdentity(params.Mnemonic12)
	if err != nil {
		return errJSON("INVALID_MNEMONIC", err.Error())
	}

	return okJSON(map[string]interface{}{
		"ok":       true,
		"identity": identityMap(id),
	})
}

// --- Crypto ---

// MlKemKeygen generates a new ML-KEM-768 key pair.
// Returns JSON: { "ok": true, "publicKey": "<base64>", "secretKey": "<base64>" }
func MlKemKeygen() (result string) {
	defer func() {
		if r := recover(); r != nil {
			result = errJSON("INTERNAL_ERROR", fmt.Sprintf("panic: %v", r))
		}
	}()

	kp, err := mcrypto.MlKemKeygen()
	if err != nil {
		return errJSON("INTERNAL_ERROR", err.Error())
	}

	return okJSON(map[string]interface{}{
		"ok":        true,
		"publicKey": kp.PublicKey,
		"secretKey": kp.SecretKey,
	})
}

// EncryptMessage encrypts a message with ML-KEM-768 + AES-256-GCM.
// Input JSON: { "recipientPublicKey": "<base64>", "plaintext": "..." }
// Returns JSON: { "ok": true, "kem": "<base64>", "ciphertext": "<base64>", "nonce": "<base64>" }
func EncryptMessage(paramsJSON string) (result string) {
	defer func() {
		if r := recover(); r != nil {
			result = errJSON("INTERNAL_ERROR", fmt.Sprintf("panic: %v", r))
		}
	}()

	var params struct {
		RecipientPublicKey string `json:"recipientPublicKey"`
		Plaintext          string `json:"plaintext"`
	}
	if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
		return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
	}

	if params.RecipientPublicKey == "" || params.Plaintext == "" {
		return errJSON("INVALID_INPUT", "missing recipientPublicKey or plaintext")
	}

	enc, err := mcrypto.EncryptMessage(params.RecipientPublicKey, params.Plaintext)
	if err != nil {
		return errJSON("INTERNAL_ERROR", err.Error())
	}

	return okJSON(map[string]interface{}{
		"ok":         true,
		"kem":        enc.Kem,
		"ciphertext": enc.Ciphertext,
		"nonce":      enc.Nonce,
	})
}

// DecryptMessage decrypts a message.
// Input JSON: { "secretKey": "<base64>", "kem": "<base64>", "ciphertext": "<base64>", "nonce": "<base64>" }
// Returns JSON: { "ok": true, "plaintext": "..." }
func DecryptMessage(paramsJSON string) (result string) {
	defer func() {
		if r := recover(); r != nil {
			result = errJSON("INTERNAL_ERROR", fmt.Sprintf("panic: %v", r))
		}
	}()

	var params struct {
		SecretKey  string `json:"secretKey"`
		Kem        string `json:"kem"`
		Ciphertext string `json:"ciphertext"`
		Nonce      string `json:"nonce"`
	}
	if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
		return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
	}

	if params.SecretKey == "" || params.Kem == "" || params.Ciphertext == "" || params.Nonce == "" {
		return errJSON("INVALID_INPUT", "missing secretKey, kem, ciphertext, or nonce")
	}

	plaintext, err := mcrypto.DecryptMessage(params.SecretKey, params.Kem, params.Ciphertext, params.Nonce)
	if err != nil {
		return errJSON("INTERNAL_ERROR", err.Error())
	}

	return okJSON(map[string]interface{}{
		"ok":        true,
		"plaintext": plaintext,
	})
}

// --- Crypto: Sign/Verify ---

// SignPayload signs data with an Ed25519 private key.
// Input JSON: { "privateKey": "<base64>", "data": "<string>" }
// Returns JSON: { "ok": true, "signature": "<base64>" }
func SignPayload(paramsJSON string) (result string) {
	defer func() {
		if r := recover(); r != nil {
			result = errJSON("INTERNAL_ERROR", fmt.Sprintf("panic: %v", r))
		}
	}()

	var params struct {
		PrivateKey string `json:"privateKey"`
		Data       string `json:"data"`
	}
	if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
		return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
	}
	if params.PrivateKey == "" || params.Data == "" {
		return errJSON("INVALID_INPUT", "missing privateKey or data")
	}

	sig, err := mcrypto.SignPayload(params.PrivateKey, params.Data)
	if err != nil {
		return errJSON("INTERNAL_ERROR", err.Error())
	}

	return okJSON(map[string]interface{}{
		"ok":        true,
		"signature": sig,
	})
}

// VerifyPayload verifies an Ed25519 signature.
// Input JSON: { "publicKey": "<base64>", "data": "<string>", "signature": "<base64>" }
// Returns JSON: { "ok": true, "valid": true/false }
func VerifyPayload(paramsJSON string) (result string) {
	defer func() {
		if r := recover(); r != nil {
			result = errJSON("INTERNAL_ERROR", fmt.Sprintf("panic: %v", r))
		}
	}()

	var params struct {
		PublicKey string `json:"publicKey"`
		Data      string `json:"data"`
		Signature string `json:"signature"`
	}
	if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
		return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
	}
	if params.PublicKey == "" || params.Data == "" || params.Signature == "" {
		return errJSON("INVALID_INPUT", "missing publicKey, data, or signature")
	}

	valid, err := mcrypto.VerifyPayload(params.PublicKey, params.Data, params.Signature)
	if err != nil {
		return errJSON("INTERNAL_ERROR", err.Error())
	}

	return okJSON(map[string]interface{}{
		"ok":    true,
		"valid": valid,
	})
}

// --- Node Lifecycle ---

// Initialize sets up the singleton node with an event callback.
// Must be called before StartNode. Safe to call multiple times.
func Initialize(cb EventCallback) {
	nodeMu.Lock()
	defer nodeMu.Unlock()
	if singletonNode == nil {
		singletonNode = node.New(&nodeCallbackAdapter{cb: cb})
	}
}

// StartNode starts the libp2p node.
// Input JSON: { "privateKeyHex": "...", "relayAddresses": [...], "namespace": "...", "autoRegister": true, "listenPort": 0 }
// Returns JSON: { "ok": true, "peerId": "...", "isStarted": true, "addresses": [...], "connections": 0 }
func StartNode(paramsJSON string) (result string) {
	defer func() {
		if r := recover(); r != nil {
			result = errJSON("INTERNAL_ERROR", fmt.Sprintf("panic: %v", r))
		}
	}()

	nodeMu.Lock()
	n := singletonNode
	nodeMu.Unlock()

	if n == nil {
		return errJSON("NOT_INITIALIZED", "call Initialize first")
	}

	var params struct {
		PrivateKeyHex  string   `json:"privateKeyHex"`
		RelayAddresses []string `json:"relayAddresses"`
		Namespace      string   `json:"namespace"`
		AutoRegister   bool     `json:"autoRegister"`
		ListenPort     int      `json:"listenPort"`
	}
	if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
		return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
	}
	if params.PrivateKeyHex == "" {
		return errJSON("INVALID_INPUT", "missing privateKeyHex")
	}

	cfg := node.NodeConfig{
		PrivateKeyHex:  params.PrivateKeyHex,
		RelayAddresses: params.RelayAddresses,
		Namespace:      params.Namespace,
		AutoRegister:   params.AutoRegister,
		ListenPort:     params.ListenPort,
	}

	_, err := n.Start(cfg)
	if err != nil {
		return errJSON("NODE_START_ERROR", err.Error())
	}

	// Return same shape as NodeStatus so Dart can parse uniformly.
	return okJSON(n.Status())
}

// StopNode stops the libp2p node.
// Returns JSON: { "ok": true }
func StopNode() (result string) {
	defer func() {
		if r := recover(); r != nil {
			result = errJSON("INTERNAL_ERROR", fmt.Sprintf("panic: %v", r))
		}
	}()

	nodeMu.Lock()
	n := singletonNode
	nodeMu.Unlock()

	if n == nil {
		return errJSON("NOT_INITIALIZED", "call Initialize first")
	}

	if err := n.Stop(); err != nil {
		return errJSON("NODE_STOP_ERROR", err.Error())
	}

	return okJSON(map[string]interface{}{
		"ok": true,
	})
}

// NodeStatus returns the current node state.
// Returns JSON: { "ok": true, "peerId": "...", "isStarted": ..., "listenAddresses": [...], "circuitAddresses": [...], "connections": [...] }
func NodeStatus() (result string) {
	defer func() {
		if r := recover(); r != nil {
			result = errJSON("INTERNAL_ERROR", fmt.Sprintf("panic: %v", r))
		}
	}()

	nodeMu.Lock()
	n := singletonNode
	nodeMu.Unlock()

	if n == nil {
		return errJSON("NOT_INITIALIZED", "call Initialize first")
	}

	return okJSON(n.Status())
}

// --- Rendezvous ---

// RendezvousRegister registers on a rendezvous namespace.
// Input JSON: { "namespace": "..." } (optional, defaults to node's namespace)
// Returns JSON: { "ok": true }
func RendezvousRegister(paramsJSON string) (result string) {
	defer func() {
		if r := recover(); r != nil {
			result = errJSON("INTERNAL_ERROR", fmt.Sprintf("panic: %v", r))
		}
	}()

	nodeMu.Lock()
	n := singletonNode
	nodeMu.Unlock()

	if n == nil {
		return errJSON("NOT_INITIALIZED", "call Initialize first")
	}

	var params struct {
		Namespace string `json:"namespace"`
	}
	if paramsJSON != "" {
		if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
			return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
		}
	}

	ns := params.Namespace
	if ns == "" {
		ns = n.Namespace()
	}

	if err := n.RendezvousRegister(ns, nil); err != nil {
		return errJSON("RENDEZVOUS_ERROR", err.Error())
	}

	return okJSON(map[string]interface{}{
		"ok": true,
	})
}

// RendezvousDiscover discovers peers on a rendezvous namespace.
// Input JSON: { "namespace": "..." } (optional, defaults to node's namespace)
// Returns JSON: { "ok": true, "peers": [{ "peerId": "...", "addresses": [...] }, ...] }
func RendezvousDiscover(paramsJSON string) (result string) {
	defer func() {
		if r := recover(); r != nil {
			result = errJSON("INTERNAL_ERROR", fmt.Sprintf("panic: %v", r))
		}
	}()

	nodeMu.Lock()
	n := singletonNode
	nodeMu.Unlock()

	if n == nil {
		return errJSON("NOT_INITIALIZED", "call Initialize first")
	}

	var params struct {
		Namespace string `json:"namespace"`
	}
	if paramsJSON != "" {
		if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
			return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
		}
	}

	ns := params.Namespace
	if ns == "" {
		ns = n.Namespace()
	}

	peers, err := n.RendezvousDiscover(ns, nil)
	if err != nil {
		return errJSON("RENDEZVOUS_ERROR", err.Error())
	}

	peerList := make([]map[string]interface{}, len(peers))
	for i, p := range peers {
		addrs := make([]string, len(p.Addrs))
		for j, a := range p.Addrs {
			addrs[j] = a.String()
		}
		peerList[i] = map[string]interface{}{
			"peerId":    p.ID.String(),
			"addresses": addrs,
		}
	}

	return okJSON(map[string]interface{}{
		"ok":    true,
		"peers": peerList,
	})
}

// --- Relay ---

// RelayReconnect performs a full Stop() + Start() restart of the libp2p
// node to recover circuit addresses. Use this to recover from background →
// foreground transitions where the relay connection has dropped.
// Returns JSON: { "ok": true }
func RelayReconnect() (result string) {
	defer func() {
		if r := recover(); r != nil {
			result = errJSON("INTERNAL_ERROR", fmt.Sprintf("panic: %v", r))
		}
	}()

	nodeMu.Lock()
	n := singletonNode
	nodeMu.Unlock()

	if n == nil {
		return errJSON("NOT_INITIALIZED", "call Initialize first")
	}

	if err := n.ReconnectRelays(); err != nil {
		return errJSON("RELAY_ERROR", err.Error())
	}

	return okJSON(map[string]interface{}{
		"ok": true,
	})
}

// --- Relay Probe ---

// RelayProbe dials a peer through the relay circuit address to check
// if they are online. Returns fast (~100ms for NO_RESERVATION, ~500ms
// for connection).
// Input JSON: { "peerId": "..." }
// Returns JSON: { "ok": true } on success, or { "ok": false, "errorCode": "NO_RESERVATION"|"RELAY_PROBE_ERROR", "errorMessage": "..." }
func RelayProbe(paramsJSON string) (result string) {
	defer func() {
		if r := recover(); r != nil {
			result = errJSON("INTERNAL_ERROR", fmt.Sprintf("panic: %v", r))
		}
	}()

	nodeMu.Lock()
	n := singletonNode
	nodeMu.Unlock()

	if n == nil {
		return errJSON("NOT_INITIALIZED", "call Initialize first")
	}

	var params struct {
		PeerId string `json:"peerId"`
	}
	if paramsJSON != "" {
		if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
			return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
		}
	}
	if params.PeerId == "" {
		return errJSON("INVALID_INPUT", "missing peerId")
	}

	if err := n.DialPeerViaRelay(params.PeerId); err != nil {
		errMsg := err.Error()
		if strings.Contains(errMsg, "NO_RESERVATION") ||
			strings.Contains(errMsg, "no reservation") ||
			strings.Contains(errMsg, "no-reservation") {
			return errJSON("NO_RESERVATION", errMsg)
		}
		return errJSON("RELAY_PROBE_ERROR", errMsg)
	}

	return okJSON(map[string]interface{}{
		"ok": true,
	})
}

// --- Peer Operations ---

// DialPeer connects to a peer.
// Input JSON: { "peerId": "...", "addresses": [...] }
// Returns JSON: { "ok": true }
func DialPeer(paramsJSON string) (result string) {
	defer func() {
		if r := recover(); r != nil {
			result = errJSON("INTERNAL_ERROR", fmt.Sprintf("panic: %v", r))
		}
	}()

	nodeMu.Lock()
	n := singletonNode
	nodeMu.Unlock()

	if n == nil {
		return errJSON("NOT_INITIALIZED", "call Initialize first")
	}

	var params struct {
		PeerId    string   `json:"peerId"`
		Addresses []string `json:"addresses"`
	}
	if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
		return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
	}
	if params.PeerId == "" {
		return errJSON("INVALID_INPUT", "missing peerId")
	}

	if err := n.DialPeer(params.PeerId, params.Addresses); err != nil {
		return errJSON("DIAL_ERROR", err.Error())
	}

	return okJSON(map[string]interface{}{
		"ok": true,
	})
}

// DisconnectPeer disconnects from a peer.
// Input JSON: { "peerId": "..." }
// Returns JSON: { "ok": true }
func DisconnectPeer(paramsJSON string) (result string) {
	defer func() {
		if r := recover(); r != nil {
			result = errJSON("INTERNAL_ERROR", fmt.Sprintf("panic: %v", r))
		}
	}()

	nodeMu.Lock()
	n := singletonNode
	nodeMu.Unlock()

	if n == nil {
		return errJSON("NOT_INITIALIZED", "call Initialize first")
	}

	var params struct {
		PeerId string `json:"peerId"`
	}
	if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
		return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
	}
	if params.PeerId == "" {
		return errJSON("INVALID_INPUT", "missing peerId")
	}

	if err := n.DisconnectPeer(params.PeerId); err != nil {
		return errJSON("DISCONNECT_ERROR", err.Error())
	}

	return okJSON(map[string]interface{}{
		"ok": true,
	})
}

// SendMessage sends a message to a peer via the chat protocol.
// Input JSON: { "peerId": "...", "message": "..." }
// Returns JSON: { "ok": true, "reply": "..." }
func SendMessage(paramsJSON string) (result string) {
	defer func() {
		if r := recover(); r != nil {
			result = errJSON("INTERNAL_ERROR", fmt.Sprintf("panic: %v", r))
		}
	}()

	nodeMu.Lock()
	n := singletonNode
	nodeMu.Unlock()

	if n == nil {
		return errJSON("NOT_INITIALIZED", "call Initialize first")
	}

	var params struct {
		PeerId    string `json:"peerId"`
		Message   string `json:"message"`
		TimeoutMs int    `json:"timeoutMs"`
	}
	if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
		return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
	}
	if params.PeerId == "" || params.Message == "" {
		return errJSON("INVALID_INPUT", "missing peerId or message")
	}

	reply, acked, err := n.SendMessage(params.PeerId, params.Message, params.TimeoutMs)
	if err != nil {
		return errJSON("SEND_ERROR", err.Error())
	}

	return okJSON(map[string]interface{}{
		"ok":    true,
		"sent":  true,
		"acked": acked,
		"reply": reply,
	})
}

// --- Inbox ---

// InboxStore stores a message in the offline inbox.
// Input JSON: { "toPeerId": "...", "message": "..." }
// Returns JSON: { "ok": true }
func InboxStore(paramsJSON string) (result string) {
	defer func() {
		if r := recover(); r != nil {
			result = errJSON("INTERNAL_ERROR", fmt.Sprintf("panic: %v", r))
		}
	}()

	nodeMu.Lock()
	n := singletonNode
	nodeMu.Unlock()

	if n == nil {
		return errJSON("NOT_INITIALIZED", "call Initialize first")
	}

	var params struct {
		ToPeerId string `json:"toPeerId"`
		Message  string `json:"message"`
	}
	if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
		return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
	}
	if params.ToPeerId == "" || params.Message == "" {
		return errJSON("INVALID_INPUT", "missing toPeerId or message")
	}

	if err := n.InboxStore(params.ToPeerId, params.Message); err != nil {
		return errJSON("INBOX_ERROR", err.Error())
	}

	return okJSON(map[string]interface{}{
		"ok": true,
	})
}

// InboxRetrieve retrieves pending messages from the offline inbox.
// Returns JSON: { "ok": true, "messages": [{ "from": "...", "message": "...", "timestamp": ... }, ...] }
func InboxRetrieve() (result string) {
	defer func() {
		if r := recover(); r != nil {
			result = errJSON("INTERNAL_ERROR", fmt.Sprintf("panic: %v", r))
		}
	}()

	nodeMu.Lock()
	n := singletonNode
	nodeMu.Unlock()

	if n == nil {
		return errJSON("NOT_INITIALIZED", "call Initialize first")
	}

	msgs, err := n.InboxRetrieve()
	if err != nil {
		return errJSON("INBOX_ERROR", err.Error())
	}

	msgList := make([]map[string]interface{}, len(msgs))
	for i, m := range msgs {
		msgList[i] = map[string]interface{}{
			"from":      m.From,
			"message":   m.Message,
			"timestamp": m.Timestamp,
		}
	}

	return okJSON(map[string]interface{}{
		"ok":       true,
		"messages": msgList,
	})
}

// InboxRegisterToken registers an FCM push token.
// Input JSON: { "token": "...", "platform": "ios"|"android" }
// Returns JSON: { "ok": true }
func InboxRegisterToken(paramsJSON string) (result string) {
	defer func() {
		if r := recover(); r != nil {
			result = errJSON("INTERNAL_ERROR", fmt.Sprintf("panic: %v", r))
		}
	}()

	nodeMu.Lock()
	n := singletonNode
	nodeMu.Unlock()

	if n == nil {
		return errJSON("NOT_INITIALIZED", "call Initialize first")
	}

	var params struct {
		Token    string `json:"token"`
		Platform string `json:"platform"`
	}
	if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
		return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
	}
	if params.Token == "" || params.Platform == "" {
		return errJSON("INVALID_INPUT", "missing token or platform")
	}

	if err := n.InboxRegisterToken(params.Token, params.Platform); err != nil {
		return errJSON("INBOX_ERROR", err.Error())
	}

	return okJSON(map[string]interface{}{
		"ok": true,
	})
}

// --- Media ---

// MediaUpload uploads a file to the relay's media store.
// Input JSON: { "id": "...", "to": "...", "mime": "...", "filePath": "..." }
// Returns JSON: { "ok": true, "id": "..." }
func MediaUpload(paramsJSON string) (result string) {
	defer func() {
		if r := recover(); r != nil {
			result = errJSON("INTERNAL_ERROR", fmt.Sprintf("panic: %v", r))
		}
	}()

	nodeMu.Lock()
	n := singletonNode
	nodeMu.Unlock()

	if n == nil {
		return errJSON("NOT_INITIALIZED", "call Initialize first")
	}

	var params struct {
		ID       string `json:"id"`
		To       string `json:"to"`
		Mime     string `json:"mime"`
		FilePath string `json:"filePath"`
	}
	if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
		return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
	}
	if params.ID == "" || params.To == "" || params.FilePath == "" {
		return errJSON("INVALID_INPUT", "missing id, to, or filePath")
	}

	if err := n.MediaUpload(params.ID, params.To, params.Mime, params.FilePath); err != nil {
		return errJSON("MEDIA_ERROR", err.Error())
	}

	return okJSON(map[string]interface{}{
		"ok": true,
		"id": params.ID,
	})
}

// MediaDownload downloads a blob from the relay's media store.
// Input JSON: { "id": "...", "outputPath": "..." }
// Returns JSON: { "ok": true, "id": "...", "mime": "...", "size": N }
func MediaDownload(paramsJSON string) (result string) {
	defer func() {
		if r := recover(); r != nil {
			result = errJSON("INTERNAL_ERROR", fmt.Sprintf("panic: %v", r))
		}
	}()

	nodeMu.Lock()
	n := singletonNode
	nodeMu.Unlock()

	if n == nil {
		return errJSON("NOT_INITIALIZED", "call Initialize first")
	}

	var params struct {
		ID         string `json:"id"`
		OutputPath string `json:"outputPath"`
	}
	if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
		return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
	}
	if params.ID == "" || params.OutputPath == "" {
		return errJSON("INVALID_INPUT", "missing id or outputPath")
	}

	mime, size, err := n.MediaDownload(params.ID, params.OutputPath)
	if err != nil {
		return errJSON("MEDIA_ERROR", err.Error())
	}

	return okJSON(map[string]interface{}{
		"ok":   true,
		"id":   params.ID,
		"mime": mime,
		"size": size,
	})
}

// MediaDelete deletes a blob from the relay's media store.
// Input JSON: { "id": "..." }
// Returns JSON: { "ok": true }
func MediaDelete(paramsJSON string) (result string) {
	defer func() {
		if r := recover(); r != nil {
			result = errJSON("INTERNAL_ERROR", fmt.Sprintf("panic: %v", r))
		}
	}()

	nodeMu.Lock()
	n := singletonNode
	nodeMu.Unlock()

	if n == nil {
		return errJSON("NOT_INITIALIZED", "call Initialize first")
	}

	var params struct {
		ID string `json:"id"`
	}
	if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
		return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
	}
	if params.ID == "" {
		return errJSON("INVALID_INPUT", "missing id")
	}

	if err := n.MediaDelete(params.ID); err != nil {
		return errJSON("MEDIA_ERROR", err.Error())
	}

	return okJSON(map[string]interface{}{
		"ok": true,
	})
}

// MediaList lists blobs available for this peer on the relay.
// Input JSON: {} (empty or no payload)
// Returns JSON: { "ok": true, "blobs": [...] }
func MediaList(paramsJSON string) (result string) {
	defer func() {
		if r := recover(); r != nil {
			result = errJSON("INTERNAL_ERROR", fmt.Sprintf("panic: %v", r))
		}
	}()

	nodeMu.Lock()
	n := singletonNode
	nodeMu.Unlock()

	if n == nil {
		return errJSON("NOT_INITIALIZED", "call Initialize first")
	}

	blobs, err := n.MediaList()
	if err != nil {
		return errJSON("MEDIA_ERROR", err.Error())
	}

	blobList := make([]map[string]interface{}, len(blobs))
	for i, b := range blobs {
		blobList[i] = map[string]interface{}{
			"id":         b.ID,
			"from":       b.From,
			"to":         b.To,
			"mime":       b.Mime,
			"size":       b.Size,
			"created_at": b.CreatedAt,
		}
	}

	return okJSON(map[string]interface{}{
		"ok":    true,
		"blobs": blobList,
	})
}

// --- Profile ---

// ProfileUpload uploads the user's profile picture to the relay.
// Input JSON: { "mime": "...", "filePath": "..." }
// Returns JSON: { "ok": true }
func ProfileUpload(paramsJSON string) (result string) {
	defer func() {
		if r := recover(); r != nil {
			result = errJSON("INTERNAL_ERROR", fmt.Sprintf("panic: %v", r))
		}
	}()

	nodeMu.Lock()
	n := singletonNode
	nodeMu.Unlock()

	if n == nil {
		return errJSON("NOT_INITIALIZED", "call Initialize first")
	}

	var params struct {
		Mime     string `json:"mime"`
		FilePath string `json:"filePath"`
	}
	if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
		return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
	}
	if params.FilePath == "" {
		return errJSON("INVALID_INPUT", "missing filePath")
	}

	if err := n.ProfileUpload(params.Mime, params.FilePath); err != nil {
		return errJSON("PROFILE_ERROR", err.Error())
	}

	return okJSON(map[string]interface{}{
		"ok": true,
	})
}

// ProfileDownload downloads a peer's profile picture from the relay.
// Input JSON: { "ownerPeerId": "...", "outputPath": "..." }
// Returns JSON: { "ok": true, "mime": "...", "size": N }
func ProfileDownload(paramsJSON string) (result string) {
	defer func() {
		if r := recover(); r != nil {
			result = errJSON("INTERNAL_ERROR", fmt.Sprintf("panic: %v", r))
		}
	}()

	nodeMu.Lock()
	n := singletonNode
	nodeMu.Unlock()

	if n == nil {
		return errJSON("NOT_INITIALIZED", "call Initialize first")
	}

	var params struct {
		OwnerPeerId string `json:"ownerPeerId"`
		OutputPath  string `json:"outputPath"`
	}
	if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
		return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
	}
	if params.OwnerPeerId == "" || params.OutputPath == "" {
		return errJSON("INVALID_INPUT", "missing ownerPeerId or outputPath")
	}

	mime, size, err := n.ProfileDownload(params.OwnerPeerId, params.OutputPath)
	if err != nil {
		return errJSON("PROFILE_ERROR", err.Error())
	}

	return okJSON(map[string]interface{}{
		"ok":   true,
		"mime": mime,
		"size": size,
	})
}

// --- Helpers ---

// identityMap converts an identity.Identity to the JSON-compatible map format.
func identityMap(id *identity.Identity) map[string]interface{} {
	return map[string]interface{}{
		"peerId":     id.PeerId,
		"publicKey":  id.PublicKey,
		"privateKey": id.PrivateKey,
		"mnemonic12": id.Mnemonic12,
		"createdAt":  id.CreatedAt,
		"updatedAt":  id.UpdatedAt,
	}
}

// okJSON marshals a success map to a JSON string. If marshalling fails
// (should never happen with basic types), it falls back to an error envelope.
func okJSON(m map[string]interface{}) string {
	b, err := json.Marshal(m)
	if err != nil {
		return errJSON("INTERNAL_ERROR", fmt.Sprintf("json marshal: %v", err))
	}
	return string(b)
}

// errJSON builds a JSON error envelope string.
func errJSON(code, message string) string {
	b, _ := json.Marshal(map[string]interface{}{
		"ok":           false,
		"errorCode":    code,
		"errorMessage": message,
	})
	return string(b)
}
