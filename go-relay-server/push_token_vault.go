package main

import (
	"bytes"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"sort"
	"strings"
)

const (
	pushTokenVaultSchemaVersion = 1

	pushTokenKeyringFileEnv         = "PUSH_TOKEN_KEYRING_FILE"
	pushTokenActiveKeyIDEnv         = "PUSH_TOKEN_ACTIVE_KEY_ID"
	pushTokenProviderEnvironmentEnv = "PUSH_PROVIDER_ENVIRONMENT"

	pushTokenIdentifierMaxBytes = 128
	pushTokenCapabilityMaxCount = 64
	pushTokenJSONMaxBytes       = 1 << 20
	pushTokenPlaintextMaxBytes  = 64 << 10
)

type pushTokenState string

const (
	pushTokenStateAbsent    pushTokenState = "absent"
	pushTokenStateMigrating pushTokenState = "migrating"
	pushTokenStateEncrypted pushTokenState = "encrypted"
)

// pushTokenStateMarker is stored only for migrating and encrypted states.
// Absence is represented by a missing Redis marker, never by an "absent" row.
type pushTokenStateMarker struct {
	State              pushTokenState
	Revision           uint64
	FleetReceiptSHA256 string
}

// pushTokenDirectoryRecord intentionally contains only route metadata. In
// particular, neither a peer identifier nor provider-token material may be
// added here; the peer is represented only by the digest bound into AEAD AAD.
type pushTokenDirectoryRecord struct {
	Handle              string
	Generation          uint64
	Platform            string
	Capabilities        []string
	ProviderEnvironment string
	SourceLegacyDigest  string
}

// pushTokenVaultEnvelope is the complete persisted vault value. Its exact
// strict JSON representation has only schema, key_id, nonce, and ciphertext.
type pushTokenVaultEnvelope struct {
	Schema     int
	KeyID      string
	Nonce      string
	Ciphertext string
}

// pushTokenVaultConfig keeps the active encryption key alongside all retained
// decryption keys. Callers load it only after observing migrating/encrypted
// state (or when explicitly starting migration), leaving marker-absent legacy
// operation independent of vault configuration.
type pushTokenVaultConfig struct {
	activeKeyID         string
	providerEnvironment string
	keys                map[string][]byte
}

type pushTokenMarkerWire struct {
	State              pushTokenState `json:"state"`
	Revision           uint64         `json:"revision"`
	FleetReceiptSHA256 string         `json:"fleet_receipt_sha256"`
}

type pushTokenDirectoryWire struct {
	Handle              string   `json:"handle"`
	Generation          uint64   `json:"generation"`
	Platform            string   `json:"platform"`
	Capabilities        []string `json:"capabilities"`
	ProviderEnvironment string   `json:"provider_environment"`
	SourceLegacyDigest  string   `json:"source_legacy_digest"`
}

type pushTokenVaultWire struct {
	Schema     int    `json:"schema"`
	KeyID      string `json:"key_id"`
	Nonce      string `json:"nonce"`
	Ciphertext string `json:"ciphertext"`
}

type pushTokenAADWire struct {
	Schema              int      `json:"schema"`
	PeerDigest          string   `json:"peer_digest"`
	Handle              string   `json:"handle"`
	Generation          uint64   `json:"generation"`
	Platform            string   `json:"platform"`
	Capabilities        []string `json:"capabilities"`
	SourceLegacyDigest  string   `json:"source_legacy_digest"`
	ProviderEnvironment string   `json:"provider_environment"`
	KeyID               string   `json:"key_id"`
}

// loadPushTokenVaultConfigFromEnv reads the exact three-variable vault
// configuration. A caller in marker-absent mode must not call this function;
// that is what keeps default-off legacy operation available without keys.
func loadPushTokenVaultConfigFromEnv() (*pushTokenVaultConfig, error) {
	return loadPushTokenVaultConfig(os.Getenv, os.ReadFile)
}

func loadPushTokenVaultConfig(
	getenv func(string) string,
	readFile func(string) ([]byte, error),
) (*pushTokenVaultConfig, error) {
	if getenv == nil || readFile == nil {
		return nil, errors.New("push token vault configuration loader is unavailable")
	}

	keyringFile := getenv(pushTokenKeyringFileEnv)
	activeKeyID := getenv(pushTokenActiveKeyIDEnv)
	providerEnvironment := getenv(pushTokenProviderEnvironmentEnv)
	if keyringFile == "" || activeKeyID == "" || providerEnvironment == "" {
		return nil, errors.New("push token vault configuration is incomplete")
	}
	if err := validatePushTokenIdentifier(activeKeyID); err != nil {
		return nil, errors.New("push token vault active key identifier is invalid")
	}
	if err := validatePushTokenIdentifier(providerEnvironment); err != nil {
		return nil, errors.New("push token provider environment is invalid")
	}

	payload, err := readFile(keyringFile)
	if err != nil {
		return nil, fmt.Errorf("read push token keyring: %w", err)
	}
	keys, err := parsePushTokenKeyring(payload)
	if err != nil {
		return nil, err
	}
	if _, ok := keys[activeKeyID]; !ok {
		return nil, errors.New("push token vault active key is not in the keyring")
	}

	return &pushTokenVaultConfig{
		activeKeyID:         activeKeyID,
		providerEnvironment: providerEnvironment,
		keys:                clonePushTokenKeys(keys),
	}, nil
}

// parsePushTokenKeyring accepts exactly
// {"version":1,"keys":{"<id>":"<base64-32-byte-key>"}}. The token-based
// object decoder retains duplicate-field information that map unmarshalling
// would otherwise discard.
func parsePushTokenKeyring(payload []byte) (map[string][]byte, error) {
	fields, err := decodePushTokenJSONObject(
		payload,
		[]string{"version", "keys"},
		pushTokenJSONMaxBytes,
	)
	if err != nil {
		return nil, errors.New("push token keyring JSON is invalid")
	}
	if !bytes.Equal(bytes.TrimSpace(fields["version"]), []byte("1")) {
		return nil, errors.New("push token keyring version is invalid")
	}

	keyFields, err := decodePushTokenJSONObject(fields["keys"], nil, pushTokenJSONMaxBytes)
	if err != nil || len(keyFields) == 0 {
		return nil, errors.New("push token keyring keys are invalid")
	}

	keys := make(map[string][]byte, len(keyFields))
	for keyID, raw := range keyFields {
		if err := validatePushTokenIdentifier(keyID); err != nil {
			return nil, errors.New("push token keyring contains an invalid key identifier")
		}
		var encoded string
		if err := json.Unmarshal(raw, &encoded); err != nil {
			return nil, errors.New("push token keyring contains a non-string key")
		}
		key, err := decodeCanonicalBase64(encoded)
		if err != nil || len(key) != 32 {
			return nil, errors.New("push token keyring contains an invalid encryption key")
		}
		keys[keyID] = append([]byte(nil), key...)
	}
	return keys, nil
}

func validateFleetReceiptSHA256(value string) error {
	if len(value) != sha256.Size*2 {
		return errors.New("fleet receipt SHA-256 must contain exactly 64 hexadecimal characters")
	}
	for i := 0; i < len(value); i++ {
		candidate := value[i]
		if (candidate < '0' || candidate > '9') &&
			(candidate < 'a' || candidate > 'f') &&
			(candidate < 'A' || candidate > 'F') {
			return errors.New("fleet receipt SHA-256 must contain exactly 64 hexadecimal characters")
		}
	}
	return nil
}

func validatePushTokenStateMarker(marker pushTokenStateMarker) error {
	switch marker.State {
	case pushTokenStateAbsent:
		if marker.Revision != 0 || marker.FleetReceiptSHA256 != "" {
			return errors.New("absent push token state must not carry marker metadata")
		}
		return nil
	case pushTokenStateMigrating, pushTokenStateEncrypted:
		return validateFleetReceiptSHA256(marker.FleetReceiptSHA256)
	default:
		return errors.New("push token state is invalid")
	}
}

func encodePushTokenStateMarker(marker pushTokenStateMarker) ([]byte, error) {
	if err := validatePushTokenStateMarker(marker); err != nil {
		return nil, err
	}
	if marker.State == pushTokenStateAbsent {
		return nil, errors.New("absent push token state is represented by a missing marker")
	}
	return json.Marshal(pushTokenMarkerWire{
		State:              marker.State,
		Revision:           marker.Revision,
		FleetReceiptSHA256: marker.FleetReceiptSHA256,
	})
}

func decodePushTokenStateMarker(payload []byte) (pushTokenStateMarker, error) {
	fields, err := decodePushTokenJSONObject(
		payload,
		[]string{"state", "revision", "fleet_receipt_sha256"},
		pushTokenJSONMaxBytes,
	)
	if err != nil {
		return pushTokenStateMarker{}, errors.New("push token state marker JSON is invalid")
	}

	var wire pushTokenMarkerWire
	if err := decodePushTokenJSONField(fields["state"], &wire.State); err != nil {
		return pushTokenStateMarker{}, errors.New("push token state marker state is invalid")
	}
	if err := decodePushTokenJSONField(fields["revision"], &wire.Revision); err != nil {
		return pushTokenStateMarker{}, errors.New("push token state marker revision is invalid")
	}
	if err := decodePushTokenJSONField(fields["fleet_receipt_sha256"], &wire.FleetReceiptSHA256); err != nil {
		return pushTokenStateMarker{}, errors.New("push token state marker receipt is invalid")
	}

	marker := pushTokenStateMarker{
		State:              wire.State,
		Revision:           wire.Revision,
		FleetReceiptSHA256: wire.FleetReceiptSHA256,
	}
	if err := validatePushTokenStateMarker(marker); err != nil {
		return pushTokenStateMarker{}, err
	}
	if marker.State == pushTokenStateAbsent {
		return pushTokenStateMarker{}, errors.New("persisted push token state marker cannot be absent")
	}
	return marker, nil
}

func encodePushTokenDirectoryRecord(record pushTokenDirectoryRecord) ([]byte, error) {
	record.Capabilities = canonicalPushTokenVaultCapabilities(record.Capabilities)
	if err := validatePushTokenDirectoryRecord(record); err != nil {
		return nil, err
	}
	return json.Marshal(pushTokenDirectoryWire{
		Handle:              record.Handle,
		Generation:          record.Generation,
		Platform:            record.Platform,
		Capabilities:        append([]string{}, record.Capabilities...),
		ProviderEnvironment: record.ProviderEnvironment,
		SourceLegacyDigest:  record.SourceLegacyDigest,
	})
}

func decodePushTokenDirectoryRecord(payload []byte) (pushTokenDirectoryRecord, error) {
	fields, err := decodePushTokenJSONObject(
		payload,
		[]string{
			"handle",
			"generation",
			"platform",
			"capabilities",
			"provider_environment",
			"source_legacy_digest",
		},
		pushTokenJSONMaxBytes,
	)
	if err != nil {
		return pushTokenDirectoryRecord{}, errors.New("push token directory JSON is invalid")
	}

	var wire pushTokenDirectoryWire
	if err := decodePushTokenJSONField(fields["handle"], &wire.Handle); err != nil {
		return pushTokenDirectoryRecord{}, errors.New("push token directory handle is invalid")
	}
	if err := decodePushTokenJSONField(fields["generation"], &wire.Generation); err != nil {
		return pushTokenDirectoryRecord{}, errors.New("push token directory generation is invalid")
	}
	if err := decodePushTokenJSONField(fields["platform"], &wire.Platform); err != nil {
		return pushTokenDirectoryRecord{}, errors.New("push token directory platform is invalid")
	}
	if bytes.Equal(bytes.TrimSpace(fields["capabilities"]), []byte("null")) ||
		decodePushTokenJSONField(fields["capabilities"], &wire.Capabilities) != nil {
		return pushTokenDirectoryRecord{}, errors.New("push token directory capabilities are invalid")
	}
	if err := decodePushTokenJSONField(fields["provider_environment"], &wire.ProviderEnvironment); err != nil {
		return pushTokenDirectoryRecord{}, errors.New("push token directory provider environment is invalid")
	}
	if err := decodePushTokenJSONField(fields["source_legacy_digest"], &wire.SourceLegacyDigest); err != nil {
		return pushTokenDirectoryRecord{}, errors.New("push token directory source digest is invalid")
	}

	record := pushTokenDirectoryRecord{
		Handle:              wire.Handle,
		Generation:          wire.Generation,
		Platform:            wire.Platform,
		Capabilities:        append([]string{}, wire.Capabilities...),
		ProviderEnvironment: wire.ProviderEnvironment,
		SourceLegacyDigest:  wire.SourceLegacyDigest,
	}
	if err := validatePushTokenDirectoryRecord(record); err != nil {
		return pushTokenDirectoryRecord{}, err
	}
	if !equalPushTokenStrings(record.Capabilities, canonicalPushTokenVaultCapabilities(record.Capabilities)) {
		return pushTokenDirectoryRecord{}, errors.New("push token directory capabilities are not canonical")
	}
	return record, nil
}

func encodePushTokenVaultEnvelope(envelope pushTokenVaultEnvelope) ([]byte, error) {
	if err := validatePushTokenVaultEnvelope(envelope); err != nil {
		return nil, err
	}
	return json.Marshal(pushTokenVaultWire{
		Schema:     envelope.Schema,
		KeyID:      envelope.KeyID,
		Nonce:      envelope.Nonce,
		Ciphertext: envelope.Ciphertext,
	})
}

func decodePushTokenVaultEnvelope(payload []byte) (pushTokenVaultEnvelope, error) {
	fields, err := decodePushTokenJSONObject(
		payload,
		[]string{"schema", "key_id", "nonce", "ciphertext"},
		pushTokenJSONMaxBytes,
	)
	if err != nil {
		return pushTokenVaultEnvelope{}, errors.New("push token vault JSON is invalid")
	}

	var wire pushTokenVaultWire
	if err := decodePushTokenJSONField(fields["schema"], &wire.Schema); err != nil {
		return pushTokenVaultEnvelope{}, errors.New("push token vault schema is invalid")
	}
	if err := decodePushTokenJSONField(fields["key_id"], &wire.KeyID); err != nil {
		return pushTokenVaultEnvelope{}, errors.New("push token vault key identifier is invalid")
	}
	if err := decodePushTokenJSONField(fields["nonce"], &wire.Nonce); err != nil {
		return pushTokenVaultEnvelope{}, errors.New("push token vault nonce is invalid")
	}
	if err := decodePushTokenJSONField(fields["ciphertext"], &wire.Ciphertext); err != nil {
		return pushTokenVaultEnvelope{}, errors.New("push token vault ciphertext is invalid")
	}

	envelope := pushTokenVaultEnvelope{
		Schema:     wire.Schema,
		KeyID:      wire.KeyID,
		Nonce:      wire.Nonce,
		Ciphertext: wire.Ciphertext,
	}
	if err := validatePushTokenVaultEnvelope(envelope); err != nil {
		return pushTokenVaultEnvelope{}, err
	}
	return envelope, nil
}

func (config *pushTokenVaultConfig) sealPushToken(
	peerID string,
	directory pushTokenDirectoryRecord,
	token string,
	entropy io.Reader,
) (pushTokenVaultEnvelope, error) {
	if err := config.validate(); err != nil {
		return pushTokenVaultEnvelope{}, err
	}
	directory.Capabilities = canonicalPushTokenVaultCapabilities(directory.Capabilities)
	if err := validatePushTokenDirectoryRecord(directory); err != nil {
		return pushTokenVaultEnvelope{}, err
	}
	if directory.ProviderEnvironment != config.providerEnvironment {
		return pushTokenVaultEnvelope{}, errors.New("push token directory provider environment does not match configuration")
	}
	if peerID == "" {
		return pushTokenVaultEnvelope{}, errors.New("push token vault peer identity is empty")
	}
	if token == "" || len(token) > pushTokenPlaintextMaxBytes {
		return pushTokenVaultEnvelope{}, errors.New("push token vault plaintext size is invalid")
	}
	if entropy == nil {
		entropy = rand.Reader
	}

	key := config.keys[config.activeKeyID]
	block, err := aes.NewCipher(key)
	if err != nil {
		return pushTokenVaultEnvelope{}, errors.New("initialize push token vault cipher")
	}
	gcm, err := newPushTokenGCM(block)
	if err != nil {
		return pushTokenVaultEnvelope{}, err
	}
	nonce := make([]byte, gcm.NonceSize())
	if _, err := io.ReadFull(entropy, nonce); err != nil {
		return pushTokenVaultEnvelope{}, fmt.Errorf("read push token vault entropy: %w", err)
	}
	aad, err := buildPushTokenVaultAAD(peerID, directory, config.activeKeyID)
	if err != nil {
		return pushTokenVaultEnvelope{}, err
	}
	ciphertext := gcm.Seal(nil, nonce, []byte(token), aad)
	envelope := pushTokenVaultEnvelope{
		Schema:     pushTokenVaultSchemaVersion,
		KeyID:      config.activeKeyID,
		Nonce:      base64.StdEncoding.EncodeToString(nonce),
		Ciphertext: base64.StdEncoding.EncodeToString(ciphertext),
	}
	if err := validatePushTokenVaultEnvelope(envelope); err != nil {
		return pushTokenVaultEnvelope{}, err
	}
	return envelope, nil
}

func (config *pushTokenVaultConfig) openPushToken(
	peerID string,
	directory pushTokenDirectoryRecord,
	envelope pushTokenVaultEnvelope,
) (string, error) {
	if err := config.validate(); err != nil {
		return "", err
	}
	if err := validatePushTokenDirectoryRecord(directory); err != nil {
		return "", err
	}
	if !equalPushTokenStrings(directory.Capabilities, canonicalPushTokenVaultCapabilities(directory.Capabilities)) {
		return "", errors.New("push token directory capabilities are not canonical")
	}
	if directory.ProviderEnvironment != config.providerEnvironment {
		return "", errors.New("push token directory provider environment does not match configuration")
	}
	if peerID == "" {
		return "", errors.New("push token vault peer identity is empty")
	}
	if err := validatePushTokenVaultEnvelope(envelope); err != nil {
		return "", err
	}
	key, ok := config.keys[envelope.KeyID]
	if !ok {
		return "", errors.New("push token vault key is not retained")
	}

	nonce, err := decodeCanonicalBase64(envelope.Nonce)
	if err != nil {
		return "", errors.New("push token vault nonce is invalid")
	}
	ciphertext, err := decodeCanonicalBase64(envelope.Ciphertext)
	if err != nil {
		return "", errors.New("push token vault ciphertext is invalid")
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return "", errors.New("initialize push token vault cipher")
	}
	gcm, err := newPushTokenGCM(block)
	if err != nil {
		return "", err
	}
	aad, err := buildPushTokenVaultAAD(peerID, directory, envelope.KeyID)
	if err != nil {
		return "", err
	}
	plaintext, err := gcm.Open(nil, nonce, ciphertext, aad)
	if err != nil {
		return "", errors.New("open push token vault: authentication failed")
	}
	if len(plaintext) == 0 || len(plaintext) > pushTokenPlaintextMaxBytes {
		return "", errors.New("open push token vault: plaintext size is invalid")
	}
	return string(plaintext), nil
}

func (config *pushTokenVaultConfig) validate() error {
	if config == nil {
		return errors.New("push token vault configuration is unavailable")
	}
	if validatePushTokenIdentifier(config.activeKeyID) != nil ||
		validatePushTokenIdentifier(config.providerEnvironment) != nil ||
		len(config.keys) == 0 {
		return errors.New("push token vault configuration is invalid")
	}
	for keyID, key := range config.keys {
		if validatePushTokenIdentifier(keyID) != nil || len(key) != 32 {
			return errors.New("push token vault keyring is invalid")
		}
	}
	if _, ok := config.keys[config.activeKeyID]; !ok {
		return errors.New("push token vault active key is not retained")
	}
	return nil
}

func validatePushTokenDirectoryRecord(record pushTokenDirectoryRecord) error {
	if err := validateOpaquePushHandle(record.Handle); err != nil {
		return err
	}
	if record.Generation == 0 {
		return errors.New("push token directory generation is invalid")
	}
	if validatePushTokenIdentifier(record.Platform) != nil {
		return errors.New("push token directory platform is invalid")
	}
	if validatePushTokenIdentifier(record.ProviderEnvironment) != nil {
		return errors.New("push token directory provider environment is invalid")
	}
	if err := validateCanonicalPushCapabilities(record.Capabilities); err != nil {
		return err
	}
	if err := validatePushTokenSourceLegacyDigest(record.SourceLegacyDigest); err != nil {
		return err
	}
	return nil
}

func validatePushTokenVaultEnvelope(envelope pushTokenVaultEnvelope) error {
	if envelope.Schema != pushTokenVaultSchemaVersion {
		return errors.New("push token vault schema is invalid")
	}
	if validatePushTokenIdentifier(envelope.KeyID) != nil {
		return errors.New("push token vault key identifier is invalid")
	}
	nonce, err := decodeCanonicalBase64(envelope.Nonce)
	if err != nil || len(nonce) != 12 {
		return errors.New("push token vault nonce is invalid")
	}
	ciphertext, err := decodeCanonicalBase64(envelope.Ciphertext)
	if err != nil || len(ciphertext) < 16 || len(ciphertext) > pushTokenPlaintextMaxBytes+16 {
		return errors.New("push token vault ciphertext is invalid")
	}
	return nil
}

func buildPushTokenVaultAAD(
	peerID string,
	directory pushTokenDirectoryRecord,
	keyID string,
) ([]byte, error) {
	if peerID == "" {
		return nil, errors.New("push token vault peer identity is empty")
	}
	directory.Capabilities = canonicalPushTokenVaultCapabilities(directory.Capabilities)
	if err := validatePushTokenDirectoryRecord(directory); err != nil {
		return nil, err
	}
	if validatePushTokenIdentifier(keyID) != nil {
		return nil, errors.New("push token vault key identifier is invalid")
	}
	peerDigest := sha256.Sum256([]byte(peerID))
	return json.Marshal(pushTokenAADWire{
		Schema:              pushTokenVaultSchemaVersion,
		PeerDigest:          hex.EncodeToString(peerDigest[:]),
		Handle:              directory.Handle,
		Generation:          directory.Generation,
		Platform:            directory.Platform,
		Capabilities:        append([]string{}, directory.Capabilities...),
		SourceLegacyDigest:  directory.SourceLegacyDigest,
		ProviderEnvironment: directory.ProviderEnvironment,
		KeyID:               keyID,
	})
}

func pushTokenLegacyDigest(payload []byte) string {
	digest := sha256.Sum256(payload)
	return hex.EncodeToString(digest[:])
}

func parsePushTokenLegacyDigest(value string) ([sha256.Size]byte, error) {
	var digest [sha256.Size]byte
	if validatePushTokenSourceLegacyDigest(value) != nil || value == "" {
		return digest, errors.New("push token source legacy digest is invalid")
	}
	decoded, err := hex.DecodeString(value)
	if err != nil || len(decoded) != len(digest) {
		return digest, errors.New("push token source legacy digest is invalid")
	}
	copy(digest[:], decoded)
	return digest, nil
}

func validatePushTokenSourceLegacyDigest(value string) error {
	if value == "" {
		return nil
	}
	if len(value) != sha256.Size*2 {
		return errors.New("push token source legacy digest is invalid")
	}
	decoded, err := hex.DecodeString(value)
	if err != nil || hex.EncodeToString(decoded) != value {
		return errors.New("push token source legacy digest is invalid")
	}
	return nil
}

func validateOpaquePushHandle(handle string) error {
	decoded, err := base64.RawURLEncoding.Strict().DecodeString(handle)
	if err != nil || len(decoded) != 32 || base64.RawURLEncoding.EncodeToString(decoded) != handle {
		return errors.New("push token directory handle is invalid")
	}
	return nil
}

func validateCanonicalPushCapabilities(capabilities []string) error {
	if len(capabilities) > pushTokenCapabilityMaxCount {
		return errors.New("push token directory has too many capabilities")
	}
	for i, capability := range capabilities {
		if validatePushTokenIdentifier(capability) != nil {
			return errors.New("push token directory capability is invalid")
		}
		if i > 0 && capabilities[i-1] >= capability {
			return errors.New("push token directory capabilities are not canonical")
		}
	}
	return nil
}

func canonicalPushTokenVaultCapabilities(capabilities []string) []string {
	seen := make(map[string]struct{}, len(capabilities))
	canonical := make([]string, 0, len(capabilities))
	for _, capability := range capabilities {
		capability = strings.TrimSpace(capability)
		if capability == "" {
			continue
		}
		if _, duplicate := seen[capability]; duplicate {
			continue
		}
		seen[capability] = struct{}{}
		canonical = append(canonical, capability)
	}
	sort.Strings(canonical)
	return canonical
}

func validatePushTokenIdentifier(value string) error {
	if len(value) == 0 || len(value) > pushTokenIdentifierMaxBytes {
		return errors.New("push token identifier length is invalid")
	}
	for i := 0; i < len(value); i++ {
		if value[i] < 0x21 || value[i] > 0x7e {
			return errors.New("push token identifier must be printable ASCII without whitespace")
		}
	}
	return nil
}

func decodeCanonicalBase64(value string) ([]byte, error) {
	decoded, err := base64.StdEncoding.Strict().DecodeString(value)
	if err != nil || base64.StdEncoding.EncodeToString(decoded) != value {
		return nil, errors.New("base64 value is not canonical")
	}
	return decoded, nil
}

func clonePushTokenKeys(keys map[string][]byte) map[string][]byte {
	clone := make(map[string][]byte, len(keys))
	for keyID, key := range keys {
		clone[keyID] = append([]byte(nil), key...)
	}
	return clone
}

func equalPushTokenStrings(left, right []string) bool {
	if len(left) != len(right) {
		return false
	}
	for i := range left {
		if left[i] != right[i] {
			return false
		}
	}
	return true
}

// decodePushTokenJSONObject parses one complete JSON object while preserving
// duplicate-key detection. allowed == nil admits arbitrary field names (used
// only for the keyring's key-ID map); a non-nil list is both the exact allow
// list and the exact required-field list.
func decodePushTokenJSONObject(
	payload []byte,
	allowed []string,
	maxBytes int,
) (map[string]json.RawMessage, error) {
	if len(payload) == 0 || len(payload) > maxBytes {
		return nil, errors.New("JSON object size is invalid")
	}
	allowedSet := make(map[string]struct{}, len(allowed))
	for _, field := range allowed {
		allowedSet[field] = struct{}{}
	}

	decoder := json.NewDecoder(bytes.NewReader(payload))
	opening, err := decoder.Token()
	if err != nil || opening != json.Delim('{') {
		return nil, errors.New("JSON value is not an object")
	}
	fields := make(map[string]json.RawMessage)
	for decoder.More() {
		token, err := decoder.Token()
		if err != nil {
			return nil, errors.New("JSON object field is invalid")
		}
		field, ok := token.(string)
		if !ok {
			return nil, errors.New("JSON object field name is invalid")
		}
		if _, duplicate := fields[field]; duplicate {
			return nil, errors.New("JSON object contains a duplicate field")
		}
		if allowed != nil {
			if _, ok := allowedSet[field]; !ok {
				return nil, errors.New("JSON object contains an unknown field")
			}
		}
		var raw json.RawMessage
		if err := decoder.Decode(&raw); err != nil {
			return nil, errors.New("JSON object field value is invalid")
		}
		fields[field] = append(json.RawMessage(nil), raw...)
	}
	closing, err := decoder.Token()
	if err != nil || closing != json.Delim('}') {
		return nil, errors.New("JSON object is not closed")
	}
	if _, err := decoder.Token(); !errors.Is(err, io.EOF) {
		return nil, errors.New("JSON object has trailing data")
	}
	if allowed != nil {
		for _, required := range allowed {
			if _, ok := fields[required]; !ok {
				return nil, errors.New("JSON object is missing a required field")
			}
		}
	}
	return fields, nil
}

func decodePushTokenJSONField(payload json.RawMessage, destination any) error {
	if bytes.Equal(bytes.TrimSpace(payload), []byte("null")) {
		return errors.New("JSON field must not be null")
	}
	decoder := json.NewDecoder(bytes.NewReader(payload))
	if err := decoder.Decode(destination); err != nil {
		return err
	}
	if _, err := decoder.Token(); !errors.Is(err, io.EOF) {
		return errors.New("JSON field has trailing data")
	}
	return nil
}

// newPushTokenGCM is kept as a tiny seam so all construction errors remain
// generic and no key material can appear in returned error text.
func newPushTokenGCM(block cipher.Block) (cipher.AEAD, error) {
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, errors.New("initialize push token vault GCM")
	}
	return gcm, nil
}
