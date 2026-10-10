package main

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/redis/go-redis/v9"
)

func TestCallFailureClassSurvivesRedisErrorMapping(t *testing.T) {
	for _, tc := range []struct {
		in   error
		want string
	}{
		{errCallWakeInFlight, callFailureWakeInFlight},
		{redis.TxFailedErr, callFailureTxConflict},
		{context.DeadlineExceeded, callFailureDeadline},
		{ErrCallBackendUnavailable, callFailureUnavailable},
		{errors.New("dial tcp: private-host refused"), callFailureOther},
	} {
		mapped := callRedisError(tc.in)
		if !errors.Is(mapped, ErrCallBackendUnavailable) {
			t.Fatalf("callRedisError(%v) = %v, want backend unavailable", tc.in, mapped)
		}
		if got := callFailureClass(mapped); got != tc.want {
			t.Fatalf("class of %v = %q, want %q", tc.in, got, tc.want)
		}
		raw, err := json.Marshal(callControlErrorResponse(mapped))
		if err != nil || string(raw) != `{"status":"ERROR","errorCode":"CALL_BACKEND_UNAVAILABLE"}` {
			t.Fatalf("wire response changed: %s, %v", raw, err)
		}
	}
	if callRedisError(ErrCallStaleEpoch) != ErrCallStaleEpoch {
		t.Fatal("mapped sentinels must stay unchanged")
	}
}

func TestAndroidCallWakeFailureKeepsFixedFirebaseClass(t *testing.T) {
	route := CallWakeRoute{Kind: CallTokenKindStandard, Platform: "android", Token: "android-call-token-fixture"}
	payload := CallWakePayload{
		CallHandle: callTestHandleA, WakeHandle: callTestWake,
		ExpiresAtMs: time.Now().Add(45 * time.Second).UnixMilli(),
	}
	for _, tc := range []struct {
		sendErr  error
		sentinel error
		class    string
	}{
		{errors.New("Requested entity was not found."), ErrCallTokenInvalid, "fcm_literal_entity_not_found"},
		{errors.New("private transient provider text"), ErrCallBackendUnavailable, "fcm_other"},
	} {
		push := NewPushServiceWithBackend(newMemoryPushTokenStore())
		push.retryDelays = []time.Duration{0, 0}
		recorder := newRecordingPushSender()
		recorder.err = tc.sendErr
		push.sender = recorder.Send
		err := pushServiceCallWakeDispatcher{push: push}.DispatchCallWake(context.Background(), route, payload)
		if !errors.Is(err, tc.sentinel) || callFailureClass(err) != tc.class {
			t.Fatalf("dispatch error = %v (class %q), want %v / %q", err, callFailureClass(err), tc.sentinel, tc.class)
		}
	}
}

func TestRefusedAckDuringInFlightWakeLogsFixedReason(t *testing.T) {
	now := time.Now().UTC()
	dispatcher := &callTestWakeDispatcher{}
	service, _ := callTestService(t, now, dispatcher)
	fixture := newCallHandlerFixture(t, service)
	sender, recipient := fixture.client.ID().String(), fixture.recipient.ID().String()
	authorizeCallFixture(t, service, now, sender, recipient)
	entered, release := make(chan struct{}), make(chan struct{})
	service.afterWakeDispatchAuthorized = func() {
		close(entered)
		<-release
	}
	stored := make(chan error, 1)
	go func() {
		_, err := service.Store(context.Background(), sender, CallStoreRequest{
			RecipientDevicePeerID: recipient, CallHandle: callTestHandleA,
			MessageID: callTestMessageA, Envelope: []byte("private-encrypted-envelope"),
			ExpiresAtMs: now.Add(40 * time.Second).UnixMilli(), WakeHandle: callTestWake,
		})
		stored <- err
	}()
	<-entered
	output := captureCallDiagnostics(t)
	response := callHandlerRoundTrip(t, fixture, fixture.recipient, map[string]any{
		"action": callAckAction, "callHandle": callTestHandleA, "messageIds": []string{callTestMessageA},
	})
	close(release)
	if err := <-stored; err != nil {
		t.Fatalf("store: %v", err)
	}
	if response["errorCode"] != "CALL_BACKEND_UNAVAILABLE" || len(response) != 2 {
		t.Fatalf("refused ACK wire response changed: %#v", response)
	}
	lines := callDiagnosticLines(output)
	if len(lines) != 1 || !strings.HasSuffix(lines[0],
		"call_control action=call_ack_v1 outcome=CALL_BACKEND_UNAVAILABLE wake=not_applicable reason=wake_in_flight") {
		t.Fatalf("refused ACK diagnostic = %q", lines)
	}
}
