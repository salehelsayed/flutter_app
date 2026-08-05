// Command iospayloadproducer creates the private APNs body used by the
// physical-iPhone notification SIMS leg. It deliberately does not submit the
// notification or touch the relay: its only durable output is an owner-only
// JSON file containing the encrypted route.
package main

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"syscall"
	"time"

	libp2pcrypto "github.com/libp2p/go-libp2p/core/crypto"
	"github.com/libp2p/go-libp2p/core/peer"
	mcrypto "github.com/mknoon/go-mknoon/crypto"
)

const (
	handoffSchema = "mknoon.sims.ios-provider-receiver-handoff.v2"
	requestSchema = "mknoon.sims.ios-payload-fast-path-provider-request.v1"
	payloadSchema = "mknoon.sims.ios-payload-private-fixture.v1"
	bundleID      = "com.mknoon.app"
)

var safeRunToken = regexp.MustCompile(`^[A-Za-z0-9._:@+-]{4,256}$`)

type providerRequest struct {
	Schema              string `json:"schema"`
	ExpectedTitle       string `json:"expectedTitle"`
	ExpectedBody        string `json:"expectedBody"`
	ExpectedMessageText string `json:"expectedMessageText"`
	ReceiverDeviceID    string `json:"receiverDeviceId"`
	PeerDeviceID        string `json:"peerDeviceId"`
}

type receiverHandoff struct {
	Schema                    string `json:"schema"`
	CaptureNonce              string `json:"captureNonce"`
	ReceiverDeviceID          string `json:"receiverDeviceId"`
	PeerDeviceID              string `json:"peerDeviceId"`
	BundleID                  string `json:"bundleId"`
	APNSEnvironment           string `json:"apnsEnvironment"`
	APNSDeviceToken           string `json:"apnsDeviceToken"`
	MLKemPublicKey            string `json:"mlKemPublicKey"`
	NotificationAuthorization string `json:"notificationAuthorization"`
	NotificationAlertSetting  string `json:"notificationAlertSetting"`
	NotificationBadgeSetting  string `json:"notificationBadgeSetting"`
	CapturedAt                string `json:"capturedAt"`
}

type encryptedFields struct {
	Kem        string `json:"kem"`
	Ciphertext string `json:"ciphertext"`
	Nonce      string `json:"nonce"`
}

type chatEnvelope struct {
	Type         string          `json:"type"`
	Version      string          `json:"version"`
	ID           string          `json:"id"`
	SenderPeerID string          `json:"senderPeerId"`
	Encrypted    encryptedFields `json:"encrypted"`
}

type apnsAlert struct {
	Title string `json:"title"`
	Body  string `json:"body"`
}

type apnsControl struct {
	Alert          apnsAlert `json:"alert"`
	MutableContent int       `json:"mutable-content"`
}

type apnsPayload struct {
	FixtureSchema string      `json:"fixture_schema"`
	APS           apnsControl `json:"aps"`
	Type          string      `json:"type"`
	SenderID      string      `json:"sender_id"`
	MessageID     string      `json:"message_id"`
	Kem           string      `json:"kem"`
	Ciphertext    string      `json:"ciphertext"`
	Nonce         string      `json:"nonce"`
}

type innerMessage struct {
	ID             string `json:"id"`
	Text           string `json:"text"`
	SenderPeerID   string `json:"senderPeerId"`
	SenderUsername string `json:"senderUsername"`
	Timestamp      string `json:"timestamp"`
}

type options struct {
	requestPath string
	handoffPath string
	runID       string
	nonce       string
	outputPath  string
}

func main() {
	if err := execute(os.Args[1:]); err != nil {
		// All returned errors are intentionally static and contain neither file
		// contents nor cryptographic/provider material.
		fmt.Fprintf(os.Stderr, "iOS payload producer failed: %v\n", err)
		os.Exit(1)
	}
}

func execute(args []string) error {
	parsed, err := parseOptions(args)
	if err != nil {
		return errors.New("invalid command contract")
	}

	requestBytes, err := readOwnerOnlyFile(parsed.requestPath)
	if err != nil {
		return errors.New("provider request is not a private regular file")
	}
	handoffBytes, err := readOwnerOnlyFile(parsed.handoffPath)
	if err != nil {
		return errors.New("receiver handoff is not a private regular file")
	}

	var request providerRequest
	if err := decodeExactJSON(requestBytes, &request); err != nil {
		return errors.New("provider request contract is invalid")
	}
	var handoff receiverHandoff
	if err := decodeExactJSON(handoffBytes, &handoff); err != nil {
		return errors.New("receiver handoff contract is invalid")
	}

	payload, err := producePayload(request, handoff, parsed.runID, parsed.nonce)
	if err != nil {
		return err
	}
	if err := writeOwnerOnlyAtomic(parsed.outputPath, payload); err != nil {
		return errors.New("private APNs payload could not be written")
	}
	return nil
}

func parseOptions(args []string) (options, error) {
	set := flag.NewFlagSet("iospayloadproducer", flag.ContinueOnError)
	set.SetOutput(io.Discard)
	var result options
	set.StringVar(&result.requestPath, "provider-request", "", "private provider request")
	set.StringVar(&result.handoffPath, "receiver-handoff", "", "private receiver handoff")
	set.StringVar(&result.runID, "run-id", "", "SIMS run identifier")
	set.StringVar(&result.nonce, "nonce", "", "SIMS run nonce")
	set.StringVar(&result.outputPath, "output", "", "owner-only APNs payload")
	if err := set.Parse(args); err != nil || set.NArg() != 0 {
		return options{}, errors.New("parse options")
	}
	if result.requestPath == "" || result.handoffPath == "" || result.outputPath == "" ||
		!safeRunToken.MatchString(result.runID) || !safeRunToken.MatchString(result.nonce) {
		return options{}, errors.New("missing options")
	}
	return result, nil
}

func decodeExactJSON(data []byte, destination any) error {
	if err := rejectDuplicateJSONKeys(data); err != nil {
		return err
	}
	decoder := json.NewDecoder(strings.NewReader(string(data)))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(destination); err != nil {
		return err
	}
	var trailing any
	if err := decoder.Decode(&trailing); err != io.EOF {
		return errors.New("trailing JSON data")
	}
	return nil
}

func rejectDuplicateJSONKeys(data []byte) error {
	decoder := json.NewDecoder(strings.NewReader(string(data)))
	if err := walkJSONValue(decoder); err != nil {
		return err
	}
	if _, err := decoder.Token(); err != io.EOF {
		if err != nil {
			return err
		}
		return errors.New("trailing JSON data")
	}
	return nil
}

func walkJSONValue(decoder *json.Decoder) error {
	token, err := decoder.Token()
	if err != nil {
		return err
	}
	delimiter, ok := token.(json.Delim)
	if !ok {
		return nil
	}
	switch delimiter {
	case '{':
		seen := make(map[string]struct{})
		for decoder.More() {
			keyToken, err := decoder.Token()
			if err != nil {
				return err
			}
			key, ok := keyToken.(string)
			if !ok {
				return errors.New("JSON object key is invalid")
			}
			if _, duplicate := seen[key]; duplicate {
				return errors.New("duplicate JSON object key")
			}
			seen[key] = struct{}{}
			if err := walkJSONValue(decoder); err != nil {
				return err
			}
		}
		closing, err := decoder.Token()
		if err != nil || closing != json.Delim('}') {
			return errors.New("JSON object is invalid")
		}
	case '[':
		for decoder.More() {
			if err := walkJSONValue(decoder); err != nil {
				return err
			}
		}
		closing, err := decoder.Token()
		if err != nil || closing != json.Delim(']') {
			return errors.New("JSON array is invalid")
		}
	default:
		return errors.New("JSON value is invalid")
	}
	return nil
}

func readOwnerOnlyFile(path string) ([]byte, error) {
	if path == "" || strings.ContainsAny(path, "\r\n") {
		return nil, errors.New("invalid path")
	}
	info, err := os.Lstat(path)
	if err != nil || !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 || info.Size() <= 0 {
		return nil, errors.New("not a regular file")
	}
	if info.Mode().Perm()&0o077 != 0 {
		return nil, errors.New("permissions are not owner-only")
	}
	if stat, ok := info.Sys().(*syscall.Stat_t); ok && int(stat.Uid) != os.Getuid() {
		return nil, errors.New("file is not operator-owned")
	}
	return os.ReadFile(path)
}

func bounded(value string, maximum int) bool {
	trimmed := strings.TrimSpace(value)
	return trimmed != "" && len(value) <= maximum && !strings.ContainsAny(value, "\r\n")
}

func boundedFixtureText(value string, maximum int) bool {
	if value == "" || value != strings.TrimSpace(value) || len(value) > maximum {
		return false
	}
	for _, character := range value {
		if character < 0x20 || character > 0x7e {
			return false
		}
	}
	return true
}

func producePayload(request providerRequest, handoff receiverHandoff, runID, nonce string) ([]byte, error) {
	if request.Schema != requestSchema || handoff.Schema != handoffSchema {
		return nil, errors.New("input schemas do not match the iOS fixture contract")
	}
	// The title is also the sender name stored in the disposable contact and
	// used by the NSE after decrypting the message. Keep it within the app's
	// contact-username bound so seed, ingest, and exact cleanup all agree.
	if !boundedFixtureText(request.ExpectedTitle, 30) ||
		!boundedFixtureText(request.ExpectedBody, 512) ||
		!boundedFixtureText(request.ExpectedMessageText, 140) ||
		!bounded(request.ReceiverDeviceID, 160) ||
		!bounded(request.PeerDeviceID, 160) {
		return nil, errors.New("provider request contains an invalid bounded field")
	}
	if strings.Contains(request.ExpectedTitle, request.ExpectedMessageText) ||
		strings.Contains(request.ExpectedBody, request.ExpectedMessageText) {
		return nil, errors.New("provider request exposes message plaintext in its alert")
	}
	if handoff.BundleID != bundleID || handoff.APNSEnvironment != "development" ||
		handoff.ReceiverDeviceID != request.ReceiverDeviceID ||
		handoff.PeerDeviceID != request.PeerDeviceID ||
		!map[string]bool{"authorized": true, "provisional": true, "ephemeral": true}[handoff.NotificationAuthorization] ||
		handoff.NotificationAlertSetting != "enabled" ||
		handoff.NotificationBadgeSetting != "enabled" ||
		!bounded(handoff.CaptureNonce, 256) {
		return nil, errors.New("receiver handoff is not bound to the sandbox request")
	}
	if _, err := peer.Decode(handoff.PeerDeviceID); err != nil {
		return nil, errors.New("receiver handoff peer identity is invalid")
	}
	if _, err := time.Parse(time.RFC3339Nano, handoff.CapturedAt); err != nil {
		return nil, errors.New("receiver handoff timestamp is invalid")
	}
	if len(handoff.APNSDeviceToken) != 64 {
		return nil, errors.New("receiver handoff APNs token is invalid")
	}
	decodedToken, err := hex.DecodeString(handoff.APNSDeviceToken)
	if err != nil || len(decodedToken) != 32 {
		return nil, errors.New("receiver handoff APNs token is invalid")
	}
	publicKey, err := base64.StdEncoding.DecodeString(handoff.MLKemPublicKey)
	if err != nil || len(publicKey) != 1184 {
		return nil, errors.New("receiver handoff ML-KEM public key is invalid")
	}

	senderPrivate, _, err := libp2pcrypto.GenerateEd25519Key(rand.Reader)
	if err != nil {
		return nil, errors.New("ephemeral sender identity generation failed")
	}
	senderID, err := peer.IDFromPrivateKey(senderPrivate)
	if err != nil {
		return nil, errors.New("ephemeral sender peer identity generation failed")
	}

	messageDigest := sha256.Sum256([]byte(strings.Join([]string{
		runID,
		nonce,
		handoff.CaptureNonce,
		handoff.PeerDeviceID,
		senderID.String(),
	}, "\x00")))
	messageID := "ios-sims-" + hex.EncodeToString(messageDigest[:16])
	inner := innerMessage{
		ID:             messageID,
		Text:           request.ExpectedMessageText,
		SenderPeerID:   senderID.String(),
		SenderUsername: request.ExpectedTitle,
		Timestamp:      time.Now().UTC().Format(time.RFC3339Nano),
	}
	innerBytes, err := json.Marshal(inner)
	if err != nil {
		return nil, errors.New("inner chat message encoding failed")
	}
	encrypted, err := mcrypto.EncryptMessage(handoff.MLKemPublicKey, string(innerBytes))
	if err != nil {
		return nil, errors.New("real ML-KEM chat encryption failed")
	}

	envelope := chatEnvelope{
		Type:         "chat_message",
		Version:      "2",
		ID:           messageID,
		SenderPeerID: senderID.String(),
		Encrypted: encryptedFields{
			Kem:        encrypted.Kem,
			Ciphertext: encrypted.Ciphertext,
			Nonce:      encrypted.Nonce,
		},
	}
	// Marshal the actual outer envelope here even though the APNs route stores
	// the same fields flat. This closes the producer boundary against an invalid
	// v2 shape before any private payload is written.
	if _, err := json.Marshal(envelope); err != nil {
		return nil, errors.New("encrypted chat envelope encoding failed")
	}

	payload := apnsPayload{
		FixtureSchema: payloadSchema,
		APS: apnsControl{
			Alert: apnsAlert{
				Title: request.ExpectedTitle,
				Body:  request.ExpectedBody,
			},
			MutableContent: 1,
		},
		Type:       "new_message",
		SenderID:   envelope.SenderPeerID,
		MessageID:  envelope.ID,
		Kem:        envelope.Encrypted.Kem,
		Ciphertext: envelope.Encrypted.Ciphertext,
		Nonce:      envelope.Encrypted.Nonce,
	}
	encoded, err := json.Marshal(payload)
	if err != nil {
		return nil, errors.New("APNs payload encoding failed")
	}
	if len(encoded)+1 > 4096 {
		return nil, errors.New("encrypted APNs payload exceeds the provider limit")
	}
	encoded = append(encoded, '\n')
	return encoded, nil
}

func writeOwnerOnlyAtomic(path string, data []byte) error {
	if path == "" || strings.ContainsAny(path, "\r\n") {
		return errors.New("invalid output path")
	}
	absolute, err := filepath.Abs(path)
	if err != nil {
		return err
	}
	parent := filepath.Dir(absolute)
	if err := os.MkdirAll(parent, 0o700); err != nil {
		return err
	}
	if info, err := os.Lstat(absolute); err == nil && info.Mode()&os.ModeSymlink != 0 {
		return errors.New("output is a symlink")
	} else if err != nil && !os.IsNotExist(err) {
		return err
	}
	temporary, err := os.CreateTemp(parent, ".ios-apns-payload-*")
	if err != nil {
		return err
	}
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)
	if err := temporary.Chmod(0o600); err != nil {
		temporary.Close()
		return err
	}
	if _, err := temporary.Write(data); err != nil {
		temporary.Close()
		return err
	}
	if err := temporary.Sync(); err != nil {
		temporary.Close()
		return err
	}
	if err := temporary.Close(); err != nil {
		return err
	}
	if err := os.Rename(temporaryPath, absolute); err != nil {
		return err
	}
	return os.Chmod(absolute, 0o600)
}
