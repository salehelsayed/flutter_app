//go:build integration

package main

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
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
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/core/protocol"
	relayv2 "github.com/libp2p/go-libp2p/p2p/protocol/circuitv2/relay"
	ma "github.com/multiformats/go-multiaddr"
)

const (
	directMediaDeviceFixtureProcessMode = "MKNOON_DIRECT_MEDIA_DEVICE_FIXTURE_PROCESS"
	directMediaDeviceFixtureHostIP      = "MKNOON_DIRECT_MEDIA_DEVICE_FIXTURE_HOST_IP"
	directMediaDeviceFixtureReadyPrefix = "MKNOON_DIRECT_MEDIA_FIXTURE_READY="
)

type directMediaDeviceFixtureReady struct {
	Schema                       string `json:"schema"`
	Multiaddr                    string `json:"multiaddr"`
	ProbeURL                     string `json:"probeUrl"`
	FixtureIdentitySHA256        string `json:"fixtureIdentitySha256"`
	Backend                      string `json:"backend"`
	Ephemeral                    bool   `json:"ephemeral"`
	AckCustodyAdmissionEnabled   bool   `json:"ackCustodyAdmissionEnabled"`
	MediaCustodyAdmissionEnabled bool   `json:"mediaCustodyAdmissionEnabled"`
}

type directMediaDeviceFixture struct {
	root      string
	host      host.Host
	stores    *controlPlaneStores
	media     *MediaStore
	redis     *miniredis.Miniredis
	probe     *http.Server
	probeLn   net.Listener
	cancel    context.CancelFunc
	ready     directMediaDeviceFixtureReady
	stop      chan struct{}
	stopOnce  sync.Once
	closeOnce sync.Once
	closeErr  error
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
	fixture, err := startDirectMediaDeviceFixture(root, "127.0.0.1")
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
	root, err := os.MkdirTemp("", "mknoon-plan347-device-fixture-")
	if err != nil {
		t.Fatalf("create fixture root: %v", err)
	}
	fixture, err := startDirectMediaDeviceFixture(root, hostIP)
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

func startDirectMediaDeviceFixture(root, advertisedHost string) (*directMediaDeviceFixture, error) {
	ctx, cancel := context.WithCancel(context.Background())
	fixture := &directMediaDeviceFixture{
		root:   root,
		cancel: cancel,
		stop:   make(chan struct{}),
	}
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
	limits := DefaultServerLimits()
	stores, err := newControlPlaneStores(ctx, backendConfig{
		Kind:                       backendKindRedis,
		RedisURL:                   "redis://" + redisServer.Addr(),
		RedisPrefix:                "plan347:",
		AckCustodyAdmissionEnabled: true,
	}, limits, filepath.Join(root, "missing-fcm-service-account.json"))
	if err != nil {
		return fail(fmt.Errorf("start production Redis stores: %w", err))
	}
	fixture.stores = stores
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
	h.SetStreamHandler(RendezvousProtocol, func(s network.Stream) {
		HandleRendezvousStream(s, stores.Rendezvous)
	})
	h.SetStreamHandler(InboxProtocol, func(s network.Stream) {
		HandleInboxStream(s, stores.Inbox, stores.GroupInbox, h, presence)
	})
	h.SetStreamHandler(MediaProtocol, func(s network.Stream) {
		HandleMediaStream(s, media, profile)
	})

	port, err := directMediaFixtureTCPPort(h)
	if err != nil {
		return fail(err)
	}
	identityHash := sha256.Sum256([]byte(h.ID().String()))
	fixture.ready = directMediaDeviceFixtureReady{
		Schema:                       "mknoon.plan347.direct-media-fixture.v1",
		Multiaddr:                    fmt.Sprintf("/ip4/%s/tcp/%d/p2p/%s", advertisedHost, port, h.ID()),
		ProbeURL:                     probeURL,
		FixtureIdentitySHA256:        hex.EncodeToString(identityHash[:]),
		Backend:                      backendKindRedis,
		Ephemeral:                    true,
		AckCustodyAdmissionEnabled:   stores.Inbox.AckCustodyAdmissionEnabled(),
		MediaCustodyAdmissionEnabled: media.DirectMediaBlobCustodyAdmissionEnabled(),
	}
	if !fixture.ready.AckCustodyAdmissionEnabled ||
		!fixture.ready.MediaCustodyAdmissionEnabled {
		return fail(fmt.Errorf("both custody admissions must be enabled"))
	}
	return fixture, nil
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
		attachmentID := request.URL.Query().Get("attachmentId")
		if !validDirectMediaFixtureProbeID(attachmentID) {
			http.Error(writer, "attachment rejected", http.StatusBadRequest)
			return
		}
		count := 0
		if directMediaFixturePendingProtectedCount(fixture.media, attachmentID) == 1 {
			count = 1
		}
		writer.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(writer).Encode(map[string]any{
			"schema":                   "mknoon.plan347.direct-media-probe.v1",
			"protectedMediaCountForId": count,
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

func directMediaFixturePendingProtectedCount(media *MediaStore, attachmentID string) int {
	if media == nil || media.custody == nil {
		return 0
	}
	media.laneMu.Lock()
	defer media.laneMu.Unlock()
	media.custody.mu.Lock()
	defer media.custody.mu.Unlock()
	if meta := media.custody.entries[attachmentID]; meta != nil &&
		meta.State == mediaCustodyStatePending {
		return 1
	}
	if media.custody.reservations[attachmentID] != nil ||
		media.custody.blocked[attachmentID] != nil {
		return 1
	}
	return 0
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
	})
	return fixture.closeErr
}

func (fixture *directMediaDeviceFixture) signalStop() {
	fixture.stopOnce.Do(func() {
		close(fixture.stop)
	})
}
