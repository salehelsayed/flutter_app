package main

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"log"
	"reflect"
	"sort"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
	mocknet "github.com/libp2p/go-libp2p/p2p/net/mock"
)

type turnTestRecordingIssuer struct {
	mu       sync.Mutex
	bundle   TurnCredentialBundle
	err      error
	subjects []string
}

type turnTestDeadlineIssuer struct {
	deadlineSeen chan bool
}

func (i *turnTestDeadlineIssuer) Issue(
	ctx context.Context,
	_ string,
) (TurnCredentialBundle, error) {
	deadline, ok := ctx.Deadline()
	i.deadlineSeen <- ok && time.Until(deadline) <= turnCredentialIssueTimeout
	if !ok {
		return TurnCredentialBundle{}, ErrTurnCredentialUnavailable
	}
	<-ctx.Done()
	return TurnCredentialBundle{}, ctx.Err()
}

type turnTestLogBuffer struct {
	mu     sync.Mutex
	buffer bytes.Buffer
}

func (b *turnTestLogBuffer) Write(data []byte) (int, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buffer.Write(data)
}

func (b *turnTestLogBuffer) String() string {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buffer.String()
}

func (i *turnTestRecordingIssuer) Issue(
	_ context.Context,
	authenticatedSubject string,
) (TurnCredentialBundle, error) {
	i.mu.Lock()
	defer i.mu.Unlock()
	i.subjects = append(i.subjects, authenticatedSubject)
	return i.bundle, i.err
}

func (i *turnTestRecordingIssuer) snapshot() (int, string) {
	i.mu.Lock()
	defer i.mu.Unlock()
	if len(i.subjects) == 0 {
		return 0, ""
	}
	return len(i.subjects), i.subjects[len(i.subjects)-1]
}

type turnCredentialStreamEnv struct {
	server     host.Host
	client     host.Host
	other      host.Host
	inbox      *InboxStore
	groupInbox *GroupInboxStore
	handled    chan struct{}
}

func setupTurnCredentialStreamEnv(
	t *testing.T,
	issuer TurnCredentialIssuer,
) *turnCredentialStreamEnv {
	t.Helper()
	mn := mocknet.New()
	server, err := mn.GenPeer()
	if err != nil {
		t.Fatal("generate local relay host")
	}
	client, err := mn.GenPeer()
	if err != nil {
		t.Fatal("generate local authenticated client")
	}
	other, err := mn.GenPeer()
	if err != nil {
		t.Fatal("generate second local authenticated client")
	}
	if err := mn.LinkAll(); err != nil {
		t.Fatal("link local relay fixture")
	}
	if err := mn.ConnectAllButSelf(); err != nil {
		t.Fatal("connect local relay fixture")
	}

	inbox := NewInboxStore(NewPushServiceWithBackend(newMemoryPushTokenStore()))
	groupInbox := NewGroupInboxStore(8, time.Hour)
	presence := NewPresenceStore()
	handled := make(chan struct{}, 1)
	server.SetStreamHandler(InboxProtocol, func(stream network.Stream) {
		defer func() { handled <- struct{}{} }()
		HandleInboxStream(stream, inbox, groupInbox, server, presence, issuer)
	})
	t.Cleanup(func() {
		_ = server.Close()
		_ = client.Close()
		_ = other.Close()
	})
	return &turnCredentialStreamEnv{
		server:     server,
		client:     client,
		other:      other,
		inbox:      inbox,
		groupInbox: groupInbox,
		handled:    handled,
	}
}

func roundTripTurnCredentialRaw(
	t *testing.T,
	env *turnCredentialStreamEnv,
	from host.Host,
	request []byte,
) ([]byte, map[string]json.RawMessage) {
	t.Helper()
	stream, err := from.NewStream(context.Background(), env.server.ID(), InboxProtocol)
	if err != nil {
		t.Fatal("open local TURN credential stream")
	}
	defer stream.Close()
	if err := writeFrame(stream, request); err != nil {
		t.Fatal("write local TURN credential request")
	}
	response, err := readFrame(stream)
	if err != nil {
		t.Fatal("read local TURN credential response")
	}
	select {
	case <-env.handled:
	case <-time.After(5 * time.Second):
		t.Fatal("local TURN credential handler did not complete")
	}
	var decoded map[string]json.RawMessage
	if err := json.Unmarshal(response, &decoded); err != nil {
		t.Fatal("decode local TURN credential response")
	}
	return response, decoded
}

func turnTestJSONKeys(decoded map[string]json.RawMessage) []string {
	keys := make([]string, 0, len(decoded))
	for key := range decoded {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	return keys
}

func turnTestJSONText(t *testing.T, decoded map[string]json.RawMessage, key string) string {
	t.Helper()
	var value string
	if err := json.Unmarshal(decoded[key], &value); err != nil {
		t.Fatal("TURN credential response field was not a string")
	}
	return value
}

func turnTestBundle() TurnCredentialBundle {
	opaque := make([]byte, 32)
	for i := range opaque {
		opaque[i] = byte(i + 1)
	}
	password := make([]byte, 20)
	for i := range password {
		password[i] = byte(i + 0x40)
	}
	return TurnCredentialBundle{
		Schema:       turnTestSchema,
		Version:      turnTestVersion,
		Username:     strconv.FormatInt(turnTestNow.Add(10*time.Minute).Unix(), 10) + ":" + base64.RawURLEncoding.EncodeToString(opaque),
		Password:     base64.StdEncoding.EncodeToString(password),
		TTLSeconds:   600,
		URLs:         []string{"turn:relay.invalid:3478?transport=udp"},
		ServerTimeMs: turnTestNow.UnixMilli(),
		ExpiresAtMs:  turnTestNow.Add(10 * time.Minute).UnixMilli(),
	}
}

func TestTurnCredentialsV1_HandlerAcceptsOnlyExactActionObject(t *testing.T) {
	issuer := &turnTestRecordingIssuer{bundle: turnTestBundle()}
	env := setupTurnCredentialStreamEnv(t, issuer)

	invalid := []struct {
		name    string
		request []byte
	}{
		{name: "empty object", request: []byte(`{}`)},
		{name: "unknown action", request: []byte(`{"action":"turn_credentials_v2"}`)},
		{name: "duplicate action", request: []byte(`{"action":"turn_credentials_v1","action":"turn_credentials_v1"}`)},
		{name: "unknown field", request: []byte(`{"action":"turn_credentials_v1","extra":true}`)},
		{name: "claimed peer id", request: []byte(`{"action":"turn_credentials_v1","peerId":"claimed"}`)},
		{name: "claimed subject", request: []byte(`{"action":"turn_credentials_v1","subject":"claimed"}`)},
		{name: "claimed sender", request: []byte(`{"action":"turn_credentials_v1","from":"claimed"}`)},
		{name: "claimed recipient", request: []byte(`{"action":"turn_credentials_v1","to":"claimed"}`)},
		{name: "non-string action", request: []byte(`{"action":1}`)},
		{name: "trailing value", request: []byte(`{"action":"turn_credentials_v1"}{}`)},
	}
	for _, tc := range invalid {
		t.Run(tc.name, func(t *testing.T) {
			_, decoded := roundTripTurnCredentialRaw(t, env, env.client, tc.request)
			if turnTestJSONText(t, decoded, "status") != "ERROR" {
				t.Fatal("non-exact TURN credential request was accepted")
			}
		})
	}
	if calls, _ := issuer.snapshot(); calls != 0 {
		t.Fatal("invalid TURN credential request reached the issuer")
	}

	_, decoded := roundTripTurnCredentialRaw(
		t,
		env,
		env.client,
		[]byte(" \n { \"action\" : \"turn_credentials_v1\" } \n"),
	)
	if turnTestJSONText(t, decoded, "status") != "OK" {
		t.Fatal("exact action-only TURN credential request was rejected")
	}
	if calls, _ := issuer.snapshot(); calls != 1 {
		t.Fatal("exact action-only request did not invoke the issuer exactly once")
	}
}

func TestTurnCredentialsV1_HandlerBindsAuthenticatedStreamSubject(t *testing.T) {
	issuer := &turnTestRecordingIssuer{bundle: turnTestBundle()}
	env := setupTurnCredentialStreamEnv(t, issuer)
	request := []byte(`{"action":"turn_credentials_v1"}`)

	_, first := roundTripTurnCredentialRaw(t, env, env.client, request)
	if turnTestJSONText(t, first, "status") != "OK" {
		t.Fatal("authenticated client did not receive TURN credentials")
	}
	if calls, subject := issuer.snapshot(); calls != 1 || subject != env.client.ID().String() {
		t.Fatal("handler did not bind issuance to the authenticated stream remote")
	}

	_, second := roundTripTurnCredentialRaw(t, env, env.other, request)
	if turnTestJSONText(t, second, "status") != "OK" {
		t.Fatal("second authenticated client did not receive TURN credentials")
	}
	if calls, subject := issuer.snapshot(); calls != 2 || subject != env.other.ID().String() {
		t.Fatal("handler reused a claimed or stale subject instead of the stream remote")
	}
}

func TestTurnCredentialsV1_HandlerSuccessHasExactAllowlistedKeys(t *testing.T) {
	bundle := turnTestBundle()
	issuer := &turnTestRecordingIssuer{bundle: bundle}
	env := setupTurnCredentialStreamEnv(t, issuer)
	response, decoded := roundTripTurnCredentialRaw(
		t,
		env,
		env.client,
		[]byte(`{"action":"turn_credentials_v1"}`),
	)

	wantKeys := []string{
		"expiresAtMs",
		"password",
		"schema",
		"serverTimeMs",
		"status",
		"ttlSeconds",
		"urls",
		"username",
		"version",
	}
	if got := turnTestJSONKeys(decoded); !reflect.DeepEqual(got, wantKeys) {
		t.Fatalf("TURN credential success keys = %v, want %v", got, wantKeys)
	}
	if turnTestJSONText(t, decoded, "status") != "OK" ||
		turnTestJSONText(t, decoded, "schema") != turnTestSchema {
		t.Fatal("TURN credential success discriminator changed")
	}
	for _, forbiddenKey := range []string{
		"secret",
		"sharedSecret",
		"staticPassword",
		"peer",
		"peerId",
		"subject",
		"identity",
		"from",
		"to",
		"callId",
	} {
		if _, exists := decoded[forbiddenKey]; exists {
			t.Fatal("TURN credential response exposed a forbidden server or identity field")
		}
	}
	if bytes.Contains(response, []byte(env.client.ID().String())) {
		t.Fatal("TURN credential response disclosed the authenticated stream identity")
	}
}

func TestTurnCredentialsV1_HandlerNilAndProviderFailureAreFiniteAndRedacted(t *testing.T) {
	privateMarker := string([]byte{0x70, 0x72, 0x69, 0x76, 0x61, 0x74, 0x65, 0x2d, 0x70, 0x72, 0x6f, 0x76, 0x69, 0x64, 0x65, 0x72})
	providerFailure := &turnTestRecordingIssuer{
		err: errors.Join(ErrTurnCredentialUnavailable, errors.New(privateMarker)),
	}

	for _, tc := range []struct {
		name   string
		issuer TurnCredentialIssuer
	}{
		{name: "disabled", issuer: nil},
		{name: "provider failure", issuer: providerFailure},
	} {
		t.Run(tc.name, func(t *testing.T) {
			var journal turnTestLogBuffer
			previousWriter := log.Writer()
			log.SetOutput(&journal)
			t.Cleanup(func() { log.SetOutput(previousWriter) })
			env := setupTurnCredentialStreamEnv(t, tc.issuer)
			response, decoded := roundTripTurnCredentialRaw(
				t,
				env,
				env.client,
				[]byte(`{"action":"turn_credentials_v1"}`),
			)
			if got, want := turnTestJSONKeys(decoded), []string{"errorCode", "status"}; !reflect.DeepEqual(got, want) {
				t.Fatalf("TURN credential failure keys = %v, want %v", got, want)
			}
			if turnTestJSONText(t, decoded, "status") != "ERROR" ||
				turnTestJSONText(t, decoded, "errorCode") != "TURN_CREDENTIALS_UNAVAILABLE" {
				t.Fatal("TURN credential outage did not use the finite unavailable response")
			}
			identity := env.client.ID().String()
			shortIdentity := identity[:min(20, len(identity))]
			for _, forbidden := range []string{
				privateMarker,
				identity,
				shortIdentity,
				turnTestBundle().Username,
				turnTestBundle().Password,
			} {
				if strings.Contains(string(response), forbidden) || strings.Contains(journal.String(), forbidden) {
					t.Fatal("TURN credential failure exposed provider, identity, or credential material")
				}
			}
		})
	}
}

func TestTurnCredentialsV1_HandlerDoesNotMutateInboxOrCustody(t *testing.T) {
	issuer := &turnTestRecordingIssuer{bundle: turnTestBundle()}
	env := setupTurnCredentialStreamEnv(t, issuer)
	legacyRecipient := turnTestSubject(0x78)
	if _, err := env.inbox.Store(legacyRecipient, inboxMessage{
		From:      turnTestSubject(0x79),
		Message:   `{"fixture":"legacy"}`,
		Timestamp: turnTestNow.UnixMilli(),
	}); err != nil {
		t.Fatal("seed legacy inbox preservation fixture")
	}
	if err := env.groupInbox.Store("turn-preservation-group", turnTestSubject(0x7a), `{"fixture":"group"}`); err != nil {
		t.Fatal("seed group inbox preservation fixture")
	}
	legacyPeersBefore, legacyMessagesBefore := env.inbox.Stats()
	custodyPeersBefore, custodyMessagesBefore := env.inbox.AckCustodyStats()
	groupsBefore, groupMessagesBefore := env.groupInbox.Stats()

	_, decoded := roundTripTurnCredentialRaw(
		t,
		env,
		env.client,
		[]byte(`{"action":"turn_credentials_v1"}`),
	)
	if turnTestJSONText(t, decoded, "status") != "OK" {
		t.Fatal("TURN credential preservation request failed")
	}
	legacyPeersAfter, legacyMessagesAfter := env.inbox.Stats()
	custodyPeersAfter, custodyMessagesAfter := env.inbox.AckCustodyStats()
	groupsAfter, groupMessagesAfter := env.groupInbox.Stats()
	if legacyPeersAfter != legacyPeersBefore || legacyMessagesAfter != legacyMessagesBefore {
		t.Fatal("TURN credential issuance mutated the legacy inbox")
	}
	if custodyPeersAfter != custodyPeersBefore || custodyMessagesAfter != custodyMessagesBefore {
		t.Fatal("TURN credential issuance mutated protected custody")
	}
	if groupsAfter != groupsBefore || groupMessagesAfter != groupMessagesBefore {
		t.Fatal("TURN credential issuance mutated the group inbox")
	}
}

func TestTurnCredentialsV1_HandlerBoundsIssuerOutageWithFiniteResponse(t *testing.T) {
	issuer := &turnTestDeadlineIssuer{deadlineSeen: make(chan bool, 1)}
	env := setupTurnCredentialStreamEnv(t, issuer)
	_, decoded := roundTripTurnCredentialRaw(
		t,
		env,
		env.client,
		[]byte(`{"action":"turn_credentials_v1"}`),
	)
	if !<-issuer.deadlineSeen {
		t.Fatal("TURN credential handler did not bound issuer work with its fixed deadline")
	}
	if got, want := turnTestJSONKeys(decoded), []string{"errorCode", "status"}; !reflect.DeepEqual(got, want) {
		t.Fatalf("TURN credential timeout keys = %v, want %v", got, want)
	}
	if turnTestJSONText(t, decoded, "status") != "ERROR" ||
		turnTestJSONText(t, decoded, "errorCode") != turnCredentialErrorUnavailable {
		t.Fatal("TURN credential issuer timeout did not return finite unavailable")
	}
}
