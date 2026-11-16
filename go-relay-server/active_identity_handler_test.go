package main

import (
	"bytes"
	"context"
	"crypto/ed25519"
	"encoding/base64"
	"encoding/json"
	"errors"
	"log"
	"os"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	libp2pcrypto "github.com/libp2p/go-libp2p/core/crypto"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
)

func b293Account(t *testing.T, seed byte) (libp2pcrypto.PrivKey, string) {
	t.Helper()
	key, err := libp2pcrypto.UnmarshalEd25519PrivateKey(ed25519.NewKeyFromSeed(bytes.Repeat([]byte{seed}, 32)))
	if err != nil {
		t.Fatal(err)
	}
	id, err := peer.IDFromPrivateKey(key)
	if err != nil {
		t.Fatal(err)
	}
	return key, id.String()
}

// Independent protocol literal: do not call a production signing helper here.
func b293Proof(day, account, transport string) []byte {
	return []byte("mknoon/activity-account-proof/v1\x00active_identity_v1\x001\x00" + day + "\x00" + account + "\x00" + transport)
}

func b293Request(t *testing.T, key libp2pcrypto.PrivKey, day, account, transport string) map[string]any {
	t.Helper()
	signature, err := key.Sign(b293Proof(day, account, transport))
	if err != nil {
		t.Fatal(err)
	}
	return map[string]any{"action": "active_identity_v1", "version": 1, "day": day, "accountPeerId": account, "signature": base64.StdEncoding.EncodeToString(signature)}
}

func b293Raw(t *testing.T, request map[string]any) []byte {
	t.Helper()
	raw, err := json.Marshal(request)
	if err != nil {
		t.Fatal(err)
	}
	return raw
}

func b293Copy(request map[string]any) map[string]any {
	copy := make(map[string]any, len(request))
	for key, value := range request {
		copy[key] = value
	}
	return copy
}

func b293Ack(t *testing.T, response activeIdentityWireResponse) {
	t.Helper()
	if response.Status != "OK" || response.Version != 1 || response.ErrorCode != "" || response.Data == nil || !response.Data.Supported || !response.Data.Accepted {
		t.Fatalf("valid assertion not durably acknowledged: %+v", response)
	}
	b293ReplyShape(t, response, false)
}

func b293Invalid(t *testing.T, response activeIdentityWireResponse) {
	t.Helper()
	if response.Status != "ERROR" || response.Version != 1 || response.ErrorCode != "ACTIVE_IDENTITY_INVALID_REQUEST" || response.Data != nil {
		t.Fatalf("invalid assertion did not get fixed refusal: %+v", response)
	}
	b293ReplyShape(t, response, true)
}

func b293ReplyShape(t *testing.T, response activeIdentityWireResponse, refused bool) {
	t.Helper()
	raw, err := json.Marshal(response)
	if err != nil {
		t.Fatal(err)
	}
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(raw, &fields); err != nil {
		t.Fatal(err)
	}
	if len(fields) != 3 || fields["status"] == nil || fields["version"] == nil {
		t.Fatalf("reply exposes unexpected fields: %s", raw)
	}
	if refused {
		if fields["errorCode"] == nil || fields["data"] != nil {
			t.Fatalf("refusal shape: %s", raw)
		}
		return
	}
	var data map[string]json.RawMessage
	if err := json.Unmarshal(fields["data"], &data); err != nil || len(data) != 2 || data["supported"] == nil || data["accepted"] == nil {
		t.Fatalf("counter reply data shape: %s", raw)
	}
}

func TestB293HandlerCanonicalAccountAcrossLinkedTransports(t *testing.T) {
	key, account := b293Account(t, 41)
	_, first := b293Account(t, 42)
	_, second := b293Account(t, 43)
	clock := &b29StoreClock{at: b29StoreMidnight(t, "2026-03-29")}
	store := b29NewStore(t, clock)
	for _, transport := range []string{first, second, first} {
		request := b293Raw(t, b293Request(t, key, "2026-03-29", account, transport))
		b293Ack(t, activeIdentityResponse(request, transport, store))
	}
	if got := b29StoreDiskEstimate(t, b29StoreDisk(t, store.path), "2026-03-29"); got != (activeIdentityEstimate{Day: 1, Week: 1, Month: 1}) {
		t.Fatalf("linked transports became different accounts: %+v", got)
	}
	otherKey, otherAccount := b293Account(t, 44)
	b293Ack(t, activeIdentityResponse(b293Raw(t, b293Request(t, otherKey, "2026-03-29", otherAccount, first)), first, store))
	if got := b29StoreDiskEstimate(t, b29StoreDisk(t, store.path), "2026-03-29"); got.Day != 2 {
		t.Fatalf("different valid accounts merged: %+v", got)
	}
}

func TestB293HandlerRejectsForeignAndMutatedProofWithoutMutation(t *testing.T) {
	key, account := b293Account(t, 41)
	transportKey, transport := b293Account(t, 42)
	foreignKey, foreign := b293Account(t, 43)
	clock := &b29StoreClock{at: b29StoreMidnight(t, "2026-03-29")}
	store := b29NewStore(t, clock)
	valid := b293Request(t, key, "2026-03-29", account, transport)
	b293Ack(t, activeIdentityResponse(b293Raw(t, valid), transport, store))
	before, err := os.ReadFile(store.path)
	if err != nil {
		t.Fatal(err)
	}
	accountID, err := peer.Decode(account)
	if err != nil {
		t.Fatal(err)
	}
	transportID, err := peer.Decode(transport)
	if err != nil {
		t.Fatal(err)
	}
	foreignSignature := b293Request(t, foreignKey, "2026-03-29", account, transport)["signature"]
	transportSignature := b293Request(t, transportKey, "2026-03-29", account, transport)["signature"]
	accountAlias := peer.ToCid(accountID).String()
	aliasSignature := b293Request(t, key, "2026-03-29", accountAlias, transport)["signature"]
	for _, tc := range []struct {
		name, authenticated string
		change              func(map[string]any)
	}{
		{"foreign-root-signature", transport, func(r map[string]any) { r["signature"] = foreignSignature }},
		{"connection-key-is-not-root-authority", transport, func(r map[string]any) { r["signature"] = transportSignature }},
		{"transport-substituted-as-account", transport, func(r map[string]any) { r["accountPeerId"] = transport }},
		{"other-account", transport, func(r map[string]any) { r["accountPeerId"] = foreign }},
		{"replayed-on-other-connection", foreign, func(map[string]any) {}},
		{"empty-connection", "", func(map[string]any) {}},
		{"noncanonical-connection", peer.ToCid(transportID).String(), func(map[string]any) {}},
		{"noncanonical-account", transport, func(r map[string]any) {
			r["accountPeerId"] = accountAlias
			r["signature"] = aliasSignature
		}},
		{"wrong-action", transport, func(r map[string]any) { r["action"] = "active_identity_v2" }},
		{"wrong-version", transport, func(r map[string]any) { r["version"] = 2 }},
		{"unsigned-day-change", transport, func(r map[string]any) { r["day"] = "2026-03-30" }},
		{"empty-account", transport, func(r map[string]any) { r["accountPeerId"] = "" }},
		{"invalid-peer-id", transport, func(r map[string]any) { r["accountPeerId"] = "not-a-peer-id" }},
		{"signature-not-base64", transport, func(r map[string]any) { r["signature"] = "%private-b293-proof" }},
		{"signature-unpadded", transport, func(r map[string]any) { r["signature"] = strings.TrimRight(r["signature"].(string), "=") }},
		{"signature-newline", transport, func(r map[string]any) { r["signature"] = r["signature"].(string) + "\n" }},
	} {
		t.Run(tc.name, func(t *testing.T) {
			request := b293Copy(valid)
			tc.change(request)
			b293Invalid(t, activeIdentityResponse(b293Raw(t, request), tc.authenticated, store))
			if after, err := os.ReadFile(store.path); err != nil || !bytes.Equal(before, after) {
				t.Fatalf("refused proof changed durable aggregate: %v", err)
			}
		})
	}
}

func TestB293HandlerStrictSchemaAndPayloadBoundary(t *testing.T) {
	key, account := b293Account(t, 41)
	_, transport := b293Account(t, 42)
	clock := &b29StoreClock{at: b29StoreMidnight(t, "2026-03-29")}
	store := b29NewStore(t, clock)
	valid := b293Request(t, key, "2026-03-29", account, transport)
	raw := b293Raw(t, valid)
	b293Ack(t, activeIdentityResponse(raw, transport, store))
	padded := append(bytes.Clone(raw), bytes.Repeat([]byte(" "), 2048-len(raw))...)
	b293Ack(t, activeIdentityResponse(padded, transport, store))
	before, err := os.ReadFile(store.path)
	if err != nil {
		t.Fatal(err)
	}
	cases := map[string][]byte{
		"empty": nil, "null": []byte("null"), "array": []byte("[]"),
		"string": []byte(`"private-b293-not-an-object"`), "number": []byte("1"), "boolean": []byte("true"),
		"trailing-object":      append(bytes.Clone(raw), []byte("{}")...),
		"oversized-valid-json": append(bytes.Clone(padded), ' '),
		"malformed":            []byte(`{"action":`),
	}
	for _, field := range []string{"action", "version", "day", "accountPeerId", "signature"} {
		missing := b293Copy(valid)
		delete(missing, field)
		cases["missing-"+field] = b293Raw(t, missing)
		null := b293Copy(valid)
		null[field] = nil
		cases["null-"+field] = b293Raw(t, null)
		wrong := b293Copy(valid)
		wrong[field] = map[string]any{"private-b293-invalid-type": true}
		cases["wrong-type-"+field] = b293Raw(t, wrong)
		alias := strings.ToUpper(field[:1]) + field[1:]
		caseAlias := b293Copy(valid)
		delete(caseAlias, field)
		caseAlias[alias] = valid[field]
		cases["case-alias-"+field] = b293Raw(t, caseAlias)
		caseDuplicate := b293Copy(valid)
		caseDuplicate[alias] = valid[field]
		cases["case-duplicate-"+field] = b293Raw(t, caseDuplicate)
		duplicate, err := json.Marshal(valid[field])
		if err != nil {
			t.Fatal(err)
		}
		cases["duplicate-"+field] = []byte(string(raw[:len(raw)-1]) + `,"` + field + `":` + string(duplicate) + `}`)
	}
	for _, field := range []string{"transportPeerId", "devicePeerId", "owner", "eventId", "recipientPeerId", "identityHash"} {
		unknown := b293Copy(valid)
		unknown[field] = "private-b293-unrelated-owner"
		cases["unknown-"+field] = b293Raw(t, unknown)
	}
	for _, version := range []string{"1.0", "1e0", `"1"`} {
		cases["version-"+version] = []byte(strings.Replace(string(raw), `"version":1`, `"version":`+version, 1))
	}
	for name, payload := range cases {
		t.Run(name, func(t *testing.T) {
			b293Invalid(t, activeIdentityResponse(payload, transport, store))
			if after, err := os.ReadFile(store.path); err != nil || !bytes.Equal(before, after) {
				t.Fatalf("invalid schema changed durable aggregate: %v", err)
			}
		})
	}
}

func TestB293HandlerNilFeatureIsTypedUnsupportedAfterValidProof(t *testing.T) {
	key, account := b293Account(t, 41)
	_, transport := b293Account(t, 42)
	valid := b293Raw(t, b293Request(t, key, "2026-03-29", account, transport))
	response := activeIdentityResponse(valid, transport, nil)
	if response.Status != "OK" || response.Version != 1 || response.ErrorCode != "" || response.Data == nil || response.Data.Supported || response.Data.Accepted {
		t.Fatalf("absent feature was not typed unsupported: %+v", response)
	}
	b293ReplyShape(t, response, false)
	b293Invalid(t, activeIdentityResponse(valid, "", nil))
}

func TestB293HandlerUsesStoreBerlinDayAndRejectsClosedFutureDates(t *testing.T) {
	key, account := b293Account(t, 41)
	_, transport := b293Account(t, 42)
	at, err := time.Parse(time.RFC3339, "2026-03-28T23:30:00Z")
	if err != nil {
		t.Fatal(err)
	}
	clock := &b29StoreClock{at: at}
	store := b29NewStore(t, clock)
	b293Ack(t, activeIdentityResponse(b293Raw(t, b293Request(t, key, "2026-03-29", account, transport)), transport, store))
	before, err := os.ReadFile(store.path)
	if err != nil {
		t.Fatal(err)
	}
	for _, day := range []string{"2026-03-28", "2026-03-30"} {
		b293Invalid(t, activeIdentityResponse(b293Raw(t, b293Request(t, key, day, account, transport)), transport, store))
	}
	if after, err := os.ReadFile(store.path); err != nil || !bytes.Equal(before, after) {
		t.Fatalf("out-of-day proof changed aggregate: %v", err)
	}
}

func TestB293HandlerAckWaitsForDurableWriter(t *testing.T) {
	key, account := b293Account(t, 41)
	otherKey, otherAccount := b293Account(t, 44)
	_, transport := b293Account(t, 42)
	clock := &b29StoreClock{at: b29StoreMidnight(t, "2026-03-29")}
	store := b29NewStore(t, clock)
	b293Ack(t, activeIdentityResponse(b293Raw(t, b293Request(t, key, "2026-03-29", account, transport)), transport, store))
	request := b293Raw(t, b293Request(t, otherKey, "2026-03-29", otherAccount, transport))
	entered, release, finished := make(chan struct{}), make(chan struct{}), make(chan struct{})
	var once sync.Once
	unblock := func() { once.Do(func() { close(release) }) }
	write := store.write
	var committed atomic.Bool
	store.write = func(path string, raw []byte) error {
		close(entered)
		select {
		case <-release:
		case <-time.After(5 * time.Second):
			return errors.New("public B293 writer barrier timed out")
		}
		err := write(path, raw)
		committed.Store(err == nil)
		return err
	}
	t.Cleanup(func() {
		unblock()
		select {
		case <-finished:
			store.write = write
		case <-time.After(5 * time.Second):
			t.Error("handler did not exit after writer cleanup")
		}
	})
	type receipt struct {
		response activeIdentityWireResponse
		durable  bool
	}
	result := make(chan receipt, 1)
	go func() {
		defer close(finished)
		response := activeIdentityResponse(request, transport, store)
		result <- receipt{response, committed.Load()}
	}()
	b29StoreWaitSignal(t, entered, "handler durable writer")
	select {
	case <-result:
		t.Fatal("handler replied before its admitted generation was durable")
	default:
	}
	unblock()
	select {
	case got := <-result:
		b293Ack(t, got.response)
		if !got.durable {
			t.Fatal("ACK preceded writer success")
		}
	case <-time.After(5 * time.Second):
		t.Fatal("handler did not reply after durable write")
	}
}

func TestB293HandlerStorageFailureRetryAndRestartDeduplicate(t *testing.T) {
	key, account := b293Account(t, 41)
	_, transport := b293Account(t, 42)
	otherKey, otherAccount := b293Account(t, 44)
	clock := &b29StoreClock{at: b29StoreMidnight(t, "2026-03-29")}
	store := b29NewStore(t, clock)
	b293Ack(t, activeIdentityResponse(b293Raw(t, b293Request(t, key, "2026-03-29", account, transport)), transport, store))
	request := b293Raw(t, b293Request(t, otherKey, "2026-03-29", otherAccount, transport))
	before, err := os.ReadFile(store.path)
	if err != nil {
		t.Fatal(err)
	}
	write := store.write
	store.write = func(string, []byte) error { return errors.New("private-b293-writer-" + otherAccount) }
	response := activeIdentityResponse(request, transport, store)
	store.write = write
	if response.Status != "ERROR" || response.Version != 1 || response.ErrorCode != "ACTIVE_IDENTITY_STORAGE_UNAVAILABLE" || response.Data != nil {
		t.Fatalf("writer failure was ACKed or exposed a private error: %+v", response)
	}
	b293ReplyShape(t, response, true)
	if after, err := os.ReadFile(store.path); err != nil || !bytes.Equal(before, after) {
		t.Fatalf("failed writer changed authoritative snapshot: %v", err)
	}
	b293Ack(t, activeIdentityResponse(request, transport, store))
	loaded, err := newActiveIdentityStore(store.path, b29StoreKey(), clock.now)
	if err != nil {
		t.Fatal(err)
	}
	b293Ack(t, activeIdentityResponse(request, transport, loaded))
	if got := b29StoreDiskEstimate(t, b29StoreDisk(t, loaded.path), "2026-03-29"); got.Day != 2 {
		t.Fatalf("durable retry/restart changed account cardinality: %+v", got)
	}
}

func TestB293HandlerAdmissionAndMidnightCloseUseStoreLock(t *testing.T) {
	key, account := b293Account(t, 41)
	otherKey, otherAccount := b293Account(t, 44)
	_, transport := b293Account(t, 42)
	start := b29StoreMidnight(t, "2026-03-28")
	clock := &b29StoreClock{at: start}
	store := b29NewStore(t, clock)
	b293Ack(t, activeIdentityResponse(b293Raw(t, b293Request(t, key, "2026-03-28", account, transport)), transport, store))
	request := b293Raw(t, b293Request(t, otherKey, "2026-03-28", otherAccount, transport))
	clock.set(start.AddDate(0, 0, 1).Add(-time.Second))
	entered, release := make(chan struct{}), make(chan struct{})
	admitFinished, closeFinished := make(chan struct{}), make(chan struct{})
	var once sync.Once
	unblock := func() { once.Do(func() { close(release) }) }
	var first, outsideLock, timedOut atomic.Bool
	clock.setHook(func(at time.Time) time.Time {
		if store.mu.TryLock() {
			store.mu.Unlock()
			outsideLock.Store(true)
		}
		if first.CompareAndSwap(false, true) {
			close(entered)
			select {
			case <-release:
			case <-time.After(5 * time.Second):
				timedOut.Store(true)
			}
		}
		return at
	})
	closingStarted := false
	t.Cleanup(func() {
		unblock()
		for _, done := range []<-chan struct{}{admitFinished, closeFinished} {
			if done == closeFinished && !closingStarted {
				continue
			}
			select {
			case <-done:
			case <-time.After(5 * time.Second):
				t.Error("midnight handler cleanup did not finish")
			}
		}
		clock.setHook(nil)
	})
	admitted := make(chan activeIdentityWireResponse, 1)
	go func() { defer close(admitFinished); admitted <- activeIdentityResponse(request, transport, store) }()
	b29StoreWaitSignal(t, entered, "signed handler admission clock")
	clock.set(start.AddDate(0, 0, 1))
	closed := make(chan error, 1)
	closingStarted = true
	go func() { defer close(closeFinished); closed <- store.advance() }()
	unblock()
	select {
	case response := <-admitted:
		b293Ack(t, response)
	case <-time.After(5 * time.Second):
		t.Fatal("signed pre-midnight admission did not finish")
	}
	if err := b29StoreWaitError(t, closed, "signed handler midnight close"); err != nil {
		t.Fatal(err)
	}
	if outsideLock.Load() || timedOut.Load() {
		t.Fatal("handler day check escaped the store lock or timed out")
	}
	clock.setHook(nil)
	if got := b29StoreFindFinal(t, b29StoreFinals(t, store), "2026-03-28"); got.Counts.Day != 2 {
		t.Fatalf("authenticated contribution missed its serialized close: %+v", got)
	}
	b293Invalid(t, activeIdentityResponse(request, transport, store))
}

func TestB293HandlerReplyLogsAndSnapshotExcludeProofIdentity(t *testing.T) {
	key, account := b293Account(t, 41)
	_, transport := b293Account(t, 42)
	clock := &b29StoreClock{at: b29StoreMidnight(t, "2026-03-29")}
	store := b29NewStore(t, clock)
	request := b293Request(t, key, "2026-03-29", account, transport)
	var logs bytes.Buffer
	previous := log.Writer()
	log.SetOutput(&logs)
	defer log.SetOutput(previous)
	b293Ack(t, activeIdentityResponse(b293Raw(t, request), transport, store))
	b293Invalid(t, activeIdentityResponse(b293Raw(t, request), account, store))
	raw, err := os.ReadFile(store.path)
	if err != nil {
		t.Fatal(err)
	}
	for _, secret := range []string{account, transport, request["signature"].(string), `"accountPeerId"`, `"transportPeerId"`, `"signature"`} {
		if bytes.Contains(raw, []byte(secret)) || strings.Contains(logs.String(), secret) {
			t.Fatal("raw proof identity persisted or logged")
		}
	}
}

func TestB293HandlerAuthenticatedInboxRouteBindsLinkedTransport(t *testing.T) {
	key, account := b293Account(t, 41)
	clock := &b29StoreClock{at: b29StoreMidnight(t, "2026-03-29")}
	store := b29NewStore(t, clock)
	inbox := NewInboxStore(NewPushServiceWithBackend(newMemoryPushTokenStore()))
	inbox.activeIdentities = store
	env := setupInboxStreamEnv(t, inbox, nil)
	handled := make(chan error, 3)
	// Mocknet deadlines are no-ops. Reset closes its pipes and cancels pending
	// frame I/O; each owner cancels and joins this watcher before returning.
	resetOnCancel := func(ctx context.Context, stream network.Stream) <-chan struct{} {
		finished := make(chan struct{})
		go func() {
			defer close(finished)
			<-ctx.Done()
			_ = stream.Reset()
		}()
		return finished
	}
	env.server.SetStreamHandler(InboxProtocol, func(stream network.Stream) {
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		resetFinished := resetOnCancel(ctx, stream)
		var handlerError error
		defer func() {
			cancel()
			select {
			case <-resetFinished:
			case <-time.After(2 * time.Second):
				handlerError = errors.New("public B293 handler reset did not finish")
			}
			select {
			case handled <- handlerError:
			default:
			}
		}()
		HandleInboxStream(stream, inbox, nil, env.server, env.presence, nil)
	})
	roundTrip := func(client host.Host, raw []byte) activeIdentityWireResponse {
		t.Helper()
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		stream, err := client.NewStream(ctx, env.server.ID(), InboxProtocol)
		if err != nil {
			cancel()
			t.Fatal(err)
		}
		resetFinished := resetOnCancel(ctx, stream)
		ioFinished := make(chan struct{})
		type frameResult struct {
			raw []byte
			err error
		}
		result := make(chan frameResult, 1)
		go func() {
			defer close(ioFinished)
			if err := writeFrame(stream, raw); err != nil {
				result <- frameResult{err: err}
				return
			}
			response, err := readFrame(stream)
			result <- frameResult{response, err}
		}()
		handlerObserved := false
		defer func() {
			cancel()
			cleanup, cleanupCancel := context.WithTimeout(context.Background(), 2*time.Second)
			defer cleanupCancel()
			for _, finished := range []<-chan struct{}{resetFinished, ioFinished} {
				select {
				case <-finished:
				case <-cleanup.Done():
					t.Error("authenticated inbox I/O cleanup did not finish")
					return
				}
			}
			if !handlerObserved {
				select {
				case handlerError := <-handled:
					if handlerError != nil {
						t.Error(handlerError)
					}
				case <-cleanup.Done():
					t.Error("authenticated inbox handler cleanup did not finish")
				}
			}
		}()
		var response []byte
		select {
		case got := <-result:
			if got.err != nil {
				t.Fatal(got.err)
			}
			response = got.raw
		case <-ctx.Done():
			t.Fatal("authenticated inbox frame I/O exceeded its reset deadline")
		}
		var decoded activeIdentityWireResponse
		if err := json.Unmarshal(response, &decoded); err != nil {
			t.Fatal(err)
		}
		select {
		case err := <-handled:
			handlerObserved = true
			if err != nil {
				t.Fatal(err)
			}
		case <-ctx.Done():
			t.Fatal("authenticated inbox handler did not finish")
		}
		return decoded
	}
	first, second := env.sender.ID().String(), env.recipient.ID().String()
	if account == first || account == second {
		t.Fatal("fixture did not separate root account from linked transports")
	}
	firstRequest := b293Raw(t, b293Request(t, key, "2026-03-29", account, first))
	b293Ack(t, roundTrip(env.sender, firstRequest))
	before, err := os.ReadFile(store.path)
	if err != nil {
		t.Fatal(err)
	}
	b293Invalid(t, roundTrip(env.recipient, firstRequest))
	if after, err := os.ReadFile(store.path); err != nil || !bytes.Equal(before, after) {
		t.Fatalf("replay on a different authenticated transport mutated aggregate: %v", err)
	}
	b293Ack(t, roundTrip(env.recipient, b293Raw(t, b293Request(t, key, "2026-03-29", account, second))))
	if got := b29StoreDiskEstimate(t, b29StoreDisk(t, store.path), "2026-03-29"); got.Day != 1 {
		t.Fatalf("authenticated linked devices counted as people: %+v", got)
	}
}
