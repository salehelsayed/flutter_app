//go:build integration

package main

import (
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha1" //nolint:gosec // coturn REST authentication mandates HMAC-SHA1.
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/core/protocol"
	relayv2 "github.com/libp2p/go-libp2p/p2p/protocol/circuitv2/relay"
	ma "github.com/multiformats/go-multiaddr"
	"github.com/prometheus/client_golang/prometheus/testutil"
)

const (
	directMediaDeviceFixtureProcessMode = "MKNOON_DIRECT_MEDIA_DEVICE_FIXTURE_PROCESS"
	directMediaDeviceFixtureHostIP      = "MKNOON_DIRECT_MEDIA_DEVICE_FIXTURE_HOST_IP"
	directMediaDeviceFixtureReadyPrefix = "MKNOON_DIRECT_MEDIA_FIXTURE_READY="
	plan393FixedWakeFixtureMode         = "MKNOON_PLAN393_FIXED_WAKE_FIXTURE"
	plan393FixtureSnapshotKind          = "plan393_relay_snapshot"
)

type directMediaDeviceFixtureReady struct {
	Schema                        string `json:"schema"`
	Multiaddr                     string `json:"multiaddr"`
	ProbeURL                      string `json:"probeUrl"`
	FixtureIdentitySHA256         string `json:"fixtureIdentitySha256"`
	Backend                       string `json:"backend"`
	Ephemeral                     bool   `json:"ephemeral"`
	AckCustodyAdmissionEnabled    bool   `json:"ackCustodyAdmissionEnabled"`
	MediaCustodyAdmissionEnabled  bool   `json:"mediaCustodyAdmissionEnabled"`
	FixedWakeRecovery             bool   `json:"fixedWakeRecovery"`
	PushTokenState                string `json:"pushTokenState"`
	WakeOutcomeAdmissionEnabled   bool   `json:"wakeOutcomeAdmissionEnabled"`
	WakeOutcomeCoordinatorStarted bool   `json:"wakeOutcomeCoordinatorStarted"`
	DirectReactionPushEnabled     bool   `json:"directReactionPushEnabled"`
	RealFCMConfigured             bool   `json:"realFcmConfigured"`
	RelayVersion                  string `json:"relayVersion"`
	RelayBinarySHA256             string `json:"relayBinarySha256"`
}

type directMediaDeviceFixtureOptions struct {
	fixedWakeRecovery  bool
	serviceAccountPath string
}

type directMediaFixtureLogEntry struct {
	at   time.Time
	line string
}

type directMediaFixtureLogBuffer struct {
	mu      sync.Mutex
	entries []directMediaFixtureLogEntry
}

func (buffer *directMediaFixtureLogBuffer) Write(payload []byte) (int, error) {
	buffer.mu.Lock()
	defer buffer.mu.Unlock()
	now := time.Now().UTC()
	for _, line := range strings.Split(strings.TrimRight(string(payload), "\n"), "\n") {
		if line != "" {
			buffer.entries = append(buffer.entries, directMediaFixtureLogEntry{at: now, line: line})
		}
	}
	return len(payload), nil
}

func (buffer *directMediaFixtureLogBuffer) Since(since time.Time) string {
	buffer.mu.Lock()
	defer buffer.mu.Unlock()
	lines := make([]string, 0, len(buffer.entries))
	for _, entry := range buffer.entries {
		if !entry.at.Before(since) {
			lines = append(lines, entry.line)
		}
	}
	return strings.Join(lines, "\n")
}

type directMediaDeviceFixture struct {
	root                string
	host                host.Host
	stores              *controlPlaneStores
	media               *MediaStore
	redis               *miniredis.Miniredis
	probe               *http.Server
	probeLn             net.Listener
	cancel              context.CancelFunc
	ready               directMediaDeviceFixtureReady
	stop                chan struct{}
	stopOnce            sync.Once
	closeOnce           sync.Once
	closeErr            error
	startedAt           time.Time
	logs                *directMediaFixtureLogBuffer
	priorLogWriter      io.Writer
	environmentRestores []func()
}

// TestDirectMediaBlobCustodyDeviceFixtureContract owns two modes. A normal
// focused go test starts the complete fixture, dials all three production
// protocol handlers, and proves deterministic teardown. The Dart adapter
// starts the same test in process mode, consumes the single readiness record,
// runs its centrally built Android campaign, then posts to the capability-bound
// probe URL to stop the fixture.
func TestDirectMediaBlobCustodyDeviceFixtureContract(t *testing.T) {
	if os.Getenv(directMediaDeviceFixtureProcessMode) == "1" {
		runDirectMediaDeviceFixtureProcess(t)
		return
	}

	t.Setenv(ackCustodyAdmissionEnabledEnv, "true")
	t.Setenv(mediaCustodyAdmissionEnabledEnv, "true")
	root, err := os.MkdirTemp("", "mknoon-plan347-fixture-contract-")
	if err != nil {
		t.Fatalf("create fixture root: %v", err)
	}
	fixture, err := startDirectMediaDeviceFixture(
		root,
		"127.0.0.1",
		directMediaDeviceFixtureOptions{},
	)
	if err != nil {
		_ = os.RemoveAll(root)
		t.Fatalf("start fixture: %v", err)
	}

	if fixture.ready.Backend != backendKindRedis || !fixture.ready.Ephemeral {
		t.Fatalf("fixture backend attestation = %#v", fixture.ready)
	}
	if !fixture.stores.Inbox.AckCustodyAdmissionEnabled() ||
		!fixture.media.DirectMediaBlobCustodyAdmissionEnabled() {
		t.Fatal("fixture did not enable both default-off custody admissions")
	}
	if _, ok := fixture.stores.InboxBackend.(*redisInboxBackend); !ok {
		t.Fatalf("fixture inbox backend = %T, want production Redis backend", fixture.stores.InboxBackend)
	}
	if filepath.Clean(fixture.media.dataDir) != filepath.Join(root, "media") {
		t.Fatalf("fixture media root escaped disposable root: %s", fixture.media.dataDir)
	}
	if len(fixture.ready.FixtureIdentitySHA256) != sha256.Size*2 {
		t.Fatalf("fixture identity digest = %q", fixture.ready.FixtureIdentitySHA256)
	}
	assertDirectMediaFixtureProbe(t, fixture.ready.ProbeURL, "not-stored", 0)

	assertDirectMediaFixtureHandlersReachable(t, fixture.ready.Multiaddr)
	assertDirectMediaFixtureShutdown(t, fixture)
	if err := fixture.Close(); err != nil {
		t.Fatalf("fixture teardown: %v", err)
	}
	if _, err := os.Stat(root); !os.IsNotExist(err) {
		t.Fatalf("disposable fixture root survived teardown: %v", err)
	}

	plan393Root, err := os.MkdirTemp("", "mknoon-plan393-fixture-contract-")
	if err != nil {
		t.Fatalf("create Plan 393 fixture root: %v", err)
	}
	serviceAccountPath := filepath.Join(plan393Root, "fixture-service-account.json")
	if err := os.WriteFile(serviceAccountPath, []byte(`{"type":"service_account"}`), 0o600); err != nil {
		_ = os.RemoveAll(plan393Root)
		t.Fatalf("write Plan 393 fixture credential: %v", err)
	}
	plan393Fixture, err := startDirectMediaDeviceFixture(
		plan393Root,
		"127.0.0.1",
		directMediaDeviceFixtureOptions{
			fixedWakeRecovery:  true,
			serviceAccountPath: serviceAccountPath,
		},
	)
	if err != nil {
		_ = os.RemoveAll(plan393Root)
		t.Fatalf("start Plan 393 fixture: %v", err)
	}
	if !plan393Fixture.ready.FixedWakeRecovery ||
		plan393Fixture.ready.PushTokenState != string(pushTokenStateEncrypted) ||
		!plan393Fixture.ready.WakeOutcomeAdmissionEnabled ||
		!plan393Fixture.ready.WakeOutcomeCoordinatorStarted ||
		!plan393Fixture.ready.DirectReactionPushEnabled ||
		!plan393Fixture.ready.RealFCMConfigured ||
		len(plan393Fixture.ready.RelayBinarySHA256) != sha256.Size*2 {
		t.Fatalf("Plan 393 fixture attestation = %#v", plan393Fixture.ready)
	}
	assertPlan393RelayFixtureSnapshot(t, plan393Fixture)
	if err := plan393Fixture.Close(); err != nil {
		t.Fatalf("Plan 393 fixture teardown: %v", err)
	}
	if _, err := os.Stat(plan393Root); !os.IsNotExist(err) {
		t.Fatalf("Plan 393 fixture root survived teardown: %v", err)
	}
}

func TestDirectMediaBlobCustodyDeviceFixtureConfiguredTurnCredentialsUseProductionHandlers(t *testing.T) {
	t.Setenv(ackCustodyAdmissionEnabledEnv, "true")
	t.Setenv(mediaCustodyAdmissionEnabledEnv, "true")
	t.Setenv(turnCredentialsEnabledEnv, "true")
	staticSecret := []byte("plan399-local-turn-secret-marker")
	t.Setenv(
		turnCredentialsURLsEnv,
		"turn:192.168.0.60:3478?transport=udp",
	)
	t.Setenv(
		turnCredentialsPrimarySecretEnv,
		base64.StdEncoding.EncodeToString(staticSecret),
	)

	root, err := os.MkdirTemp("", "mknoon-plan399-turn-fixture-")
	if err != nil {
		t.Fatalf("create fixture root: %v", err)
	}
	fixture, err := startDirectMediaDeviceFixture(
		root,
		"127.0.0.1",
		directMediaDeviceFixtureOptions{},
	)
	if err != nil {
		_ = os.RemoveAll(root)
		t.Fatalf("start fixture: %v", err)
	}
	defer func() {
		if err := fixture.Close(); err != nil {
			t.Errorf("fixture teardown: %v", err)
		}
	}()

	response := requestDirectMediaFixtureTurnCredentials(t, fixture.ready.Multiaddr)
	if response["status"] != "OK" ||
		response["schema"] != turnCredentialSchema ||
		response["version"] != float64(turnCredentialVersion) {
		t.Fatal("configured fixture TURN response status/schema/version changed")
	}
	urls, ok := response["urls"].([]any)
	if !ok || len(urls) != 1 || urls[0] != "turn:192.168.0.60:3478?transport=udp" {
		t.Fatalf("configured fixture TURN URLs = %#v", response["urls"])
	}
	for _, forbidden := range []string{
		"secret",
		"sharedSecret",
		"peerId",
		"subject",
		"callId",
	} {
		if _, exists := response[forbidden]; exists {
			t.Fatalf("configured fixture disclosed forbidden %s", forbidden)
		}
	}
	username, usernameOK := response["username"].(string)
	password, passwordOK := response["password"].(string)
	if !usernameOK || username == "" || !passwordOK || password == "" {
		t.Fatal("configured fixture TURN response omitted ephemeral credentials")
	}
	mac := hmac.New(sha1.New, staticSecret)
	_, _ = mac.Write([]byte(username))
	expectedPassword := base64.StdEncoding.EncodeToString(mac.Sum(nil))
	if !hmac.Equal([]byte(password), []byte(expectedPassword)) {
		t.Fatal("fixture TURN response was not minted by the configured secret")
	}
	encodedResponse, err := json.Marshal(response)
	if err != nil {
		t.Fatalf("encode configured fixture TURN response: %v", err)
	}
	captured := string(encodedResponse) + "\n" + fixture.logs.Since(time.Time{})
	for _, forbidden := range []string{
		string(staticSecret),
		base64.StdEncoding.EncodeToString(staticSecret),
	} {
		if strings.Contains(captured, forbidden) {
			t.Fatal("configured fixture disclosed static TURN credential material")
		}
	}
}

func TestDirectMediaBlobCustodyDeviceFixtureMissingTurnCredentialsFailFinite(t *testing.T) {
	t.Setenv(ackCustodyAdmissionEnabledEnv, "true")
	t.Setenv(mediaCustodyAdmissionEnabledEnv, "true")
	t.Setenv(turnCredentialsEnabledEnv, "false")
	t.Setenv(turnCredentialsURLsEnv, "")
	t.Setenv(turnCredentialsPrimarySecretEnv, "")

	root, err := os.MkdirTemp("", "mknoon-plan399-turn-unavailable-fixture-")
	if err != nil {
		t.Fatalf("create fixture root: %v", err)
	}
	fixture, err := startDirectMediaDeviceFixture(
		root,
		"127.0.0.1",
		directMediaDeviceFixtureOptions{},
	)
	if err != nil {
		_ = os.RemoveAll(root)
		t.Fatalf("start fixture without TURN credentials: %v", err)
	}
	defer func() {
		if err := fixture.Close(); err != nil {
			t.Errorf("fixture teardown: %v", err)
		}
	}()

	response := requestDirectMediaFixtureTurnCredentials(t, fixture.ready.Multiaddr)
	if response["status"] != "ERROR" || response["errorCode"] != turnCredentialErrorUnavailable {
		t.Fatalf("missing fixture TURN credentials response = %#v", response)
	}
}

func TestDirectMediaBlobCustodyDeviceFixtureCallControlUsesProductionHandlers(t *testing.T) {
	t.Setenv(ackCustodyAdmissionEnabledEnv, "true")
	t.Setenv(mediaCustodyAdmissionEnabledEnv, "true")
	t.Setenv(turnCredentialsEnabledEnv, "false")

	root, err := os.MkdirTemp("", "mknoon-plan399-call-control-fixture-")
	if err != nil {
		t.Fatalf("create fixture root: %v", err)
	}
	fixture, err := startDirectMediaDeviceFixture(
		root,
		"127.0.0.1",
		directMediaDeviceFixtureOptions{},
	)
	if err != nil {
		_ = os.RemoveAll(root)
		t.Fatalf("start fixture: %v", err)
	}
	defer func() {
		if err := fixture.Close(); err != nil {
			t.Errorf("fixture teardown: %v", err)
		}
	}()

	response := requestDirectMediaFixtureCallControl(
		t,
		fixture.ready.Multiaddr,
		map[string]any{"action": "call_retrieve_v1", "limit": 1},
	)
	if response["status"] != "OK" ||
		response["schema"] != CallMailboxSchema ||
		response["version"] != float64(CallControlVersion) {
		t.Fatalf("configured fixture call-control response = %#v", response)
	}
}

func runDirectMediaDeviceFixtureProcess(t *testing.T) {
	t.Helper()
	hostIP := os.Getenv(directMediaDeviceFixtureHostIP)
	if parsed := net.ParseIP(hostIP); parsed == nil || parsed.To4() == nil {
		t.Fatalf("%s must contain the adapter-selected IPv4 address", directMediaDeviceFixtureHostIP)
	}
	if !loadAckCustodyAdmissionEnabledFromEnv() ||
		!loadDirectMediaBlobCustodyAdmissionEnabledFromEnv() {
		t.Fatal("fixture process requires both custody admission flags")
	}
	fixedWakeRecovery := os.Getenv(plan393FixedWakeFixtureMode) == "1"
	serviceAccountPath := ""
	if fixedWakeRecovery {
		serviceAccountPath = os.Getenv("SIMS_PROVIDER_FCM_CREDENTIAL_PATH")
		if info, err := os.Stat(serviceAccountPath); err != nil || !info.Mode().IsRegular() || info.Size() <= 0 {
			t.Fatal("Plan 393 fixture process requires a regular FCM service-account file")
		}
	}
	root, err := os.MkdirTemp("", "mknoon-plan347-device-fixture-")
	if err != nil {
		t.Fatalf("create fixture root: %v", err)
	}
	fixture, err := startDirectMediaDeviceFixture(
		root,
		hostIP,
		directMediaDeviceFixtureOptions{
			fixedWakeRecovery:  fixedWakeRecovery,
			serviceAccountPath: serviceAccountPath,
		},
	)
	if err != nil {
		_ = os.RemoveAll(root)
		t.Fatalf("start fixture: %v", err)
	}
	defer func() {
		if err := fixture.Close(); err != nil {
			t.Errorf("fixture teardown: %v", err)
		}
	}()

	encoded, err := json.Marshal(fixture.ready)
	if err != nil {
		t.Fatalf("marshal readiness: %v", err)
	}
	fmt.Printf("%s%s\n", directMediaDeviceFixtureReadyPrefix, encoded)

	signals := make(chan os.Signal, 1)
	signal.Notify(signals, syscall.SIGINT, syscall.SIGTERM)
	defer signal.Stop(signals)
	select {
	case <-fixture.stop:
	case <-signals:
	}
}

func startDirectMediaDeviceFixture(
	root string,
	advertisedHost string,
	options directMediaDeviceFixtureOptions,
) (*directMediaDeviceFixture, error) {
	ctx, cancel := context.WithCancel(context.Background())
	fixture := &directMediaDeviceFixture{
		root:      root,
		cancel:    cancel,
		stop:      make(chan struct{}),
		startedAt: time.Now().UTC(),
		logs:      &directMediaFixtureLogBuffer{},
	}
	fixture.priorLogWriter = log.Writer()
	log.SetOutput(io.MultiWriter(fixture.priorLogWriter, fixture.logs))
	fail := func(err error) (*directMediaDeviceFixture, error) {
		_ = fixture.Close()
		return nil, err
	}

	if err := os.MkdirAll(root, 0o700); err != nil {
		return fail(fmt.Errorf("create fixture root: %w", err))
	}
	redisServer, err := miniredis.Run()
	if err != nil {
		return fail(fmt.Errorf("start Redis-compatible state: %w", err))
	}
	fixture.redis = redisServer
	if options.fixedWakeRecovery {
		if err := fixture.configurePlan393PushTokenVault(); err != nil {
			return fail(fmt.Errorf("configure Plan 393 push token vault: %w", err))
		}
	}
	limits := DefaultServerLimits()
	serviceAccountPath := filepath.Join(root, "missing-fcm-service-account.json")
	if options.fixedWakeRecovery {
		serviceAccountPath = options.serviceAccountPath
	}
	stores, err := newControlPlaneStores(ctx, backendConfig{
		Kind:                       backendKindRedis,
		RedisURL:                   "redis://" + redisServer.Addr(),
		RedisPrefix:                "plan347:",
		AckCustodyAdmissionEnabled: true,
	}, limits, serviceAccountPath)
	if err != nil {
		return fail(fmt.Errorf("start production Redis stores: %w", err))
	}
	fixture.stores = stores
	pushTokenState := string(pushTokenStateAbsent)
	wakeCoordinatorStarted := false
	if options.fixedWakeRecovery {
		pushBackend, ok := stores.PushTokenBackend.(*redisPushTokenBackend)
		if !ok {
			return fail(fmt.Errorf("Plan 393 fixture push backend is %T", stores.PushTokenBackend))
		}
		receipt := sha256.Sum256([]byte("mknoon-plan393-ephemeral-token-vault"))
		if err := pushBackend.Migrate(hex.EncodeToString(receipt[:])); err != nil {
			return fail(fmt.Errorf("initialize encrypted push token state: %w", err))
		}
		marker, err := pushBackend.readState(pushBackend.client)
		if err != nil || marker.State != pushTokenStateEncrypted {
			return fail(fmt.Errorf("encrypted push token state is unavailable: state=%q err=%v", marker.State, err))
		}
		pushTokenState = string(marker.State)
		stores.Inbox.SetDirectReactionPushEnabled(true)
		if stores.WakeOutcomeCoordinator == nil {
			return fail(fmt.Errorf("Plan 393 fixture has no durable wake coordinator"))
		}
		stores.WakeOutcomeCoordinator.Start(ctx)
		wakeCoordinatorStarted = true
	}
	stores.Rendezvous.StartCleanup(ctx)

	media, err := NewMediaStore(filepath.Join(root, "media"))
	if err != nil {
		return fail(fmt.Errorf("start production media store: %w", err))
	}
	fixture.media = media
	media.StartCleanup(ctx)
	probeURL, err := fixture.startProbe(advertisedHost)
	if err != nil {
		return fail(fmt.Errorf("start protected-state probe: %w", err))
	}
	profile := NewProfileStore(filepath.Join(root, "profiles"))
	presence := NewPresenceStore()

	h, err := libp2p.New(
		libp2p.ListenAddrStrings("/ip4/0.0.0.0/tcp/0"),
		libp2p.EnableRelayService(
			relayv2.WithResources(relayResourcesFromServerLimits(limits)),
		),
		libp2p.ForceReachabilityPublic(),
	)
	if err != nil {
		return fail(fmt.Errorf("start libp2p host: %w", err))
	}
	fixture.host = h
	biz = newBusinessMetrics()
	turnCredentials, err := loadTurnCredentialIssuerFromEnv()
	if err != nil {
		return fail(fmt.Errorf("configure TURN credential issuer: %w", err))
	}
	registerRelayProtocolHandlers(h, relayProtocolDependencies{
		Rendezvous:      stores.Rendezvous,
		Inbox:           stores.Inbox,
		GroupInbox:      stores.GroupInbox,
		Presence:        presence,
		TurnCredentials: turnCredentials,
		CallControl:     stores.CallControl,
		Media:           media,
		Profile:         profile,
	})

	port, err := directMediaFixtureTCPPort(h)
	if err != nil {
		return fail(err)
	}
	identityHash := sha256.Sum256([]byte(h.ID().String()))
	relayBinarySHA256, err := currentExecutableSHA256()
	if err != nil {
		return fail(fmt.Errorf("hash fixture executable: %w", err))
	}
	fixture.ready = directMediaDeviceFixtureReady{
		Schema:                        "mknoon.plan347.direct-media-fixture.v1",
		Multiaddr:                     fmt.Sprintf("/ip4/%s/tcp/%d/p2p/%s", advertisedHost, port, h.ID()),
		ProbeURL:                      probeURL,
		FixtureIdentitySHA256:         hex.EncodeToString(identityHash[:]),
		Backend:                       backendKindRedis,
		Ephemeral:                     true,
		AckCustodyAdmissionEnabled:    stores.Inbox.AckCustodyAdmissionEnabled(),
		MediaCustodyAdmissionEnabled:  media.DirectMediaBlobCustodyAdmissionEnabled(),
		FixedWakeRecovery:             options.fixedWakeRecovery,
		PushTokenState:                pushTokenState,
		WakeOutcomeAdmissionEnabled:   stores.Inbox.WakeOutcomeAdmissionEnabled(),
		WakeOutcomeCoordinatorStarted: wakeCoordinatorStarted,
		DirectReactionPushEnabled:     stores.Inbox.directReactionPushEnabled,
		RealFCMConfigured:             options.fixedWakeRecovery && serviceAccountPath != "",
		RelayVersion:                  "relay-server v" + version + "+plan393-fixture",
		RelayBinarySHA256:             relayBinarySHA256,
	}
	if !fixture.ready.AckCustodyAdmissionEnabled ||
		!fixture.ready.MediaCustodyAdmissionEnabled {
		return fail(fmt.Errorf("both custody admissions must be enabled"))
	}
	return fixture, nil
}

func (fixture *directMediaDeviceFixture) configurePlan393PushTokenVault() error {
	key := make([]byte, 32)
	if _, err := rand.Read(key); err != nil {
		return err
	}
	keyringPath := filepath.Join(fixture.root, "plan393-push-token-keyring.json")
	payload, err := json.Marshal(map[string]any{
		"version": 1,
		"keys": map[string]string{
			"plan393-ephemeral": base64.StdEncoding.EncodeToString(key),
		},
	})
	if err != nil {
		return err
	}
	if err := os.WriteFile(keyringPath, payload, 0o600); err != nil {
		return err
	}
	for name, value := range map[string]string{
		pushTokenKeyringFileEnv:         keyringPath,
		pushTokenActiveKeyIDEnv:         "plan393-ephemeral",
		pushTokenProviderEnvironmentEnv: "plan393-fixture",
	} {
		previous, present := os.LookupEnv(name)
		if err := os.Setenv(name, value); err != nil {
			return err
		}
		fixture.environmentRestores = append(fixture.environmentRestores, func() {
			if present {
				_ = os.Setenv(name, previous)
			} else {
				_ = os.Unsetenv(name)
			}
		})
	}
	return nil
}

func currentExecutableSHA256() (string, error) {
	path, err := os.Executable()
	if err != nil {
		return "", err
	}
	file, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer file.Close()
	digest := sha256.New()
	if _, err := io.Copy(digest, file); err != nil {
		return "", err
	}
	return hex.EncodeToString(digest.Sum(nil)), nil
}

func (fixture *directMediaDeviceFixture) startProbe(advertisedHost string) (string, error) {
	secret := make([]byte, 32)
	if _, err := rand.Read(secret); err != nil {
		return "", fmt.Errorf("create probe capability: %w", err)
	}
	listener, err := net.Listen("tcp", "0.0.0.0:0")
	if err != nil {
		return "", err
	}
	fixture.probeLn = listener
	path := "/" + hex.EncodeToString(secret)
	mux := http.NewServeMux()
	mux.HandleFunc(path, func(writer http.ResponseWriter, request *http.Request) {
		if request.Method == http.MethodPost {
			if request.URL.RawQuery != "" {
				http.Error(writer, "query rejected", http.StatusBadRequest)
				return
			}
			writer.WriteHeader(http.StatusNoContent)
			fixture.signalStop()
			return
		}
		if request.Method != http.MethodGet {
			http.Error(writer, "method rejected", http.StatusMethodNotAllowed)
			return
		}
		query := request.URL.Query()
		if query.Get("kind") == plan393FixtureSnapshotKind {
			if len(query) != 2 || !fixture.ready.FixedWakeRecovery {
				http.Error(writer, "snapshot rejected", http.StatusBadRequest)
				return
			}
			sinceUnixMs, err := strconv.ParseInt(query.Get("sinceUnixMs"), 10, 64)
			if err != nil || sinceUnixMs < 0 {
				http.Error(writer, "snapshot time rejected", http.StatusBadRequest)
				return
			}
			fixture.writePlan393RelaySnapshot(
				writer,
				time.UnixMilli(sinceUnixMs).UTC(),
			)
			return
		}
		if query.Has("kind") {
			http.Error(writer, "snapshot kind rejected", http.StatusBadRequest)
			return
		}
		attachmentID := query.Get("attachmentId")
		// 362: an optional recipientPeerId selects one exact composite
		// (recipient, id) record; an absent recipient keeps the legacy
		// aggregate-by-ID probe, which now counts every sibling target row.
		recipientPeerID := query.Get("recipientPeerId")
		inboxMessageID := query.Get("inboxMessageId")
		if (attachmentID == "" && inboxMessageID == "") ||
			(attachmentID != "" && !validDirectMediaFixtureProbeID(attachmentID)) ||
			(recipientPeerID != "" && !validDirectMediaFixtureProbeID(recipientPeerID)) {
			http.Error(writer, "attachment rejected", http.StatusBadRequest)
			return
		}
		if inboxMessageID != "" &&
			(!validDirectMediaFixtureProbeID(inboxMessageID) || recipientPeerID == "") {
			http.Error(writer, "inbox identity rejected", http.StatusBadRequest)
			return
		}
		count := 0
		if attachmentID != "" {
			count = directMediaFixturePendingProtectedCount(
				fixture.media, recipientPeerID, attachmentID,
			)
		}
		inboxCount := 0
		inboxEnvelopeSHA256 := ""
		if inboxMessageID != "" {
			pending, _, err := fixture.stores.Inbox.RetrieveAckCustodyPending(
				recipientPeerID, 100,
			)
			if err != nil {
				http.Error(writer, "inbox probe unavailable", http.StatusServiceUnavailable)
				return
			}
			for _, entry := range pending {
				var envelope map[string]any
				if json.Unmarshal([]byte(entry.Message), &envelope) != nil ||
					envelope["id"] != inboxMessageID {
					continue
				}
				inboxCount++
				digest := sha256.Sum256([]byte(entry.Message))
				inboxEnvelopeSHA256 = hex.EncodeToString(digest[:])
			}
			if inboxCount != 1 {
				inboxEnvelopeSHA256 = ""
			}
		}
		writer.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(writer).Encode(map[string]any{
			"schema":                        "mknoon.plan347.direct-media-probe.v1",
			"protectedMediaCountForId":      count,
			"protectedInboxCountForMessage": inboxCount,
			"protectedInboxEnvelopeSha256":  inboxEnvelopeSHA256,
		})
	})
	server := &http.Server{Handler: mux, ReadHeaderTimeout: 5 * time.Second}
	fixture.probe = server
	go func() {
		if err := server.Serve(listener); err != nil && err != http.ErrServerClosed {
			fmt.Fprintf(os.Stderr, "plan347 fixture probe failed: %v\n", err)
		}
	}()
	port := listener.Addr().(*net.TCPAddr).Port
	return fmt.Sprintf("http://%s:%d%s", advertisedHost, port, path), nil
}

func (fixture *directMediaDeviceFixture) writePlan393RelaySnapshot(
	writer http.ResponseWriter,
	since time.Time,
) {
	opaque := testutil.ToFloat64(selectedPushRouteCounter.WithLabelValues("opaque"))
	rich := testutil.ToFloat64(selectedPushRouteCounter.WithLabelValues("rich"))
	writer.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(writer).Encode(map[string]any{
		"schema":                        "mknoon.plan393.relay-fixture-snapshot.v1",
		"relayVersion":                  fixture.ready.RelayVersion,
		"relayBinarySha256":             fixture.ready.RelayBinarySHA256,
		"backend":                       fixture.ready.Backend,
		"ephemeral":                     fixture.ready.Ephemeral,
		"pushTokenState":                fixture.ready.PushTokenState,
		"wakeOutcomeAdmissionEnabled":   fixture.ready.WakeOutcomeAdmissionEnabled,
		"wakeOutcomeCoordinatorStarted": fixture.ready.WakeOutcomeCoordinatorStarted,
		"directReactionPushEnabled":     fixture.ready.DirectReactionPushEnabled,
		"realFcmConfigured":             fixture.ready.RealFCMConfigured,
		"processStartTimeSeconds":       float64(fixture.startedAt.UnixMilli()) / 1000,
		"selectedRoutes": map[string]int{
			"opaque": int(opaque),
			"rich":   int(rich),
		},
		"journal": fixture.logs.Since(since),
	})
}

func directMediaFixturePendingProtectedCount(
	media *MediaStore, recipientPeerID, attachmentID string,
) int {
	if media == nil || media.custody == nil {
		return 0
	}
	media.laneMu.Lock()
	defer media.laneMu.Unlock()
	media.custody.mu.Lock()
	defer media.custody.mu.Unlock()
	if recipientPeerID != "" {
		key := custodyKeyOf(recipientPeerID, attachmentID)
		if meta := media.custody.entries[key]; meta != nil &&
			meta.State == mediaCustodyStatePending {
			return 1
		}
		if media.custody.reservations[key] != nil ||
			media.custody.blocked[key] != nil {
			return 1
		}
		return 0
	}
	count := 0
	for key, meta := range media.custody.entries {
		if key.id == attachmentID && meta.State == mediaCustodyStatePending {
			count++
		}
	}
	for key := range media.custody.reservations {
		if key.id == attachmentID {
			count++
		}
	}
	for key := range media.custody.blocked {
		if key.id == attachmentID {
			count++
		}
	}
	return count
}

func validDirectMediaFixtureProbeID(value string) bool {
	if value == "" || len(value) > 160 || strings.TrimSpace(value) != value {
		return false
	}
	for _, char := range value {
		if (char >= 'a' && char <= 'z') || (char >= 'A' && char <= 'Z') ||
			(char >= '0' && char <= '9') || strings.ContainsRune("._:-", char) {
			continue
		}
		return false
	}
	return true
}

func assertDirectMediaFixtureProbe(t *testing.T, rawURL, attachmentID string, want int) {
	t.Helper()
	client := &http.Client{Timeout: 5 * time.Second}
	request, err := http.NewRequest(http.MethodGet, rawURL+"?attachmentId="+attachmentID, nil)
	if err != nil {
		t.Fatalf("create fixture probe request: %v", err)
	}
	response, err := client.Do(request)
	if err != nil {
		t.Fatalf("query fixture protected state: %v", err)
	}
	defer response.Body.Close()
	var payload struct {
		Schema string `json:"schema"`
		Count  int    `json:"protectedMediaCountForId"`
	}
	if err := json.NewDecoder(response.Body).Decode(&payload); err != nil {
		t.Fatalf("decode fixture probe response: %v", err)
	}
	if response.StatusCode != http.StatusOK ||
		payload.Schema != "mknoon.plan347.direct-media-probe.v1" || payload.Count != want {
		t.Fatalf("fixture probe = status %d payload %#v, want count %d", response.StatusCode, payload, want)
	}
}

func assertPlan393RelayFixtureSnapshot(t *testing.T, fixture *directMediaDeviceFixture) {
	t.Helper()
	client := &http.Client{Timeout: 5 * time.Second}
	request, err := http.NewRequest(
		http.MethodGet,
		fixture.ready.ProbeURL+"?kind="+plan393FixtureSnapshotKind+"&sinceUnixMs=0",
		nil,
	)
	if err != nil {
		t.Fatalf("create Plan 393 snapshot request: %v", err)
	}
	response, err := client.Do(request)
	if err != nil {
		t.Fatalf("query Plan 393 relay snapshot: %v", err)
	}
	defer response.Body.Close()
	var payload struct {
		Schema                        string         `json:"schema"`
		RelayBinarySHA256             string         `json:"relayBinarySha256"`
		Backend                       string         `json:"backend"`
		Ephemeral                     bool           `json:"ephemeral"`
		PushTokenState                string         `json:"pushTokenState"`
		WakeOutcomeAdmissionEnabled   bool           `json:"wakeOutcomeAdmissionEnabled"`
		WakeOutcomeCoordinatorStarted bool           `json:"wakeOutcomeCoordinatorStarted"`
		DirectReactionPushEnabled     bool           `json:"directReactionPushEnabled"`
		RealFCMConfigured             bool           `json:"realFcmConfigured"`
		SelectedRoutes                map[string]int `json:"selectedRoutes"`
	}
	if err := json.NewDecoder(response.Body).Decode(&payload); err != nil {
		t.Fatalf("decode Plan 393 relay snapshot: %v", err)
	}
	if response.StatusCode != http.StatusOK ||
		payload.Schema != "mknoon.plan393.relay-fixture-snapshot.v1" ||
		payload.RelayBinarySHA256 != fixture.ready.RelayBinarySHA256 ||
		payload.Backend != backendKindRedis || !payload.Ephemeral ||
		payload.PushTokenState != string(pushTokenStateEncrypted) ||
		!payload.WakeOutcomeAdmissionEnabled ||
		!payload.WakeOutcomeCoordinatorStarted ||
		!payload.DirectReactionPushEnabled || !payload.RealFCMConfigured ||
		payload.SelectedRoutes["opaque"] != 0 || payload.SelectedRoutes["rich"] != 0 {
		t.Fatalf("Plan 393 relay snapshot = status %d payload %#v", response.StatusCode, payload)
	}
}

func assertDirectMediaFixtureShutdown(t *testing.T, fixture *directMediaDeviceFixture) {
	t.Helper()
	client := &http.Client{Timeout: 5 * time.Second}
	request, err := http.NewRequest(http.MethodPost, fixture.ready.ProbeURL, nil)
	if err != nil {
		t.Fatalf("create fixture shutdown request: %v", err)
	}
	response, err := client.Do(request)
	if err != nil {
		t.Fatalf("post fixture shutdown: %v", err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusNoContent {
		t.Fatalf("fixture shutdown status = %d, want %d", response.StatusCode, http.StatusNoContent)
	}
	select {
	case <-fixture.stop:
	case <-time.After(5 * time.Second):
		t.Fatal("fixture shutdown did not signal process stop")
	}
}

func directMediaFixtureTCPPort(h host.Host) (int, error) {
	for _, address := range h.Addrs() {
		value, err := address.ValueForProtocol(ma.P_TCP)
		if err != nil {
			continue
		}
		port, err := strconv.Atoi(value)
		if err == nil && port > 0 {
			return port, nil
		}
	}
	return 0, fmt.Errorf("libp2p fixture has no TCP listen address")
}

func assertDirectMediaFixtureHandlersReachable(t *testing.T, rawAddress string) {
	t.Helper()
	address, err := ma.NewMultiaddr(rawAddress)
	if err != nil {
		t.Fatalf("parse fixture address: %v", err)
	}
	info, err := peer.AddrInfoFromP2pAddr(address)
	if err != nil {
		t.Fatalf("fixture peer info: %v", err)
	}
	client, err := libp2p.New(libp2p.NoListenAddrs)
	if err != nil {
		t.Fatalf("start fixture probe: %v", err)
	}
	defer client.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := client.Connect(ctx, *info); err != nil {
		t.Fatalf("dial fixture: %v", err)
	}
	for _, protocolID := range []protocol.ID{
		RendezvousProtocol,
		InboxProtocol,
		MediaProtocol,
	} {
		stream, err := client.NewStream(ctx, info.ID, protocolID)
		if err != nil {
			t.Fatalf("open production handler %s: %v", protocolID, err)
		}
		_ = stream.Reset()
	}
}

func requestDirectMediaFixtureTurnCredentials(
	t *testing.T,
	rawAddress string,
) map[string]any {
	t.Helper()
	return requestDirectMediaFixtureInbox(
		t,
		rawAddress,
		map[string]any{"action": "turn_credentials_v1"},
	)
}

func requestDirectMediaFixtureCallControl(
	t *testing.T,
	rawAddress string,
	request map[string]any,
) map[string]any {
	t.Helper()
	return requestDirectMediaFixtureInbox(t, rawAddress, request)
}

func requestDirectMediaFixtureInbox(
	t *testing.T,
	rawAddress string,
	request map[string]any,
) map[string]any {
	t.Helper()
	address, err := ma.NewMultiaddr(rawAddress)
	if err != nil {
		t.Fatalf("parse fixture address: %v", err)
	}
	info, err := peer.AddrInfoFromP2pAddr(address)
	if err != nil {
		t.Fatalf("fixture peer info: %v", err)
	}
	client, err := libp2p.New(libp2p.NoListenAddrs)
	if err != nil {
		t.Fatalf("start fixture TURN client: %v", err)
	}
	defer client.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := client.Connect(ctx, *info); err != nil {
		t.Fatalf("dial fixture: %v", err)
	}
	stream, err := client.NewStream(ctx, info.ID, InboxProtocol)
	if err != nil {
		t.Fatalf("open fixture TURN stream: %v", err)
	}
	defer stream.Close()
	requestBytes, err := json.Marshal(request)
	if err != nil {
		t.Fatalf("encode fixture inbox request: %v", err)
	}
	if err := writeFrame(stream, requestBytes); err != nil {
		t.Fatalf("write fixture inbox request: %v", err)
	}
	encoded, err := readFrame(stream)
	if err != nil {
		t.Fatalf("read fixture inbox response: %v", err)
	}
	var response map[string]any
	if err := json.Unmarshal(encoded, &response); err != nil {
		t.Fatalf("decode fixture inbox response: %v", err)
	}
	return response
}

func (fixture *directMediaDeviceFixture) Close() error {
	fixture.closeOnce.Do(func() {
		fixture.signalStop()
		if fixture.cancel != nil {
			fixture.cancel()
		}
		if fixture.probe != nil {
			shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			if err := fixture.probe.Shutdown(shutdownCtx); err != nil && fixture.closeErr == nil {
				fixture.closeErr = err
			}
			cancel()
		} else if fixture.probeLn != nil {
			if err := fixture.probeLn.Close(); err != nil && fixture.closeErr == nil {
				fixture.closeErr = err
			}
		}
		if fixture.host != nil {
			if err := fixture.host.Close(); err != nil && fixture.closeErr == nil {
				fixture.closeErr = err
			}
		}
		if fixture.stores != nil {
			if err := fixture.stores.Close(); err != nil && fixture.closeErr == nil {
				fixture.closeErr = err
			}
		}
		if fixture.redis != nil {
			fixture.redis.Close()
		}
		if fixture.root != "" {
			if err := os.RemoveAll(fixture.root); err != nil && fixture.closeErr == nil {
				fixture.closeErr = err
			}
		}
		for index := len(fixture.environmentRestores) - 1; index >= 0; index-- {
			fixture.environmentRestores[index]()
		}
		if fixture.priorLogWriter != nil {
			log.SetOutput(fixture.priorLogWriter)
		}
	})
	return fixture.closeErr
}

func (fixture *directMediaDeviceFixture) signalStop() {
	fixture.stopOnce.Do(func() {
		close(fixture.stop)
	})
}
