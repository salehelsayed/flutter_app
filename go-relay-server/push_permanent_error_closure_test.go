package main

import (
	"bytes"
	"context"
	"fmt"
	"log"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"reflect"
	"regexp"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/messaging"
	"github.com/alicebob/miniredis/v2"
	miniredisserver "github.com/alicebob/miniredis/v2/server"
	"github.com/prometheus/client_golang/prometheus/testutil"
	"google.golang.org/api/option"
)

// syncLogBuffer is a mutex-guarded log sink: dispatched fan-outs log from the
// send goroutine concurrently with the storing goroutine's wake lines.
type syncLogBuffer struct {
	mu sync.Mutex
	b  bytes.Buffer
}

func (s *syncLogBuffer) Write(p []byte) (int, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.b.Write(p)
}

func (s *syncLogBuffer) String() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.b.String()
}

// Plan 320 TC-320-01 — the HEADLINE typed arm. A REAL SDK client pointed at a
// fake FCM (httptest) that answers the v1 error JSON with
// details[].errorCode=UNREGISTERED: the typed predicate must classify it
// permanent — exactly one HTTP hit, token evicted, invalid_token counted,
// reason=typed_unregistered logged. The response message text is deliberately
// opaque (matches NO literal), so this row is also the standing do-not-wrap
// detector: messaging.Is* type-asserts *internal.FirebaseError without
// Unwrap, and one fmt.Errorf("…: %w") in ps.send would fall through to the
// transient ladder and red this row.
func TestRelayNotificationClosure_PermanentTokenErrorEvictsWithoutRetry(t *testing.T) {
	var hits int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		atomic.AddInt32(&hits, 1)
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusNotFound)
		fmt.Fprint(w, `{"error":{"code":404,"status":"NOT_FOUND","message":"opaque provider message","details":[{"@type":"type.googleapis.com/google.firebase.fcm.v1.FcmError","errorCode":"UNREGISTERED"}]}}`)
	}))
	defer srv.Close()

	ctx := context.Background()
	app, err := firebase.NewApp(
		ctx,
		&firebase.Config{ProjectID: "test-project"},
		option.WithEndpoint(srv.URL),
		option.WithoutAuthentication(),
	)
	if err != nil {
		t.Fatalf("firebase app against fake FCM: %v", err)
	}
	client, err := app.Messaging(ctx)
	if err != nil {
		t.Fatalf("messaging client against fake FCM: %v", err)
	}

	tokenStore := newMemoryPushTokenStore()
	push := NewPushServiceWithBackend(tokenStore)
	push.retryDelays = []time.Duration{0, 0}
	push.client = client // real SDK client path; ps.sender stays nil
	tokenStore.RegisterToken("peer-typed-dead", "typed-dead-token", "android")

	journal := &bytes.Buffer{}
	previousWriter := log.Writer()
	log.SetOutput(journal)
	t.Cleanup(func() { log.SetOutput(previousWriter) })

	invalidTokenCounter := pushSentCounter.WithLabelValues("invalid_token")
	before := testutil.ToFloat64(invalidTokenCounter)

	push.SendNotification(ctx, "peer-typed-dead", "peer-sender", `{"id":"msg-typed","text":"hi"}`)

	if got := atomic.LoadInt32(&hits); got != 1 {
		t.Fatalf("fake FCM hits = %d, want exactly 1 (typed permanent error must not retry)", got)
	}
	if tokenStore.LookupToken("peer-typed-dead") != nil {
		t.Fatal("token was not evicted on typed UNREGISTERED")
	}
	if delta := testutil.ToFloat64(invalidTokenCounter) - before; delta != 1 {
		t.Fatalf("invalid_token delta = %v, want 1", delta)
	}
	if got := journal.String(); !strings.Contains(got, "reason=typed_unregistered") {
		t.Fatalf("journal = %q, want reason=typed_unregistered attribution", got)
	}
}

// Plan 320 TC-320-01b — the BLOCKER-1 row. The production journal shows FCM's
// error *message* text ("NotRegistered", and for the same dead peer at another
// time "Requested entity was not found."), which is NOT the SDK errorCode the
// typed predicates read. Without a literal arm the fix ships inert: the legacy
// hyphenated literals match neither string, so a permanent dead-token error
// walks the transient ladder and the token is never evicted.
func TestRelayNotificationClosure_ObservedPermanentTextEvictsWithoutRetry(t *testing.T) {
	for _, observed := range []string{
		"NotRegistered",
		"Requested entity was not found.",
	} {
		tokenStore := newMemoryPushTokenStore()
		push := NewPushServiceWithBackend(tokenStore)
		push.retryDelays = []time.Duration{0, 0}
		recorder := newRecordingPushSender()
		push.sender = recorder.Send
		tokenStore.RegisterToken("peer-dead", "dead-token", "android")
		recorder.onSend = func(ctx context.Context, msg *messaging.Message) (string, error) {
			return "", fmt.Errorf("%s", observed)
		}

		push.SendNotification(
			context.Background(),
			"peer-dead",
			"peer-sender",
			`{"id":"msg-1","text":"hi"}`,
		)

		if got := recorder.SendCallCount(); got != 1 {
			t.Fatalf("observed=%q send calls = %d, want 1 (permanent error must not retry)", observed, got)
		}
		if tokenStore.LookupToken("peer-dead") != nil {
			t.Fatalf("observed=%q token was not evicted", observed)
		}
	}
}

// Plan 320 TC-320-02 — SENDER_ID_MISMATCH is permanent too.
func TestRelayNotificationClosure_SenderIdMismatchIsPermanent(t *testing.T) {
	tokenStore := newMemoryPushTokenStore()
	push := NewPushServiceWithBackend(tokenStore)
	push.retryDelays = []time.Duration{0, 0}
	recorder := newRecordingPushSender()
	push.sender = recorder.Send
	tokenStore.RegisterToken("peer-mismatch", "other-project-token", "android")
	recorder.onSend = func(ctx context.Context, msg *messaging.Message) (string, error) {
		return "", fmt.Errorf("SenderId mismatch")
	}

	push.SendNotification(
		context.Background(),
		"peer-mismatch",
		"peer-sender",
		`{"id":"msg-2","text":"hi"}`,
	)

	if got := recorder.SendCallCount(); got != 1 {
		t.Fatalf("send calls = %d, want 1", got)
	}
	if tokenStore.LookupToken("peer-mismatch") != nil {
		t.Fatal("token was not evicted on sender-id mismatch")
	}
}

// Plan 320 TC-320-03 — transient errors keep the ladder and the token.
// Deliberately on the ps.sender stub seam: the SDK layers its own retry ladder
// under a real client, so a real-client fixture's attempt count would not mean
// what this row asserts.
func TestRelayNotificationClosure_TransientErrorKeepsRetryLadderAndToken(t *testing.T) {
	tokenStore := newMemoryPushTokenStore()
	push := NewPushServiceWithBackend(tokenStore)
	push.retryDelays = []time.Duration{0, 0}
	recorder := newRecordingPushSender()
	push.sender = recorder.Send
	tokenStore.RegisterToken("peer-live", "live-token", "android")
	recorder.onSend = func(ctx context.Context, msg *messaging.Message) (string, error) {
		return "", fmt.Errorf("service unavailable")
	}

	push.SendNotification(
		context.Background(),
		"peer-live",
		"peer-sender",
		`{"id":"msg-3","text":"hi"}`,
	)

	if got := recorder.SendCallCount(); got != 3 {
		t.Fatalf("send calls = %d, want 3 (transient keeps the full ladder)", got)
	}
	if tokenStore.LookupToken("peer-live") == nil {
		t.Fatal("a transient error must never evict a live token")
	}
}

// Plan 320 TC-320-04 — the legacy hyphenated literals still evict.
func TestRelayNotificationClosure_LegacyInvalidTokenLiteralsStillEvict(t *testing.T) {
	for _, legacy := range []string{
		"registration-token-not-registered",
		"invalid-registration-token",
	} {
		tokenStore := newMemoryPushTokenStore()
		push := NewPushServiceWithBackend(tokenStore)
		push.retryDelays = []time.Duration{0, 0}
		recorder := newRecordingPushSender()
		push.sender = recorder.Send
		tokenStore.RegisterToken("peer-legacy", "legacy-token", "ios")
		recorder.onSend = func(ctx context.Context, msg *messaging.Message) (string, error) {
			return "", fmt.Errorf("%s", legacy)
		}

		push.SendNotification(
			context.Background(),
			"peer-legacy",
			"peer-sender",
			`{"id":"msg-4","text":"hi"}`,
		)

		if got := recorder.SendCallCount(); got != 1 {
			t.Fatalf("legacy=%q send calls = %d, want 1", legacy, got)
		}
		if tokenStore.LookupToken("peer-legacy") != nil {
			t.Fatalf("legacy=%q token was not evicted", legacy)
		}
	}
}

func plan368OwnedProviderLogFormats(t *testing.T) map[string]int {
	t.Helper()
	paths, err := filepath.Glob("*.go")
	if err != nil {
		t.Fatalf("glob Go source: %v", err)
	}
	pattern := regexp.MustCompile(
		`log\.(?:Printf|Println)\s*\(\s*"(\[(?:PUSH|REDIS\]\[PUSH|GROUP_REACTION_WAKE)\][^"]*)"`,
	)
	formats := make(map[string]int)
	for _, path := range paths {
		if strings.HasSuffix(path, "_test.go") {
			continue
		}
		raw, readErr := os.ReadFile(path)
		if readErr != nil {
			t.Fatalf("read %s: %v", path, readErr)
		}
		for _, match := range pattern.FindAllStringSubmatch(string(raw), -1) {
			formats[match[1]]++
		}
	}
	return formats
}

// Plan 368 TC-368-05 replaces the old transition-correlation contract. Owned
// provider/wake records are a finite coarse vocabulary; runtime canaries prove
// that peer, route, provider, event, payload, and raw-error values never enter
// either a structured key or formatted message text.
func TestRelayNotificationClosure_ProviderWakeLogsOmitPrivateValues(t *testing.T) {
	wantFormats := map[string]int{
		"[PUSH] outcome=provider_init_failed stage=firebase_app":     1,
		"[PUSH] outcome=provider_init_failed stage=messaging_client": 1,
		"[PUSH] outcome=provider_initialized":                        1,
		"[PUSH] outcome=registered":                                  1,
		"[PUSH] outcome=unregistered":                                1,
		"[PUSH] outcome=opaque_route_invalid":                        1,
		"[PUSH] outcome=unsupported_platform":                        1,
		"[PUSH] outcome=missing_route":                               2,
		"[PUSH] provider unavailable outcome=provider_unavailable":   1,
		"[PUSH] outcome=invalid_payload":                             1,
		"[PUSH] outcome=success attempt=%d total_attempts=%d":        1,
		"[PUSH] outcome=revoke_failed reason=%s":                     2,
		"[PUSH] outcome=invalid_token reason=%s":                     1,
		"[PUSH] outcome=payload_too_large fallback=disabled":         1,
		"[PUSH] outcome=payload_too_large fallback=unavailable":      1,
		"[PUSH] outcome=success fallback=strict":                     1,
		"[PUSH] outcome=invalid_token reason=%s fallback=strict":     1,
		"[PUSH] outcome=fallback_failed fallback=strict":             1,
		"[PUSH] outcome=failed attempts=%d":                          1,
		"[PUSH] outcome=retrying attempt=%d total_attempts=%d":       1,
		"[PUSH] outcome=context_canceled":                            1,
		"[PUSH] outcome=registration_failed":                         1,
		"[PUSH] outcome=unregistration_failed":                       1,
		"[REDIS][PUSH] outcome=count_state_read_failed":              1,
		"[REDIS][PUSH] outcome=count_scan_failed":                    1,
		"[REDIS][PUSH] outcome=platform_count_state_read_failed":     1,
		"[REDIS][PUSH] outcome=platform_count_scan_failed":           1,
		"[GROUP_REACTION_WAKE] outcome=duplicate_suppressed":         1,
		"[GROUP_REACTION_WAKE] outcome=invalid_or_disabled":          1,
		"[GROUP_REACTION_WAKE] outcome=push_unavailable":             1,
		"[GROUP_REACTION_WAKE] outcome=no_wake_recipients":           1,
		"[GROUP_REACTION_WAKE] outcome=incapable_skipped":            1,
		"[GROUP_REACTION_WAKE] outcome=dispatched":                   1,
	}
	gotFormats := plan368OwnedProviderLogFormats(t)
	if !reflect.DeepEqual(gotFormats, wantFormats) {
		t.Fatalf("owned provider log formats:\n got: %#v\nwant: %#v", gotFormats, wantFormats)
	}
	ownedSiteCount := 0
	for _, count := range gotFormats {
		ownedSiteCount += count
	}
	if ownedSiteCount != 35 {
		t.Fatalf("owned provider log sites = %d, want exact 35", ownedSiteCount)
	}

	const (
		peerCanary        = "plan368-log-peer-private-canary"
		senderCanary      = "plan368-log-sender-private-canary"
		tokenCanary       = "plan368-log-provider-token-private-canary"
		platformCanary    = "plan368-log-platform-private-canary"
		payloadCanary     = "plan368-log-ciphertext-private-canary"
		errorCanary       = "plan368-log-provider-error-private-canary"
		revokeErrorCanary = "plan368-log-revoke-error-private-canary"
		groupCanary       = "plan368-log-group-private-canary"
		transitionCanary  = "plan368-log-transition-private-canary"
		groupSender       = "plan368-log-group-sender-private-canary"
		groupAuthor       = "plan368-log-group-author-private-canary"
		credentialClient  = "plan368-log-credential-client-private-canary"
		credentialSecret  = "plan368-log-credential-secret-private-canary"
		credentialRefresh = "plan368-log-credential-refresh-private-canary"
		projectCanary     = "plan368-log-provider-project-private-canary"
	)
	privateValues := []string{
		peerCanary,
		senderCanary,
		tokenCanary,
		platformCanary,
		payloadCanary,
		errorCanary,
		revokeErrorCanary,
		groupCanary,
		transitionCanary,
		groupSender,
		groupAuthor,
		credentialClient,
		credentialSecret,
		credentialRefresh,
		projectCanary,
	}
	journal := &syncLogBuffer{}
	previousWriter := log.Writer()
	previousFlags := log.Flags()
	previousPrefix := log.Prefix()
	log.SetOutput(journal)
	log.SetFlags(0)
	log.SetPrefix("")
	t.Cleanup(func() {
		log.SetOutput(previousWriter)
		log.SetFlags(previousFlags)
		log.SetPrefix(previousPrefix)
	})

	// Drive all three provider-init outcomes. None may echo credential paths,
	// provider configuration, authenticated peers, tokens, or backend errors.
	credentialDir := t.TempDir()
	firebaseAppCredential := filepath.Join(credentialDir, "plan368-log-firebase-app-credential-private-canary.json")
	t.Setenv("FIREBASE_CONFIG", "{"+errorCanary)
	if push := newPushServiceWithTokenBackend(
		context.Background(),
		firebaseAppCredential,
		newMemoryPushTokenStore(),
	); push.client != nil {
		t.Fatal("malformed Firebase config unexpectedly initialized provider")
	}

	messagingCredential := filepath.Join(credentialDir, "plan368-log-messaging-credential-private-canary.json")
	if err := os.WriteFile(messagingCredential, []byte("{"+errorCanary), 0o600); err != nil {
		t.Fatalf("write malformed credential: %v", err)
	}
	t.Setenv("FIREBASE_CONFIG", fmt.Sprintf(`{"projectId":%q}`, projectCanary))
	if push := newPushServiceWithTokenBackend(
		context.Background(),
		messagingCredential,
		newMemoryPushTokenStore(),
	); push.client != nil {
		t.Fatal("malformed credential unexpectedly initialized messaging client")
	}

	validCredential := filepath.Join(credentialDir, "plan368-log-valid-credential-private-canary.json")
	validCredentialJSON := fmt.Sprintf(
		`{"type":"authorized_user","client_id":%q,"client_secret":%q,"refresh_token":%q}`,
		credentialClient,
		credentialSecret,
		credentialRefresh,
	)
	if err := os.WriteFile(validCredential, []byte(validCredentialJSON), 0o600); err != nil {
		t.Fatalf("write valid credential: %v", err)
	}
	initializedPush := newPushServiceWithTokenBackend(
		context.Background(),
		validCredential,
		newMemoryPushTokenStore(),
	)
	if initializedPush.client == nil {
		t.Fatal("valid offline credential did not initialize messaging client")
	}
	privateValues = append(
		privateValues,
		filepath.Base(firebaseAppCredential),
		filepath.Base(messagingCredential),
		filepath.Base(validCredential),
	)

	// Registration success/failure and unregistration success/failure are
	// exercised through both the service and authenticated stream owner.
	registrationStore := newMemoryPushTokenStore()
	registrationPush := NewPushServiceWithBackend(registrationStore)
	if err := registrationPush.RegisterToken(
		peerCanary,
		tokenCanary,
		platformCanary,
		opaqueWakeCapability,
	); err != nil {
		t.Fatalf("RegisterToken(): %v", err)
	}
	if err := registrationPush.UnregisterToken(peerCanary); err != nil {
		t.Fatalf("UnregisterToken(): %v", err)
	}
	registrationPush.SendNotification(
		context.Background(),
		peerCanary,
		senderCanary,
		`{"type":"chat_message","version":"2","id":"plan368-log-missing-private","encrypted":{"kem":"k","ciphertext":"`+payloadCanary+`","nonce":"n"}}`,
	)
	registrationPush.SendGroupNotification(
		context.Background(),
		peerCanary,
		groupCanary,
		groupSender,
		"plan368-log-missing-group-message-private-canary",
		ordinaryGroupCiphertextEnvelope(16),
	)
	privateValues = append(privateValues, "plan368-log-missing-group-message-private-canary")

	failingRegistration := newFailingRegisterPushTokenBackend()
	failingRegistrationInbox := NewInboxStore(NewPushServiceWithBackend(failingRegistration))
	failingRegistrationEnv := setupInboxStreamEnv(
		t,
		failingRegistrationInbox,
		NewGroupInboxStore(500, 0),
	)
	failingRegistrationStream, err := failingRegistrationEnv.sender.NewStream(
		context.Background(),
		failingRegistrationEnv.server.ID(),
		InboxProtocol,
	)
	if err != nil {
		t.Fatalf("open failing registration stream: %v", err)
	}
	sendInboxReq(t, failingRegistrationStream, inboxRequest{
		Action:   "register_token",
		Token:    tokenCanary,
		Platform: platformCanary,
	})
	failingRegistrationResponse := recvInboxResp(t, failingRegistrationStream)
	_ = failingRegistrationStream.Close()
	if failingRegistrationResponse.Status != "ERROR" {
		t.Fatalf("failing registration response = %#v", failingRegistrationResponse)
	}
	privateValues = append(privateValues, failingRegistrationEnv.sender.ID().String())

	unregisterStore := newMemoryPushTokenStore()
	failingUnregister := &plan367UnregisterBackend{
		PushTokenBackend: unregisterStore,
		err:              fmt.Errorf("%s", revokeErrorCanary),
	}
	failingUnregisterInbox := NewInboxStore(NewPushServiceWithBackend(failingUnregister))
	failingUnregisterEnv := setupInboxStreamEnv(t, failingUnregisterInbox, NewGroupInboxStore(500, 0))
	failingUnregisterResponse := plan367UnregisterRequest(t, failingUnregisterEnv)
	if failingUnregisterResponse.Status != "ERROR" {
		t.Fatalf("failing unregistration response = %#v", failingUnregisterResponse)
	}
	privateValues = append(privateValues, failingUnregisterEnv.sender.ID().String())

	// Drive both marker-read and SCAN failures for both Redis count APIs. The
	// scan-only hook leaves marker GET intact so the two failure classes cannot
	// accidentally collapse into the same source site.
	stateFailureRedis := miniredis.RunT(t)
	stateFailureBackend := newRedisPushTokenBackend(
		newTestRedisClient(t, stateFailureRedis),
		"plan368-log-state-private-canary:",
	)
	stateFailureRedis.SetError(errorCanary)
	_ = stateFailureBackend.TokenCount()
	_ = stateFailureBackend.PlatformCounts()
	stateFailureRedis.SetError("")
	privateValues = append(privateValues, "plan368-log-state-private-canary:")

	scanFailureRedis := miniredis.RunT(t)
	scanFailureRedis.Server().SetPreHook(func(peer *miniredisserver.Peer, command string, _ ...string) bool {
		if !strings.EqualFold(command, "scan") {
			return false
		}
		peer.WriteError(errorCanary)
		return true
	})
	scanFailureBackend := newRedisPushTokenBackend(
		newTestRedisClient(t, scanFailureRedis),
		"plan368-log-scan-private-canary:",
	)
	_ = scanFailureBackend.TokenCount()
	_ = scanFailureBackend.PlatformCounts()
	scanFailureRedis.Server().SetPreHook(nil)
	privateValues = append(privateValues, "plan368-log-scan-private-canary:")

	// Empty opaque handles and unsupported platforms fail closed without
	// logging the lease or the private resolved platform.
	emptyStore := newMemoryPushTokenStore()
	if err := emptyStore.RegisterToken(peerCanary, tokenCanary, "android", opaqueWakeCapability); err != nil {
		t.Fatalf("empty fixture RegisterToken(): %v", err)
	}
	emptyRoute := plan367Route(t, emptyStore, peerCanary)
	privateValues = append(privateValues, emptyRoute.Handle)
	emptyRoute.Handle = ""
	emptyProbe := &plan368BackendProbe{
		delegate: emptyStore,
		lookup: func(int, string) (*pushRouteLease, error) {
			copy := copyPushRouteLease(emptyRoute)
			return &copy, nil
		},
	}
	emptyPush := NewPushServiceWithBackend(emptyProbe)
	emptyRecorder := newRecordingPushSender()
	emptyPush.sender = emptyRecorder.Send
	emptyPush.SendNotification(
		context.Background(),
		peerCanary,
		senderCanary,
		ordinaryChatCiphertextEnvelope(8, 16),
	)
	unsupportedStore := newMemoryPushTokenStore()
	if err := unsupportedStore.RegisterToken(
		peerCanary,
		tokenCanary,
		platformCanary,
		opaqueWakeCapability,
	); err != nil {
		t.Fatalf("unsupported fixture RegisterToken(): %v", err)
	}
	unsupportedRoute := plan367Route(t, unsupportedStore, peerCanary)
	privateValues = append(privateValues, unsupportedRoute.Handle)
	unsupportedPush := NewPushServiceWithBackend(unsupportedStore)
	unsupportedRecorder := newRecordingPushSender()
	unsupportedPush.sender = unsupportedRecorder.Send
	unsupportedPush.SendNotification(
		context.Background(),
		peerCanary,
		senderCanary,
		ordinaryChatCiphertextEnvelope(8, 16),
	)

	// Provider-unavailable, nil-payload, success, retry, terminal failure,
	// permanent revoke failure, fixed-size refusal, and cancellation all carry
	// only the fixed outcome/reason/attempt vocabulary.
	unavailableStore := newMemoryPushTokenStore()
	_ = unavailableStore.RegisterToken(peerCanary, tokenCanary, "android", opaqueWakeCapability)
	unavailableRoute := plan367Route(t, unavailableStore, peerCanary)
	privateValues = append(privateValues, unavailableRoute.Handle)
	unavailablePush := NewPushServiceWithBackend(unavailableStore)
	unavailablePush.SendNotification(
		context.Background(),
		peerCanary,
		senderCanary,
		ordinaryChatCiphertextEnvelope(8, 16),
	)

	nilPayloadPush := NewPushServiceWithBackend(newMemoryPushTokenStore())
	nilPayloadRecorder := newRecordingPushSender()
	nilPayloadPush.sender = nilPayloadRecorder.Send
	nilPayloadPush.sendWithRetry(context.Background(), nil, pushRouteLease{}, false)

	successStore := newMemoryPushTokenStore()
	_ = successStore.RegisterToken(peerCanary, tokenCanary, "android", opaqueWakeCapability)
	successRoute := plan367Route(t, successStore, peerCanary)
	privateValues = append(privateValues, successRoute.Handle)
	successPush := NewPushServiceWithBackend(successStore)
	successPush.retryDelays = nil
	successRecorder := newRecordingPushSender()
	successPush.sender = successRecorder.Send
	successPush.SendNotification(
		context.Background(),
		peerCanary,
		senderCanary,
		ordinaryChatCiphertextEnvelope(8, 16),
	)

	transientStore := newMemoryPushTokenStore()
	_ = transientStore.RegisterToken(peerCanary, tokenCanary, "android", opaqueWakeCapability)
	transientRoute := plan367Route(t, transientStore, peerCanary)
	privateValues = append(privateValues, transientRoute.Handle)
	transientPush := NewPushServiceWithBackend(transientStore)
	transientPush.retryDelays = []time.Duration{0}
	transientRecorder := newRecordingPushSender()
	transientRecorder.onSend = func(context.Context, *messaging.Message) (string, error) {
		return "", fmt.Errorf("%s", errorCanary)
	}
	transientPush.sender = transientRecorder.Send
	transientPush.SendNotification(
		context.Background(),
		peerCanary,
		senderCanary,
		ordinaryChatCiphertextEnvelope(8, 16),
	)

	permanentStore := newMemoryPushTokenStore()
	_ = permanentStore.RegisterToken(peerCanary, tokenCanary, "android", opaqueWakeCapability)
	permanentRoute := plan367Route(t, permanentStore, peerCanary)
	privateValues = append(privateValues, permanentRoute.Handle)
	permanentProbe := &plan368BackendProbe{
		delegate: permanentStore,
		revoke: func(int, pushRouteLease) (bool, error) {
			return false, fmt.Errorf("%s", revokeErrorCanary)
		},
	}
	permanentPush := NewPushServiceWithBackend(permanentProbe)
	permanentPush.retryDelays = nil
	permanentRecorder := newRecordingPushSender()
	permanentRecorder.onSend = func(context.Context, *messaging.Message) (string, error) {
		return "", fmt.Errorf("registration-token-not-registered")
	}
	permanentPush.sender = permanentRecorder.Send
	permanentPush.SendNotification(
		context.Background(),
		peerCanary,
		senderCanary,
		ordinaryChatCiphertextEnvelope(8, 16),
	)

	sizeStore := newMemoryPushTokenStore()
	_ = sizeStore.RegisterToken(peerCanary, tokenCanary, "android", opaqueWakeCapability)
	sizeRoute := plan367Route(t, sizeStore, peerCanary)
	privateValues = append(privateValues, sizeRoute.Handle)
	sizePush := NewPushServiceWithBackend(sizeStore)
	sizeRecorder := newRecordingPushSender()
	sizeRecorder.onSend = func(context.Context, *messaging.Message) (string, error) {
		return "", fmt.Errorf("Message is too large: %s", errorCanary)
	}
	sizePush.sender = sizeRecorder.Send
	sizePush.SendNotification(
		context.Background(),
		peerCanary,
		senderCanary,
		ordinaryChatCiphertextEnvelope(8, 16),
	)

	// Drive every strict legacy fallback terminal: unavailable, success,
	// permanent+revoke-failed, and generic failure. Raw provider/backend errors
	// must never replace the finite fallback and reason vocabulary.
	strictUnavailablePush := NewPushServiceWithBackend(newMemoryPushTokenStore())
	strictUnavailablePush.retryDelays = nil
	strictUnavailableRecorder := newRecordingPushSender()
	strictUnavailableRecorder.onSend = func(context.Context, *messaging.Message) (string, error) {
		return "", fmt.Errorf("Message is too large: %s", errorCanary)
	}
	strictUnavailablePush.sender = strictUnavailableRecorder.Send
	strictUnavailablePush.sendWithRetry(
		context.Background(),
		&messaging.Message{Token: tokenCanary},
		pushRouteLease{},
		true,
	)
	if strictUnavailableRecorder.SendCallCount() != 1 {
		t.Fatalf("strict unavailable sends = %d, want one", strictUnavailableRecorder.SendCallCount())
	}

	strictSuccessStore := newMemoryPushTokenStore()
	_ = strictSuccessStore.RegisterToken(peerCanary, tokenCanary, "android")
	strictSuccessRoute := plan367Route(t, strictSuccessStore, peerCanary)
	privateValues = append(privateValues, strictSuccessRoute.Handle)
	strictSuccessPush := NewPushServiceWithBackend(strictSuccessStore)
	strictSuccessPush.retryDelays = nil
	strictSuccessRecorder := newRecordingPushSender()
	strictSuccessRecorder.onSend = func(context.Context, *messaging.Message) (string, error) {
		if strictSuccessRecorder.SendCallCount() == 1 {
			return "", fmt.Errorf("Message is too large: %s", errorCanary)
		}
		return "plan368-log-strict-success-private-canary", nil
	}
	strictSuccessPush.sender = strictSuccessRecorder.Send
	strictSuccessPush.SendNotification(
		context.Background(),
		peerCanary,
		senderCanary,
		ordinaryChatCiphertextEnvelope(8, 16),
	)
	if strictSuccessRecorder.SendCallCount() != 2 {
		t.Fatalf("strict success sends = %d, want original plus fallback", strictSuccessRecorder.SendCallCount())
	}
	privateValues = append(privateValues, "plan368-log-strict-success-private-canary")

	strictPermanentStore := newMemoryPushTokenStore()
	_ = strictPermanentStore.RegisterToken(peerCanary, tokenCanary, "android")
	strictPermanentRoute := plan367Route(t, strictPermanentStore, peerCanary)
	strictPermanentProbe := &plan368BackendProbe{
		delegate: strictPermanentStore,
		revoke: func(int, pushRouteLease) (bool, error) {
			return false, fmt.Errorf("%s", revokeErrorCanary)
		},
	}
	privateValues = append(privateValues, strictPermanentRoute.Handle)
	strictPermanentPush := NewPushServiceWithBackend(strictPermanentProbe)
	strictPermanentPush.retryDelays = nil
	strictPermanentRecorder := newRecordingPushSender()
	strictPermanentRecorder.onSend = func(context.Context, *messaging.Message) (string, error) {
		if strictPermanentRecorder.SendCallCount() == 1 {
			return "", fmt.Errorf("Message is too large: %s", errorCanary)
		}
		return "", fmt.Errorf("registration-token-not-registered: %s", errorCanary)
	}
	strictPermanentPush.sender = strictPermanentRecorder.Send
	strictPermanentPush.SendNotification(
		context.Background(),
		peerCanary,
		senderCanary,
		ordinaryChatCiphertextEnvelope(8, 16),
	)
	if strictPermanentRecorder.SendCallCount() != 2 {
		t.Fatalf("strict permanent sends = %d, want original plus fallback", strictPermanentRecorder.SendCallCount())
	}
	plan368AssertCalls(t, strictPermanentProbe, 1, 1, 1)

	strictFailureStore := newMemoryPushTokenStore()
	_ = strictFailureStore.RegisterToken(peerCanary, tokenCanary, "android")
	strictFailureRoute := plan367Route(t, strictFailureStore, peerCanary)
	privateValues = append(privateValues, strictFailureRoute.Handle)
	strictFailurePush := NewPushServiceWithBackend(strictFailureStore)
	strictFailurePush.retryDelays = nil
	strictFailureRecorder := newRecordingPushSender()
	strictFailureRecorder.onSend = func(context.Context, *messaging.Message) (string, error) {
		if strictFailureRecorder.SendCallCount() == 1 {
			return "", fmt.Errorf("Message is too large: %s", errorCanary)
		}
		return "", fmt.Errorf("%s", errorCanary)
	}
	strictFailurePush.sender = strictFailureRecorder.Send
	strictFailurePush.SendNotification(
		context.Background(),
		peerCanary,
		senderCanary,
		ordinaryChatCiphertextEnvelope(8, 16),
	)
	if strictFailureRecorder.SendCallCount() != 2 {
		t.Fatalf("strict generic failure sends = %d, want original plus fallback", strictFailureRecorder.SendCallCount())
	}

	canceledStore := newMemoryPushTokenStore()
	_ = canceledStore.RegisterToken(peerCanary, tokenCanary, "android", opaqueWakeCapability)
	canceledRoute := plan367Route(t, canceledStore, peerCanary)
	privateValues = append(privateValues, canceledRoute.Handle)
	canceledPush := NewPushServiceWithBackend(canceledStore)
	canceledPush.retryDelays = []time.Duration{time.Hour}
	canceledRecorder := newRecordingPushSender()
	canceledRecorder.onSend = func(context.Context, *messaging.Message) (string, error) {
		return "", fmt.Errorf("%s", errorCanary)
	}
	canceledPush.sender = canceledRecorder.Send
	canceledContext, cancel := context.WithCancel(context.Background())
	cancel()
	canceledPush.SendNotification(
		canceledContext,
		peerCanary,
		senderCanary,
		ordinaryChatCiphertextEnvelope(8, 16),
	)

	// Drive every group-reaction wake outcome with the same private group,
	// participant, transition, and ciphertext canaries. The old contradictory
	// test would fail this exact runtime assertion on dispatched/duplicate.
	fixture := newSignedGroupReactionFixture(
		t,
		groupCanary,
		"plan368-log-reactor-account-private-canary",
		groupSender,
	)
	privateValues = append(privateValues, "plan368-log-reactor-account-private-canary")
	buildEnvelope := func(eventID, action string, nominated []string) string {
		t.Helper()
		return fixture.envelope(
			t,
			eventID,
			action,
			"state-"+eventID,
			"target-"+eventID,
			[]string{groupAuthor},
			nominated,
		)
	}

	disabledStore := NewGroupInboxStore(500, 7*24*time.Hour)
	if err := disabledStore.StoreWithPushRecipients(
		groupCanary,
		groupSender,
		buildEnvelope("plan368-log-disabled-transition-private-canary", "add", []string{groupAuthor}),
		[]string{groupAuthor},
	); err != nil {
		t.Fatalf("disabled group StoreWithPushRecipients(): %v", err)
	}
	privateValues = append(privateValues, "plan368-log-disabled-transition-private-canary")

	pushUnavailableStore := NewGroupInboxStore(500, 7*24*time.Hour)
	pushUnavailableStore.SetGroupReactionPushEnabled(true)
	if err := pushUnavailableStore.StoreWithPushRecipients(
		groupCanary,
		groupSender,
		buildEnvelope("plan368-log-unavailable-transition-private-canary", "add", []string{groupAuthor}),
		[]string{groupAuthor},
	); err != nil {
		t.Fatalf("push-unavailable group StoreWithPushRecipients(): %v", err)
	}
	privateValues = append(privateValues, "plan368-log-unavailable-transition-private-canary")

	groupTokens := newMemoryPushTokenStore()
	_ = groupTokens.RegisterToken(groupAuthor, tokenCanary, "android", groupReactionCapability, opaqueWakeCapability)
	groupRoute := plan367Route(t, groupTokens, groupAuthor)
	privateValues = append(privateValues, groupRoute.Handle)
	groupPush := NewPushServiceWithBackend(groupTokens)
	groupRecorder := newRecordingPushSender()
	groupPush.sender = groupRecorder.Send

	emptyNominationStore := NewGroupInboxStore(500, 7*24*time.Hour)
	emptyNominationStore.SetPush(groupPush)
	emptyNominationStore.SetGroupReactionPushEnabled(true)
	if err := emptyNominationStore.StoreWithPushRecipients(
		groupCanary,
		groupSender,
		buildEnvelope("plan368-log-empty-transition-private-canary", "add", nil),
		[]string{groupAuthor},
	); err != nil {
		t.Fatalf("empty-nomination StoreWithPushRecipients(): %v", err)
	}
	privateValues = append(privateValues, "plan368-log-empty-transition-private-canary")

	incapableTokens := newMemoryPushTokenStore()
	_ = incapableTokens.RegisterToken(groupAuthor, tokenCanary, "android", opaqueWakeCapability)
	incapableRoute := plan367Route(t, incapableTokens, groupAuthor)
	privateValues = append(privateValues, incapableRoute.Handle)
	incapablePush := NewPushServiceWithBackend(incapableTokens)
	incapableRecorder := newRecordingPushSender()
	incapablePush.sender = incapableRecorder.Send
	incapableStore := NewGroupInboxStore(500, 7*24*time.Hour)
	incapableStore.SetPush(incapablePush)
	incapableStore.SetGroupReactionPushEnabled(true)
	if err := incapableStore.StoreWithPushRecipients(
		groupCanary,
		groupSender,
		buildEnvelope("plan368-log-incapable-transition-private-canary", "add", []string{groupAuthor}),
		[]string{groupAuthor},
	); err != nil {
		t.Fatalf("incapable StoreWithPushRecipients(): %v", err)
	}
	privateValues = append(privateValues, "plan368-log-incapable-transition-private-canary")

	dispatchedStore := NewGroupInboxStore(500, 7*24*time.Hour)
	dispatchedStore.SetPush(groupPush)
	dispatchedStore.SetGroupReactionPushEnabled(true)
	dispatchedEnvelope := buildEnvelope(transitionCanary, "add", []string{groupAuthor})
	if !strings.Contains(dispatchedEnvelope, "ciphertext-"+transitionCanary) {
		t.Fatal("group fixture lost ciphertext canary premise")
	}
	privateValues = append(privateValues, "ciphertext-"+transitionCanary)
	if err := dispatchedStore.StoreWithPushRecipients(
		groupCanary,
		groupSender,
		dispatchedEnvelope,
		[]string{groupAuthor},
	); err != nil {
		t.Fatalf("dispatched StoreWithPushRecipients(): %v", err)
	}
	waitForGroupReactionPushes(t, groupRecorder, 1)
	if err := dispatchedStore.StoreWithPushRecipients(
		groupCanary,
		groupSender,
		dispatchedEnvelope,
		[]string{groupAuthor},
	); err != nil {
		t.Fatalf("duplicate StoreWithPushRecipients(): %v", err)
	}

	ownedJournal := make([]string, 0)
	for _, line := range strings.Split(journal.String(), "\n") {
		if strings.Contains(line, "[PUSH]") || strings.Contains(line, "[REDIS][PUSH]") ||
			strings.Contains(line, "[GROUP_REACTION_WAKE]") {
			ownedJournal = append(ownedJournal, line)
		}
	}
	if len(ownedJournal) == 0 {
		t.Fatal("owned provider journal is empty")
	}
	joined := strings.Join(ownedJournal, "\n")
	for _, outcome := range []string{
		"outcome=registered",
		"outcome=unregistered",
		"outcome=opaque_route_invalid",
		"outcome=unsupported_platform",
		"outcome=provider_unavailable",
		"outcome=invalid_payload",
		"outcome=success",
		"outcome=retrying",
		"outcome=failed",
		"outcome=revoke_failed",
		"outcome=invalid_token",
		"outcome=payload_too_large",
		"outcome=context_canceled",
		"outcome=invalid_or_disabled",
		"outcome=push_unavailable",
		"outcome=no_wake_recipients",
		"outcome=incapable_skipped",
		"outcome=dispatched",
		"outcome=duplicate_suppressed",
	} {
		if !strings.Contains(joined, outcome) {
			t.Fatalf("owned journal missing exercised %q outcome:\n%s", outcome, joined)
		}
	}
	for _, record := range []string{
		"[PUSH] outcome=provider_init_failed stage=firebase_app",
		"[PUSH] outcome=provider_init_failed stage=messaging_client",
		"[PUSH] outcome=provider_initialized",
		"[PUSH] outcome=registration_failed",
		"[PUSH] outcome=unregistration_failed",
		"[REDIS][PUSH] outcome=count_state_read_failed",
		"[REDIS][PUSH] outcome=count_scan_failed",
		"[REDIS][PUSH] outcome=platform_count_state_read_failed",
		"[REDIS][PUSH] outcome=platform_count_scan_failed",
		"[PUSH] outcome=payload_too_large fallback=unavailable",
		"[PUSH] outcome=success fallback=strict",
		"[PUSH] outcome=invalid_token reason=literal_legacy_not_registered fallback=strict",
		"[PUSH] outcome=fallback_failed fallback=strict",
	} {
		if !strings.Contains(joined, record) {
			t.Fatalf("owned journal missing exact exercised record %q:\n%s", record, joined)
		}
	}
	if got := strings.Count(joined, "[PUSH] outcome=missing_route"); got != 2 {
		t.Fatalf("runtime missing-route records = %d, want both direct and group source sites:\n%s", got, joined)
	}
	if got := strings.Count(joined, "[PUSH] outcome=revoke_failed reason=literal_legacy_not_registered"); got != 2 {
		t.Fatalf("runtime revoke-failed records = %d, want primary and strict source sites:\n%s", got, joined)
	}
	if got := strings.Count(joined, "[PUSH] outcome=fallback_failed fallback=strict"); got != 2 {
		t.Fatalf("runtime strict fallback-failed records = %d, want permanent and generic outcomes:\n%s", got, joined)
	}
	for _, privateValue := range privateValues {
		if privateValue != "" && strings.Contains(joined, privateValue) {
			t.Fatalf("owned provider journal leaked private value %q:\n%s", privateValue, joined)
		}
	}
	for _, forbiddenField := range []string{
		"peer=",
		"sender=",
		"recipient=",
		"group=",
		"conversation=",
		"message=",
		"event=",
		"transition=",
		"reaction=",
		"handle=",
		"token=",
		"platform=",
		"payload=",
		"ciphertext=",
		"error=",
	} {
		if strings.Contains(joined, forbiddenField) {
			t.Fatalf("owned provider journal contains forbidden field %q:\n%s", forbiddenField, joined)
		}
	}
}

// Plan 320 TC-320-06 (P3) — all THREE formerly-silent decline paths emit
// counted outcomes, and for one transition the emitted outcome count equals
// len(notificationRecipientTransportPeerIds) — the accounting identity the
// uncounted in-loop self-skip used to break.
func TestRelayNotificationClosure_SilentWakeGuardsAreCounted(t *testing.T) {
	const from = "reactor-transport"

	journal := &syncLogBuffer{}
	previousWriter := log.Writer()
	log.SetOutput(journal)
	t.Cleanup(func() { log.SetOutput(previousWriter) })

	// (a) recognized-but-disabled: the flag is default-off (TC-320-11), so a
	// valid add reaction hits the invalid_or_disabled guard.
	flagOffGroup := "group-wake-flag-off"
	flagOffFixture := newSignedGroupReactionFixture(t, flagOffGroup, "reactor-account", from)
	flagOffStore := NewGroupInboxStore(500, 7*24*time.Hour)
	invalidOrDisabled := groupReactionWakeCounter.WithLabelValues("invalid_or_disabled")
	beforeInvalid := testutil.ToFloat64(invalidOrDisabled)
	flagOffEnvelope := flagOffFixture.envelope(
		t,
		"flag-off-transition",
		"add",
		"flag-off-state",
		"target-message",
		[]string{"author-transport"},
		[]string{"author-transport"},
	)
	if err := flagOffStore.StoreWithPushRecipients(
		flagOffGroup, from, flagOffEnvelope, []string{"author-transport"},
	); err != nil {
		t.Fatalf("store flag-off reaction: %v", err)
	}
	if delta := testutil.ToFloat64(invalidOrDisabled) - beforeInvalid; delta != 1 {
		t.Fatalf("invalid_or_disabled delta = %v, want 1", delta)
	}
	if !strings.Contains(journal.String(), "outcome=invalid_or_disabled") {
		t.Fatalf("journal = %q, want invalid_or_disabled line", journal.String())
	}

	// (b) push-service-nil: flag on, no push service wired.
	nilPushGroup := "group-wake-nil-push"
	nilPushFixture := newSignedGroupReactionFixture(t, nilPushGroup, "reactor-account", from)
	nilPushStore := NewGroupInboxStore(500, 7*24*time.Hour)
	nilPushStore.SetGroupReactionPushEnabled(true)
	pushUnavailable := groupReactionWakeCounter.WithLabelValues("push_unavailable")
	beforeUnavailable := testutil.ToFloat64(pushUnavailable)
	nilPushEnvelope := nilPushFixture.envelope(
		t,
		"nil-push-transition",
		"add",
		"nil-push-state",
		"target-message",
		[]string{"author-transport"},
		[]string{"author-transport"},
	)
	if err := nilPushStore.StoreWithPushRecipients(
		nilPushGroup, from, nilPushEnvelope, []string{"author-transport"},
	); err != nil {
		t.Fatalf("store nil-push reaction: %v", err)
	}
	if delta := testutil.ToFloat64(pushUnavailable) - beforeUnavailable; delta != 1 {
		t.Fatalf("push_unavailable delta = %v, want 1", delta)
	}
	if !strings.Contains(journal.String(), "outcome=push_unavailable") {
		t.Fatalf("journal = %q, want push_unavailable line", journal.String())
	}

	// (c) the in-loop self-skip, plus the accounting identity: a nomination of
	// [capable, incapable, self] must emit exactly three counted outcomes.
	const (
		capable   = "author-capable-transport"
		incapable = "author-incapable-transport"
	)
	identityGroup := "group-wake-identity"
	identityFixture := newSignedGroupReactionFixture(t, identityGroup, "reactor-account", from)
	tokens := newMemoryPushTokenStore()
	tokens.RegisterToken(capable, "capable-token", "android", groupReactionCapability)
	tokens.RegisterToken(incapable, "incapable-token", "android", directReactionCapability)
	push := NewPushServiceWithBackend(tokens)
	recorder := newRecordingPushSender()
	push.sender = recorder.Send
	identityStore := NewGroupInboxStore(500, 7*24*time.Hour)
	identityStore.SetPush(push)
	identityStore.SetGroupReactionPushEnabled(true)

	nominations := []string{capable, incapable, from}
	selfSkipped := groupReactionWakeCounter.WithLabelValues("self_or_empty_skipped")
	incapableSkipped := groupReactionWakeCounter.WithLabelValues("incapable_skipped")
	attempted := groupReactionWakeCounter.WithLabelValues("attempted")
	beforeSelf := testutil.ToFloat64(selfSkipped)
	beforeIncapable := testutil.ToFloat64(incapableSkipped)
	beforeAttempted := testutil.ToFloat64(attempted)

	identityEnvelope := identityFixture.envelope(
		t,
		"identity-transition",
		"add",
		"identity-state",
		"target-message",
		nominations,
		nominations,
	)
	if err := identityStore.StoreWithPushRecipients(
		identityGroup, from, identityEnvelope, nominations,
	); err != nil {
		t.Fatalf("store identity reaction: %v", err)
	}
	waitForGroupReactionPushes(t, recorder, 1)

	selfDelta := testutil.ToFloat64(selfSkipped) - beforeSelf
	incapableDelta := testutil.ToFloat64(incapableSkipped) - beforeIncapable
	attemptedDelta := testutil.ToFloat64(attempted) - beforeAttempted
	if selfDelta != 1 {
		t.Fatalf("self_or_empty_skipped delta = %v, want 1", selfDelta)
	}
	if incapableDelta != 1 {
		t.Fatalf("incapable_skipped delta = %v, want 1", incapableDelta)
	}
	if attemptedDelta != 1 {
		t.Fatalf("attempted delta = %v, want 1", attemptedDelta)
	}
	if emitted := selfDelta + incapableDelta + attemptedDelta; emitted != float64(len(nominations)) {
		t.Fatalf("accounting identity broken: emitted outcomes = %v, want %d", emitted, len(nominations))
	}
}

// Plan 320 TC-320-07 — the wake counter label set stays backward compatible:
// the pre-dispatch LOG token became "dispatched", but the counter label must
// remain "attempted" (dashboards read it), and the legacy outcome series stay
// addressable.
func TestRelayNotificationClosure_WakeOutcomeLabelsRemainCompatible(t *testing.T) {
	for _, outcome := range []string{
		"attempted", "duplicate_suppressed", "no_wake_recipients", "incapable_skipped",
	} {
		if got := testutil.ToFloat64(groupReactionWakeCounter.WithLabelValues(outcome)); got < 0 {
			t.Fatalf("legacy outcome %q not addressable", outcome)
		}
	}

	const (
		groupID = "group-wake-label-compat"
		from    = "reactor-transport"
		author  = "author-labels-transport"
	)
	fixture := newSignedGroupReactionFixture(t, groupID, "reactor-account", from)
	tokens := newMemoryPushTokenStore()
	tokens.RegisterToken(author, "author-token", "android", groupReactionCapability)
	push := NewPushServiceWithBackend(tokens)
	recorder := newRecordingPushSender()
	push.sender = recorder.Send
	store := NewGroupInboxStore(500, 7*24*time.Hour)
	store.SetPush(push)
	store.SetGroupReactionPushEnabled(true)

	attempted := groupReactionWakeCounter.WithLabelValues("attempted")
	renamed := groupReactionWakeCounter.WithLabelValues("dispatched")
	beforeAttempted := testutil.ToFloat64(attempted)
	beforeRenamed := testutil.ToFloat64(renamed)

	envelope := fixture.envelope(
		t,
		"label-compat-transition",
		"add",
		"label-compat-state",
		"target-message",
		[]string{author},
		[]string{author},
	)
	if err := store.StoreWithPushRecipients(groupID, from, envelope, []string{author}); err != nil {
		t.Fatalf("store reaction: %v", err)
	}
	waitForGroupReactionPushes(t, recorder, 1)

	if delta := testutil.ToFloat64(attempted) - beforeAttempted; delta != 1 {
		t.Fatalf("attempted delta = %v, want 1 (dashboard label must survive the log-token rename)", delta)
	}
	if delta := testutil.ToFloat64(renamed) - beforeRenamed; delta != 0 {
		t.Fatalf("a 'dispatched' counter series incremented (%v) — the rename must stay log-only", delta)
	}
}
