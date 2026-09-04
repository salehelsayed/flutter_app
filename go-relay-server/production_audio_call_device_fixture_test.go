//go:build integration

package main

import (
	"bufio"
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha1" //nolint:gosec // coturn REST authentication mandates HMAC-SHA1.
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"testing"
	"time"
)

const (
	productionAudioCallFixtureProcessMode = "MKNOON_PRODUCTION_AUDIO_CALL_DEVICE_FIXTURE_PROCESS"
	productionAudioCallFixtureHostIP      = "MKNOON_PRODUCTION_AUDIO_CALL_FIXTURE_HOST_IP"
	productionAudioCallFixtureReadyPrefix = "MKNOON_PRODUCTION_AUDIO_CALL_FIXTURE_READY="
	productionAudioCallFixtureSchema      = "mknoon.plan399.production-audio-call-fixture.v1"
	productionAudioCallCredentialSchema   = "mknoon.call_audio_oracle.credentials.v1"
	productionAudioCallCredentialFile     = "CALL_AUDIO_ORACLE_CREDENTIALS_FILE"
	productionAudioCallResultFile         = "CALL_AUDIO_ORACLE_RESULT_FILE"
	productionAudioCallTurnTransport      = "udp"
	productionAudioCallCoturnLockSchema   = "mknoon.call_audio_oracle.coturn_lock.v1"
	productionAudioCallRelayPortCount     = 24
)

type productionAudioCallCoturnLock struct {
	Schema  string `json:"schema"`
	Image   string `json:"image"`
	Digest  string `json:"digest"`
	Source  string `json:"source"`
	Version string `json:"version"`
	License string `json:"license"`
}

type productionAudioCallFixtureReady struct {
	Schema                        string `json:"schema"`
	Multiaddr                     string `json:"multiaddr"`
	ProbeURL                      string `json:"probeUrl"`
	FixtureIdentitySHA256         string `json:"fixtureIdentitySha256"`
	Backend                       string `json:"backend"`
	Ephemeral                     bool   `json:"ephemeral"`
	AckCustodyAdmissionEnabled    bool   `json:"ackCustodyAdmissionEnabled"`
	MediaCustodyAdmissionEnabled  bool   `json:"mediaCustodyAdmissionEnabled"`
	RelayVersion                  string `json:"relayVersion"`
	RelayBinarySHA256             string `json:"relayBinarySha256"`
	TurnHost                      string `json:"turnHost"`
	TurnPort                      int    `json:"turnPort"`
	TurnTransport                 string `json:"turnTransport"`
	TurnURL                       string `json:"turnUrl"`
	CoturnImage                   string `json:"coturnImage"`
	CoturnDigest                  string `json:"coturnDigest"`
	CoturnVersion                 string `json:"coturnVersion"`
	CoturnLockSHA256              string `json:"coturnLockSha256"`
	CoturnContainerIdentitySHA256 string `json:"coturnContainerIdentitySha256"`
	OracleCredentialsFile         string `json:"oracleCredentialsFile"`
	OracleResultFile              string `json:"oracleResultFile"`
}

type productionAudioCallOraclePeerCredential struct {
	Username        string `json:"username"`
	Password        string `json:"password"`
	IssuedAtUnixMS  int64  `json:"issued_at_unix_ms"`
	ExpiresAtUnixMS int64  `json:"expires_at_unix_ms"`
}

type productionAudioCallOracleCredentials struct {
	Schema                string                                  `json:"schema"`
	TurnURL               string                                  `json:"turn_url"`
	FixtureInstanceSHA256 string                                  `json:"fixture_instance_sha256"`
	ExpectedTransport     string                                  `json:"expected_transport"`
	PeerA                 productionAudioCallOraclePeerCredential `json:"peer_a"`
	PeerB                 productionAudioCallOraclePeerCredential `json:"peer_b"`
}

type productionAudioCallDeviceFixture struct {
	root                string
	relay               *directMediaDeviceFixture
	ready               productionAudioCallFixtureReady
	dockerExecutable    string
	containerName       string
	turnSecret          []byte
	environmentRestores []func()
	closeOnce           sync.Once
	closeErr            error
}

func TestProductionAudioCallDeviceFixture_ProductionRelayTurnCredentialsCoturnAndTeardown(t *testing.T) {
	if os.Getenv(productionAudioCallFixtureProcessMode) == "1" {
		runProductionAudioCallFixtureProcess(t)
		return
	}

	hostIP := productionAudioCallFixtureTestHostIP(t)
	fixture, err := startProductionAudioCallDeviceFixture(hostIP)
	if err != nil {
		t.Fatalf("start combined production audio-call fixture: %v", err)
	}
	root := fixture.root
	containerName := fixture.containerName
	assertProductionAudioCallFixtureReady(t, fixture)
	assertDirectMediaFixtureHandlersReachable(t, fixture.ready.Multiaddr)
	assertProductionAudioCallOracleCredentials(t, fixture)
	if err := fixture.Close(); err != nil {
		t.Fatalf("close combined production audio-call fixture: %v", err)
	}
	assertProductionAudioCallFixtureRemoved(t, root, containerName)
}

func runProductionAudioCallFixtureProcess(t *testing.T) {
	t.Helper()
	hostIP := os.Getenv(productionAudioCallFixtureHostIP)
	if !productionAudioCallPrivateLANIPv4(hostIP) {
		t.Fatalf("%s must contain the adapter-selected private LAN IPv4 address", productionAudioCallFixtureHostIP)
	}
	fixture, err := startProductionAudioCallDeviceFixture(hostIP)
	if err != nil {
		t.Fatalf("start combined production audio-call fixture: %v", err)
	}
	defer func() {
		if err := fixture.Close(); err != nil {
			t.Errorf("combined production audio-call fixture teardown: %v", err)
		}
	}()

	encoded, err := json.Marshal(fixture.ready)
	if err != nil {
		t.Fatalf("marshal combined fixture readiness: %v", err)
	}
	fmt.Printf("%s%s\n", productionAudioCallFixtureReadyPrefix, encoded)

	signals := make(chan os.Signal, 1)
	signal.Notify(signals, syscall.SIGINT, syscall.SIGTERM)
	defer signal.Stop(signals)
	select {
	case <-fixture.relay.stop:
	case <-signals:
	}
}

func startProductionAudioCallDeviceFixture(hostIP string) (*productionAudioCallDeviceFixture, error) {
	if !productionAudioCallPrivateLANIPv4(hostIP) {
		return nil, errors.New("fixture host must be a private LAN IPv4 address")
	}
	repositoryRoot, err := productionAudioCallRepositoryRoot()
	if err != nil {
		return nil, err
	}
	tempParent := filepath.Join(repositoryRoot, "build", "tmp")
	if err := os.MkdirAll(tempParent, 0o700); err != nil {
		return nil, fmt.Errorf("create combined fixture temp parent: %w", err)
	}
	root, err := os.MkdirTemp(tempParent, "production-audio-call-fixture-")
	if err != nil {
		return nil, fmt.Errorf("create combined fixture root: %w", err)
	}
	if err := os.Chmod(root, 0o700); err != nil {
		_ = os.RemoveAll(root)
		return nil, fmt.Errorf("restrict combined fixture root: %w", err)
	}
	fixture := &productionAudioCallDeviceFixture{
		root:             root,
		dockerExecutable: "docker",
	}
	fail := func(cause error) (*productionAudioCallDeviceFixture, error) {
		_ = fixture.Close()
		return nil, cause
	}

	lockPath := filepath.Join(repositoryRoot, "tool", "call_audio_oracle", "coturn.lock.json")
	lock, lockSHA256, err := loadProductionAudioCallCoturnLock(lockPath)
	if err != nil {
		return fail(err)
	}
	secretSeed := make([]byte, 32)
	if _, err := io.ReadFull(rand.Reader, secretSeed); err != nil {
		return fail(fmt.Errorf("create ephemeral coturn REST secret: %w", err))
	}
	fixture.turnSecret = []byte(hex.EncodeToString(secretSeed))
	clear(secretSeed)

	listenPort, relayMinPort, relayMaxPort, err := reserveProductionAudioCallPortSet()
	if err != nil {
		return fail(err)
	}
	configPath := filepath.Join(root, "turnserver.conf")
	if err := writeProductionAudioCallCoturnConfig(
		configPath,
		hostIP,
		fixture.turnSecret,
		relayMinPort,
		relayMaxPort,
	); err != nil {
		return fail(err)
	}
	containerID, containerName, err := fixture.startCoturn(
		lock,
		configPath,
		listenPort,
		relayMinPort,
		relayMaxPort,
	)
	if err != nil {
		return fail(err)
	}
	fixture.containerName = containerName
	if err := waitForProductionAudioCallCoturn(hostIP, listenPort, 30*time.Second); err != nil {
		return fail(err)
	}

	turnURL := fmt.Sprintf("turn:%s:%d?transport=%s", hostIP, listenPort, productionAudioCallTurnTransport)
	for name, value := range map[string]string{
		ackCustodyAdmissionEnabledEnv:   "true",
		mediaCustodyAdmissionEnabledEnv: "true",
		turnCredentialsEnabledEnv:       "true",
		turnCredentialsURLsEnv:          turnURL,
		turnCredentialsPrimarySecretEnv: base64.StdEncoding.EncodeToString(fixture.turnSecret),
	} {
		if err := fixture.setEnvironment(name, value); err != nil {
			return fail(fmt.Errorf("configure production relay TURN issuer: %w", err))
		}
	}

	// startDirectMediaDeviceFixture owns miniredis, production Redis-backed
	// stores, and the production libp2p host. Its implementation calls
	// registerRelayProtocolHandlers with the real rendezvous, inbox/TURN,
	// call-control, and media dependencies.
	relay, err := startDirectMediaDeviceFixture(
		root,
		hostIP,
		directMediaDeviceFixtureOptions{},
	)
	if err != nil {
		return fail(fmt.Errorf("start production relay fixture: %w", err))
	}
	fixture.relay = relay

	credentialsPath := filepath.Join(root, "oracle-credentials.json")
	resultPath := filepath.Join(root, "oracle-result.json")
	containerIdentity := sha256.Sum256([]byte(strings.TrimSpace(containerID)))
	containerIdentitySHA256 := hex.EncodeToString(containerIdentity[:])
	if err := fixture.writeOracleCredentials(
		turnURL,
		containerIdentitySHA256,
		credentialsPath,
	); err != nil {
		return fail(err)
	}
	if _, err := os.Stat(resultPath); !os.IsNotExist(err) {
		return fail(errors.New("oracle result path was not absent at fixture readiness"))
	}
	fixture.ready = productionAudioCallFixtureReady{
		Schema:                        productionAudioCallFixtureSchema,
		Multiaddr:                     relay.ready.Multiaddr,
		ProbeURL:                      relay.ready.ProbeURL,
		FixtureIdentitySHA256:         relay.ready.FixtureIdentitySHA256,
		Backend:                       relay.ready.Backend,
		Ephemeral:                     relay.ready.Ephemeral,
		AckCustodyAdmissionEnabled:    relay.ready.AckCustodyAdmissionEnabled,
		MediaCustodyAdmissionEnabled:  relay.ready.MediaCustodyAdmissionEnabled,
		RelayVersion:                  relay.ready.RelayVersion,
		RelayBinarySHA256:             relay.ready.RelayBinarySHA256,
		TurnHost:                      hostIP,
		TurnPort:                      listenPort,
		TurnTransport:                 productionAudioCallTurnTransport,
		TurnURL:                       turnURL,
		CoturnImage:                   lock.Image,
		CoturnDigest:                  lock.Digest,
		CoturnVersion:                 lock.Version,
		CoturnLockSHA256:              lockSHA256,
		CoturnContainerIdentitySHA256: containerIdentitySHA256,
		OracleCredentialsFile:         credentialsPath,
		OracleResultFile:              resultPath,
	}
	return fixture, nil
}

func (fixture *productionAudioCallDeviceFixture) setEnvironment(name, value string) error {
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
	return nil
}

func (fixture *productionAudioCallDeviceFixture) writeOracleCredentials(
	turnURL string,
	fixtureInstanceSHA256 string,
	path string,
) error {
	if !regexpHexSHA256(fixtureInstanceSHA256) {
		return errors.New("coturn fixture instance digest is invalid")
	}
	// This is the same production constructor used by the relay handler. The
	// oracle gets only two issued bundles, never the shared REST secret.
	service, err := NewTurnCredentialService(
		TurnCredentialServiceConfig{
			URLs:               []string{turnURL},
			TTL:                10 * time.Minute,
			MaxClockSkew:       30 * time.Second,
			MaxRequests:        6,
			RateWindow:         time.Minute,
			MaxTrackedSubjects: 8,
		},
		lookupTurnSecretProvider{lookup: os.LookupEnv},
		time.Now,
		rand.Reader,
	)
	if err != nil {
		return fmt.Errorf("create production oracle credential issuer: %w", err)
	}
	issue := func(subject string) (productionAudioCallOraclePeerCredential, error) {
		bundle, issueErr := service.Issue(context.Background(), subject)
		if issueErr != nil {
			return productionAudioCallOraclePeerCredential{}, issueErr
		}
		return productionAudioCallOraclePeerCredential{
			Username:        bundle.Username,
			Password:        bundle.Password,
			IssuedAtUnixMS:  bundle.ServerTimeMs,
			ExpiresAtUnixMS: bundle.ExpiresAtMs,
		}, nil
	}
	peerA, err := issue("production-audio-oracle-peer-a")
	if err != nil {
		return fmt.Errorf("issue oracle peer A credential: %w", err)
	}
	peerB, err := issue("production-audio-oracle-peer-b")
	if err != nil {
		return fmt.Errorf("issue oracle peer B credential: %w", err)
	}
	if peerA.Username == peerB.Username || peerA.Password == peerB.Password {
		return errors.New("production issuer did not mint distinct oracle credentials")
	}
	payload := productionAudioCallOracleCredentials{
		Schema:                productionAudioCallCredentialSchema,
		TurnURL:               turnURL,
		FixtureInstanceSHA256: fixtureInstanceSHA256,
		ExpectedTransport:     productionAudioCallTurnTransport,
		PeerA:                 peerA,
		PeerB:                 peerB,
	}
	file, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		return fmt.Errorf("create private oracle credential file: %w", err)
	}
	encoder := json.NewEncoder(file)
	encodeErr := encoder.Encode(payload)
	closeErr := file.Close()
	if encodeErr != nil {
		return fmt.Errorf("write private oracle credential file: %w", encodeErr)
	}
	if closeErr != nil {
		return fmt.Errorf("close private oracle credential file: %w", closeErr)
	}
	if err := requireProductionAudioCallPrivateFile(path); err != nil {
		return err
	}
	return nil
}

func (fixture *productionAudioCallDeviceFixture) startCoturn(
	lock productionAudioCallCoturnLock,
	configPath string,
	listenPort int,
	relayMinPort int,
	relayMaxPort int,
) (string, string, error) {
	if _, err := exec.LookPath(fixture.dockerExecutable); err != nil {
		return "", "", errors.New("docker is required for the pinned coturn fixture")
	}
	immutableImage := lock.Image[:strings.LastIndex(lock.Image, ":")] + "@" + lock.Digest
	if err := ensureProductionAudioCallCoturnImage(fixture.dockerExecutable, immutableImage, lock); err != nil {
		return "", "", err
	}
	nameToken := make([]byte, 8)
	if _, err := io.ReadFull(rand.Reader, nameToken); err != nil {
		return "", "", fmt.Errorf("create coturn container identity: %w", err)
	}
	containerName := "mknoon-plan399-coturn-" + hex.EncodeToString(nameToken)
	clear(nameToken)
	command := exec.Command(
		fixture.dockerExecutable,
		"run", "--detach", "--rm",
		"--name", containerName,
		"--publish", fmt.Sprintf("0.0.0.0:%d:3478/tcp", listenPort),
		"--publish", fmt.Sprintf("0.0.0.0:%d:3478/udp", listenPort),
		"--publish", fmt.Sprintf("0.0.0.0:%d-%d:%d-%d/udp", relayMinPort, relayMaxPort, relayMinPort, relayMaxPort),
		"--volume", configPath+":/run/mknoon/turnserver.conf:ro",
		immutableImage,
		"-c", "/run/mknoon/turnserver.conf",
	)
	var stdout bytes.Buffer
	command.Stdout = &stdout
	command.Stderr = io.Discard
	if err := command.Run(); err != nil {
		return "", "", errors.New("start digest-pinned coturn container failed")
	}
	containerID := strings.TrimSpace(stdout.String())
	if !validProductionAudioCallContainerID(containerID) {
		_ = stopProductionAudioCallCoturn(fixture.dockerExecutable, containerName)
		return "", "", errors.New("docker returned an invalid coturn container identity")
	}
	if err := verifyProductionAudioCallCoturnContainerImage(
		fixture.dockerExecutable,
		containerName,
		immutableImage,
	); err != nil {
		_ = stopProductionAudioCallCoturn(fixture.dockerExecutable, containerName)
		return "", "", err
	}
	return containerID, containerName, nil
}

func loadProductionAudioCallCoturnLock(path string) (productionAudioCallCoturnLock, string, error) {
	encoded, err := os.ReadFile(path)
	if err != nil {
		return productionAudioCallCoturnLock{}, "", fmt.Errorf("read coturn lock: %w", err)
	}
	decoder := json.NewDecoder(bytes.NewReader(encoded))
	decoder.DisallowUnknownFields()
	var lock productionAudioCallCoturnLock
	if err := decoder.Decode(&lock); err != nil {
		return productionAudioCallCoturnLock{}, "", fmt.Errorf("decode coturn lock: %w", err)
	}
	if decoder.Decode(&struct{}{}) != io.EOF {
		return productionAudioCallCoturnLock{}, "", errors.New("coturn lock has trailing JSON")
	}
	if lock.Schema != productionAudioCallCoturnLockSchema ||
		lock.Image != "coturn/coturn:4.17.2-r0" ||
		!regexpSHA256Digest(lock.Digest) ||
		lock.Version != "4.17.2-r0" || lock.Source != "https://github.com/coturn/coturn" ||
		lock.License != "BSD-3-Clause" {
		return productionAudioCallCoturnLock{}, "", errors.New("coturn lock is not the approved immutable dependency")
	}
	digest := sha256.Sum256(encoded)
	return lock, hex.EncodeToString(digest[:]), nil
}

func writeProductionAudioCallCoturnConfig(
	path string,
	hostIP string,
	secret []byte,
	relayMinPort int,
	relayMaxPort int,
) error {
	if len(secret) < 32 || strings.ContainsAny(string(secret), "\r\n\x00") {
		return errors.New("ephemeral coturn REST secret is invalid")
	}
	contents := strings.Join([]string{
		"listening-port=3478",
		"fingerprint",
		"use-auth-secret",
		"static-auth-secret=" + string(secret),
		"realm=mknoon.local.invalid",
		"external-ip=" + hostIP,
		"min-port=" + strconv.Itoa(relayMinPort),
		"max-port=" + strconv.Itoa(relayMaxPort),
		"no-tls",
		"no-dtls",
		"no-multicast-peers",
		"stale-nonce=600",
		"total-quota=32",
		"user-quota=8",
		"no-cli",
		"no-software-attribute",
		"log-file=stdout",
	}, "\n") + "\n"
	if err := os.WriteFile(path, []byte(contents), 0o600); err != nil {
		return fmt.Errorf("write private coturn config: %w", err)
	}
	if err := requireProductionAudioCallPrivateFile(path); err != nil {
		return err
	}
	return nil
}

func requireProductionAudioCallPrivateFile(path string) error {
	info, err := os.Stat(path)
	if err != nil {
		return fmt.Errorf("stat private fixture file: %w", err)
	}
	if !info.Mode().IsRegular() || info.Mode().Perm() != 0o600 {
		return fmt.Errorf("private fixture file mode = %s, want -rw-------", info.Mode())
	}
	return nil
}

func ensureProductionAudioCallCoturnImage(
	dockerExecutable string,
	immutableImage string,
	lock productionAudioCallCoturnLock,
) error {
	inspect := exec.Command(dockerExecutable, "image", "inspect", immutableImage)
	inspect.Stdout = io.Discard
	inspect.Stderr = io.Discard
	if err := inspect.Run(); err != nil {
		pull := exec.Command(dockerExecutable, "pull", immutableImage)
		pull.Stdout = io.Discard
		pull.Stderr = io.Discard
		if err := pull.Run(); err != nil {
			return errors.New("pull digest-pinned coturn image failed")
		}
	}
	repoDigestCommand := exec.Command(
		dockerExecutable,
		"image", "inspect", "--format", "{{json .RepoDigests}}", immutableImage,
	)
	repoDigests, err := repoDigestCommand.Output()
	if err != nil || !bytes.Contains(repoDigests, []byte("coturn/coturn@"+lock.Digest)) {
		return errors.New("local coturn image does not match the dependency lock digest")
	}
	return nil
}

func verifyProductionAudioCallCoturnContainerImage(
	dockerExecutable string,
	containerName string,
	immutableImage string,
) error {
	containerImage, err := exec.Command(
		dockerExecutable, "inspect", "--format", "{{.Image}}", containerName,
	).Output()
	if err != nil {
		return errors.New("inspect coturn container image failed")
	}
	lockedImage, err := exec.Command(
		dockerExecutable, "image", "inspect", "--format", "{{.Id}}", immutableImage,
	).Output()
	if err != nil || strings.TrimSpace(string(containerImage)) != strings.TrimSpace(string(lockedImage)) {
		return errors.New("running coturn container image does not match the locked digest")
	}
	return nil
}

func reserveProductionAudioCallPortSet() (int, int, int, error) {
	for attempt := 0; attempt < 128; attempt++ {
		seed := make([]byte, 4)
		if _, err := io.ReadFull(rand.Reader, seed); err != nil {
			return 0, 0, 0, err
		}
		listenPort := 36000 + int(seed[0])<<4 + int(seed[1]&0x0f)
		relayMinPort := 50000 + (int(seed[2])<<4+int(seed[3]&0x0f))%14000
		relayMaxPort := relayMinPort + productionAudioCallRelayPortCount - 1
		if relayMaxPort > 65535 || listenPort >= relayMinPort && listenPort <= relayMaxPort {
			continue
		}
		closers, err := bindProductionAudioCallPortSet(listenPort, relayMinPort, relayMaxPort)
		if err != nil {
			continue
		}
		for _, closer := range closers {
			_ = closer.Close()
		}
		return listenPort, relayMinPort, relayMaxPort, nil
	}
	return 0, 0, 0, errors.New("could not reserve an isolated coturn port set")
}

func bindProductionAudioCallPortSet(listenPort, relayMinPort, relayMaxPort int) ([]io.Closer, error) {
	closers := make([]io.Closer, 0, productionAudioCallRelayPortCount+2)
	fail := func(err error) ([]io.Closer, error) {
		for _, closer := range closers {
			_ = closer.Close()
		}
		return nil, err
	}
	tcp, err := net.Listen("tcp4", fmt.Sprintf("0.0.0.0:%d", listenPort))
	if err != nil {
		return fail(err)
	}
	closers = append(closers, tcp)
	udp, err := net.ListenPacket("udp4", fmt.Sprintf("0.0.0.0:%d", listenPort))
	if err != nil {
		return fail(err)
	}
	closers = append(closers, udp)
	for port := relayMinPort; port <= relayMaxPort; port++ {
		listener, err := net.ListenPacket("udp4", fmt.Sprintf("0.0.0.0:%d", port))
		if err != nil {
			return fail(err)
		}
		closers = append(closers, listener)
	}
	return closers, nil
}

func waitForProductionAudioCallCoturn(host string, port int, timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		connection, err := net.DialTimeout("tcp4", net.JoinHostPort(host, strconv.Itoa(port)), 500*time.Millisecond)
		if err == nil {
			_ = connection.Close()
			return nil
		}
		time.Sleep(100 * time.Millisecond)
	}
	return errors.New("digest-pinned coturn did not become reachable before deadline")
}

func stopProductionAudioCallCoturn(dockerExecutable, containerName string) error {
	if containerName == "" {
		return nil
	}
	command := exec.Command(dockerExecutable, "rm", "--force", containerName)
	command.Stdout = io.Discard
	command.Stderr = io.Discard
	if err := command.Run(); err != nil {
		inspect := exec.Command(dockerExecutable, "inspect", containerName)
		inspect.Stdout = io.Discard
		inspect.Stderr = io.Discard
		if inspect.Run() == nil {
			return errors.New("coturn container survived forced teardown")
		}
	}
	return nil
}

func (fixture *productionAudioCallDeviceFixture) Close() error {
	fixture.closeOnce.Do(func() {
		if err := stopProductionAudioCallCoturn(fixture.dockerExecutable, fixture.containerName); err != nil {
			fixture.closeErr = err
		}
		if fixture.relay != nil {
			if err := fixture.relay.Close(); err != nil && fixture.closeErr == nil {
				fixture.closeErr = err
			}
		} else if fixture.root != "" {
			if err := os.RemoveAll(fixture.root); err != nil && fixture.closeErr == nil {
				fixture.closeErr = err
			}
		}
		for index := len(fixture.environmentRestores) - 1; index >= 0; index-- {
			fixture.environmentRestores[index]()
		}
		clear(fixture.turnSecret)
		fixture.turnSecret = nil
	})
	return fixture.closeErr
}

func assertProductionAudioCallFixtureReady(t *testing.T, fixture *productionAudioCallDeviceFixture) {
	t.Helper()
	ready := fixture.ready
	if ready.Schema != productionAudioCallFixtureSchema || ready.Backend != backendKindRedis ||
		!ready.Ephemeral || !ready.AckCustodyAdmissionEnabled || !ready.MediaCustodyAdmissionEnabled ||
		ready.TurnHost == "" || ready.TurnPort <= 0 || ready.TurnTransport != productionAudioCallTurnTransport ||
		ready.TurnURL != fmt.Sprintf("turn:%s:%d?transport=udp", ready.TurnHost, ready.TurnPort) ||
		!regexpHexSHA256(ready.FixtureIdentitySHA256) || !regexpHexSHA256(ready.RelayBinarySHA256) ||
		!regexpHexSHA256(ready.CoturnLockSHA256) || !regexpHexSHA256(ready.CoturnContainerIdentitySHA256) {
		t.Fatalf("combined fixture readiness = %#v", ready)
	}
	if err := requireProductionAudioCallPrivateFile(ready.OracleCredentialsFile); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(ready.OracleResultFile); !os.IsNotExist(err) {
		t.Fatal("oracle result path must remain absent before the oracle runs")
	}
	if err := waitForProductionAudioCallCoturn(ready.TurnHost, ready.TurnPort, 5*time.Second); err != nil {
		t.Fatal(err)
	}
}

func assertProductionAudioCallOracleCredentials(t *testing.T, fixture *productionAudioCallDeviceFixture) {
	t.Helper()
	file, err := os.Open(fixture.ready.OracleCredentialsFile)
	if err != nil {
		t.Fatalf("open oracle credential file: %v", err)
	}
	defer file.Close()
	decoder := json.NewDecoder(bufio.NewReader(file))
	decoder.DisallowUnknownFields()
	var credentials productionAudioCallOracleCredentials
	if err := decoder.Decode(&credentials); err != nil {
		t.Fatalf("decode oracle credential file: %v", err)
	}
	now := time.Now().UnixMilli()
	if credentials.Schema != productionAudioCallCredentialSchema ||
		credentials.TurnURL != fixture.ready.TurnURL ||
		credentials.FixtureInstanceSHA256 != fixture.ready.CoturnContainerIdentitySHA256 ||
		credentials.ExpectedTransport != productionAudioCallTurnTransport ||
		credentials.PeerA.Username == credentials.PeerB.Username ||
		credentials.PeerA.Password == credentials.PeerB.Password ||
		credentials.PeerA.IssuedAtUnixMS > now || credentials.PeerB.IssuedAtUnixMS > now ||
		credentials.PeerA.ExpiresAtUnixMS <= now || credentials.PeerB.ExpiresAtUnixMS <= now {
		t.Fatalf("oracle credentials failed their bounded issuance contract")
	}
	for _, peer := range []productionAudioCallOraclePeerCredential{credentials.PeerA, credentials.PeerB} {
		mac := hmacSHA1(fixture.turnSecret, peer.Username)
		if !bytes.Equal([]byte(peer.Password), []byte(mac)) {
			t.Fatal("oracle credential was not issued under the fixture coturn authority")
		}
	}
}

func assertProductionAudioCallFixtureRemoved(t *testing.T, root, containerName string) {
	t.Helper()
	if _, err := os.Stat(root); !os.IsNotExist(err) {
		t.Fatalf("combined fixture root survived teardown: %v", err)
	}
	command := exec.Command("docker", "inspect", containerName)
	command.Stdout = io.Discard
	command.Stderr = io.Discard
	if command.Run() == nil {
		t.Fatal("combined fixture coturn container survived teardown")
	}
}

func productionAudioCallFixtureTestHostIP(t *testing.T) string {
	t.Helper()
	if configured := strings.TrimSpace(os.Getenv(productionAudioCallFixtureHostIP)); configured != "" {
		if !productionAudioCallPrivateLANIPv4(configured) {
			t.Fatalf("configured fixture host %q is not a private LAN IPv4", configured)
		}
		return configured
	}
	interfaces, err := net.Interfaces()
	if err != nil {
		t.Skip("private LAN interface unavailable")
	}
	for _, networkInterface := range interfaces {
		if networkInterface.Flags&net.FlagUp == 0 || networkInterface.Flags&net.FlagLoopback != 0 {
			continue
		}
		addresses, _ := networkInterface.Addrs()
		for _, address := range addresses {
			host, _, _ := net.ParseCIDR(address.String())
			if host != nil && productionAudioCallPrivateLANIPv4(host.String()) {
				return host.String()
			}
		}
	}
	t.Skip("private LAN IPv4 unavailable for coturn fixture")
	return ""
}

func productionAudioCallPrivateLANIPv4(value string) bool {
	ip := net.ParseIP(value)
	if ip == nil || ip.To4() == nil {
		return false
	}
	bytes := ip.To4()
	return bytes[0] == 10 || bytes[0] == 192 && bytes[1] == 168 ||
		bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31
}

func productionAudioCallRepositoryRoot() (string, error) {
	workingDirectory, err := os.Getwd()
	if err != nil {
		return "", fmt.Errorf("resolve fixture working directory: %w", err)
	}
	candidates := []string{workingDirectory, filepath.Dir(workingDirectory)}
	for _, candidate := range candidates {
		if info, statErr := os.Stat(filepath.Join(candidate, "tool", "call_audio_oracle", "go.mod")); statErr == nil && info.Mode().IsRegular() {
			return filepath.Abs(candidate)
		}
	}
	return "", errors.New("repository root with call audio oracle was not found")
}

func validProductionAudioCallContainerID(value string) bool {
	return len(value) == 64 && regexpHexSHA256(value)
}

func regexpHexSHA256(value string) bool {
	if len(value) != sha256.Size*2 {
		return false
	}
	_, err := hex.DecodeString(value)
	return err == nil && strings.ToLower(value) == value
}

func regexpSHA256Digest(value string) bool {
	return strings.HasPrefix(value, "sha256:") && regexpHexSHA256(strings.TrimPrefix(value, "sha256:"))
}

func hmacSHA1(secret []byte, username string) string {
	mac := hmac.New(sha1.New, secret)
	_, _ = mac.Write([]byte(username))
	return base64.StdEncoding.EncodeToString(mac.Sum(nil))
}
