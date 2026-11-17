package main

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"os"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	libp2pcrypto "github.com/libp2p/go-libp2p/core/crypto"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
)

func b29E1Request(t *testing.T, key libp2pcrypto.PrivKey, week, account, transport string, kinds []string) map[string]any {
	t.Helper()
	proof := []byte("mknoon/activity-account-proof/v1\x00engagement_identity_v1\x001\x00" + week + "\x00" + strings.Join(kinds, ",") + "\x00" + account + "\x00" + transport)
	signature, err := key.Sign(proof)
	if err != nil {
		t.Fatal(err)
	}
	return map[string]any{"action": "engagement_identity_v1", "version": 1, "week": week, "kinds": kinds, "accountPeerId": account, "signature": base64.StdEncoding.EncodeToString(signature)}
}

func b29E1Ack(t *testing.T, response activeEngagementWireResponse) {
	t.Helper()
	if response.Status != "OK" || response.Version != 1 || response.ErrorCode != "" || response.Data == nil || !response.Data.Supported || !response.Data.Accepted {
		t.Fatalf("valid engagement not durably acknowledged: %+v", response)
	}
}

func b29E1Invalid(t *testing.T, response activeEngagementWireResponse) {
	t.Helper()
	if response.Status != "ERROR" || response.Version != 1 || response.ErrorCode != "ACTIVE_ENGAGEMENT_INVALID_REQUEST" || response.Data != nil {
		t.Fatalf("invalid engagement did not receive fixed private refusal: %+v", response)
	}
}

func TestB29E1HandlerCanonicalAccountKindsAndDurableRestart(t *testing.T) {
	key, account := b293Account(t, 61)
	_, first := b293Account(t, 62)
	_, second := b293Account(t, 63)
	clock := &b29StoreClock{at: b29StoreMidnight(t, "2026-03-29")}
	store := b29EngagementStore(t, clock)
	for _, transport := range []string{first, second, first} {
		raw := b293Raw(t, b29E1Request(t, key, "2026-W13", account, transport, []string{"active", "chat", "call"}))
		b29E1Ack(t, activeEngagementResponse(raw, transport, store))
	}
	b29EngagementCounts(t, store, "2026-W13", activeEngagementEstimate{Active: 1, Chat: 1, Call: 1, Reciprocal: 1})
	if got := b29StoreDiskEstimate(t, b29StoreDisk(t, store.path), "2026-03-29"); got.Day != 0 {
		t.Fatal("weekly assertion invented daily activity")
	}
	loaded := b29EngagementReload(t, store, clock, true)
	b29EngagementCounts(t, loaded, "2026-W13", activeEngagementEstimate{Active: 1, Chat: 1, Call: 1, Reciprocal: 1})
	groupKey, groupAccount := b293Account(t, 64)
	b29E1Ack(t, activeEngagementResponse(b293Raw(t, b29E1Request(t, groupKey, "2026-W13", groupAccount, first, []string{"active", "group"})), first, loaded))
	b29EngagementCounts(t, loaded, "2026-W13", activeEngagementEstimate{Active: 2, Chat: 1, Call: 1, Group: 1, Reciprocal: 1})
}

func TestB29E1HandlerStrictSchemaKindsProofAndNoMutation(t *testing.T) {
	key, account := b293Account(t, 61)
	_, transport := b293Account(t, 62)
	_, foreign := b293Account(t, 63)
	clock := &b29StoreClock{at: b29StoreMidnight(t, "2026-03-29")}
	store := b29EngagementStore(t, clock)
	valid := b29E1Request(t, key, "2026-W13", account, transport, []string{"active", "chat"})
	raw := b293Raw(t, valid)
	b29E1Ack(t, activeEngagementResponse(raw, transport, store))
	before, err := os.ReadFile(store.path)
	if err != nil {
		t.Fatal(err)
	}
	cases := map[string][]byte{"empty": nil, "null": []byte("null"), "array": []byte("[]"), "trailing": append(bytes.Clone(raw), '{', '}'), "oversize": append(bytes.Clone(raw), bytes.Repeat([]byte(" "), 2049)...)}
	for _, field := range []string{"action", "version", "week", "kinds", "accountPeerId", "signature"} {
		for _, mutation := range []string{"missing", "null", "case-alias", "duplicate"} {
			r := b293Copy(valid)
			switch mutation {
			case "missing":
				delete(r, field)
			case "null":
				r[field] = nil
			case "case-alias":
				delete(r, field)
				r[strings.ToUpper(field[:1])+field[1:]] = valid[field]
			case "duplicate":
				v, _ := json.Marshal(valid[field])
				cases[mutation+field] = []byte(string(raw[:len(raw)-1]) + `,"` + field + `":` + string(v) + `}`)
				continue
			}
			cases[mutation+field] = b293Raw(t, r)
		}
	}
	for _, field := range []string{"pairDigest", "recipientPeerId", "messageId", "groupId", "epoch", "transportPeerId", "reciprocal"} {
		r := b293Copy(valid)
		r[field] = "private-forbidden"
		cases[field] = b293Raw(t, r)
	}
	for name, kinds := range map[string][]string{"empty-kinds": {}, "null-kinds": nil, "missing-active": {"chat"}, "duplicate-kinds": {"active", "chat", "chat"}, "out-of-order": {"active", "group", "call"}, "reciprocal-kind": {"active", "reciprocal"}, "unknown-kind": {"active", "private-pair"}} {
		cases[name] = b293Raw(t, b29E1Request(t, key, "2026-W13", account, transport, kinds))
	}
	for _, week := range []string{"2026-W1", "2026-W54", "2026-W12", "2026-W14", "2026-03-29"} {
		cases[week] = b293Raw(t, b29E1Request(t, key, week, account, transport, []string{"active"}))
	}
	for _, field := range []string{"action", "week", "kinds", "accountPeerId", "signature"} {
		r := b293Copy(valid)
		switch field {
		case "action":
			r[field] = "active_identity_v1"
		case "week":
			r[field] = "2026-W14"
		case "kinds":
			r[field] = []string{"active", "call"}
		case "accountPeerId":
			r[field] = foreign
		case "signature":
			r[field] = valid[field].(string) + "\n"
		}
		cases["unsigned-"+field] = b293Raw(t, r)
	}
	for name, payload := range cases {
		t.Run(name, func(t *testing.T) {
			b29E1Invalid(t, activeEngagementResponse(payload, transport, store))
			if after, err := os.ReadFile(store.path); err != nil || !bytes.Equal(before, after) {
				t.Fatal("rejected assertion mutated durable snapshot")
			}
		})
	}
	b29E1Invalid(t, activeEngagementResponse(raw, foreign, store))
}

func TestB29E1HandlerDisabledAndPrivateStorageErrors(t *testing.T) {
	key, account := b293Account(t, 61)
	_, transport := b293Account(t, 62)
	clock := &b29StoreClock{at: b29StoreMidnight(t, "2026-03-29")}
	raw := b293Raw(t, b29E1Request(t, key, "2026-W13", account, transport, []string{"active"}))
	for _, store := range []*activeIdentityStore{nil, b29NewStore(t, clock)} {
		got := activeEngagementResponse(raw, transport, store)
		if got.Status != "OK" || got.Version != 1 || got.ErrorCode != "" || got.Data == nil || got.Data.Supported || got.Data.Accepted {
			t.Fatalf("disabled extension not typed unsupported: %+v", got)
		}
		b29E1Invalid(t, activeEngagementResponse(raw, account, store))
	}
	store := b29EngagementStore(t, clock)
	b29E1Ack(t, activeEngagementResponse(raw, transport, store))
	write := store.write
	store.write = func(string, []byte) error { return errors.New("private-writer-" + account) }
	response := activeEngagementResponse(raw, transport, store)
	store.write = write
	if response.Status != "ERROR" || response.ErrorCode != "ACTIVE_ENGAGEMENT_STORAGE_UNAVAILABLE" || response.Data != nil {
		t.Fatal("storage failure ACKed or leaked")
	}
	b29E1Ack(t, activeEngagementResponse(raw, transport, store))
	bytesOnDisk, err := os.ReadFile(store.path)
	if err != nil {
		t.Fatal(err)
	}
	for _, private := range []string{account, transport, b29E1Signature(raw)} {
		if bytes.Contains(bytesOnDisk, []byte(private)) {
			t.Fatal("proof identity persisted")
		}
	}
}

func b29E1Signature(raw []byte) string {
	var r map[string]any
	_ = json.Unmarshal(raw, &r)
	s, _ := r["signature"].(string)
	return s
}

func TestB29E1HandlerWaitsForOwnDurableGeneration(t *testing.T) {
	key, account := b293Account(t, 61)
	_, transport := b293Account(t, 62)
	clock := &b29StoreClock{at: b29StoreMidnight(t, "2026-03-29")}
	store := b29EngagementStore(t, clock)
	raw := b293Raw(t, b29E1Request(t, key, "2026-W13", account, transport, []string{"active"}))
	b29E1Ack(t, activeEngagementResponse(raw, transport, store))
	entered, release, finished := make(chan struct{}), make(chan struct{}), make(chan struct{})
	var once sync.Once
	unblock := func() { once.Do(func() { close(release) }) }
	var committed atomic.Bool
	write := store.write
	store.write = func(path string, data []byte) error {
		close(entered)
		select {
		case <-release:
		case <-time.After(3 * time.Second):
			return errors.New("writer barrier timeout")
		}
		err := write(path, data)
		committed.Store(err == nil)
		return err
	}
	t.Cleanup(func() {
		unblock()
		select {
		case <-finished:
			store.write = write
		case <-time.After(3 * time.Second):
			t.Error("handler cleanup did not join")
		}
	})
	type receipt struct {
		response activeEngagementWireResponse
		durable  bool
	}
	result := make(chan receipt, 1)
	go func() {
		defer close(finished)
		r := activeEngagementResponse(raw, transport, store)
		result <- receipt{r, committed.Load()}
	}()
	b29StoreWaitSignal(t, entered, "engagement durable barrier")
	select {
	case <-result:
		t.Fatal("ACK before own durable generation")
	default:
	}
	unblock()
	select {
	case r := <-result:
		b29E1Ack(t, r.response)
		if !r.durable {
			t.Fatal("ACK before writer success")
		}
	case <-time.After(3 * time.Second):
		t.Fatal("handler did not finish")
	}
}

func TestB29E1HandlerAuthenticatedInboxRouteBindsLinkedTransport(t *testing.T) {
	key, account := b293Account(t, 41)
	clock := &b29StoreClock{at: b29StoreMidnight(t, "2026-03-29")}
	store := b29EngagementStore(t, clock)
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
	roundTrip := func(client host.Host, raw []byte) activeEngagementWireResponse {
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
		var decoded activeEngagementWireResponse
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
	firstRequest := b293Raw(t, b29E1Request(t, key, "2026-W13", account, first, []string{"active", "chat"}))
	b29E1Ack(t, roundTrip(env.sender, firstRequest))
	before, err := os.ReadFile(store.path)
	if err != nil {
		t.Fatal(err)
	}
	b29E1Invalid(t, roundTrip(env.recipient, firstRequest))
	if after, err := os.ReadFile(store.path); err != nil || !bytes.Equal(before, after) {
		t.Fatalf("replay on a different authenticated transport mutated aggregate: %v", err)
	}
	b29E1Ack(t, roundTrip(env.recipient, b293Raw(t, b29E1Request(t, key, "2026-W13", account, second, []string{"active", "chat"}))))
	b29EngagementCounts(t, store, "2026-W13", activeEngagementEstimate{Active: 1, Chat: 1, Reciprocal: 1})
}
