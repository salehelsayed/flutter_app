package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	libp2pcrypto "github.com/libp2p/go-libp2p/core/crypto"
	"github.com/redis/go-redis/v9"
)

type callPostExecFailureHook struct {
	mu      sync.Mutex
	armed   bool
	after   bool
	fired   bool
	failure error
}

type callDeadlineCaptureDispatcher struct {
	deadline    time.Time
	observedAt  time.Time
	hasDeadline bool
}

func (d *callDeadlineCaptureDispatcher) DispatchCallWake(
	ctx context.Context,
	_ CallWakeRoute,
	_ CallWakePayload,
) error {
	d.observedAt = time.Now()
	d.deadline, d.hasDeadline = ctx.Deadline()
	return nil
}

func (h *callPostExecFailureHook) arm(after bool) {
	h.mu.Lock()
	h.armed = true
	h.after = after
	h.mu.Unlock()
}

func (h *callPostExecFailureHook) didFire() bool {
	h.mu.Lock()
	defer h.mu.Unlock()
	return h.fired
}

func (h *callPostExecFailureHook) DialHook(next redis.DialHook) redis.DialHook {
	return func(ctx context.Context, network, addr string) (net.Conn, error) {
		return next(ctx, network, addr)
	}
}

func (h *callPostExecFailureHook) ProcessHook(next redis.ProcessHook) redis.ProcessHook {
	return func(ctx context.Context, cmd redis.Cmder) error {
		return next(ctx, cmd)
	}
}

func (h *callPostExecFailureHook) ProcessPipelineHook(next redis.ProcessPipelineHook) redis.ProcessPipelineHook {
	return func(ctx context.Context, cmds []redis.Cmder) error {
		h.mu.Lock()
		armed, after := h.armed, h.after
		if armed {
			h.armed = false
			h.fired = true
		}
		h.mu.Unlock()
		if armed && !after {
			return h.failure
		}
		if err := next(ctx, cmds); err != nil {
			return err
		}
		if armed {
			return h.failure
		}
		return nil
	}
}

func TestVC202CallMailboxEnforcesEventByteAndRateCaps(t *testing.T) {
	now := time.Unix(1_801_000_000, 0).UTC()

	t.Run("64 events", func(t *testing.T) {
		service, _ := callTestService(t, now, nil)
		sender, recipient := callTestPeerID(t), callTestPeerID(t)
		authorizeCallFixture(t, service, now, sender, recipient)
		for i := 1; i <= CallMaxEventsPerCall; i++ {
			_, err := service.Store(context.Background(), sender, CallStoreRequest{
				RecipientDevicePeerID: recipient, CallHandle: callTestHandleA,
				MessageID: callTestRandomID(1_000 + i), Envelope: []byte("e"),
				ExpiresAtMs: now.Add(45 * time.Second).UnixMilli(), WakeHandle: callTestWake,
			})
			if err != nil {
				t.Fatalf("event %d: %v", i, err)
			}
		}
		_, err := service.Store(context.Background(), sender, CallStoreRequest{
			RecipientDevicePeerID: recipient, CallHandle: callTestHandleA,
			MessageID: callTestRandomID(2_000), Envelope: []byte("e"),
			ExpiresAtMs: now.Add(45 * time.Second).UnixMilli(), WakeHandle: callTestWake,
		})
		if !errors.Is(err, ErrCallEventCapacity) {
			t.Fatalf("65th event error = %v", err)
		}
	})

	t.Run("256 KiB total", func(t *testing.T) {
		service, _ := callTestService(t, now, nil)
		sender, recipient := callTestPeerID(t), callTestPeerID(t)
		authorizeCallFixture(t, service, now, sender, recipient)
		for i, size := range []int{CallMaxEnvelopeBytes, CallMaxEnvelopeBytes, 64 * 1024} {
			_, err := service.Store(context.Background(), sender, CallStoreRequest{
				RecipientDevicePeerID: recipient, CallHandle: callTestHandleA,
				MessageID: callTestRandomID(3_000 + i), Envelope: bytes.Repeat([]byte("x"), size),
				ExpiresAtMs: now.Add(45 * time.Second).UnixMilli(), WakeHandle: callTestWake,
			})
			if err != nil {
				t.Fatalf("byte segment %d: %v", i, err)
			}
		}
		_, err := service.Store(context.Background(), sender, CallStoreRequest{
			RecipientDevicePeerID: recipient, CallHandle: callTestHandleA,
			MessageID: callTestRandomID(3_100), Envelope: []byte("x"),
			ExpiresAtMs: now.Add(45 * time.Second).UnixMilli(), WakeHandle: callTestWake,
		})
		if !errors.Is(err, ErrCallByteCapacity) {
			t.Fatalf("256 KiB + 1 error = %v", err)
		}
	})

	t.Run("bounded sender rate", func(t *testing.T) {
		service, _ := callTestService(t, now, nil)
		sender, recipient := callTestPeerID(t), callTestPeerID(t)
		authorizeCallFixture(t, service, now, sender, recipient)
		for i := 0; i < callStoreRateLimit; i++ {
			handle := callTestHandleA
			if i >= CallMaxEventsPerCall {
				handle = callTestHandleB
			}
			_, err := service.Store(context.Background(), sender, CallStoreRequest{
				RecipientDevicePeerID: recipient, CallHandle: handle,
				MessageID: callTestRandomID(4_000 + i), Envelope: []byte("e"),
				ExpiresAtMs: now.Add(45 * time.Second).UnixMilli(), WakeHandle: callTestWake,
			})
			if err != nil {
				t.Fatalf("rate fixture event %d: %v", i, err)
			}
		}
		_, err := service.Store(context.Background(), sender, CallStoreRequest{
			RecipientDevicePeerID: recipient, CallHandle: callTestHandleB,
			MessageID: callTestRandomID(9_999), Envelope: []byte("e"),
			ExpiresAtMs: now.Add(45 * time.Second).UnixMilli(), WakeHandle: callTestWake,
		})
		if !errors.Is(err, ErrCallRateLimited) {
			t.Fatalf("rate overflow error = %v", err)
		}
	})
}

func TestVC202PartialAckRetainsExactReplayFactsAndNeverRewakes(t *testing.T) {
	now := time.Unix(1_801_100_000, 0).UTC()
	dispatcher := &callTestWakeDispatcher{}
	service, _ := callTestService(t, now, dispatcher)
	sender, recipient := callTestPeerID(t), callTestPeerID(t)
	authorizeCallFixture(t, service, now, sender, recipient)
	first := CallStoreRequest{
		RecipientDevicePeerID: recipient, CallHandle: callTestHandleA,
		MessageID: callTestMessageA, Envelope: []byte("first-encrypted-event"),
		ExpiresAtMs: now.Add(45 * time.Second).UnixMilli(), WakeHandle: callTestWake,
	}
	second := first
	second.MessageID = callTestMessageB
	second.Envelope = []byte("second-encrypted-event")
	if _, err := service.Store(context.Background(), sender, first); err != nil {
		t.Fatal("store first")
	}
	if _, err := service.Store(context.Background(), sender, second); err != nil {
		t.Fatal("store second")
	}
	if acked, err := service.Ack(context.Background(), recipient, CallAckRequest{
		CallHandle: callTestHandleA, MessageIDs: []string{callTestMessageA},
	}); err != nil || acked != 1 {
		t.Fatalf("partial Ack = (%d, %v)", acked, err)
	}
	duplicate, err := service.Store(context.Background(), sender, first)
	if err != nil || duplicate.StoreStatus != CallStoreStatusDuplicate {
		t.Fatalf("acked exact replay = (%#v, %v)", duplicate, err)
	}
	changed := first
	changed.Envelope = []byte("changed-encrypted-event")
	if _, err := service.Store(context.Background(), sender, changed); !errors.Is(err, ErrCallIdentityConflict) {
		t.Fatalf("acked changed replay error = %v", err)
	}
	result, err := service.Retrieve(context.Background(), recipient, CallRetrieveRequest{CallHandle: callTestHandleA})
	if err != nil || len(result.Events) != 1 || result.Events[0].MessageID != callTestMessageB {
		t.Fatalf("post-ACK pending events = (%#v, %v)", result, err)
	}
	if len(dispatcher.payloads) != 2 {
		t.Fatalf("acked replay dispatched wake; count=%d", len(dispatcher.payloads))
	}
}

func TestVC202CallMailboxRejectsMalformedAttributionAndExpiresAtBoundary(t *testing.T) {
	logicalNow := time.Unix(1_801_200_000, 0).UTC()
	service, _ := callTestService(t, logicalNow, nil)
	sender, otherSender := callTestPeerID(t), callTestPeerID(t)
	recipient, wrongRecipient := callTestPeerID(t), callTestPeerID(t)
	authorizeCallFixture(t, service, logicalNow, sender, recipient)
	base := CallStoreRequest{
		RecipientDevicePeerID: recipient, CallHandle: callTestHandleA,
		MessageID: callTestMessageA, Envelope: []byte("encrypted"),
		ExpiresAtMs: logicalNow.Add(45 * time.Second).UnixMilli(), WakeHandle: callTestWake,
	}
	tests := []struct {
		name    string
		sender  string
		mutate  func(*CallStoreRequest)
		wantErr error
	}{
		{name: "bad sender", sender: "not-a-peer", mutate: func(*CallStoreRequest) {}, wantErr: ErrCallInvalidRequest},
		{name: "bad recipient", sender: sender, mutate: func(r *CallStoreRequest) { r.RecipientDevicePeerID = "bad" }, wantErr: ErrCallInvalidRequest},
		{name: "bad call handle", sender: sender, mutate: func(r *CallStoreRequest) { r.CallHandle = "BAD" }, wantErr: ErrCallInvalidRequest},
		{name: "bad message ID", sender: sender, mutate: func(r *CallStoreRequest) { r.MessageID = "short" }, wantErr: ErrCallInvalidRequest},
		{name: "bad UTF-8", sender: sender, mutate: func(r *CallStoreRequest) { r.Envelope = []byte{0xff} }, wantErr: ErrCallInvalidRequest},
		{name: "already expired", sender: sender, mutate: func(r *CallStoreRequest) { r.ExpiresAtMs = logicalNow.UnixMilli() }, wantErr: ErrCallExpiry},
		{name: "wrong authorized sender", sender: otherSender, mutate: func(*CallStoreRequest) {}, wantErr: ErrCallUnauthorized},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			request := base
			tc.mutate(&request)
			if _, err := service.Store(context.Background(), tc.sender, request); !errors.Is(err, tc.wantErr) {
				t.Fatalf("error = %v, want %v", err, tc.wantErr)
			}
		})
	}
	if _, err := service.Store(context.Background(), sender, base); err != nil {
		t.Fatalf("exact 45-second boundary rejected: %v", err)
	}
	wrong, err := service.Retrieve(context.Background(), wrongRecipient, CallRetrieveRequest{CallHandle: callTestHandleA})
	if err != nil || len(wrong.Events) != 0 {
		t.Fatalf("wrong recipient retrieved event: (%#v, %v)", wrong, err)
	}
	logicalNow = logicalNow.Add(45 * time.Second)
	service.now = func() time.Time { return logicalNow }
	expired, err := service.Retrieve(context.Background(), recipient, CallRetrieveRequest{CallHandle: callTestHandleA})
	if err != nil || len(expired.Events) != 0 {
		t.Fatalf("expired retrieve = (%#v, %v)", expired, err)
	}
}

func TestVC202RetrieveCancelRaceIsAtomic(t *testing.T) {
	now := time.Unix(1_801_300_000, 0).UTC()
	service, _ := callTestService(t, now, nil)
	sender, recipient := callTestPeerID(t), callTestPeerID(t)
	authorizeCallFixture(t, service, now, sender, recipient)
	request := CallStoreRequest{
		RecipientDevicePeerID: recipient, CallHandle: callTestHandleA,
		MessageID: callTestMessageA, Envelope: []byte("race-envelope"),
		ExpiresAtMs: now.Add(45 * time.Second).UnixMilli(), WakeHandle: callTestWake,
	}
	if _, err := service.Store(context.Background(), sender, request); err != nil {
		t.Fatal("store race fixture")
	}
	entered := make(chan struct{})
	release := make(chan struct{})
	var once sync.Once
	service.backend.beforeRetrieveCommit = func() {
		once.Do(func() {
			close(entered)
			<-release
		})
	}
	type retrieveOutcome struct {
		result CallRetrieveResult
		err    error
	}
	done := make(chan retrieveOutcome, 1)
	go func() {
		result, err := service.Retrieve(context.Background(), recipient, CallRetrieveRequest{CallHandle: callTestHandleA})
		done <- retrieveOutcome{result: result, err: err}
	}()
	<-entered
	if err := service.Cancel(context.Background(), sender, CallCancelRequest{
		RecipientDevicePeerID: recipient, CallHandle: callTestHandleA,
	}); err != nil {
		t.Fatalf("cancel race fixture: %v", err)
	}
	close(release)
	outcome := <-done
	if outcome.err != nil || len(outcome.result.Events) != 0 {
		t.Fatalf("cancel-winning retrieve returned payload: (%#v, %v)", outcome.result, outcome.err)
	}
}

func TestVC202WakeOccursOnlyAfterCommitAndNotAfterTerminalState(t *testing.T) {
	now := time.Unix(1_801_400_000, 0).UTC()
	baseRequest := func(recipient string) CallStoreRequest {
		return CallStoreRequest{
			RecipientDevicePeerID: recipient, CallHandle: callTestHandleA,
			MessageID: callTestMessageA, Envelope: []byte("wake-order-envelope"),
			ExpiresAtMs: now.Add(45 * time.Second).UnixMilli(), WakeHandle: callTestWake,
		}
	}

	t.Run("failed commit never dispatches", func(t *testing.T) {
		dispatcher := &callTestWakeDispatcher{}
		service, _ := callTestService(t, now, dispatcher)
		sender, recipient := callTestPeerID(t), callTestPeerID(t)
		authorizeCallFixture(t, service, now, sender, recipient)
		service.backend.beforeStoreCommit = func() error { return errors.New("commit fixture") }
		if _, err := service.Store(context.Background(), sender, baseRequest(recipient)); !errors.Is(err, ErrCallBackendUnavailable) {
			t.Fatalf("failed commit error = %v", err)
		}
		if len(dispatcher.payloads) != 0 {
			t.Fatal("wake dispatched before commit")
		}
	})

	for _, terminal := range []string{"ack", "cancel"} {
		t.Run(terminal+" before wake claim", func(t *testing.T) {
			dispatcher := &callTestWakeDispatcher{}
			service, _ := callTestService(t, now, dispatcher)
			sender, recipient := callTestPeerID(t), callTestPeerID(t)
			authorizeCallFixture(t, service, now, sender, recipient)
			request := baseRequest(recipient)
			entered := make(chan struct{})
			release := make(chan struct{})
			service.beforeWakeClaim = func() { close(entered); <-release }
			done := make(chan error, 1)
			go func() { _, err := service.Store(context.Background(), sender, request); done <- err }()
			<-entered
			var err error
			if terminal == "ack" {
				_, err = service.Ack(context.Background(), recipient, CallAckRequest{
					CallHandle: request.CallHandle, MessageIDs: []string{request.MessageID},
				})
			} else {
				err = service.Cancel(context.Background(), sender, CallCancelRequest{
					RecipientDevicePeerID: recipient, CallHandle: request.CallHandle,
				})
			}
			if err != nil {
				t.Fatalf("terminal action: %v", err)
			}
			close(release)
			if err := <-done; err != nil {
				t.Fatalf("committed store returned error: %v", err)
			}
			if len(dispatcher.payloads) != 0 {
				t.Fatalf("wake dispatched after %s", terminal)
			}
		})
	}

	t.Run("expiry before wake claim", func(t *testing.T) {
		logicalNow := now
		dispatcher := &callTestWakeDispatcher{}
		service, _ := callTestService(t, logicalNow, dispatcher)
		service.now = func() time.Time { return logicalNow }
		sender, recipient := callTestPeerID(t), callTestPeerID(t)
		authorizeCallFixture(t, service, logicalNow, sender, recipient)
		service.beforeWakeClaim = func() { logicalNow = logicalNow.Add(45 * time.Second) }
		if _, err := service.Store(context.Background(), sender, baseRequest(recipient)); err != nil {
			t.Fatalf("committed expiring store: %v", err)
		}
		if len(dispatcher.payloads) != 0 {
			t.Fatal("wake dispatched at expiry boundary")
		}
	})

	t.Run("provider failure keeps committed custody and bounded queue", func(t *testing.T) {
		dispatcher := &callTestWakeDispatcher{err: ErrCallBackendUnavailable}
		service, _ := callTestService(t, now, dispatcher)
		sender, recipient := callTestPeerID(t), callTestPeerID(t)
		authorizeCallFixture(t, service, now, sender, recipient)
		if _, err := service.Store(context.Background(), sender, baseRequest(recipient)); err != nil {
			t.Fatalf("store with provider outage: %v", err)
		}
		result, err := service.Retrieve(context.Background(), recipient, CallRetrieveRequest{CallHandle: callTestHandleA})
		if err != nil || len(result.Events) != 1 || len(dispatcher.payloads) != 1 {
			t.Fatalf("provider outage custody = (%#v, %v), dispatches=%d", result, err, len(dispatcher.payloads))
		}
	})
}

func TestVC202PostCommitWakeRedisErrorsRetainReceiptAndRetryUnfinishedWake(t *testing.T) {
	now := time.Unix(1_801_450_000, 0).UTC()
	for _, failurePoint := range []string{"claim", "current"} {
		t.Run(failurePoint, func(t *testing.T) {
			dispatcher := &callTestWakeDispatcher{}
			service, server := callTestService(t, now, dispatcher)
			sender, recipient := callTestPeerID(t), callTestPeerID(t)
			authorizeCallFixture(t, service, now, sender, recipient)
			request := CallStoreRequest{
				RecipientDevicePeerID: recipient, CallHandle: callTestHandleA,
				MessageID: callTestMessageA, Envelope: []byte("post-commit-wake-outage"),
				ExpiresAtMs: now.Add(45 * time.Second).UnixMilli(), WakeHandle: callTestWake,
			}
			if failurePoint == "claim" {
				service.beforeWakeClaim = server.Close
			} else {
				service.beforeWakeCurrent = server.Close
			}

			receipt, firstErr := service.Store(context.Background(), sender, request)
			if err := server.Restart(); err != nil {
				t.Fatalf("restart Redis: %v", err)
			}
			service.beforeWakeClaim = nil
			service.beforeWakeCurrent = nil
			duplicate, retryErr := service.Store(context.Background(), sender, request)
			secondDuplicate, secondRetryErr := service.Store(context.Background(), sender, request)

			if receipt.StoreStatus != CallStoreStatusStored || receipt.ReceiptAtMs != now.UnixMilli() {
				t.Fatalf("committed receipt lost at %s error: %#v", failurePoint, receipt)
			}
			if !errors.Is(firstErr, ErrCallBackendUnavailable) {
				t.Fatalf("%s Redis error = %v, want backend unavailable", failurePoint, firstErr)
			}
			if retryErr != nil || duplicate.StoreStatus != CallStoreStatusDuplicate {
				t.Fatalf("unfinished wake retry = (%#v, %v)", duplicate, retryErr)
			}
			if secondRetryErr != nil || secondDuplicate.StoreStatus != CallStoreStatusDuplicate {
				t.Fatalf("completed wake duplicate = (%#v, %v)", secondDuplicate, secondRetryErr)
			}
			if len(dispatcher.payloads) != 1 {
				t.Fatalf("wake dispatches after retry = %d, want exactly 1", len(dispatcher.payloads))
			}
			result, err := service.Retrieve(context.Background(), recipient, CallRetrieveRequest{CallHandle: request.CallHandle})
			if err != nil || len(result.Events) != 1 {
				t.Fatalf("committed custody after wake outage = (%#v, %v)", result, err)
			}
		})
	}
}

func TestVC202AmbiguousWakeTransactionsRecoverOnceWithoutPermanentSuppression(t *testing.T) {
	baseNow := time.Unix(1_801_460_000, 0).UTC()
	tests := []struct {
		name                   string
		arm                    func(*CallControlService, *callTestWakeDispatcher, *callPostExecFailureHook)
		wantStateAfterFailure  string
		wantDispatchesAfterOne int
	}{
		{
			name: "WakeCurrent post-EXEC reply loss",
			arm: func(service *CallControlService, _ *callTestWakeDispatcher, hook *callPostExecFailureHook) {
				service.beforeWakeCurrent = func() { hook.arm(true) }
			},
			wantStateAfterFailure:  redisCallWakeDispatching,
			wantDispatchesAfterOne: 1,
		},
		{
			name: "AuthorizeWakeDispatch pre-EXEC failure",
			arm: func(service *CallControlService, _ *callTestWakeDispatcher, hook *callPostExecFailureHook) {
				var once sync.Once
				service.afterWakeDispatchOwned = func() { once.Do(func() { hook.arm(false) }) }
			},
			wantStateAfterFailure:  redisCallWakeDispatching,
			wantDispatchesAfterOne: 1,
		},
		{
			name: "AuthorizeWakeDispatch post-EXEC reply loss",
			arm: func(service *CallControlService, _ *callTestWakeDispatcher, hook *callPostExecFailureHook) {
				var once sync.Once
				service.afterWakeDispatchOwned = func() { once.Do(func() { hook.arm(true) }) }
			},
			wantStateAfterFailure:  redisCallWakeDispatching,
			wantDispatchesAfterOne: 1,
		},
		{
			name: "CompleteWake pre-EXEC failure",
			arm: func(_ *CallControlService, dispatcher *callTestWakeDispatcher, hook *callPostExecFailureHook) {
				var once sync.Once
				dispatcher.onDispatch = func() { once.Do(func() { hook.arm(false) }) }
			},
			wantStateAfterFailure:  redisCallWakeDispatching,
			wantDispatchesAfterOne: 2,
		},
		{
			name: "CompleteWake post-EXEC reply loss",
			arm: func(_ *CallControlService, dispatcher *callTestWakeDispatcher, hook *callPostExecFailureHook) {
				var once sync.Once
				dispatcher.onDispatch = func() { once.Do(func() { hook.arm(true) }) }
			},
			wantStateAfterFailure:  redisCallWakeCompleted,
			wantDispatchesAfterOne: 1,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			logicalNow := baseNow
			dispatcher := &callTestWakeDispatcher{}
			service, _ := callTestService(t, logicalNow, dispatcher)
			service.now = func() time.Time { return logicalNow }
			hook := &callPostExecFailureHook{failure: errors.New("ambiguous EXEC fixture")}
			service.backend.client.AddHook(hook)
			sender, recipient := callTestPeerID(t), callTestPeerID(t)
			authorizeCallFixture(t, service, logicalNow, sender, recipient)
			request := CallStoreRequest{
				RecipientDevicePeerID: recipient, CallHandle: callTestHandleA,
				MessageID: callTestMessageA, Envelope: []byte("ambiguous-wake-transaction"),
				ExpiresAtMs: logicalNow.Add(45 * time.Second).UnixMilli(), WakeHandle: callTestWake,
			}
			test.arm(service, dispatcher, hook)

			receipt, firstErr := service.Store(context.Background(), sender, request)
			if receipt.StoreStatus != CallStoreStatusStored || !errors.Is(firstErr, ErrCallBackendUnavailable) {
				t.Fatalf("ambiguous first store = (%#v, %v)", receipt, firstErr)
			}
			if !hook.didFire() {
				t.Fatal("EXEC failure hook did not fire")
			}
			claimRaw, err := service.backend.client.HGet(
				context.Background(), service.backend.callKeys(recipient, request.CallHandle).claims, request.MessageID,
			).Result()
			if err != nil {
				t.Fatalf("read wake claim after ambiguity: %v", err)
			}
			claim, err := decodeRedisCallWakeClaim(claimRaw)
			if err != nil || claim.State != test.wantStateAfterFailure {
				t.Fatalf("wake claim after ambiguity = (%#v, %v), want %q", claim, err, test.wantStateAfterFailure)
			}

			service.beforeWakeCurrent = nil
			logicalNow = logicalNow.Add(10 * time.Second)
			duplicate, retryErr := service.Store(context.Background(), sender, request)
			if retryErr != nil || duplicate.StoreStatus != CallStoreStatusDuplicate {
				t.Fatalf("recovering exact duplicate = (%#v, %v)", duplicate, retryErr)
			}
			if len(dispatcher.payloads) != test.wantDispatchesAfterOne {
				t.Fatalf("dispatches after recovery = %d, want %d", len(dispatcher.payloads), test.wantDispatchesAfterOne)
			}
			for retry := 0; retry < 4; retry++ {
				logicalNow = logicalNow.Add(time.Second)
				duplicate, retryErr = service.Store(context.Background(), sender, request)
				if retryErr != nil || duplicate.StoreStatus != CallStoreStatusDuplicate {
					t.Fatalf("completed duplicate %d = (%#v, %v)", retry, duplicate, retryErr)
				}
			}
			if len(dispatcher.payloads) != test.wantDispatchesAfterOne {
				t.Fatalf("unbounded recovery dispatches = %d, want %d", len(dispatcher.payloads), test.wantDispatchesAfterOne)
			}
		})
	}
}

func TestVC202WakeRecoveryIsAttemptBoundedAndTerminallyCleaned(t *testing.T) {
	logicalNow := time.Unix(1_801_465_000, 0).UTC()
	dispatcher := &callTestWakeDispatcher{}
	service, _ := callTestService(t, logicalNow, dispatcher)
	service.now = func() time.Time { return logicalNow }
	hook := &callPostExecFailureHook{failure: errors.New("CompleteWake unavailable fixture")}
	service.backend.client.AddHook(hook)
	dispatcher.onDispatch = func() { hook.arm(false) }
	sender, recipient := callTestPeerID(t), callTestPeerID(t)
	authorizeCallFixture(t, service, logicalNow, sender, recipient)
	request := CallStoreRequest{
		RecipientDevicePeerID: recipient, CallHandle: callTestHandleA,
		MessageID: callTestMessageA, Envelope: []byte("bounded-wake-recovery"),
		ExpiresAtMs: logicalNow.Add(45 * time.Second).UnixMilli(), WakeHandle: callTestWake,
	}

	receipt, err := service.Store(context.Background(), sender, request)
	if receipt.StoreStatus != CallStoreStatusStored || !errors.Is(err, ErrCallBackendUnavailable) || len(dispatcher.payloads) != 1 {
		t.Fatalf("first ambiguous dispatch = (%#v, %v), dispatches=%d", receipt, err, len(dispatcher.payloads))
	}
	if duplicate, retryErr := service.Store(context.Background(), sender, request); duplicate.StoreStatus != CallStoreStatusDuplicate ||
		!errors.Is(retryErr, ErrCallBackendUnavailable) || len(dispatcher.payloads) != 1 {
		t.Fatalf("live-lease duplicate = (%#v, %v), dispatches=%d", duplicate, retryErr, len(dispatcher.payloads))
	}

	logicalNow = logicalNow.Add(10 * time.Second)
	if duplicate, retryErr := service.Store(context.Background(), sender, request); duplicate.StoreStatus != CallStoreStatusDuplicate ||
		!errors.Is(retryErr, ErrCallBackendUnavailable) || len(dispatcher.payloads) != 2 {
		t.Fatalf("leased recovery dispatch = (%#v, %v), dispatches=%d", duplicate, retryErr, len(dispatcher.payloads))
	}
	if duplicate, retryErr := service.Store(context.Background(), sender, request); duplicate.StoreStatus != CallStoreStatusDuplicate ||
		!errors.Is(retryErr, ErrCallBackendUnavailable) || len(dispatcher.payloads) != 2 {
		t.Fatalf("second live-lease duplicate = (%#v, %v), dispatches=%d", duplicate, retryErr, len(dispatcher.payloads))
	}

	logicalNow = logicalNow.Add(10 * time.Second)
	duplicate, retryErr := service.Store(context.Background(), sender, request)
	if retryErr != nil || duplicate.StoreStatus != CallStoreStatusDuplicate || len(dispatcher.payloads) != 2 {
		t.Fatalf("exhausted bounded recovery = (%#v, %v), dispatches=%d", duplicate, retryErr, len(dispatcher.payloads))
	}
	if acked, ackErr := service.Ack(context.Background(), recipient, CallAckRequest{
		CallHandle: request.CallHandle, MessageIDs: []string{request.MessageID},
	}); ackErr != nil || acked != 1 {
		t.Fatalf("ACK after bounded recovery exhaustion = (%d, %v)", acked, ackErr)
	}
	keys := service.backend.callKeys(recipient, request.CallHandle)
	assertCallMailboxDrained(t, service, keys, request.CallHandle)
	if tombstone, tombErr := service.backend.client.Exists(context.Background(), keys.tombstone).Result(); tombErr != nil || tombstone != 1 {
		t.Fatalf("terminal cleanup tombstone = (%d, %v)", tombstone, tombErr)
	}
}

func TestVC202ExpiredWakeOwnerCannotDispatchAfterRecoveryTerminalizes(t *testing.T) {
	logicalNow := time.Unix(1_801_467_500, 0).UTC()
	dispatcher := &callTestWakeDispatcher{}
	service, _ := callTestService(t, logicalNow, dispatcher)
	service.now = func() time.Time { return logicalNow }
	sender, recipient := callTestPeerID(t), callTestPeerID(t)
	authorizeCallFixture(t, service, logicalNow, sender, recipient)
	request := CallStoreRequest{
		RecipientDevicePeerID: recipient, CallHandle: callTestHandleA,
		MessageID: callTestMessageA, Envelope: []byte("fenced-wake-owner"),
		ExpiresAtMs: logicalNow.Add(45 * time.Second).UnixMilli(), WakeHandle: callTestWake,
	}

	entered := make(chan struct{})
	release := make(chan struct{})
	var hookMu sync.Mutex
	hookCalls := 0
	service.beforeWakeDispatch = func() {
		hookMu.Lock()
		hookCalls++
		first := hookCalls == 1
		hookMu.Unlock()
		if first {
			close(entered)
			<-release
		}
	}
	type storeOutcome struct {
		receipt CallStoreReceipt
		err     error
	}
	firstDone := make(chan storeOutcome, 1)
	go func() {
		receipt, err := service.Store(context.Background(), sender, request)
		firstDone <- storeOutcome{receipt: receipt, err: err}
	}()
	<-entered

	logicalNow = logicalNow.Add(10 * time.Second)
	duplicate, err := service.Store(context.Background(), sender, request)
	if err != nil || duplicate.StoreStatus != CallStoreStatusDuplicate || len(dispatcher.payloads) != 1 {
		t.Fatalf("recovery owner store = (%#v, %v), dispatches=%d", duplicate, err, len(dispatcher.payloads))
	}
	if acked, ackErr := service.Ack(context.Background(), recipient, CallAckRequest{
		CallHandle: request.CallHandle, MessageIDs: []string{request.MessageID},
	}); ackErr != nil || acked != 1 {
		t.Fatalf("terminal ACK after recovery dispatch = (%d, %v)", acked, ackErr)
	}

	close(release)
	first := <-firstDone
	if first.err != nil || first.receipt.StoreStatus != CallStoreStatusStored {
		t.Fatalf("expired owner store = (%#v, %v)", first.receipt, first.err)
	}
	if len(dispatcher.payloads) != 1 {
		t.Fatalf("expired owner dispatched after terminal; count=%d", len(dispatcher.payloads))
	}
}

func TestVC202PostRenewalOwnerCannotDispatchAfterTakeoverTerminalizes(t *testing.T) {
	logicalNow := time.Unix(1_801_468_750, 0).UTC()
	dispatcher := &callTestWakeDispatcher{}
	service, _ := callTestService(t, logicalNow, dispatcher)
	service.now = func() time.Time { return logicalNow }
	sender, recipient := callTestPeerID(t), callTestPeerID(t)
	authorizeCallFixture(t, service, logicalNow, sender, recipient)
	request := CallStoreRequest{
		RecipientDevicePeerID: recipient, CallHandle: callTestHandleA,
		MessageID: callTestMessageA, Envelope: []byte("post-renewal-fenced-wake-owner"),
		ExpiresAtMs: logicalNow.Add(45 * time.Second).UnixMilli(), WakeHandle: callTestWake,
	}

	entered := make(chan struct{})
	release := make(chan struct{})
	var hookMu sync.Mutex
	hookCalls := 0
	service.afterWakeDispatchOwned = func() {
		hookMu.Lock()
		hookCalls++
		first := hookCalls == 1
		hookMu.Unlock()
		if first {
			close(entered)
			<-release
		}
	}
	type storeOutcome struct {
		receipt CallStoreReceipt
		err     error
	}
	firstDone := make(chan storeOutcome, 1)
	go func() {
		receipt, err := service.Store(context.Background(), sender, request)
		firstDone <- storeOutcome{receipt: receipt, err: err}
	}()
	<-entered

	logicalNow = logicalNow.Add(10 * time.Second)
	duplicate, err := service.Store(context.Background(), sender, request)
	if err != nil || duplicate.StoreStatus != CallStoreStatusDuplicate || len(dispatcher.payloads) != 1 {
		t.Fatalf("takeover owner store = (%#v, %v), dispatches=%d", duplicate, err, len(dispatcher.payloads))
	}
	if acked, ackErr := service.Ack(context.Background(), recipient, CallAckRequest{
		CallHandle: request.CallHandle, MessageIDs: []string{request.MessageID},
	}); ackErr != nil || acked != 1 {
		t.Fatalf("terminal ACK after takeover dispatch = (%d, %v)", acked, ackErr)
	}

	close(release)
	first := <-firstDone
	if first.err != nil || first.receipt.StoreStatus != CallStoreStatusStored {
		t.Fatalf("post-renewal expired owner store = (%#v, %v)", first.receipt, first.err)
	}
	if len(dispatcher.payloads) != 1 {
		t.Fatalf("post-renewal expired owner dispatched after terminal; count=%d", len(dispatcher.payloads))
	}
}

func TestVC202AuthorizedWakeOwnerBlocksTakeoverTerminalizationUntilProviderReturn(t *testing.T) {
	logicalNow := time.Unix(1_801_469_375, 0).UTC()
	dispatcher := &callTestWakeDispatcher{}
	service, _ := callTestService(t, logicalNow, dispatcher)
	service.now = func() time.Time { return logicalNow }
	sender, recipient := callTestPeerID(t), callTestPeerID(t)
	authorizeCallFixture(t, service, logicalNow, sender, recipient)
	request := CallStoreRequest{
		RecipientDevicePeerID: recipient, CallHandle: callTestHandleA,
		MessageID: callTestMessageA, Envelope: []byte("authorized-wake-owner"),
		ExpiresAtMs: logicalNow.Add(45 * time.Second).UnixMilli(), WakeHandle: callTestWake,
	}

	entered := make(chan struct{})
	release := make(chan struct{})
	var hookMu sync.Mutex
	hookCalls := 0
	service.afterWakeDispatchAuthorized = func() {
		hookMu.Lock()
		hookCalls++
		first := hookCalls == 1
		hookMu.Unlock()
		if first {
			close(entered)
			<-release
		}
	}
	type storeOutcome struct {
		receipt CallStoreReceipt
		err     error
	}
	firstDone := make(chan storeOutcome, 1)
	go func() {
		receipt, err := service.Store(context.Background(), sender, request)
		firstDone <- storeOutcome{receipt: receipt, err: err}
	}()
	<-entered

	logicalNow = logicalNow.Add(10 * time.Second)
	duplicate, takeoverErr := service.Store(context.Background(), sender, request)
	if takeoverErr != nil || duplicate.StoreStatus != CallStoreStatusDuplicate || len(dispatcher.payloads) != 1 {
		t.Fatalf("takeover owner store = (%#v, %v), dispatches=%d", duplicate, takeoverErr, len(dispatcher.payloads))
	}
	claimRaw, err := service.backend.client.HGet(
		context.Background(), service.backend.callKeys(recipient, request.CallHandle).claims, request.MessageID,
	).Result()
	if err != nil {
		t.Fatalf("read retained authorization set: %v", err)
	}
	claim, err := decodeRedisCallWakeClaim(claimRaw)
	if err != nil || claim.State != redisCallWakeDispatching || claim.Attempts != callMaxWakeDispatchAttempts ||
		claim.Owner != "" || len(claim.ActiveOwners) != 1 {
		t.Fatalf("retained authorization set after takeover = (%#v, %v)", claim, err)
	}
	ackedDuring, terminalErr := service.Ack(context.Background(), recipient, CallAckRequest{
		CallHandle: request.CallHandle, MessageIDs: []string{request.MessageID},
	})
	close(release)
	first := <-firstDone

	if ackedDuring != 0 || !errors.Is(terminalErr, ErrCallBackendUnavailable) {
		t.Fatalf(
			"authorized owner did not fence terminal ACK: terminal=(%d, %v), dispatches after terminal=%d",
			ackedDuring, terminalErr, len(dispatcher.payloads),
		)
	}
	if first.err != nil || first.receipt.StoreStatus != CallStoreStatusStored {
		t.Fatalf("authorized owner store = (%#v, %v)", first.receipt, first.err)
	}
	if len(dispatcher.payloads) != 2 {
		t.Fatalf("provider dispatches before terminal retry = %d, want 2", len(dispatcher.payloads))
	}
	if acked, err := service.Ack(context.Background(), recipient, CallAckRequest{
		CallHandle: request.CallHandle, MessageIDs: []string{request.MessageID},
	}); err != nil || acked != 1 {
		t.Fatalf("terminal ACK after all authorized owners returned = (%d, %v)", acked, err)
	}
}

func TestVC202AuthorizedWakeOwnerHardExpiryPreventsProviderEntryAndCleansState(t *testing.T) {
	logicalNow := time.Unix(1_801_469_687, 0).UTC()
	dispatcher := &callTestWakeDispatcher{}
	service, _ := callTestService(t, logicalNow, dispatcher)
	service.now = func() time.Time { return logicalNow }
	sender, recipient := callTestPeerID(t), callTestPeerID(t)
	authorizeCallFixture(t, service, logicalNow, sender, recipient)
	request := CallStoreRequest{
		RecipientDevicePeerID: recipient, CallHandle: callTestHandleA,
		MessageID: callTestMessageA, Envelope: []byte("hard-expiry-authorized-wake-owner"),
		ExpiresAtMs: logicalNow.Add(45 * time.Second).UnixMilli(), WakeHandle: callTestWake,
	}

	entered := make(chan struct{})
	release := make(chan struct{})
	service.afterWakeDispatchAuthorized = func() {
		close(entered)
		<-release
	}
	type storeOutcome struct {
		receipt CallStoreReceipt
		err     error
	}
	done := make(chan storeOutcome, 1)
	go func() {
		receipt, err := service.Store(context.Background(), sender, request)
		done <- storeOutcome{receipt: receipt, err: err}
	}()
	<-entered

	logicalNow = time.UnixMilli(request.ExpiresAtMs)
	if acked, err := service.Ack(context.Background(), recipient, CallAckRequest{
		CallHandle: request.CallHandle, MessageIDs: []string{request.MessageID},
	}); err != nil || acked != 0 {
		t.Fatalf("hard-expiry ACK = (%d, %v)", acked, err)
	}
	keys := service.backend.callKeys(recipient, request.CallHandle)
	if live, err := service.backend.client.Exists(
		context.Background(), keys.meta, keys.events, keys.ids, keys.claims,
	).Result(); err != nil || live != 0 {
		t.Fatalf("hard expiry retained live state = (%d, %v)", live, err)
	}

	close(release)
	outcome := <-done
	if outcome.err != nil || outcome.receipt.StoreStatus != CallStoreStatusStored {
		t.Fatalf("expired authorized owner store = (%#v, %v)", outcome.receipt, outcome.err)
	}
	if len(dispatcher.payloads) != 0 {
		t.Fatalf("authorized owner entered provider after hard expiry; dispatches=%d", len(dispatcher.payloads))
	}
}

func TestVC202ReleaseLastAuthorizedWakeOwnerCompletesAfterTakeover(t *testing.T) {
	for _, terminal := range []string{"ack", "cancel"} {
		t.Run(terminal, func(t *testing.T) {
			logicalNow := time.Unix(1_801_469_765, 0).UTC()
			dispatcher := &callTestWakeDispatcher{}
			service, _ := callTestService(t, logicalNow, dispatcher)
			service.now = func() time.Time { return logicalNow }
			hook := &callPostExecFailureHook{failure: errors.New("stale owner CompleteWake unavailable fixture")}
			service.backend.client.AddHook(hook)
			sender, recipient := callTestPeerID(t), callTestPeerID(t)
			authorizeCallFixture(t, service, logicalNow, sender, recipient)
			request := CallStoreRequest{
				RecipientDevicePeerID: recipient, CallHandle: callTestHandleA,
				MessageID: callTestMessageA, Envelope: []byte("released-last-authorized-wake-owner"),
				ExpiresAtMs: logicalNow.Add(45 * time.Second).UnixMilli(), WakeHandle: callTestWake,
			}

			entered := make(chan struct{})
			release := make(chan struct{})
			var authorizationMu sync.Mutex
			authorizationCalls := 0
			service.afterWakeDispatchAuthorized = func() {
				authorizationMu.Lock()
				authorizationCalls++
				first := authorizationCalls == 1
				authorizationMu.Unlock()
				if first {
					close(entered)
					<-release
				}
			}
			var dispatchMu sync.Mutex
			dispatchCalls := 0
			dispatcher.onDispatch = func() {
				dispatchMu.Lock()
				dispatchCalls++
				staleOwnerDispatch := dispatchCalls == 2
				dispatchMu.Unlock()
				if staleOwnerDispatch {
					hook.arm(false)
				}
			}
			type storeOutcome struct {
				receipt CallStoreReceipt
				err     error
			}
			firstDone := make(chan storeOutcome, 1)
			go func() {
				receipt, err := service.Store(context.Background(), sender, request)
				firstDone <- storeOutcome{receipt: receipt, err: err}
			}()
			<-entered

			logicalNow = logicalNow.Add(10 * time.Second)
			duplicate, takeoverErr := service.Store(context.Background(), sender, request)
			if takeoverErr != nil || duplicate.StoreStatus != CallStoreStatusDuplicate || len(dispatcher.payloads) != 1 {
				t.Fatalf("takeover owner store = (%#v, %v), dispatches=%d", duplicate, takeoverErr, len(dispatcher.payloads))
			}
			claimKey := service.backend.callKeys(recipient, request.CallHandle).claims
			claimRaw, err := service.backend.client.HGet(context.Background(), claimKey, request.MessageID).Result()
			if err != nil {
				t.Fatalf("read retained stale owner authorization: %v", err)
			}
			claim, err := decodeRedisCallWakeClaim(claimRaw)
			if err != nil || claim.State != redisCallWakeDispatching || claim.Owner != "" ||
				len(claim.ActiveOwners) != 1 {
				t.Fatalf("retained stale owner authorization = (%#v, %v)", claim, err)
			}

			close(release)
			first := <-firstDone
			if first.receipt.StoreStatus != CallStoreStatusStored || !errors.Is(first.err, ErrCallBackendUnavailable) ||
				!hook.didFire() || len(dispatcher.payloads) != 2 {
				t.Fatalf("stale owner ambiguous completion = (%#v, %v), hook=%t dispatches=%d", first.receipt, first.err, hook.didFire(), len(dispatcher.payloads))
			}
			claimRaw, err = service.backend.client.HGet(context.Background(), claimKey, request.MessageID).Result()
			if err != nil {
				t.Fatalf("read released stale owner claim: %v", err)
			}
			claim, err = decodeRedisCallWakeClaim(claimRaw)
			if err != nil || claim.State != redisCallWakeCompleted {
				t.Fatalf("released stale owner claim = (%#v, %v), want valid completed claim", claim, err)
			}

			if terminal == "ack" {
				acked, ackErr := service.Ack(context.Background(), recipient, CallAckRequest{
					CallHandle: request.CallHandle, MessageIDs: []string{request.MessageID},
				})
				if ackErr != nil || acked != 1 {
					t.Fatalf("ACK after stale owner release = (%d, %v)", acked, ackErr)
				}
			} else if err := service.Cancel(context.Background(), sender, CallCancelRequest{
				RecipientDevicePeerID: recipient, CallHandle: request.CallHandle,
			}); err != nil {
				t.Fatalf("cancel after stale owner release: %v", err)
			}
			keys := service.backend.callKeys(recipient, request.CallHandle)
			if terminal == "ack" {
				assertCallMailboxDrained(t, service, keys, request.CallHandle)
			} else if live, err := service.backend.client.Exists(
				context.Background(), keys.meta, keys.events, keys.ids, keys.claims,
			).Result(); err != nil || live != 0 {
				t.Fatalf("terminal cleanup after stale owner release = (%d, %v)", live, err)
			}
		})
	}
}

func TestVC202WakeProviderContextUsesHardCallDeadline(t *testing.T) {
	now := time.Now().UTC().Truncate(time.Millisecond)
	dispatcher := &callDeadlineCaptureDispatcher{}
	service, _ := callTestService(t, now, dispatcher)
	sender, recipient := callTestPeerID(t), callTestPeerID(t)
	authorizeCallFixture(t, service, now, sender, recipient)
	clockCalls := 0
	service.now = func() time.Time {
		clockCalls++
		sampled := time.Now().UTC()
		if clockCalls == 4 {
			// Simulate descheduling after the authorization clock sample but
			// before the provider context is created.
			time.Sleep(100 * time.Millisecond)
		}
		return sampled
	}
	request := CallStoreRequest{
		RecipientDevicePeerID: recipient, CallHandle: callTestHandleA,
		MessageID: callTestMessageA, Envelope: []byte("deadline-aware-provider-context"),
		ExpiresAtMs: now.Add(45 * time.Second).UnixMilli(), WakeHandle: callTestWake,
	}
	if _, err := service.Store(context.Background(), sender, request); err != nil {
		t.Fatalf("store with deadline capture: %v", err)
	}
	wantDeadline := time.UnixMilli(request.ExpiresAtMs)
	if !dispatcher.hasDeadline || !dispatcher.deadline.Equal(wantDeadline) {
		t.Fatalf("provider context deadline = (%s, %t), want absolute call expiry %s", dispatcher.deadline, dispatcher.hasDeadline, wantDeadline)
	}
	deadlineWindow := dispatcher.deadline.Sub(dispatcher.observedAt)
	if deadlineWindow <= 0 || deadlineWindow > CallMaxPreconnectTTL {
		t.Fatalf(
			"provider context deadline = (%s, %t), observed window=%s, want within the live call",
			dispatcher.deadline, dispatcher.hasDeadline, deadlineWindow,
		)
	}
}

func TestVC202PartialAckCannotReleaseInFlightWakeDispatch(t *testing.T) {
	now := time.Unix(1_801_470_000, 0).UTC()
	dispatcher := &callTestWakeDispatcher{}
	service, _ := callTestService(t, now, dispatcher)
	sender, recipient := callTestPeerID(t), callTestPeerID(t)
	authorizeCallFixture(t, service, now, sender, recipient)
	first := CallStoreRequest{
		RecipientDevicePeerID: recipient, CallHandle: callTestHandleA,
		MessageID: callTestMessageA, Envelope: []byte("completed-first-event"),
		ExpiresAtMs: now.Add(45 * time.Second).UnixMilli(), WakeHandle: callTestWake,
	}
	second := first
	second.MessageID = callTestMessageB
	second.Envelope = []byte("dispatching-second-event")
	if _, err := service.Store(context.Background(), sender, first); err != nil {
		t.Fatalf("store first event: %v", err)
	}

	entered := make(chan struct{})
	release := make(chan struct{})
	service.beforeWakeDispatch = func() { close(entered); <-release }
	done := make(chan error, 1)
	go func() {
		_, err := service.Store(context.Background(), sender, second)
		done <- err
	}()
	<-entered

	if acked, err := service.Ack(context.Background(), recipient, CallAckRequest{
		CallHandle: first.CallHandle, MessageIDs: []string{second.MessageID},
	}); acked != 0 || !errors.Is(err, ErrCallBackendUnavailable) {
		t.Fatalf("partial ACK of dispatching event = (%d, %v)", acked, err)
	}
	if acked, err := service.Ack(context.Background(), recipient, CallAckRequest{
		CallHandle: first.CallHandle, MessageIDs: []string{first.MessageID, second.MessageID},
	}); acked != 0 || !errors.Is(err, ErrCallBackendUnavailable) {
		t.Fatalf("terminal ACK while event dispatches = (%d, %v)", acked, err)
	}
	result, err := service.Retrieve(context.Background(), recipient, CallRetrieveRequest{CallHandle: first.CallHandle})
	if err != nil || len(result.Events) != 2 {
		t.Fatalf("in-flight ACK changed mailbox = (%#v, %v)", result, err)
	}
	if len(dispatcher.payloads) != 1 {
		t.Fatalf("provider dispatch escaped before guard release; count=%d", len(dispatcher.payloads))
	}

	close(release)
	if err := <-done; err != nil {
		t.Fatalf("second store after dispatch release: %v", err)
	}
	if acked, err := service.Ack(context.Background(), recipient, CallAckRequest{
		CallHandle: first.CallHandle, MessageIDs: []string{first.MessageID, second.MessageID},
	}); err != nil || acked != 2 {
		t.Fatalf("terminal ACK after dispatch completion = (%d, %v)", acked, err)
	}
	if len(dispatcher.payloads) != 2 {
		t.Fatalf("provider dispatch count = %d, want 2 before terminal", len(dispatcher.payloads))
	}
}

func TestVC202WakeDispatchGuardSerializesTerminalState(t *testing.T) {
	now := time.Unix(1_801_475_000, 0).UTC()
	for _, terminal := range []string{"ack", "cancel"} {
		t.Run(terminal, func(t *testing.T) {
			dispatcher := &callTestWakeDispatcher{}
			service, _ := callTestService(t, now, dispatcher)
			sender, recipient := callTestPeerID(t), callTestPeerID(t)
			authorizeCallFixture(t, service, now, sender, recipient)
			request := CallStoreRequest{
				RecipientDevicePeerID: recipient, CallHandle: callTestHandleA,
				MessageID: callTestMessageA, Envelope: []byte("wake-terminal-guard"),
				ExpiresAtMs: now.Add(45 * time.Second).UnixMilli(), WakeHandle: callTestWake,
			}
			entered := make(chan struct{})
			release := make(chan struct{})
			service.beforeWakeDispatch = func() { close(entered); <-release }
			type storeOutcome struct {
				receipt CallStoreReceipt
				err     error
			}
			done := make(chan storeOutcome, 1)
			go func() {
				receipt, err := service.Store(context.Background(), sender, request)
				done <- storeOutcome{receipt: receipt, err: err}
			}()
			<-entered

			var terminalErr error
			if terminal == "ack" {
				_, terminalErr = service.Ack(context.Background(), recipient, CallAckRequest{
					CallHandle: request.CallHandle, MessageIDs: []string{request.MessageID},
				})
			} else {
				terminalErr = service.Cancel(context.Background(), sender, CallCancelRequest{
					RecipientDevicePeerID: recipient, CallHandle: request.CallHandle,
				})
			}
			dispatchedWhileTerminalRan := len(dispatcher.payloads)
			close(release)
			outcome := <-done

			if !errors.Is(terminalErr, ErrCallBackendUnavailable) {
				t.Fatalf("terminal action during dispatch guard error = %v", terminalErr)
			}
			if dispatchedWhileTerminalRan != 0 {
				t.Fatal("provider dispatch escaped before guarded terminal result")
			}
			if outcome.err != nil || outcome.receipt.StoreStatus != CallStoreStatusStored || len(dispatcher.payloads) != 1 {
				t.Fatalf("guarded store = (%#v, %v), dispatches=%d", outcome.receipt, outcome.err, len(dispatcher.payloads))
			}
			if terminal == "ack" {
				acked, err := service.Ack(context.Background(), recipient, CallAckRequest{
					CallHandle: request.CallHandle, MessageIDs: []string{request.MessageID},
				})
				if err != nil || acked != 1 {
					t.Fatalf("ACK after dispatch completion = (%d, %v)", acked, err)
				}
			} else if err := service.Cancel(context.Background(), sender, CallCancelRequest{
				RecipientDevicePeerID: recipient, CallHandle: request.CallHandle,
			}); err != nil {
				t.Fatalf("cancel after dispatch completion: %v", err)
			}
			if len(dispatcher.payloads) != 1 {
				t.Fatalf("terminal retry produced another wake; dispatches=%d", len(dispatcher.payloads))
			}
		})
	}
}

func TestVC202EveryRequiredRedisMutationFailsClosed(t *testing.T) {
	now := time.Now().UTC().Truncate(time.Millisecond)
	server := miniredis.RunT(t)
	client := redis.NewClient(&redis.Options{
		Addr: server.Addr(), MaxRetries: -1,
		DialTimeout: 20 * time.Millisecond, ReadTimeout: 20 * time.Millisecond, WriteTimeout: 20 * time.Millisecond,
	})
	t.Cleanup(func() { _ = client.Close() })
	service := NewCallControlService(newRedisCallControlStore(client, "vc202-outage:"), nil, func() time.Time { return now })
	sender := callTestPeerID(t)
	recipient, recipientKey := callTestPeerIdentity(t)
	authorizeCallFixture(t, service, now, sender, recipient)
	for _, handle := range []string{callTestHandleA, callTestHandleB} {
		if _, err := service.Store(context.Background(), sender, CallStoreRequest{
			RecipientDevicePeerID: recipient, CallHandle: handle, MessageID: callTestMessageA,
			Envelope: []byte("outage-envelope"), ExpiresAtMs: now.Add(45 * time.Second).UnixMilli(),
			WakeHandle: callTestWake,
		}); err != nil {
			t.Fatal("prepare outage call")
		}
	}
	endpoint := signedCallEndpoint(t, recipient, recipient, recipientKey, "android", now.Add(time.Hour), 2, 2)
	server.Close()

	checks := map[string]func() error{
		"store": func() error {
			_, err := service.Store(context.Background(), sender, CallStoreRequest{
				RecipientDevicePeerID: recipient, CallHandle: callTestHandleC,
				MessageID: callTestMessageB, Envelope: []byte("outage-envelope"),
				ExpiresAtMs: now.Add(45 * time.Second).UnixMilli(), WakeHandle: callTestWake,
			})
			return err
		},
		"retrieve receipt write": func() error {
			_, err := service.Retrieve(context.Background(), recipient, CallRetrieveRequest{CallHandle: callTestHandleA})
			return err
		},
		"ack": func() error {
			_, err := service.Ack(context.Background(), recipient, CallAckRequest{CallHandle: callTestHandleA, MessageIDs: []string{callTestMessageA}})
			return err
		},
		"cancel": func() error {
			return service.Cancel(context.Background(), sender, CallCancelRequest{RecipientDevicePeerID: recipient, CallHandle: callTestHandleB})
		},
		"endpoint set":    func() error { return service.SetEndpoint(context.Background(), recipient, endpoint) },
		"endpoint revoke": func() error { return service.RevokeEndpoint(context.Background(), recipient, recipient, 2) },
		"wake set": func() error {
			return service.SetWakeHandle(context.Background(), recipient, CallWakeHandleRecord{AuthorizedSenderPeerID: sender, WakeHandle: callTestHandleC, ExpiresAtMs: now.Add(time.Hour).UnixMilli()})
		},
		"wake revoke": func() error { return service.RevokeWakeHandle(context.Background(), recipient, sender) },
		"token set": func() error {
			return service.SetCallToken(context.Background(), recipient, CallTokenRecord{Kind: CallTokenKindStandard, Platform: "android", Token: "new-token", ExpiresAtMs: now.Add(time.Hour).UnixMilli()})
		},
		"token revoke": func() error { return service.RevokeCallToken(context.Background(), recipient, CallTokenKindStandard) },
	}
	for name, check := range checks {
		t.Run(name, func(t *testing.T) {
			if err := check(); !errors.Is(err, ErrCallBackendUnavailable) {
				t.Fatalf("error = %v, want backend unavailable", err)
			}
		})
	}
}

func TestVC202NilDurableClientFailsClosedWithoutPanicking(t *testing.T) {
	now := time.Now().UTC().Truncate(time.Millisecond)
	service := NewCallControlService(
		newRedisCallControlStore(nil, "vc202-nil-client:"),
		nil,
		func() time.Time { return now },
	)
	sender := callTestPeerID(t)
	account, accountKey := callTestPeerIdentity(t)
	device := callTestPeerID(t)
	endpoint := signedCallEndpoint(
		t, account, device, accountKey, "android", now.Add(time.Hour), 1, 1,
	)
	storeRequest := CallStoreRequest{
		RecipientDevicePeerID: device,
		CallHandle:            callTestHandleA,
		MessageID:             callTestMessageA,
		Envelope:              []byte("encrypted-envelope"),
		ExpiresAtMs:           now.Add(CallMaxPreconnectTTL).UnixMilli(),
		WakeHandle:            callTestWake,
	}

	checks := map[string]func() error{
		"store": func() error {
			_, err := service.Store(context.Background(), sender, storeRequest)
			return err
		},
		"retrieve": func() error {
			_, err := service.Retrieve(context.Background(), device, CallRetrieveRequest{
				CallHandle: callTestHandleA,
			})
			return err
		},
		"ack": func() error {
			_, err := service.Ack(context.Background(), device, CallAckRequest{
				CallHandle: callTestHandleA, MessageIDs: []string{callTestMessageA},
			})
			return err
		},
		"cancel": func() error {
			return service.Cancel(context.Background(), sender, CallCancelRequest{
				RecipientDevicePeerID: device, CallHandle: callTestHandleA,
			})
		},
		"endpoint set": func() error {
			return service.SetEndpoint(context.Background(), device, endpoint)
		},
		"endpoint get": func() error {
			_, err := service.GetEndpoint(context.Background(), sender, account)
			return err
		},
		"endpoint revoke": func() error {
			return service.RevokeEndpoint(context.Background(), device, account, 1)
		},
		"wake set": func() error {
			return service.SetWakeHandle(context.Background(), device, CallWakeHandleRecord{
				AuthorizedSenderPeerID: sender,
				WakeHandle:             callTestWake,
				ExpiresAtMs:            now.Add(time.Hour).UnixMilli(),
			})
		},
		"wake revoke": func() error {
			return service.RevokeWakeHandle(context.Background(), device, sender)
		},
		"token set": func() error {
			return service.SetCallToken(context.Background(), device, CallTokenRecord{
				Kind: CallTokenKindStandard, Platform: "android", Token: "call-token",
				ExpiresAtMs: now.Add(time.Hour).UnixMilli(),
			})
		},
		"token get": func() error {
			_, err := service.GetCallToken(context.Background(), device, CallTokenKindStandard)
			return err
		},
		"token revoke": func() error {
			return service.RevokeCallToken(context.Background(), device, CallTokenKindStandard)
		},
	}
	for name, check := range checks {
		t.Run(name, func(t *testing.T) {
			if err := check(); !errors.Is(err, ErrCallBackendUnavailable) {
				t.Fatalf("error = %v, want backend unavailable", err)
			}
		})
	}
}

func TestVC202EndpointHighWaterSignatureRevocationAndExpiry(t *testing.T) {
	logicalNow := time.Unix(1_801_500_000, 0).UTC()
	service, _ := callTestService(t, logicalNow, nil)
	service.now = func() time.Time { return logicalNow }
	account, accountKey := callTestPeerIdentity(t)
	device := callTestPeerID(t)
	otherDevice, otherKey := callTestPeerIdentity(t)
	requester := callTestPeerID(t)

	initial := signedCallEndpoint(t, account, device, accountKey, "android", logicalNow.Add(time.Second), 8, 13)
	if err := service.SetEndpoint(context.Background(), device, initial); err != nil {
		t.Fatalf("initial endpoint: %v", err)
	}
	forged := initial
	forged.PreferenceEpoch = 9
	forged.RoutingHandle = callTestHandleB
	if err := service.SetEndpoint(context.Background(), device, forged); !errors.Is(err, ErrCallUnauthorized) {
		t.Fatalf("tampered endpoint error = %v", err)
	}
	wrongSignature := signedCallEndpoint(t, account, device, otherKey, "android", logicalNow.Add(time.Hour), 9, 14)
	if err := service.SetEndpoint(context.Background(), device, wrongSignature); !errors.Is(err, ErrCallUnauthorized) {
		t.Fatalf("wrong-key endpoint error = %v", err)
	}
	wrongDevice := signedCallEndpoint(t, account, otherDevice, otherKey, "android", logicalNow.Add(time.Hour), 9, 14)
	if err := service.SetEndpoint(context.Background(), device, wrongDevice); !errors.Is(err, ErrCallInvalidRequest) {
		t.Fatalf("wrong authenticated device error = %v", err)
	}

	logicalNow = logicalNow.Add(2 * time.Second)
	if got, err := service.GetEndpoint(context.Background(), requester, account); err != nil || got != nil {
		t.Fatalf("expired endpoint = (%#v, %v)", got, err)
	}
	rollback := signedCallEndpoint(t, account, device, accountKey, "android", logicalNow.Add(time.Hour), 7, 13)
	if err := service.SetEndpoint(context.Background(), device, rollback); !errors.Is(err, ErrCallStaleEpoch) {
		t.Fatalf("post-expiry rollback error = %v", err)
	}
	current := signedCallEndpoint(t, account, device, accountKey, "android", logicalNow.Add(time.Hour), 9, 14)
	if err := service.SetEndpoint(context.Background(), device, current); err != nil {
		t.Fatalf("current endpoint: %v", err)
	}
	rotatedKeyEpoch := signedCallEndpoint(t, account, device, accountKey, "android", logicalNow.Add(time.Hour), 10, 3)
	if err := service.SetEndpoint(context.Background(), device, rotatedKeyEpoch); err != nil {
		t.Fatalf("higher preference with changed lower device-key epoch: %v", err)
	}
	if err := service.SetEndpoint(context.Background(), device, current); !errors.Is(err, ErrCallStaleEpoch) {
		t.Fatalf("old preference replay after key rotation error = %v", err)
	}
	if err := service.RevokeEndpoint(context.Background(), device, account, 11); err != nil {
		t.Fatalf("RevokeEndpoint: %v", err)
	}
	if got, err := service.GetEndpoint(context.Background(), requester, account); err != nil || got != nil {
		t.Fatalf("revoked endpoint = (%#v, %v)", got, err)
	}
	republish := signedCallEndpoint(t, account, device, accountKey, "android", logicalNow.Add(time.Hour), 11, 3)
	if err := service.SetEndpoint(context.Background(), device, republish); !errors.Is(err, ErrCallStaleEpoch) {
		t.Fatalf("revoked epoch republish error = %v", err)
	}
}

func TestVC202EndpointRevokeCannotLowerTombstoneHighWater(t *testing.T) {
	now := time.Unix(1_801_550_000, 0).UTC()
	service, _ := callTestService(t, now, nil)
	account, accountKey := callTestPeerIdentity(t)
	device := callTestPeerID(t)
	record := signedCallEndpoint(t, account, device, accountKey, "android", now.Add(time.Hour), 10, 4)
	if err := service.SetEndpoint(context.Background(), device, record); err != nil {
		t.Fatalf("set endpoint: %v", err)
	}
	if err := service.RevokeEndpoint(context.Background(), device, account, 12); err != nil {
		t.Fatalf("initial revoke: %v", err)
	}
	if err := service.RevokeEndpoint(context.Background(), device, account, 7); !errors.Is(err, ErrCallStaleEpoch) {
		t.Fatalf("lower repeated revoke error = %v, want stale epoch", err)
	}
	tombEpoch, err := service.backend.client.HGet(
		context.Background(), service.backend.endpointTombstoneKey(account), "preferenceEpoch",
	).Uint64()
	if err != nil || tombEpoch != 12 {
		t.Fatalf("endpoint tombstone high-water = (%d, %v), want 12", tombEpoch, err)
	}
	rollback := signedCallEndpoint(t, account, device, accountKey, "android", now.Add(time.Hour), 11, 4)
	if err := service.SetEndpoint(context.Background(), device, rollback); !errors.Is(err, ErrCallStaleEpoch) {
		t.Fatalf("publish below revoked high-water error = %v", err)
	}
}

func TestVC202WakeDirectoryUsesTypedOpaqueMembersAndExpires(t *testing.T) {
	logicalNow := time.Unix(1_801_575_000, 0).UTC()
	service, server := callTestService(t, logicalNow, nil)
	service.now = func() time.Time { return logicalNow }
	recipient := callTestPeerID(t)
	senders := []string{callTestPeerID(t), callTestPeerID(t), callTestPeerID(t)}
	for index, expiry := range []time.Duration{time.Second, time.Hour} {
		if err := service.SetWakeHandle(context.Background(), recipient, CallWakeHandleRecord{
			AuthorizedSenderPeerID: senders[index], WakeHandle: callTestRandomID(25_000 + index),
			ExpiresAtMs: logicalNow.Add(expiry).UnixMilli(),
		}); err != nil {
			t.Fatalf("set wake handle %d: %v", index, err)
		}
	}
	directory := service.backend.wakeDirectoryKey(recipient)
	if ttl, err := service.backend.client.PTTL(context.Background(), directory).Result(); err != nil || ttl <= 0 || ttl > time.Hour {
		t.Fatalf("wake directory TTL = (%s, %v)", ttl, err)
	}
	server.FastForward(2 * time.Second)
	logicalNow = logicalNow.Add(2 * time.Second)
	if err := service.SetWakeHandle(context.Background(), recipient, CallWakeHandleRecord{
		AuthorizedSenderPeerID: senders[2], WakeHandle: callTestRandomID(25_002),
		ExpiresAtMs: logicalNow.Add(time.Hour).UnixMilli(),
	}); err != nil {
		t.Fatalf("set wake handle after expiry: %v", err)
	}
	members, err := service.backend.client.ZRange(context.Background(), directory, 0, -1).Result()
	if err != nil || len(members) != 2 {
		t.Fatalf("pruned wake directory = (%#v, %v)", members, err)
	}
	for _, member := range members {
		var typed struct {
			Schema       string `json:"schema"`
			Version      int    `json:"version"`
			SenderDigest string `json:"senderDigest"`
		}
		if err := json.Unmarshal([]byte(member), &typed); err != nil ||
			typed.Schema != "mknoon.call_wake_directory.v1" || typed.Version != CallControlVersion ||
			len(typed.SenderDigest) != 64 {
			t.Fatalf("untyped wake directory member %q: (%#v, %v)", member, typed, err)
		}
		for _, sender := range senders {
			if strings.Contains(member, sender) || strings.Contains(member, encodeRedisComponent(sender)) {
				t.Fatalf("wake directory retained sender identity in %q", member)
			}
		}
	}
	server.FastForward(time.Hour + time.Second)
	if exists, err := service.backend.client.Exists(context.Background(), directory).Result(); err != nil || exists != 0 {
		t.Fatalf("wake directory survived final typed record = (%d, %v)", exists, err)
	}
}

func TestVC202WakeRotationTokenRefreshInvalidCleanupAndPlatformBinding(t *testing.T) {
	now := time.Unix(1_801_600_000, 0).UTC()

	t.Run("wake rotation and revoke", func(t *testing.T) {
		service, _ := callTestService(t, now, nil)
		sender, recipient := callTestPeerID(t), callTestPeerID(t)
		authorizeCallFixture(t, service, now, sender, recipient)
		newWake := callTestHandleC
		if err := service.SetWakeHandle(context.Background(), recipient, CallWakeHandleRecord{
			AuthorizedSenderPeerID: sender, WakeHandle: newWake, ExpiresAtMs: now.Add(time.Hour).UnixMilli(),
		}); err != nil {
			t.Fatalf("rotate wake: %v", err)
		}
		request := CallStoreRequest{
			RecipientDevicePeerID: recipient, CallHandle: callTestHandleA,
			MessageID: callTestMessageA, Envelope: []byte("rotated-wake-envelope"),
			ExpiresAtMs: now.Add(45 * time.Second).UnixMilli(), WakeHandle: callTestWake,
		}
		if _, err := service.Store(context.Background(), sender, request); !errors.Is(err, ErrCallUnauthorized) {
			t.Fatalf("old wake after rotation error = %v", err)
		}
		request.WakeHandle = newWake
		if _, err := service.Store(context.Background(), sender, request); err != nil {
			t.Fatalf("new wake rejected: %v", err)
		}
		if err := service.RevokeWakeHandle(context.Background(), recipient, sender); err != nil {
			t.Fatalf("revoke wake: %v", err)
		}
		request.CallHandle = callTestHandleB
		request.MessageID = callTestMessageB
		if _, err := service.Store(context.Background(), sender, request); !errors.Is(err, ErrCallUnauthorized) {
			t.Fatalf("revoked wake error = %v", err)
		}
	})

	t.Run("android never selects VoIP and invalid cleanup is kind-local", func(t *testing.T) {
		dispatcher := &callTestWakeDispatcher{err: ErrCallTokenInvalid}
		service, _ := callTestService(t, now, dispatcher)
		sender, recipient := callTestPeerID(t), callTestPeerID(t)
		authorizeCallFixture(t, service, now, sender, recipient)
		if err := service.SetCallToken(context.Background(), recipient, CallTokenRecord{
			Kind: CallTokenKindStandard, Platform: "android", Token: "refreshed-standard",
			ExpiresAtMs: now.Add(time.Hour).UnixMilli(),
		}); err != nil {
			t.Fatal("refresh standard")
		}
		if err := service.SetCallToken(
			context.Background(), recipient,
			callTestIOSVoIPToken("independent-voip", now.Add(time.Hour), 1),
		); err != nil {
			t.Fatal("set voip")
		}
		if _, err := service.Store(context.Background(), sender, CallStoreRequest{
			RecipientDevicePeerID: recipient, CallHandle: callTestHandleA,
			MessageID: callTestMessageA, Envelope: []byte("token-envelope"),
			ExpiresAtMs: now.Add(45 * time.Second).UnixMilli(), WakeHandle: callTestWake,
		}); err != nil {
			t.Fatalf("store: %v", err)
		}
		if len(dispatcher.routes) != 1 || dispatcher.routes[0].Kind != CallTokenKindStandard ||
			dispatcher.routes[0].Platform != "android" || dispatcher.routes[0].Token != "refreshed-standard" {
			t.Fatalf("android route = %#v", dispatcher.routes)
		}
		standard, err := service.GetCallToken(context.Background(), recipient, CallTokenKindStandard)
		if err != nil || standard != nil {
			t.Fatalf("invalid standard token survived cleanup: (%#v, %v)", standard, err)
		}
		voip, err := service.GetCallToken(context.Background(), recipient, CallTokenKindIOSVoIP)
		if err != nil || voip == nil || voip.Token != "independent-voip" {
			t.Fatalf("standard cleanup overwrote VoIP token: (%#v, %v)", voip, err)
		}
	})

	t.Run("ios requires VoIP and never falls back to standard", func(t *testing.T) {
		dispatcher := &callTestWakeDispatcher{}
		service, _ := callTestService(t, now, dispatcher)
		sender, recipient := callTestPeerID(t), callTestPeerID(t)
		authorizeCallFixture(t, service, now, sender, recipient)
		if err := service.backend.SetEndpoint(context.Background(), CallEndpointRecord{
			Schema: CallEndpointSchema, Version: CallControlVersion,
			AccountPeerID: recipient, DevicePeerID: recipient,
			Capabilities: []string{"voice_call_v1"}, Platform: "ios",
			ExpiresAtMs: now.Add(time.Hour).UnixMilli(), PreferenceEpoch: 2,
			DeviceKeyEpoch: 2, RoutingHandle: callTestHandleB, Signature: []byte("fixture"),
		}, now); err != nil {
			t.Fatal("set iOS endpoint fixture")
		}
		if _, err := service.Store(context.Background(), sender, CallStoreRequest{
			RecipientDevicePeerID: recipient, CallHandle: callTestHandleA,
			MessageID: callTestMessageA, Envelope: []byte("ios-no-fallback"),
			ExpiresAtMs: now.Add(45 * time.Second).UnixMilli(), WakeHandle: callTestWake,
		}); err != nil {
			t.Fatal("store without VoIP token")
		}
		if len(dispatcher.routes) != 0 {
			t.Fatal("iOS endpoint fell back to standard token")
		}
	})
}

func TestVC202InvalidTokenCleanupFailsClosedAfterMailboxCommit(t *testing.T) {
	now := time.Unix(1_801_650_000, 0).UTC()
	dispatcher := &callTestWakeDispatcher{err: ErrCallTokenInvalid}
	service, server := callTestService(t, now, dispatcher)
	sender, recipient := callTestPeerID(t), callTestPeerID(t)
	authorizeCallFixture(t, service, now, sender, recipient)
	dispatcher.onDispatch = server.Close

	receipt, err := service.Store(context.Background(), sender, CallStoreRequest{
		RecipientDevicePeerID: recipient, CallHandle: callTestHandleA,
		MessageID: callTestMessageA, Envelope: []byte("committed-before-invalid-token-cleanup"),
		ExpiresAtMs: now.Add(45 * time.Second).UnixMilli(), WakeHandle: callTestWake,
	})
	if receipt.StoreStatus != CallStoreStatusStored || receipt.ReceiptAtMs != now.UnixMilli() {
		t.Fatalf("committed mailbox receipt was discarded: %#v", receipt)
	}
	if !errors.Is(err, ErrCallBackendUnavailable) {
		t.Fatalf("invalid-token cleanup outage error = %v, want backend unavailable", err)
	}
}

func TestVC202ProductionDispatcherNeverUsesOrdinaryPushForIOSVoIP(t *testing.T) {
	push := NewPushServiceWithBackend(newMemoryPushTokenStore())
	recorder := newRecordingPushSender()
	push.sender = recorder.Send
	dispatcher := pushServiceCallWakeDispatcher{push: push}
	route := CallWakeRoute{
		Kind: CallTokenKindIOSVoIP, Platform: "ios", Token: "raw-pushkit-token",
	}
	payload := CallWakePayload{
		CallHandle: callTestHandleA, WakeHandle: callTestWake,
		ExpiresAtMs: time.Now().Add(45 * time.Second).UnixMilli(),
	}

	if message, err := buildCallWakeMessage(route, payload); message != nil || !errors.Is(err, ErrCallBackendUnavailable) {
		t.Fatalf("iOS ordinary push message = (%#v, %v), want unavailable", message, err)
	}
	if err := dispatcher.DispatchCallWake(context.Background(), route, payload); !errors.Is(err, ErrCallBackendUnavailable) {
		t.Fatalf("iOS production dispatch error = %v, want unavailable", err)
	}
	if calls := recorder.SendCallCount(); calls != 0 {
		t.Fatalf("iOS VoIP route invoked ordinary PushService.send %d time(s)", calls)
	}
}

func TestVC202TombstonesArePayloadFreeBoundedAndPrivacySourcesHaveNoSensitiveLabels(t *testing.T) {
	now := time.Unix(1_801_700_000, 0).UTC()
	service, server := callTestService(t, now, nil)
	server.SetTime(now)
	sender, recipient := callTestPeerID(t), callTestPeerID(t)
	authorizeCallFixture(t, service, now, sender, recipient)
	ctx := context.Background()
	for i := 0; i < 10; i++ {
		handle := callTestRandomID(20_000 + i)
		messageID := callTestRandomID(21_000 + i)
		envelope := fmt.Sprintf("unique-tombstone-payload-%d", i)
		if _, err := service.Store(ctx, sender, CallStoreRequest{
			RecipientDevicePeerID: recipient, CallHandle: handle, MessageID: messageID,
			Envelope: []byte(envelope), ExpiresAtMs: now.Add(45 * time.Second).UnixMilli(),
			WakeHandle: callTestWake,
		}); err != nil {
			t.Fatalf("store tombstone %d: %v", i, err)
		}
		if _, err := service.Ack(ctx, recipient, CallAckRequest{CallHandle: handle, MessageIDs: []string{messageID}}); err != nil {
			t.Fatalf("ack tombstone %d: %v", i, err)
		}
	}
	keys, err := service.backend.client.Keys(ctx, "vc202:call:v1:mailbox:*:call:*:tombstone").Result()
	if err != nil || len(keys) != 10 {
		t.Fatalf("tombstone keys = (%d, %v)", len(keys), err)
	}
	for _, key := range keys {
		// A drained mailbox stays open until the call expires; its tombstone
		// then guards replays for the tombstone TTL on top of that.
		ttl, err := service.backend.client.PTTL(ctx, key).Result()
		if err != nil || ttl <= 0 || ttl > CallMaxPreconnectTTL+CallReplayTombstoneTTL {
			t.Fatalf("tombstone TTL = (%s, %v)", ttl, err)
		}
		fields, err := service.backend.client.HGetAll(ctx, key).Result()
		if err != nil {
			t.Fatal("read tombstone")
		}
		raw, _ := json.Marshal(fields)
		if bytes.Contains(raw, []byte("unique-tombstone-payload")) || bytes.Contains(raw, []byte("envelope")) {
			t.Fatalf("tombstone retained payload: %s", raw)
		}
	}

	for _, path := range []string{"call_control.go", "call_control_redis.go", "call_control_handler.go", "call_wake.go"} {
		raw, err := os.ReadFile(path)
		if err != nil {
			t.Fatalf("read %s: %v", path, err)
		}
		for _, forbidden := range []string{"log.", "WithLabelValues("} {
			if strings.Contains(string(raw), forbidden) {
				t.Fatalf("%s contains privacy-sensitive log/metric-label surface %q", path, forbidden)
			}
		}
	}
}

func TestVC202TerminalTombstonesHaveHardPerRecipientCapacity(t *testing.T) {
	now := time.Unix(1_801_750_000, 0).UTC()
	service, _ := callTestService(t, now, nil)
	recipient := callTestPeerID(t)
	senderCount := (callMaxTerminalTombstonesPerRecipient + callStoreRateLimit - 1) / callStoreRateLimit
	senders := make([]string, senderCount)
	for i := range senders {
		senders[i] = callTestPeerID(t)
		if err := service.SetWakeHandle(context.Background(), recipient, CallWakeHandleRecord{
			AuthorizedSenderPeerID: senders[i], WakeHandle: callTestWake,
			ExpiresAtMs: now.Add(time.Hour).UnixMilli(),
		}); err != nil {
			t.Fatalf("authorize sender %d: %v", i, err)
		}
	}
	ctx := context.Background()
	firstRequest := CallStoreRequest{}
	for i := 0; i < callMaxTerminalTombstonesPerRecipient; i++ {
		request := CallStoreRequest{
			RecipientDevicePeerID: recipient,
			CallHandle:            callTestRandomID(30_000 + i),
			MessageID:             callTestRandomID(40_000 + i),
			Envelope:              []byte("capacity-tombstone"),
			ExpiresAtMs:           now.Add(45 * time.Second).UnixMilli(),
			WakeHandle:            callTestWake,
		}
		if i == 0 {
			firstRequest = request
		}
		sender := senders[i/callStoreRateLimit]
		if _, err := service.Store(ctx, sender, request); err != nil {
			t.Fatalf("store reserved tombstone %d: %v", i, err)
		}
		if acked, err := service.Ack(ctx, recipient, CallAckRequest{
			CallHandle: request.CallHandle, MessageIDs: []string{request.MessageID},
		}); err != nil || acked != 1 {
			t.Fatalf("terminalize reserved tombstone %d = (%d, %v)", i, acked, err)
		}
	}
	keys, err := service.backend.client.Keys(ctx, "vc202:call:v1:mailbox:*:call:*:tombstone").Result()
	if err != nil || len(keys) != callMaxTerminalTombstonesPerRecipient {
		t.Fatalf("terminal tombstone cardinality = (%d, %v), want %d", len(keys), err, callMaxTerminalTombstonesPerRecipient)
	}
	overflow := CallStoreRequest{
		RecipientDevicePeerID: recipient,
		CallHandle:            callTestRandomID(50_000),
		MessageID:             callTestRandomID(50_001),
		Envelope:              []byte("must-not-commit-at-capacity"),
		ExpiresAtMs:           now.Add(45 * time.Second).UnixMilli(),
		WakeHandle:            callTestWake,
	}
	if receipt, err := service.Store(ctx, senders[len(senders)-1], overflow); !errors.Is(err, ErrCallRecipientCapacity) || receipt != (CallStoreReceipt{}) {
		t.Fatalf("store beyond tombstone capacity = (%#v, %v)", receipt, err)
	}
	overflowKeys := service.backend.callKeys(recipient, overflow.CallHandle)
	if exists, err := service.backend.client.Exists(ctx, overflowKeys.meta, overflowKeys.events, overflowKeys.ids).Result(); err != nil || exists != 0 {
		t.Fatalf("overflow store committed payload state = (%d, %v)", exists, err)
	}
	if receipt, err := service.Store(ctx, senders[0], firstRequest); err != nil ||
		receipt.StoreStatus != CallStoreStatusDuplicate || receipt.EventCount != 0 {
		t.Fatalf("old duplicate protection weakened at capacity: (%#v, %v)", receipt, err)
	}
}

// assertCallMailboxDrained checks the post-ack shape of a fully drained call
// mailbox: no undelivered events, the handle gone from the recipient's pending
// index, and the remaining call record bounded by the call's own expiry so
// later same-call events (ringing, accept, terminate) are still accepted.
func assertCallMailboxDrained(t *testing.T, service *CallControlService, keys redisCallKeySet, handle string) {
	t.Helper()
	ctx := context.Background()
	if pending, err := service.backend.client.LLen(ctx, keys.events).Result(); err != nil || pending != 0 {
		t.Fatalf("drained mailbox retained events = (%d, %v)", pending, err)
	}
	if err := service.backend.client.ZScore(ctx, keys.handles, handle).Err(); !errors.Is(err, redis.Nil) {
		t.Fatalf("drained handle still pending in recipient index: %v", err)
	}
	// The call record itself stays (bounded by the call expiry set at store
	// time) so later same-call events are still accepted.
	if live, err := service.backend.client.Exists(ctx, keys.meta).Result(); err != nil || live != 1 {
		t.Fatalf("drained call record = (%d, %v), want retained until call expiry", live, err)
	}
}

func signedCallEndpoint(
	t *testing.T,
	account, device string,
	key libp2pcrypto.PrivKey,
	platform string,
	expiresAt time.Time,
	preferenceEpoch, deviceKeyEpoch uint64,
) CallEndpointRecord {
	t.Helper()
	record := CallEndpointRecord{
		AccountPeerID: account, DevicePeerID: device,
		Capabilities: []string{"voice_call_v1"}, Platform: platform,
		ExpiresAtMs: expiresAt.UnixMilli(), PreferenceEpoch: preferenceEpoch,
		DeviceKeyEpoch: deviceKeyEpoch, RoutingHandle: callTestHandleA,
	}
	canonical, err := canonicalCallEndpointRecord(record)
	if err != nil {
		t.Fatal("canonical endpoint fixture")
	}
	record.Signature, err = key.Sign(canonical)
	if err != nil {
		t.Fatal("sign endpoint fixture")
	}
	return record
}

func callTestRandomID(value int) string {
	return fmt.Sprintf("%032x", value)
}
