package main

import (
	"bytes"
	"context"
	"errors"
	"io"
	"log"
	"strings"
	"testing"
	"time"

	"github.com/prometheus/client_golang/prometheus/testutil"
	"github.com/redis/go-redis/v9"
)

func controlledMissingRouteBackend(t *testing.T, kind string) (PushTokenBackend, func(time.Duration)) {
	t.Helper()
	if kind == "memory" {
		backend := newMemoryPushTokenStore()
		now := time.Unix(1_800_000_000, 0)
		backend.absenceNow = func() time.Time { return now }
		return backend, func(duration time.Duration) { now = now.Add(duration) }
	}
	if kind == "redis_legacy" {
		server, backend := plan367RedisBackend(t, "absence-controls:", nil)
		return backend, server.FastForward
	}
	server, backend, _ := plan367NewEncryptedFixture(t, "absence-controls:")
	return backend, server.FastForward
}

func expectMissingObservation(t *testing.T, backend PushTokenBackend, reason, platform string) {
	t.Helper()
	observation := NewPushServiceWithBackend(backend).observeMissingRoute("route-peer")
	if string(observation.reason) != reason || observation.platform != platform {
		t.Fatalf("observation = %q/%q, want %q/%q", observation.reason, observation.platform, reason, platform)
	}
}

func TestPushMissingRouteRetentionAndRegistration(t *testing.T) {
	for _, kind := range []string{"memory", "redis_legacy", "redis_encrypted"} {
		t.Run(kind, func(t *testing.T) {
			backend, advance := controlledMissingRouteBackend(t, kind)
			register := func(token string) pushRouteLease {
				t.Helper()
				if err := backend.RegisterToken("route-peer", token, "ios"); err != nil {
					t.Fatal(err)
				}
				return plan367Route(t, backend, "route-peer")
			}
			leaseA := register("token-a")
			if err := backend.UnregisterToken("route-peer"); err != nil {
				t.Fatal(err)
			}
			expectMissingObservation(t, backend, "unregistered_by_client", "ios")
			leaseB := register("token-b")
			expectMissingObservation(t, backend, "unknown", "unknown")
			if revoked, err := backend.RevokeIfCurrent(leaseA); err != nil || revoked {
				t.Fatalf("stale rejection revoked successor: revoked=%v error=%v", revoked, err)
			}
			if _, err := backend.ResolveRoute(leaseB); err != nil {
				t.Fatalf("successor lost: %v", err)
			}
			if revoked, err := backend.RevokeIfCurrent(leaseB); err != nil || !revoked {
				t.Fatalf("current rejection: revoked=%v error=%v", revoked, err)
			}
			expectMissingObservation(t, backend, "revoked_after_provider_rejection", "ios")
			if original, ok := backend.(*redisPushTokenBackend); ok {
				client := redis.NewClient(original.client.Options())
				t.Cleanup(func() { _ = client.Close() })
				restarted := newRedisPushTokenBackend(client, original.prefix)
				expectMissingObservation(t, restarted, "revoked_after_provider_rejection", "ios")
			}
			advance(time.Hour)
			if err := backend.UnregisterToken("route-peer"); err != nil {
				t.Fatal(err)
			}
			expectMissingObservation(t, backend, "revoked_after_provider_rejection", "ios")
			advance(23*time.Hour + time.Millisecond)
			expectMissingObservation(t, backend, "unknown", "unknown")
			if memory, ok := backend.(*memoryPushTokenStore); ok && len(memory.absences) != 0 {
				t.Fatal("expired in-memory marker was retained")
			}
			leaseC := register("token-c")
			advance(25 * time.Hour)
			if _, err := backend.ResolveRoute(leaseC); err != nil {
				t.Fatalf("diagnostic TTL expired an active registration: %v", err)
			}
		})
	}
}

type suppliedMissingRouteBackend struct {
	PushTokenBackend
	observation missingPushRouteObservation
}

func (backend suppliedMissingRouteBackend) ObserveMissingRoute(string) missingPushRouteObservation {
	return backend.observation
}

func TestPushMissingRouteClosedOutput(t *testing.T) {
	for _, test := range []struct {
		name, reason, platform, wantReason, wantPlatform string
	}{
		{"invalid reason", "private-reason", "ios", "unknown", "unknown"},
		{"invalid platform", "unregistered_by_client", "private-platform", "unregistered_by_client", "unknown"},
		{"canonical ios", "revoked_after_provider_rejection", " iOS ", "revoked_after_provider_rejection", "ios"},
		{"canonical android", "unregistered_by_client", " Android ", "unregistered_by_client", "android"},
	} {
		t.Run(test.name, func(t *testing.T) {
			backend := suppliedMissingRouteBackend{
				PushTokenBackend: newMemoryPushTokenStore(),
				observation:      missingPushRouteObservation{reason: pushMissingRouteReason(test.reason), platform: test.platform},
			}
			journal := &bytes.Buffer{}
			previous := log.Writer()
			log.SetOutput(journal)
			defer log.SetOutput(previous)
			before := missingRouteMetric(t, test.wantReason, test.wantPlatform)
			missingRouteSend(NewPushServiceWithBackend(backend), "direct")
			if !strings.Contains(journal.String(), "missing_route_reason="+test.wantReason) || strings.Contains(journal.String(), "private-") || strings.Contains(journal.String(), "platform=") {
				t.Fatalf("unsafe or incorrect closed record: %q", journal.String())
			}
			if delta := missingRouteMetric(t, test.wantReason, test.wantPlatform) - before; delta != 1 {
				t.Fatalf("closed metric delta = %v", delta)
			}
		})
	}
}

func TestPushMissingRouteCorruptAndUnavailableHistory(t *testing.T) {
	for _, kind := range []string{"redis_legacy", "redis_encrypted"} {
		t.Run(kind, func(t *testing.T) {
			backend := missingRouteBackend(t, kind).(*redisPushTokenBackend)
			for _, corrupt := range []string{"private-material", "unregistered_by_client|private-platform", "revoked_after_provider_rejection|ios|private-material"} {
				if err := backend.client.Set(context.Background(), backend.absenceKey("route-peer"), corrupt, time.Hour).Err(); err != nil {
					t.Fatal(err)
				}
				expectMissingObservation(t, backend, "unknown", "unknown")
			}
			if err := backend.client.Set(context.Background(), backend.absenceKey("route-peer"), "unregistered_by_client|ios", time.Hour).Err(); err != nil {
				t.Fatal(err)
			}
			backend.client.AddHook(&missingRouteReadFailureHook{})
			expectMissingObservation(t, backend, "unknown", "unknown")
		})
	}
}

type missingRouteReadFailureHook struct{}

func (*missingRouteReadFailureHook) DialHook(next redis.DialHook) redis.DialHook { return next }
func (*missingRouteReadFailureHook) ProcessPipelineHook(next redis.ProcessPipelineHook) redis.ProcessPipelineHook {
	return next
}
func (*missingRouteReadFailureHook) ProcessHook(next redis.ProcessHook) redis.ProcessHook {
	return func(ctx context.Context, command redis.Cmder) error {
		if command.Name() == "mget" {
			return errors.New("private diagnostic read failure")
		}
		return next(ctx, command)
	}
}

type missingRouteServerError string

func (err missingRouteServerError) Error() string { return string(err) }
func (missingRouteServerError) RedisError()       {}

type missingRoutePipelineFailureHook struct {
	absenceKey string
	mode       string
	fired      int
	after      func()
}

func (*missingRoutePipelineFailureHook) DialHook(next redis.DialHook) redis.DialHook { return next }
func (*missingRoutePipelineFailureHook) ProcessHook(next redis.ProcessHook) redis.ProcessHook {
	return next
}
func (hook *missingRoutePipelineFailureHook) ProcessPipelineHook(next redis.ProcessPipelineHook) redis.ProcessPipelineHook {
	return func(ctx context.Context, commands []redis.Cmder) error {
		var diagnostic redis.Cmder
		var primary redis.Cmder
		for _, command := range commands {
			args := command.Args()
			if len(args) < 2 {
				continue
			}
			if args[1] == hook.absenceKey {
				diagnostic = command
			} else if command.Name() == "set" || command.Name() == "del" {
				primary = command
			}
		}
		if diagnostic == nil || (hook.fired > 0 && hook.mode != "watch") {
			return next(ctx, commands)
		}
		hook.fired++
		if hook.mode == "watch" {
			return redis.TxFailedErr
		}
		if err := next(ctx, commands); err != nil {
			return err
		}
		if hook.after != nil {
			hook.after()
		}
		var failure error = missingRouteServerError("ERR private diagnostic command failure")
		switch hook.mode {
		case "primary":
			primary.SetErr(failure)
			return failure
		case "execabort":
			failure = missingRouteServerError("EXECABORT private transaction failure")
		case "network":
			failure = io.EOF
		}
		diagnostic.SetErr(failure)
		return failure
	}
}

func TestPushMissingRouteDiagnosticMutationIsolation(t *testing.T) {
	for _, kind := range []string{"redis_legacy", "redis_encrypted"} {
		for _, operation := range []string{"register", "unregister", "revoke"} {
			t.Run(kind+"/"+operation+"/diagnostic only", func(t *testing.T) {
				backend := missingRouteBackend(t, kind).(*redisPushTokenBackend)
				if err := backend.RegisterToken("route-peer", "token-a", "ios"); err != nil {
					t.Fatal(err)
				}
				lease := plan367Route(t, backend, "route-peer")
				hook := &missingRoutePipelineFailureHook{absenceKey: backend.absenceKey("route-peer"), mode: "diagnostic"}
				if operation != "register" {
					hook.after = func() { _ = backend.client.Del(context.Background(), hook.absenceKey).Err() }
				}
				backend.client.AddHook(hook)
				var err error
				switch operation {
				case "register":
					err = backend.RegisterToken("route-peer", "token-b", "ios")
				case "unregister":
					err = backend.UnregisterToken("route-peer")
				case "revoke":
					var revoked bool
					revoked, err = backend.RevokeIfCurrent(lease)
					if !revoked {
						t.Error("successful primary revoke was not acknowledged")
					}
				}
				if err != nil || hook.fired != 1 {
					t.Fatalf("isolated diagnostic error changed primary result: error=%v fired=%d", err, hook.fired)
				}
				route, err := backend.LookupRoute("route-peer")
				if err != nil || (route != nil) != (operation == "register") {
					t.Fatal("primary mutation did not complete")
				}
				if operation != "register" {
					expectMissingObservation(t, backend, "unknown", "unknown")
				}
			})
		}
		for _, mode := range []string{"primary", "execabort", "network", "watch"} {
			t.Run(kind+"/preserve "+mode, func(t *testing.T) {
				backend := missingRouteBackend(t, kind).(*redisPushTokenBackend)
				if err := backend.RegisterToken("route-peer", "token-a", "ios"); err != nil {
					t.Fatal(err)
				}
				hook := &missingRoutePipelineFailureHook{absenceKey: backend.absenceKey("route-peer"), mode: mode}
				backend.client.AddHook(hook)
				if err := backend.UnregisterToken("route-peer"); err == nil {
					t.Fatal("primary or uncertain transaction failure was hidden")
				}
				if hook.fired == 0 {
					t.Fatal("failure injection was not exercised")
				}
				if mode == "watch" {
					if route, err := backend.LookupRoute("route-peer"); err != nil || route == nil {
						t.Fatal("failed WATCH mutated the route")
					}
				}
			})
		}
	}
}

type missingRouteLookupErrorBackend struct{ PushTokenBackend }

func (missingRouteLookupErrorBackend) LookupRoute(string) (*pushRouteLease, error) {
	return nil, errors.New("private route lookup failure")
}

func TestPushMissingRoutePreservesLookupErrors(t *testing.T) {
	for _, scope := range []string{"direct", "group"} {
		t.Run(scope, func(t *testing.T) {
			journal := &bytes.Buffer{}
			previous := log.Writer()
			log.SetOutput(journal)
			defer log.SetOutput(previous)
			push := NewPushServiceWithBackend(missingRouteLookupErrorBackend{newMemoryPushTokenStore()})
			lookup := pushSentCounter.WithLabelValues("route_lookup_failed")
			before := testutil.ToFloat64(lookup)
			beforeMissing := testutil.ToFloat64(pushSentCounter.WithLabelValues("missing_token"))
			missingRouteSend(push, scope)
			if testutil.ToFloat64(lookup)-before != 1 || testutil.ToFloat64(pushSentCounter.WithLabelValues("missing_token")) != beforeMissing || strings.Contains(journal.String(), "missing_route") || strings.Contains(journal.String(), "private") {
				t.Fatal("lookup failure was relabeled or leaked")
			}
		})
	}
}

type missingRouteDirectStoreHook struct {
	InboxBackend
	beforeStore func()
}

func (backend *missingRouteDirectStoreHook) Store(peerID string, entry inboxMessage) (InboxStoreResult, error) {
	backend.beforeStore()
	return backend.InboxBackend.Store(peerID, entry)
}

func (*missingRouteDirectStoreHook) StoreWithWakeOutcome(string, inboxMessage, wakeOutcomeAdmission) (InboxStoreResult, wakeOutcomeAdmissionStatus, error) {
	return "", "", errors.New("absent route unexpectedly admitted provider work")
}

type missingRouteGroupStoreHook struct {
	GroupInboxBackend
	beforeStore func()
}

func (backend *missingRouteGroupStoreHook) StoreWithRecipients(groupID, from, message string, recipients []string) (GroupInboxStoreResult, error) {
	backend.beforeStore()
	return backend.GroupInboxBackend.StoreWithRecipients(groupID, from, message, recipients)
}

func (*missingRouteGroupStoreHook) StoreWithRecipientsAndWakeOutcomes(string, string, string, []string, []wakeOutcomeAdmission) (GroupInboxStoreResult, []wakeOutcomeAdmissionResult, error) {
	return "", nil, errors.New("absent group route unexpectedly admitted provider work")
}

func TestPushMissingRoutePreflightObservationSurvivesPersistence(t *testing.T) {
	for _, kind := range []string{"memory", "redis_legacy", "redis_encrypted"} {
		for _, scope := range []string{"direct", "group"} {
			t.Run(kind+"/"+scope, func(t *testing.T) {
				tokens := missingRouteBackend(t, kind)
				if err := tokens.RegisterToken("route-peer", "initial-token", "ios"); err != nil {
					t.Fatal(err)
				}
				if err := tokens.UnregisterToken("route-peer"); err != nil {
					t.Fatal(err)
				}
				push := NewPushServiceWithBackend(tokens)
				recorder := newRecordingPushSender()
				push.sender = recorder.Send
				beforeStore := func() {
					if err := tokens.RegisterToken("route-peer", "successor-token", "ios"); err != nil {
						t.Fatal(err)
					}
					lease := plan367Route(t, tokens, "route-peer")
					if removed, err := tokens.RevokeIfCurrent(lease); err != nil || !removed {
						t.Fatalf("interleaved removal: %v %v", removed, err)
					}
				}
				var store func() error
				var count func() int
				if scope == "direct" {
					backend := &missingRouteDirectStoreHook{InboxBackend: newMemoryInboxBackend(), beforeStore: beforeStore}
					inbox := NewInboxStoreWithBackend(backend, push)
					inbox.SetWakeOutcomeAdmissionEnabled(true)
					entry := inboxMessage{From: "peer-from", Message: tc396DirectMessageEnvelope("absence-direct"), Timestamp: time.Now().UnixMilli()}
					store = func() error { _, err := inbox.Store("route-peer", entry); return err }
					count = func() int { return backend.Count("route-peer") }
				} else {
					backend := &missingRouteGroupStoreHook{GroupInboxBackend: newMemoryGroupInboxBackend(100, time.Hour), beforeStore: beforeStore}
					inbox := NewGroupInboxStoreWithBackend(backend)
					inbox.SetPush(push)
					inbox.SetWakeOutcomeAdmissionEnabled(true)
					store = func() error {
						return inbox.StoreWithPushRecipients("88888888-8888-4888-8888-888888888888", "peer-from", ordinaryGroupCiphertextEnvelope(8), []string{"route-peer"})
					}
					count = func() int { _, messages := backend.Stats(); return messages }
				}
				journal := &bytes.Buffer{}
				previous := log.Writer()
				log.SetOutput(journal)
				defer log.SetOutput(previous)
				beforeReason := missingRouteMetric(t, "unregistered_by_client", "ios")
				beforeMissing := testutil.ToFloat64(pushSentCounter.WithLabelValues("missing_token"))
				if err := store(); err != nil {
					t.Fatal(err)
				}
				if count() != 1 {
					t.Fatal("message did not persist before missing-route accounting")
				}
				expectMissingObservation(t, tokens, "revoked_after_provider_rejection", "ios")
				if !strings.Contains(journal.String(), "[PUSH] outcome=missing_route missing_route_reason=unregistered_by_client") {
					t.Fatalf("preflight reason changed during persistence: %q", journal.String())
				}
				if delta := missingRouteMetric(t, "unregistered_by_client", "ios") - beforeReason; delta != 1 {
					t.Fatalf("frozen observation metric delta=%v", delta)
				}
				if err := store(); err != nil {
					t.Fatal(err)
				}
				if count() != 1 || testutil.ToFloat64(pushSentCounter.WithLabelValues("missing_token"))-beforeMissing != 1 || recorder.SendCallCount() != 0 {
					t.Fatal("duplicate or original missing route changed provider/store accounting")
				}
			})
		}
	}
}
