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
	"time"

	"github.com/google/uuid"

	mcrypto "github.com/mknoon/go-mknoon/crypto"
	"github.com/mknoon/go-mknoon/identity"
	"github.com/mknoon/go-mknoon/node"
)

var (
	singletonNode            *node.Node
	singletonCallbackAdapter *nodeCallbackAdapter
	nodeMu                   sync.Mutex
)

// nodeCallbackAdapter adapts bridge.EventCallback to node.EventCallback.
type nodeCallbackAdapter struct {
	mu sync.RWMutex
	cb EventCallback
}

func (a *nodeCallbackAdapter) SetCallback(cb EventCallback) {
	a.mu.Lock()
	defer a.mu.Unlock()
	a.cb = cb
}

func (a *nodeCallbackAdapter) OnEvent(jsonString string) {
	a.mu.RLock()
	cb := a.cb
	a.mu.RUnlock()
	if cb == nil {
		return
	}
	cb.OnEvent(jsonString)
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

	start := time.Now()
	kp, err := mcrypto.MlKemKeygen()
	keygenMs := time.Since(start).Milliseconds()
	if err != nil {
		return errJSON("INTERNAL_ERROR", err.Error())
	}

	return okJSON(map[string]interface{}{
		"ok":        true,
		"publicKey": kp.PublicKey,
		"secretKey": kp.SecretKey,
		"keygenMs":  keygenMs,
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

	encryptStart := time.Now()
	enc, err := mcrypto.EncryptMessage(params.RecipientPublicKey, params.Plaintext)
	encryptMs := time.Since(encryptStart).Milliseconds()
	if err != nil {
		return errJSON("INTERNAL_ERROR", err.Error())
	}

	return okJSON(map[string]interface{}{
		"ok":               true,
		"kem":              enc.Kem,
		"ciphertext":       enc.Ciphertext,
		"nonce":            enc.Nonce,
		"encryptMs":        encryptMs,
		"payloadSizeBytes": len(params.Plaintext),
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

	decryptStart := time.Now()
	plaintext, err := mcrypto.DecryptMessage(params.SecretKey, params.Kem, params.Ciphertext, params.Nonce)
	decryptMs := time.Since(decryptStart).Milliseconds()
	if err != nil {
		return errJSON("INTERNAL_ERROR", err.Error())
	}

	return okJSON(map[string]interface{}{
		"ok":               true,
		"plaintext":        plaintext,
		"decryptMs":        decryptMs,
		"payloadSizeBytes": len(plaintext),
	})
}

// --- Crypto: Contact Request Encryption ---

// EncryptContactRequest encrypts a signed contact request payload for a recipient
// using their Ed25519 public key via ephemeral X25519 ECDH + HKDF-SHA256 + AES-256-GCM.
// Input JSON: { "recipientPublicKey": "<base64 Ed25519>", "plaintext": "...", "msgId": "...", "ts": "..." }
// Returns JSON: { "ok": true, "ephemeralPublicKey": "...", "ciphertext": "...", "nonce": "..." }
// AAD = msgId + "|" + ts (bound to AES-GCM, prevents tampering of outer fields)
func EncryptContactRequest(paramsJSON string) (result string) {
	defer func() {
		if r := recover(); r != nil {
			result = errJSON("INTERNAL_ERROR", fmt.Sprintf("panic: %v", r))
		}
	}()

	var params struct {
		RecipientPublicKey string `json:"recipientPublicKey"`
		Plaintext          string `json:"plaintext"`
		MsgId              string `json:"msgId"`
		Ts                 string `json:"ts"`
	}
	if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
		return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
	}

	if params.RecipientPublicKey == "" || params.Plaintext == "" || params.MsgId == "" || params.Ts == "" {
		return errJSON("INVALID_INPUT", "missing recipientPublicKey, plaintext, msgId, or ts")
	}

	enc, err := mcrypto.EncryptContactRequest(params.RecipientPublicKey, params.Plaintext, params.MsgId, params.Ts)
	if err != nil {
		return errJSON("INTERNAL_ERROR", err.Error())
	}

	return okJSON(map[string]interface{}{
		"ok":                 true,
		"ephemeralPublicKey": enc.EphemeralPublicKey,
		"ciphertext":         enc.Ciphertext,
		"nonce":              enc.Nonce,
	})
}

// DecryptContactRequest decrypts a v2 contact request using the recipient's own Ed25519 private key.
// Input JSON: { "privateKey": "<base64 Ed25519 64-byte>", "ephemeralPublicKey": "...", "ciphertext": "...", "nonce": "...", "msgId": "...", "ts": "..." }
// Returns JSON: { "ok": true, "plaintext": "..." }
// Decryption fails if msgId/ts were tampered (AAD mismatch)
func DecryptContactRequest(paramsJSON string) (result string) {
	defer func() {
		if r := recover(); r != nil {
			result = errJSON("INTERNAL_ERROR", fmt.Sprintf("panic: %v", r))
		}
	}()

	var params struct {
		PrivateKey         string `json:"privateKey"`
		EphemeralPublicKey string `json:"ephemeralPublicKey"`
		Ciphertext         string `json:"ciphertext"`
		Nonce              string `json:"nonce"`
		MsgId              string `json:"msgId"`
		Ts                 string `json:"ts"`
	}
	if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
		return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
	}

	if params.PrivateKey == "" || params.EphemeralPublicKey == "" ||
		params.Ciphertext == "" || params.Nonce == "" ||
		params.MsgId == "" || params.Ts == "" {
		return errJSON("INVALID_INPUT", "missing privateKey, ephemeralPublicKey, ciphertext, nonce, msgId, or ts")
	}

	plaintext, err := mcrypto.DecryptContactRequest(
		params.PrivateKey, params.EphemeralPublicKey,
		params.Ciphertext, params.Nonce,
		params.MsgId, params.Ts,
	)
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
	if singletonCallbackAdapter == nil {
		singletonCallbackAdapter = &nodeCallbackAdapter{}
	}
	singletonCallbackAdapter.SetCallback(cb)
	if singletonNode == nil {
		singletonNode = node.New(singletonCallbackAdapter)
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
		PrivateKeyHex  string             `json:"privateKeyHex"`
		RelayAddresses []string           `json:"relayAddresses"`
		Namespace      string             `json:"namespace"`
		AutoRegister   bool               `json:"autoRegister"`
		ListenPort     int                `json:"listenPort"`
		FeatureFlags   *node.FeatureFlags `json:"featureFlags"`
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
		FeatureFlags:   params.FeatureFlags,
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
		Namespace       string   `json:"namespace"`
		ServerAddresses []string `json:"serverAddresses"`
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

	if err := n.RendezvousRegister(ns, params.ServerAddresses); err != nil {
		return errJSON("RENDEZVOUS_ERROR", err.Error())
	}

	return okJSON(map[string]interface{}{
		"ok": true,
	})
}

// RendezvousDiscover discovers peers on a rendezvous namespace.
// Input JSON: { "namespace": "...", "serverAddresses": [...], "timeoutMs": N } (all optional)
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
		Namespace       string   `json:"namespace"`
		ServerAddresses []string `json:"serverAddresses"`
		TimeoutMs       int      `json:"timeoutMs"`
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

	peers, err := n.RendezvousDiscoverWithTimeout(ns, params.ServerAddresses, params.TimeoutMs)
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

// RelayReconnect attempts in-place relay recovery first, then falls back to
// a full host restart if needed. Use this to recover from background →
// foreground transitions where the relay connection has dropped.
//
// Phase 4: Returns structured recovery fields so callers can branch on
// recoveryMode instead of parsing error strings.
// Returns JSON with structured recovery attribution fields including
// recoveryMode, relayState, healthyRelayCount, reusedHost, coalescing counts,
// and timing breakdowns.
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

	recoveryResult, err := n.ReconnectRelays()
	if err != nil {
		return errJSON("RELAY_ERROR", err.Error())
	}

	resp := map[string]interface{}{
		"ok": true,
	}

	// Merge structured recovery fields.
	if recoveryResult != nil {
		resp["recoveryMode"] = recoveryResult.RecoveryMode
		resp["relayState"] = recoveryResult.RelayState
		resp["healthyRelayCount"] = recoveryResult.HealthyRelayCount
		resp["reusedHost"] = recoveryResult.ReusedHost
		resp["coalescedRecoveryRequests"] = recoveryResult.CoalescedRecoveryRequests
		resp["relayRefreshMs"] = recoveryResult.RelayRefreshMs
		resp["relayWarmMs"] = recoveryResult.RelayWarmMs
		resp["reserveRpcMs"] = recoveryResult.ReserveRpcMs
		resp["relayWarmParallelism"] = recoveryResult.RelayWarmParallelism
		if recoveryResult.ForegroundRecoveryPath != "" {
			resp["foregroundRecoveryPath"] = recoveryResult.ForegroundRecoveryPath
		}
		resp["foregroundRelayDialTimeoutMs"] = recoveryResult.ForegroundRelayDialTimeoutMs
		resp["autorelayRetryCadenceMs"] = recoveryResult.AutorelayRetryCadenceMs
		resp["circuitAddressWaitMs"] = recoveryResult.CircuitAddressWaitMs
		if recoveryResult.ReservationPath != "" {
			resp["reservationPath"] = recoveryResult.ReservationPath
		}
		if recoveryResult.ReservationWinnerPeer != "" {
			resp["reservationWinnerPeer"] = recoveryResult.ReservationWinnerPeer
		}
		resp["personalReregisterMs"] = recoveryResult.PersonalReregisterMs
		if recoveryResult.ErrorCode != "" {
			resp["errorCode"] = recoveryResult.ErrorCode
		}
		if recoveryResult.Reason != "" {
			resp["reason"] = recoveryResult.Reason
		}
	}

	return okJSON(resp)
}

// GroupAcknowledgeRecovery clears the pending needsGroupRecovery signal after
// Flutter has successfully rejoined group topics.
// Returns JSON: { "ok": true }
func GroupAcknowledgeRecovery() (result string) {
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

	if err := n.AcknowledgeGroupRecovery(); err != nil {
		return errJSON("GROUP_ERROR", err.Error())
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
		TimeoutMs int      `json:"timeoutMs"`
	}
	if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
		return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
	}
	if params.PeerId == "" {
		return errJSON("INVALID_INPUT", "missing peerId")
	}

	if err := n.DialPeerWithTimeout(params.PeerId, params.Addresses, params.TimeoutMs); err != nil {
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
		PeerId        string `json:"peerId"`
		Message       string `json:"message"`
		TimeoutMs     int    `json:"timeoutMs"`
		CorrelationId string `json:"correlationId"`
	}
	if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
		return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
	}
	if params.PeerId == "" || params.Message == "" {
		return errJSON("INVALID_INPUT", "missing peerId or message")
	}

	sendResult, err := n.SendMessageWithTransport(
		params.PeerId,
		params.Message,
		params.TimeoutMs,
	)
	if err != nil {
		return errJSON("SEND_ERROR", err.Error())
	}

	resp := map[string]interface{}{
		"ok":           true,
		"sent":         true,
		"acked":        sendResult.Acked,
		"reply":        sendResult.Reply,
		"transport":    sendResult.Transport,
		"streamOpenMs": sendResult.StreamOpenMs,
		"writeMs":      sendResult.WriteMs,
		"ackWaitMs":    sendResult.AckWaitMs,
	}
	if params.CorrelationId != "" {
		resp["correlationId"] = params.CorrelationId
	}
	return okJSON(resp)
}

// ConfirmDirectMessage resolves a pending deferred direct-ack nonce.
// Input JSON: { "nonce": "...", "ok": true|false }
// Returns JSON: { "ok": true }
func ConfirmDirectMessage(paramsJSON string) (result string) {
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
		Nonce string `json:"nonce"`
		Ok    bool   `json:"ok"`
	}
	if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
		return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
	}
	if params.Nonce == "" {
		return errJSON("INVALID_INPUT", "missing nonce")
	}

	n.ResolveDirectConfirm(params.Nonce, params.Ok)

	return okJSON(map[string]interface{}{
		"ok": true,
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
		ToPeerId  string `json:"toPeerId"`
		Message   string `json:"message"`
		TimeoutMs int    `json:"timeoutMs"`
	}
	if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
		return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
	}
	if params.ToPeerId == "" || params.Message == "" {
		return errJSON("INVALID_INPUT", "missing toPeerId or message")
	}

	if err := n.InboxStore(params.ToPeerId, params.Message, params.TimeoutMs); err != nil {
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
			"id":        m.ID,
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

// InboxRetrieveWithParams retrieves pending messages with optional timeout and
// pagination support.
// Input JSON: { "timeoutMs": N } (optional; 0 uses default timeout)
// Returns JSON: { "ok": true, "messages": [...], "hasMore": true/false }
func InboxRetrieveWithParams(paramsJSON string) (result string) {
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
		TimeoutMs int `json:"timeoutMs"`
	}
	if paramsJSON != "" {
		if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
			return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
		}
	}

	res, err := n.InboxRetrieveWithTimeout(params.TimeoutMs)
	if err != nil {
		return errJSON("INBOX_ERROR", err.Error())
	}

	msgList := make([]map[string]interface{}, len(res.Messages))
	for i, m := range res.Messages {
		msgList[i] = map[string]interface{}{
			"id":        m.ID,
			"from":      m.From,
			"message":   m.Message,
			"timestamp": m.Timestamp,
		}
	}

	return okJSON(map[string]interface{}{
		"ok":       true,
		"messages": msgList,
		"hasMore":  res.HasMore,
	})
}

// InboxRetrievePendingWithParams retrieves pending messages without deleting
// them from the relay.
// Input JSON: { "timeoutMs": N } (optional; 0 uses default timeout)
// Returns JSON: { "ok": true, "messages": [...], "hasMore": true/false }
func InboxRetrievePendingWithParams(paramsJSON string) (result string) {
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
		TimeoutMs int `json:"timeoutMs"`
	}
	if paramsJSON != "" {
		if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
			return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
		}
	}

	res, err := n.InboxRetrievePendingWithTimeout(params.TimeoutMs)
	if err != nil {
		return errJSON("INBOX_ERROR", err.Error())
	}

	msgList := make([]map[string]interface{}, len(res.Messages))
	for i, m := range res.Messages {
		msgList[i] = map[string]interface{}{
			"id":        m.ID,
			"from":      m.From,
			"message":   m.Message,
			"timestamp": m.Timestamp,
		}
	}

	return okJSON(map[string]interface{}{
		"ok":       true,
		"messages": msgList,
		"hasMore":  res.HasMore,
	})
}

// InboxAck deletes only the relay inbox entries whose stable entry IDs match
// the provided list.
// Input JSON: { "entryIds": ["..."], "timeoutMs": N }
// Returns JSON: { "ok": true, "acked": N }
func InboxAck(paramsJSON string) (result string) {
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
		EntryIds  []string `json:"entryIds"`
		TimeoutMs int      `json:"timeoutMs"`
	}
	if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
		return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
	}
	if len(params.EntryIds) == 0 {
		return errJSON("INVALID_INPUT", "missing entryIds")
	}

	acked, err := n.InboxAck(params.EntryIds, params.TimeoutMs)
	if err != nil {
		return errJSON("INBOX_ERROR", err.Error())
	}

	return okJSON(map[string]interface{}{
		"ok":    true,
		"acked": acked,
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
		ID           string   `json:"id"`
		To           string   `json:"to"`
		Mime         string   `json:"mime"`
		FilePath     string   `json:"filePath"`
		AllowedPeers []string `json:"allowedPeers,omitempty"`
	}
	if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
		return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
	}
	if params.ID == "" || params.To == "" || params.FilePath == "" {
		return errJSON("INVALID_INPUT", "missing id, to, or filePath")
	}

	if err := n.MediaUpload(params.ID, params.To, params.Mime, params.FilePath, params.AllowedPeers); err != nil {
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

// --- Group Messaging ---

// GenerateGroupKey generates a random AES-256 key for group symmetric encryption.
// Returns JSON: { "ok": true, "groupKey": "<base64>" }
func GenerateGroupKey() (result string) {
	defer func() {
		if r := recover(); r != nil {
			result = errJSON("INTERNAL_ERROR", fmt.Sprintf("panic: %v", r))
		}
	}()

	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		return errJSON("INTERNAL_ERROR", err.Error())
	}

	return okJSON(map[string]interface{}{
		"ok":       true,
		"groupKey": groupKey,
	})
}

// GroupCreate creates a new group: generates UUID, group key, builds config, joins topic.
// Input JSON: { "name": "...", "groupType": "chat"|"announcement"|"qa", "creatorPeerId": "...", "creatorPublicKey": "...", "creatorMlKemPublicKey": "..." }
// Returns JSON: { "ok": true, "groupId": "...", "groupKey": "...", "keyEpoch": 1, "groupConfig": {...} }
func GroupCreate(paramsJSON string) (result string) {
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
		Name                  string `json:"name"`
		GroupType             string `json:"groupType"`
		CreatorPeerId         string `json:"creatorPeerId"`
		CreatorPublicKey      string `json:"creatorPublicKey"`
		CreatorMlKemPublicKey string `json:"creatorMlKemPublicKey"`
		Description           string `json:"description"`
	}
	if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
		return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
	}

	params.Name = strings.TrimSpace(params.Name)
	params.GroupType = strings.TrimSpace(params.GroupType)
	params.CreatorPeerId = strings.TrimSpace(params.CreatorPeerId)
	params.CreatorPublicKey = strings.TrimSpace(params.CreatorPublicKey)
	params.CreatorMlKemPublicKey = strings.TrimSpace(params.CreatorMlKemPublicKey)

	if params.Name == "" ||
		params.GroupType == "" ||
		params.CreatorPeerId == "" ||
		params.CreatorPublicKey == "" ||
		params.CreatorMlKemPublicKey == "" {
		return errJSON("INVALID_INPUT", "missing required group create creator material: name, groupType, creatorPeerId, creatorPublicKey, or creatorMlKemPublicKey")
	}
	if !isSupportedBridgeGroupType(params.GroupType) {
		return errJSON("INVALID_INPUT", fmt.Sprintf("unsupported groupType: %s", params.GroupType))
	}

	// 1. Generate UUID for groupId.
	groupId := uuid.New().String()

	// 2. Generate group key.
	groupKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		return errJSON("INTERNAL_ERROR", err.Error())
	}

	// 3. Build GroupConfig with creator as admin member.
	config := &node.GroupConfig{
		Name:        params.Name,
		GroupType:   node.GroupType(params.GroupType),
		Description: params.Description,
		Members: []node.GroupMember{
			{
				PeerId:         params.CreatorPeerId,
				Role:           node.GroupRoleAdmin,
				PublicKey:      params.CreatorPublicKey,
				MlKemPublicKey: params.CreatorMlKemPublicKey,
			},
		},
		CreatedBy: params.CreatorPeerId,
		CreatedAt: time.Now().UTC().Format(time.RFC3339Nano),
	}

	// 4. Build GroupKeyInfo with keyEpoch=1.
	keyInfo := &node.GroupKeyInfo{
		Key:      groupKey,
		KeyEpoch: 1,
	}

	// 5. Join group topic.
	if err := n.JoinGroupTopic(groupId, config, keyInfo); err != nil {
		return errJSON("GROUP_ERROR", err.Error())
	}

	// 6. Serialize config for return.
	configMap := map[string]interface{}{
		"name":      config.Name,
		"groupType": string(config.GroupType),
		"members":   config.Members,
		"createdBy": config.CreatedBy,
		"createdAt": config.CreatedAt,
	}
	if config.Description != "" {
		configMap["description"] = config.Description
	}

	return okJSON(map[string]interface{}{
		"ok":          true,
		"groupId":     groupId,
		"groupKey":    groupKey,
		"keyEpoch":    1,
		"groupConfig": configMap,
	})
}

func isSupportedBridgeGroupType(groupType string) bool {
	switch node.GroupType(groupType) {
	case node.GroupTypeChat, node.GroupTypeAnnouncement, node.GroupTypeQA:
		return true
	default:
		return false
	}
}

// GroupJoinTopic joins an existing group topic.
// Input JSON: { "groupId": "...", "groupConfig": {...}, "groupKey": "...", "keyEpoch": N }
// Returns JSON: { "ok": true }
func GroupJoinTopic(paramsJSON string) (result string) {
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
		GroupId     string           `json:"groupId"`
		GroupConfig node.GroupConfig `json:"groupConfig"`
		GroupKey    string           `json:"groupKey"`
		KeyEpoch    int              `json:"keyEpoch"`
	}
	if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
		return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
	}

	if params.GroupId == "" || params.GroupKey == "" {
		return errJSON("INVALID_INPUT", "missing groupId or groupKey")
	}

	keyInfo := &node.GroupKeyInfo{
		Key:      params.GroupKey,
		KeyEpoch: params.KeyEpoch,
	}

	if err := n.JoinGroupTopic(params.GroupId, &params.GroupConfig, keyInfo); err != nil {
		if strings.Contains(err.Error(), "already joined group topic:") {
			if _, refreshErr := n.RefreshJoinedGroupStateIfNewer(params.GroupId, &params.GroupConfig, keyInfo); refreshErr != nil {
				return errJSON("GROUP_ERROR", refreshErr.Error())
			}
			return okJSON(map[string]interface{}{
				"ok":   true,
				"note": "ALREADY_JOINED",
			})
		}
		return errJSON("GROUP_ERROR", err.Error())
	}

	return okJSON(map[string]interface{}{
		"ok": true,
	})
}

// GroupLeaveTopic leaves a group topic.
// Input JSON: { "groupId": "..." }
// Returns JSON: { "ok": true }
func GroupLeaveTopic(paramsJSON string) (result string) {
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
		GroupId string `json:"groupId"`
	}
	if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
		return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
	}

	if params.GroupId == "" {
		return errJSON("INVALID_INPUT", "missing groupId")
	}

	if err := n.LeaveGroupTopic(params.GroupId); err != nil {
		return errJSON("GROUP_ERROR", err.Error())
	}

	return okJSON(map[string]interface{}{
		"ok": true,
	})
}

// GroupPublish encrypts, signs, and publishes a message to a group topic.
// Input JSON: { "groupId": "...", "text": "...", "senderPeerId": "...", "senderPublicKey": "...", "senderPrivateKey": "...", "senderUsername": "..." }
// Returns JSON: { "ok": true, "messageId": "...", "topicPeers": N }
func GroupPublish(paramsJSON string) (result string) {
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
		GroupId               string                   `json:"groupId"`
		Text                  string                   `json:"text"`
		SenderPeerId          string                   `json:"senderPeerId"`
		SenderPublicKey       string                   `json:"senderPublicKey"`
		SenderPrivateKey      string                   `json:"senderPrivateKey"`
		SenderUsername        string                   `json:"senderUsername"`
		SenderDeviceId        string                   `json:"senderDeviceId,omitempty"`
		SenderTransportPeerId string                   `json:"senderTransportPeerId,omitempty"`
		SenderDevicePublicKey string                   `json:"senderDevicePublicKey,omitempty"`
		SenderKeyPackageId    string                   `json:"senderKeyPackageId,omitempty"`
		MessageId             string                   `json:"messageId,omitempty"`
		Timestamp             string                   `json:"timestamp,omitempty"`
		QuotedMessageId       string                   `json:"quotedMessageId,omitempty"`
		Media                 []map[string]interface{} `json:"media,omitempty"`
	}
	if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
		return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
	}

	if params.GroupId == "" || params.SenderPeerId == "" ||
		params.SenderPublicKey == "" || params.SenderPrivateKey == "" {
		return errJSON("INVALID_INPUT", "missing groupId, senderPeerId, senderPublicKey, or senderPrivateKey")
	}
	if strings.TrimSpace(params.Text) == "" && len(params.Media) == 0 {
		return errJSON("INVALID_INPUT", "either text or media is required")
	}

	opts := buildGroupPublishOpts(params.Media, params.QuotedMessageId)
	if opts == nil {
		opts = make(map[string]interface{}, 4)
	}
	if params.SenderDeviceId != "" {
		opts["senderDeviceId"] = params.SenderDeviceId
	}
	if params.SenderTransportPeerId != "" {
		opts["senderTransportPeerId"] = params.SenderTransportPeerId
	}
	if params.SenderDevicePublicKey != "" {
		opts["senderDevicePublicKey"] = params.SenderDevicePublicKey
	}
	if params.SenderKeyPackageId != "" {
		opts["senderKeyPackageId"] = params.SenderKeyPackageId
	}
	if params.Timestamp != "" {
		opts["timestamp"] = params.Timestamp
	}

	msgId, topicPeers, err := n.PublishGroupMessage(
		params.GroupId,
		params.SenderPrivateKey,
		params.SenderPeerId,
		params.SenderPublicKey,
		params.SenderUsername,
		params.Text,
		params.MessageId,
		opts,
	)
	if err != nil {
		return errJSON("GROUP_ERROR", err.Error())
	}

	return okJSON(map[string]interface{}{
		"ok":         true,
		"messageId":  msgId,
		"topicPeers": topicPeers,
	})
}

func buildGroupPublishOpts(media []map[string]interface{}, quotedMessageId string) map[string]interface{} {
	if len(media) == 0 && quotedMessageId == "" {
		return nil
	}

	opts := make(map[string]interface{}, 2)
	if len(media) > 0 {
		opts["media"] = media
	}
	if quotedMessageId != "" {
		opts["quotedMessageId"] = quotedMessageId
	}
	return opts
}

// GroupPublishReaction encrypts, signs, and publishes a reaction to a group topic.
// Input JSON: { "groupId": "...", "senderPeerId": "...", "senderPublicKey": "...", "senderPrivateKey": "...", "reactionPayload": "..." }
// The reactionPayload is a JSON string that gets encrypted inside the v3 group_reaction envelope.
// Returns JSON: { "ok": true }
func GroupPublishReaction(paramsJSON string) (result string) {
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
		GroupId               string `json:"groupId"`
		SenderPeerId          string `json:"senderPeerId"`
		SenderPublicKey       string `json:"senderPublicKey"`
		SenderPrivateKey      string `json:"senderPrivateKey"`
		SenderDeviceId        string `json:"senderDeviceId,omitempty"`
		SenderTransportPeerId string `json:"senderTransportPeerId,omitempty"`
		SenderDevicePublicKey string `json:"senderDevicePublicKey,omitempty"`
		SenderKeyPackageId    string `json:"senderKeyPackageId,omitempty"`
		ReactionPayload       string `json:"reactionPayload"`
	}
	if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
		return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
	}

	if params.GroupId == "" || params.SenderPeerId == "" ||
		params.SenderPublicKey == "" || params.SenderPrivateKey == "" ||
		params.ReactionPayload == "" {
		return errJSON("INVALID_INPUT", "missing required fields")
	}

	opts := make(map[string]interface{}, 4)
	if params.SenderDeviceId != "" {
		opts["senderDeviceId"] = params.SenderDeviceId
	}
	if params.SenderTransportPeerId != "" {
		opts["senderTransportPeerId"] = params.SenderTransportPeerId
	}
	if params.SenderDevicePublicKey != "" {
		opts["senderDevicePublicKey"] = params.SenderDevicePublicKey
	}
	if params.SenderKeyPackageId != "" {
		opts["senderKeyPackageId"] = params.SenderKeyPackageId
	}

	err := n.PublishGroupReaction(
		params.GroupId,
		params.SenderPrivateKey,
		params.SenderPeerId,
		params.SenderPublicKey,
		params.ReactionPayload,
		opts,
	)
	if err != nil {
		return errJSON("GROUP_ERROR", err.Error())
	}

	return okJSON(map[string]interface{}{
		"ok": true,
	})
}

// GroupUpdateConfig updates the stored group configuration.
// Input JSON: { "groupId": "...", "groupConfig": {...} }
// Returns JSON: { "ok": true }
func GroupUpdateConfig(paramsJSON string) (result string) {
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
		GroupId     string           `json:"groupId"`
		GroupConfig node.GroupConfig `json:"groupConfig"`
	}
	if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
		return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
	}

	if params.GroupId == "" {
		return errJSON("INVALID_INPUT", "missing groupId")
	}

	n.UpdateGroupConfig(params.GroupId, &params.GroupConfig)

	return okJSON(map[string]interface{}{
		"ok": true,
	})
}

// GroupRotateKey is a legacy rotation command that is intentionally unsupported
// because it cannot own durable key distribution before committing validator state.
// Input JSON: { "groupId": "..." }
// Returns JSON: { "ok": false, "errorCode": "LEGACY_ROTATE_KEY_UNSUPPORTED", ... }
// Raw callers should use group:generateNextKey, distribute the key, then group:updateKey.
func GroupRotateKey(paramsJSON string) (result string) {
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
		GroupId string `json:"groupId"`
	}
	if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
		return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
	}

	if params.GroupId == "" {
		return errJSON("INVALID_INPUT", "missing groupId")
	}

	return errJSON("LEGACY_ROTATE_KEY_UNSUPPORTED", "legacy group key rotation is unsupported; use group:generateNextKey, distribute the key, then group:updateKey")
}

// GroupGenerateNextKey generates the next key and epoch without mutating
// the stored validator state.
// Input JSON: { "groupId": "..." }
// Returns JSON: { "ok": true, "groupKey": "...", "keyEpoch": N }
func GroupGenerateNextKey(paramsJSON string) (result string) {
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
		GroupId string `json:"groupId"`
	}
	if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
		return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
	}

	if params.GroupId == "" {
		return errJSON("INVALID_INPUT", "missing groupId")
	}

	currentKeyInfo := n.GetGroupKeyInfo(params.GroupId)
	if currentKeyInfo == nil {
		return errJSON("GROUP_KEY_NOT_FOUND", "current group key not found; restore or join the group before generating the next key")
	}

	newKey, err := mcrypto.GenerateGroupKey()
	if err != nil {
		return errJSON("INTERNAL_ERROR", err.Error())
	}
	newEpoch := currentKeyInfo.KeyEpoch + 1

	return okJSON(map[string]interface{}{
		"ok":       true,
		"groupKey": newKey,
		"keyEpoch": newEpoch,
	})
}

// GroupUpdateKey updates the stored group key without generating a new one.
// Used by non-admin members when receiving a key update via P2P.
// Input JSON: { "groupId": "...", "groupKey": "...", "keyEpoch": N }
// Returns JSON: { "ok": true }
func GroupUpdateKey(paramsJSON string) (result string) {
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
		GroupId  string `json:"groupId"`
		GroupKey string `json:"groupKey"`
		KeyEpoch int    `json:"keyEpoch"`
	}
	if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
		return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
	}

	if params.GroupId == "" || params.GroupKey == "" {
		return errJSON("INVALID_INPUT", "missing groupId or groupKey")
	}

	n.UpdateGroupKey(params.GroupId, &node.GroupKeyInfo{
		Key:      params.GroupKey,
		KeyEpoch: params.KeyEpoch,
	})

	return okJSON(map[string]interface{}{
		"ok": true,
	})
}

// GroupEncryptMessage encrypts a plaintext message with a group key.
// Input JSON: { "groupKey": "<base64>", "plaintext": "..." }
// Returns JSON: { "ok": true, "ciphertext": "<base64>", "nonce": "<base64>" }
func GroupEncryptMessage(paramsJSON string) (result string) {
	defer func() {
		if r := recover(); r != nil {
			result = errJSON("INTERNAL_ERROR", fmt.Sprintf("panic: %v", r))
		}
	}()

	var params struct {
		GroupKey  string `json:"groupKey"`
		Plaintext string `json:"plaintext"`
	}
	if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
		return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
	}

	if params.GroupKey == "" || params.Plaintext == "" {
		return errJSON("INVALID_INPUT", "missing groupKey or plaintext")
	}

	ctB64, nonceB64, err := mcrypto.EncryptGroupMessage(params.GroupKey, params.Plaintext)
	if err != nil {
		return errJSON("INTERNAL_ERROR", err.Error())
	}

	return okJSON(map[string]interface{}{
		"ok":         true,
		"ciphertext": ctB64,
		"nonce":      nonceB64,
	})
}

// GroupDecryptMessage decrypts a ciphertext message with a group key.
// Input JSON: { "groupKey": "<base64>", "ciphertext": "<base64>", "nonce": "<base64>" }
// Returns JSON: { "ok": true, "plaintext": "..." }
func GroupDecryptMessage(paramsJSON string) (result string) {
	defer func() {
		if r := recover(); r != nil {
			result = errJSON("INTERNAL_ERROR", fmt.Sprintf("panic: %v", r))
		}
	}()

	var params struct {
		GroupKey   string `json:"groupKey"`
		Ciphertext string `json:"ciphertext"`
		Nonce      string `json:"nonce"`
	}
	if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
		return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
	}

	if params.GroupKey == "" || params.Ciphertext == "" || params.Nonce == "" {
		return errJSON("INVALID_INPUT", "missing groupKey, ciphertext, or nonce")
	}

	plaintext, err := mcrypto.DecryptGroupMessage(params.GroupKey, params.Ciphertext, params.Nonce)
	if err != nil {
		return errJSON("INTERNAL_ERROR", err.Error())
	}

	return okJSON(map[string]interface{}{
		"ok":        true,
		"plaintext": plaintext,
	})
}

// GroupInboxStore stores a group message in the relay's group inbox.
//
//	Input JSON: {
//	  "groupId": "...",
//	  "message": "...",
//	  "recipientPeerIds": ["peer-2"]
//	}
//
// Returns JSON: { "ok": true }
func GroupInboxStore(paramsJSON string) (result string) {
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
		GroupId          string   `json:"groupId"`
		Message          string   `json:"message"`
		RecipientPeerIds []string `json:"recipientPeerIds"`
	}
	if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
		return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
	}

	if params.GroupId == "" || params.Message == "" {
		return errJSON("INVALID_INPUT", "missing groupId or message")
	}

	if err := n.GroupInboxStore(
		params.GroupId,
		params.Message,
		params.RecipientPeerIds,
		"",
		"",
	); err != nil {
		return errJSON("GROUP_INBOX_ERROR", err.Error())
	}

	return okJSON(map[string]interface{}{
		"ok": true,
	})
}

// GroupInboxRetrieve retrieves missed group messages from the relay's group inbox.
// Input JSON: { "groupId": "...", "sinceTimestamp": N }
// Returns JSON: { "ok": true, "messages": [...] }
func GroupInboxRetrieve(paramsJSON string) (result string) {
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
		GroupId        string `json:"groupId"`
		SinceTimestamp int64  `json:"sinceTimestamp"`
	}
	if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
		return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
	}

	if params.GroupId == "" {
		return errJSON("INVALID_INPUT", "missing groupId")
	}

	msgs, err := n.GroupInboxRetrieve(params.GroupId, params.SinceTimestamp)
	if err != nil {
		return errJSON("GROUP_INBOX_ERROR", err.Error())
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

// GroupInboxRetrieveCursor retrieves missed group messages from the relay's
// group inbox using cursor-based pagination.
// Input JSON: { "groupId": "...", "cursor": "...", "limit": N }
// Returns JSON: { "ok": true, "messages": [...], "cursor": "..." }
func GroupInboxRetrieveCursor(paramsJSON string) (result string) {
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
		GroupId string `json:"groupId"`
		Cursor  string `json:"cursor"`
		Limit   int    `json:"limit"`
	}
	if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
		return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
	}

	if params.GroupId == "" {
		return errJSON("INVALID_INPUT", "missing groupId")
	}

	page, err := n.GroupInboxRetrieveWithCursorResult(
		params.GroupId,
		params.Cursor,
		params.Limit,
	)
	if err != nil {
		return errJSON("GROUP_INBOX_ERROR", err.Error())
	}

	msgList := make([]map[string]interface{}, len(page.Messages))
	for i, m := range page.Messages {
		msgList[i] = map[string]interface{}{
			"from":      m.From,
			"message":   m.Message,
			"timestamp": m.Timestamp,
		}
	}

	return okJSON(map[string]interface{}{
		"ok":          true,
		"messages":    msgList,
		"cursor":      page.NextCursor,
		"historyGaps": page.HistoryGaps,
	})
}

// GroupHistoryRepairRange requests encrypted replay envelopes for one
// explicit history gap from one candidate source peer.
// Input JSON: { "groupId": "...", "gapId": "...", "sourcePeerId": "...",
// "missingAfterMessageId": "...", "missingBeforeMessageId": "...",
// "expectedRangeHash": "...", "expectedHeadMessageId": "...", "limit": N }
func GroupHistoryRepairRange(paramsJSON string) (result string) {
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

	var params node.GroupHistoryRepairRangeRequest
	if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
		return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
	}

	normalized, err := node.NormalizeGroupHistoryRepairRangeRequest(params)
	if err != nil {
		return errJSON("INVALID_INPUT", err.Error())
	}

	resp, err := n.GroupHistoryRepairRange(normalized)
	if err != nil {
		return errJSON("GROUP_HISTORY_REPAIR_ERROR", err.Error())
	}

	msgList := make([]map[string]interface{}, len(resp.Messages))
	for i, m := range resp.Messages {
		msgList[i] = map[string]interface{}{
			"from":      m.From,
			"message":   m.Message,
			"timestamp": m.Timestamp,
		}
	}

	return okJSON(map[string]interface{}{
		"ok":            true,
		"groupId":       resp.GroupId,
		"gapId":         resp.GapId,
		"sourcePeerId":  resp.SourcePeerId,
		"rangeHash":     resp.RangeHash,
		"headMessageId": resp.HeadMessageId,
		"messages":      msgList,
	})
}

// --- Blob Crypto ---

// BlobKeygen generates a random 32-byte AES-256 symmetric key.
// Returns JSON: { "ok": true, "keyBase64": "<base64>" }
func BlobKeygen(_ string) (result string) {
	defer func() {
		if r := recover(); r != nil {
			result = errJSON("INTERNAL_ERROR", fmt.Sprintf("panic: %v", r))
		}
	}()

	key, err := mcrypto.GenerateSymmetricKey()
	if err != nil {
		return errJSON("INTERNAL_ERROR", err.Error())
	}

	return okJSON(map[string]interface{}{
		"ok":        true,
		"keyBase64": key,
	})
}

// BlobEncrypt encrypts a file with AES-256-GCM using a symmetric key.
// Input JSON: { "filePath": "...", "keyBase64": "<base64>" }
// Returns JSON: { "ok": true, "encryptedPath": "...", "nonce": "<base64>" }
func BlobEncrypt(paramsJSON string) (result string) {
	defer func() {
		if r := recover(); r != nil {
			result = errJSON("INTERNAL_ERROR", fmt.Sprintf("panic: %v", r))
		}
	}()

	var params struct {
		FilePath  string `json:"filePath"`
		KeyBase64 string `json:"keyBase64"`
	}
	if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
		return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
	}

	if params.FilePath == "" || params.KeyBase64 == "" {
		return errJSON("INVALID_INPUT", "missing filePath or keyBase64")
	}

	encryptedPath, nonce, err := mcrypto.EncryptFile(params.FilePath, params.KeyBase64)
	if err != nil {
		return errJSON("ENCRYPT_ERROR", err.Error())
	}

	return okJSON(map[string]interface{}{
		"ok":            true,
		"encryptedPath": encryptedPath,
		"nonce":         nonce,
	})
}

// BlobDecrypt decrypts a file with AES-256-GCM using a symmetric key + nonce.
// Input JSON: { "filePath": "...", "keyBase64": "<base64>", "nonce": "<base64>" }
// Returns JSON: { "ok": true, "decryptedPath": "..." }
func BlobDecrypt(paramsJSON string) (result string) {
	defer func() {
		if r := recover(); r != nil {
			result = errJSON("INTERNAL_ERROR", fmt.Sprintf("panic: %v", r))
		}
	}()

	var params struct {
		FilePath  string `json:"filePath"`
		KeyBase64 string `json:"keyBase64"`
		Nonce     string `json:"nonce"`
	}
	if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
		return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
	}

	if params.FilePath == "" || params.KeyBase64 == "" || params.Nonce == "" {
		return errJSON("INVALID_INPUT", "missing filePath, keyBase64, or nonce")
	}

	decryptedPath, err := mcrypto.DecryptFile(params.FilePath, params.KeyBase64, params.Nonce)
	if err != nil {
		return errJSON("DECRYPT_ERROR", err.Error())
	}

	return okJSON(map[string]interface{}{
		"ok":            true,
		"decryptedPath": decryptedPath,
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
