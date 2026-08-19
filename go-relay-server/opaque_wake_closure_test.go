package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"io"
	"net/http"
	"path/filepath"
	"reflect"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"firebase.google.com/go/v4/messaging"
)

type plan368BackendProbe struct {
	delegate PushTokenBackend

	mu             sync.Mutex
	lookupCalls    int
	resolveCalls   int
	revokeCalls    int
	resolvedRoutes []pushRouteLease
	revokedRoutes  []pushRouteLease
	lookup         func(call int, peerID string) (*pushRouteLease, error)
	resolve        func(call int, route pushRouteLease) (*resolvedPushTarget, error)
	revoke         func(call int, route pushRouteLease) (bool, error)
}

func (p *plan368BackendProbe) RegisterToken(
	peerID,
	tokenValue,
	platform string,
	capabilities ...string,
) error {
	return p.delegate.RegisterToken(peerID, tokenValue, platform, capabilities...)
}

func (p *plan368BackendProbe) UnregisterToken(peerID string) error {
	return p.delegate.UnregisterToken(peerID)
}

func (p *plan368BackendProbe) LookupRoute(peerID string) (*pushRouteLease, error) {
	p.mu.Lock()
	p.lookupCalls++
	call := p.lookupCalls
	hook := p.lookup
	p.mu.Unlock()
	if hook != nil {
		return hook(call, peerID)
	}
	return p.delegate.LookupRoute(peerID)
}

func (p *plan368BackendProbe) ResolveRoute(route pushRouteLease) (*resolvedPushTarget, error) {
	p.mu.Lock()
	p.resolveCalls++
	call := p.resolveCalls
	p.resolvedRoutes = append(p.resolvedRoutes, copyPushRouteLease(route))
	hook := p.resolve
	p.mu.Unlock()
	if hook != nil {
		return hook(call, copyPushRouteLease(route))
	}
	return p.delegate.ResolveRoute(route)
}

func (p *plan368BackendProbe) RevokeIfCurrent(route pushRouteLease) (bool, error) {
	p.mu.Lock()
	p.revokeCalls++
	call := p.revokeCalls
	p.revokedRoutes = append(p.revokedRoutes, copyPushRouteLease(route))
	hook := p.revoke
	p.mu.Unlock()
	if hook != nil {
		return hook(call, copyPushRouteLease(route))
	}
	return p.delegate.RevokeIfCurrent(route)
}

func (p *plan368BackendProbe) TokenCount() int { return p.delegate.TokenCount() }

func (p *plan368BackendProbe) PlatformCounts() map[string]int {
	return p.delegate.PlatformCounts()
}

func (p *plan368BackendProbe) counts() (lookups, resolves, revokes int) {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.lookupCalls, p.resolveCalls, p.revokeCalls
}

func (p *plan368BackendProbe) revoked() []pushRouteLease {
	p.mu.Lock()
	defer p.mu.Unlock()
	result := make([]pushRouteLease, len(p.revokedRoutes))
	for index, route := range p.revokedRoutes {
		result[index] = copyPushRouteLease(route)
	}
	return result
}

type plan368AdapterCase struct {
	name         string
	capabilities []string
	invoke       func(push *PushService)
	richMessage  func(tokenValue, platform string) *messaging.Message
}

func plan368AdapterCases() []plan368AdapterCase {
	const (
		peerID         = "plan368-adapter-recipient-private"
		directSender   = "plan368-adapter-direct-sender-private"
		groupID        = "plan368-adapter-group-private"
		groupSender    = "plan368-adapter-group-sender-private"
		groupMessageID = "plan368-adapter-group-message-private"
	)
	directMessage := ordinaryChatCiphertextEnvelope(8, 16)
	directReaction := directReactionEnvelope(
		"plan368-adapter-direct-reaction-private",
		"add",
		"plan368-adapter-target-private",
		directSender,
	)
	groupMessage := ordinaryGroupCiphertextEnvelope(16)
	groupReaction := `{"kind":"group_offline_replay","version":1,"payloadType":"group_reaction","messageId":"plan368-adapter-group-base-private","keyEpoch":7,"ciphertext":"plan368-adapter-group-cipher-private","nonce":"plan368-adapter-group-nonce-private"}`
	groupMetadata := groupReactionPushMetadata{
		TransitionID:              "plan368-adapter-group-reaction-private",
		Action:                    "add",
		TargetMessageID:           "plan368-adapter-group-target-private",
		ReactorPeerID:             "plan368-adapter-reactor-private",
		ReactorTransportPeerID:    "plan368-adapter-reactor-transport-private",
		BaseEnvelopeHash:          "plan368-adapter-base-hash-private",
		NotificationExtensionJSON: `{"plan368":"private-extension"}`,
		SenderPublicKey:           "plan368-adapter-public-key-private",
	}

	return []plan368AdapterCase{
		{
			name: "direct",
			invoke: func(push *PushService) {
				push.SendNotification(context.Background(), peerID, directSender, directMessage)
			},
			richMessage: func(tokenValue, platform string) *messaging.Message {
				return projectPushMessageForPlatform(
					buildPushMessage(tokenValue, directSender, directMessage),
					platform,
				)
			},
		},
		{
			name:         "direct reaction",
			capabilities: []string{directReactionCapability},
			invoke: func(push *PushService) {
				push.SendReactionNotification(context.Background(), peerID, directSender, directReaction)
			},
			richMessage: func(tokenValue, platform string) *messaging.Message {
				return projectPushMessageForPlatform(
					buildReactionPushMessage(tokenValue, directSender, directReaction),
					platform,
				)
			},
		},
		{
			name: "group",
			invoke: func(push *PushService) {
				push.SendGroupNotification(
					context.Background(),
					peerID,
					groupID,
					groupSender,
					groupMessageID,
					groupMessage,
				)
			},
			richMessage: func(tokenValue, platform string) *messaging.Message {
				return projectPushMessageForPlatform(
					buildGroupPushMessage(
						tokenValue,
						groupID,
						groupSender,
						groupMessageID,
						groupMessage,
					),
					platform,
				)
			},
		},
		{
			name:         "group reaction",
			capabilities: []string{groupReactionCapability},
			invoke: func(push *PushService) {
				push.SendGroupReactionNotification(
					context.Background(),
					peerID,
					groupID,
					groupReaction,
					groupMetadata,
				)
			},
			richMessage: func(tokenValue, platform string) *messaging.Message {
				return projectPushMessageForPlatform(
					buildGroupReactionPushMessage(
						tokenValue,
						groupID,
						groupReaction,
						groupMetadata,
					),
					platform,
				)
			},
		},
	}
}

func plan368Capabilities(adapter plan368AdapterCase, opaque bool) []string {
	capabilities := append([]string(nil), adapter.capabilities...)
	if opaque {
		capabilities = append(capabilities, opaqueWakeCapability)
	}
	return capabilities
}

func plan368OpaqueMessage(tokenValue, platform string, now time.Time) (*messaging.Message, error) {
	draft, err := buildOpaqueWakeMessage(platform, now)
	if err != nil || draft == nil {
		return draft, err
	}
	message := *draft
	message.Token = tokenValue
	return &message, nil
}

func plan368AssertCalls(
	t *testing.T,
	probe *plan368BackendProbe,
	wantLookup,
	wantResolve,
	wantRevoke int,
) {
	t.Helper()
	lookup, resolve, revoke := probe.counts()
	if lookup != wantLookup || resolve != wantResolve || revoke != wantRevoke {
		t.Fatalf(
			"route calls = lookup %d resolve %d revoke %d, want %d/%d/%d",
			lookup,
			resolve,
			revoke,
			wantLookup,
			wantResolve,
			wantRevoke,
		)
	}
}

func TestRelayNotificationClosure_OpaqueWakeRouteSelectionAndLegacyCompatibility(t *testing.T) {
	const (
		peerID        = "plan368-adapter-recipient-private"
		providerToken = "plan368-route-provider-token"
		platform      = "android"
	)

	for _, adapter := range plan368AdapterCases() {
		adapter := adapter
		t.Run(adapter.name+" opaque precedence", func(t *testing.T) {
			store := newMemoryPushTokenStore()
			if err := store.RegisterToken(
				peerID,
				providerToken,
				platform,
				plan368Capabilities(adapter, true)...,
			); err != nil {
				t.Fatalf("RegisterToken(): %v", err)
			}
			probe := &plan368BackendProbe{delegate: store}
			push := NewPushServiceWithBackend(probe)
			push.retryDelays = nil
			recorder := newRecordingPushSender()
			push.sender = recorder.Send

			adapter.invoke(push)

			if recorder.SendCallCount() != 1 {
				t.Fatalf("provider sends = %d, want exactly one", recorder.SendCallCount())
			}
			want, err := plan368OpaqueMessage(providerToken, platform, time.Time{})
			if err != nil {
				t.Fatalf("build fixed request: %v", err)
			}
			plan367AssertMessageEquivalent(t, recorder.LastMessage(), want)
			plan368AssertCalls(t, probe, 1, 1, 0)
		})

		t.Run(adapter.name+" legacy rich compatibility", func(t *testing.T) {
			store := newMemoryPushTokenStore()
			if err := store.RegisterToken(
				peerID,
				providerToken,
				platform,
				adapter.capabilities...,
			); err != nil {
				t.Fatalf("RegisterToken(): %v", err)
			}
			probe := &plan368BackendProbe{delegate: store}
			push := NewPushServiceWithBackend(probe)
			push.retryDelays = nil
			recorder := newRecordingPushSender()
			push.sender = recorder.Send

			adapter.invoke(push)

			if recorder.SendCallCount() != 1 {
				t.Fatalf("provider sends = %d, want exactly one", recorder.SendCallCount())
			}
			want := adapter.richMessage(providerToken, platform)
			if want == nil {
				t.Fatal("legacy fixture did not build a rich request")
			}
			plan367AssertMessageEquivalent(t, recorder.LastMessage(), want)
			plan368AssertCalls(t, probe, 1, 1, 0)
		})

		t.Run(adapter.name+" empty opaque handle fails closed", func(t *testing.T) {
			store := newMemoryPushTokenStore()
			if err := store.RegisterToken(
				peerID,
				providerToken,
				platform,
				plan368Capabilities(adapter, true)...,
			); err != nil {
				t.Fatalf("RegisterToken(): %v", err)
			}
			empty := plan367Route(t, store, peerID)
			empty.Handle = ""
			probe := &plan368BackendProbe{
				delegate: store,
				lookup: func(int, string) (*pushRouteLease, error) {
					copy := copyPushRouteLease(empty)
					return &copy, nil
				},
			}
			push := NewPushServiceWithBackend(probe)
			recorder := newRecordingPushSender()
			push.sender = recorder.Send

			adapter.invoke(push)

			if recorder.SendCallCount() != 0 {
				t.Fatalf("empty opaque handle sent %d provider requests", recorder.SendCallCount())
			}
			plan368AssertCalls(t, probe, 1, 0, 0)
		})
	}

	for _, platformValue := range []string{"", "web-private-platform"} {
		platformValue := platformValue
		name := platformValue
		if name == "" {
			name = "empty"
		}
		t.Run("opaque platform "+name+" fails closed", func(t *testing.T) {
			store := newMemoryPushTokenStore()
			if err := store.RegisterToken(
				peerID,
				providerToken,
				platformValue,
				opaqueWakeCapability,
			); err != nil {
				t.Fatalf("RegisterToken(): %v", err)
			}
			probe := &plan368BackendProbe{delegate: store}
			push := NewPushServiceWithBackend(probe)
			recorder := newRecordingPushSender()
			push.sender = recorder.Send

			push.SendNotification(
				context.Background(),
				peerID,
				"plan368-unsupported-platform-sender-private",
				ordinaryChatCiphertextEnvelope(8, 16),
			)

			if recorder.SendCallCount() != 0 {
				t.Fatalf("platform %q sent %d provider requests", platformValue, recorder.SendCallCount())
			}
			plan368AssertCalls(t, probe, 1, 1, 0)
		})
	}

	for _, row := range []struct {
		name               string
		registeredPlatform string
		canonicalPlatform  string
	}{
		{name: "android mixed case and whitespace", registeredPlatform: "  AnDrOiD\t", canonicalPlatform: "android"},
		{name: "ios mixed case and whitespace", registeredPlatform: "\nIoS  ", canonicalPlatform: "ios"},
	} {
		row := row
		t.Run(row.name+" canonicalizes", func(t *testing.T) {
			store := newMemoryPushTokenStore()
			if err := store.RegisterToken(
				peerID,
				providerToken,
				row.registeredPlatform,
				opaqueWakeCapability,
			); err != nil {
				t.Fatalf("RegisterToken(): %v", err)
			}
			probe := &plan368BackendProbe{delegate: store}
			push := NewPushServiceWithBackend(probe)
			push.retryDelays = nil
			canonicalNow := time.Unix(1_800_000_000, 0).UTC()
			push.now = func() time.Time { return canonicalNow }
			recorder := newRecordingPushSender()
			push.sender = recorder.Send

			push.SendNotification(
				context.Background(),
				peerID,
				"plan368-canonical-platform-sender-private",
				ordinaryChatCiphertextEnvelope(8, 16),
			)

			if recorder.SendCallCount() != 1 {
				t.Fatalf("canonical platform sent %d provider requests, want one", recorder.SendCallCount())
			}
			want, err := plan368OpaqueMessage(providerToken, row.canonicalPlatform, canonicalNow)
			if err != nil {
				t.Fatalf("build canonical fixed request: %v", err)
			}
			plan367AssertMessageEquivalent(t, recorder.LastMessage(), want)
			plan368AssertCalls(t, probe, 1, 1, 0)
		})
	}

	t.Run("lookup error does not resolve or downgrade", func(t *testing.T) {
		store := newMemoryPushTokenStore()
		probe := &plan368BackendProbe{
			delegate: store,
			lookup: func(int, string) (*pushRouteLease, error) {
				return nil, errors.New("plan368-private-marker-read-error")
			},
		}
		push := NewPushServiceWithBackend(probe)
		recorder := newRecordingPushSender()
		push.sender = recorder.Send
		push.SendNotification(
			context.Background(),
			peerID,
			"plan368-lookup-error-sender-private",
			ordinaryChatCiphertextEnvelope(8, 16),
		)
		if recorder.SendCallCount() != 0 {
			t.Fatalf("lookup error sent %d provider requests", recorder.SendCallCount())
		}
		plan368AssertCalls(t, probe, 1, 0, 0)
	})

	t.Run("non-stale resolve error does not retry or downgrade", func(t *testing.T) {
		store := newMemoryPushTokenStore()
		if err := store.RegisterToken(peerID, providerToken, platform, opaqueWakeCapability); err != nil {
			t.Fatalf("RegisterToken(): %v", err)
		}
		probe := &plan368BackendProbe{
			delegate: store,
			resolve: func(int, pushRouteLease) (*resolvedPushTarget, error) {
				return nil, errors.New("plan368-private-route-decrypt-error")
			},
		}
		push := NewPushServiceWithBackend(probe)
		recorder := newRecordingPushSender()
		push.sender = recorder.Send
		push.SendNotification(
			context.Background(),
			peerID,
			"plan368-resolve-error-sender-private",
			ordinaryChatCiphertextEnvelope(8, 16),
		)
		if recorder.SendCallCount() != 0 {
			t.Fatalf("resolve error sent %d provider requests", recorder.SendCallCount())
		}
		plan368AssertCalls(t, probe, 1, 1, 0)
	})

	t.Run("stale rich route upgrades to opaque with the same lease identity", func(t *testing.T) {
		store := newMemoryPushTokenStore()
		if err := store.RegisterToken(
			peerID,
			providerToken,
			platform,
			directReactionCapability,
		); err != nil {
			t.Fatalf("initial RegisterToken(): %v", err)
		}
		before := plan367Route(t, store, peerID)
		probe := &plan368BackendProbe{delegate: store}
		probe.resolve = func(call int, route pushRouteLease) (*resolvedPushTarget, error) {
			if call == 1 {
				if err := store.RegisterToken(
					peerID,
					providerToken,
					platform,
					directReactionCapability,
					opaqueWakeCapability,
				); err != nil {
					t.Errorf("capability upgrade: %v", err)
				}
			}
			return store.ResolveRoute(route)
		}
		push := NewPushServiceWithBackend(probe)
		push.retryDelays = nil
		recorder := newRecordingPushSender()
		push.sender = recorder.Send
		push.SendReactionNotification(
			context.Background(),
			peerID,
			"plan368-stale-upgrade-sender-private",
			directReactionEnvelope(
				"plan368-stale-upgrade-event-private",
				"add",
				"plan368-stale-upgrade-target-private",
				"plan368-stale-upgrade-sender-private",
			),
		)

		after := plan367Route(t, store, peerID)
		if before.Handle != after.Handle || before.Generation != after.Generation {
			t.Fatalf("capability-only upgrade changed lease identity: before=%#v after=%#v", before, after)
		}
		if recorder.SendCallCount() != 1 {
			t.Fatalf("stale upgrade sends = %d, want one", recorder.SendCallCount())
		}
		want, err := plan368OpaqueMessage(providerToken, platform, time.Time{})
		if err != nil {
			t.Fatalf("build fixed request: %v", err)
		}
		plan367AssertMessageEquivalent(t, recorder.LastMessage(), want)
		plan368AssertCalls(t, probe, 2, 2, 0)
	})

	t.Run("stale opaque route never downgrades with the same lease identity", func(t *testing.T) {
		store := newMemoryPushTokenStore()
		if err := store.RegisterToken(
			peerID,
			providerToken,
			platform,
			directReactionCapability,
			opaqueWakeCapability,
		); err != nil {
			t.Fatalf("initial RegisterToken(): %v", err)
		}
		before := plan367Route(t, store, peerID)
		probe := &plan368BackendProbe{delegate: store}
		probe.resolve = func(call int, route pushRouteLease) (*resolvedPushTarget, error) {
			if call == 1 {
				if err := store.RegisterToken(
					peerID,
					providerToken,
					platform,
					directReactionCapability,
				); err != nil {
					t.Errorf("capability downgrade: %v", err)
				}
			}
			return store.ResolveRoute(route)
		}
		push := NewPushServiceWithBackend(probe)
		recorder := newRecordingPushSender()
		push.sender = recorder.Send
		push.SendReactionNotification(
			context.Background(),
			peerID,
			"plan368-stale-downgrade-sender-private",
			directReactionEnvelope(
				"plan368-stale-downgrade-event-private",
				"add",
				"plan368-stale-downgrade-target-private",
				"plan368-stale-downgrade-sender-private",
			),
		)

		after := plan367Route(t, store, peerID)
		if before.Handle != after.Handle || before.Generation != after.Generation {
			t.Fatalf("capability-only downgrade changed lease identity: before=%#v after=%#v", before, after)
		}
		if recorder.SendCallCount() != 0 {
			t.Fatalf("opaque-to-rich downgrade sent %d provider requests", recorder.SendCallCount())
		}
		plan368AssertCalls(t, probe, 2, 1, 0)
	})

	t.Run("stale opaque route refreshes to a newer opaque route", func(t *testing.T) {
		const refreshedToken = "plan368-stale-refreshed-provider-token"
		store := newMemoryPushTokenStore()
		if err := store.RegisterToken(peerID, providerToken, platform, opaqueWakeCapability); err != nil {
			t.Fatalf("initial RegisterToken(): %v", err)
		}
		original := plan367Route(t, store, peerID)
		probe := &plan368BackendProbe{delegate: store}
		probe.resolve = func(call int, route pushRouteLease) (*resolvedPushTarget, error) {
			if call == 1 {
				if err := store.RegisterToken(peerID, refreshedToken, platform, opaqueWakeCapability); err != nil {
					t.Errorf("opaque refresh RegisterToken(): %v", err)
				}
			}
			return store.ResolveRoute(route)
		}
		push := NewPushServiceWithBackend(probe)
		push.retryDelays = nil
		recorder := newRecordingPushSender()
		push.sender = recorder.Send

		push.SendNotification(
			context.Background(),
			peerID,
			"plan368-stale-opaque-refresh-sender-private",
			ordinaryChatCiphertextEnvelope(8, 16),
		)

		if recorder.SendCallCount() != 1 {
			t.Fatalf("opaque refresh sends = %d, want one", recorder.SendCallCount())
		}
		want, err := plan368OpaqueMessage(refreshedToken, platform, time.Time{})
		if err != nil {
			t.Fatalf("build refreshed fixed request: %v", err)
		}
		plan367AssertMessageEquivalent(t, recorder.LastMessage(), want)
		current := plan367Route(t, store, peerID)
		if current.Generation <= original.Generation || current.Handle == original.Handle {
			t.Fatalf("opaque refresh route = %#v, want newer identity than %#v", current, original)
		}
		plan368AssertCalls(t, probe, 2, 2, 0)
	})

	t.Run("stale opaque route refreshes to no route and terminates", func(t *testing.T) {
		store := newMemoryPushTokenStore()
		if err := store.RegisterToken(peerID, providerToken, platform, opaqueWakeCapability); err != nil {
			t.Fatalf("initial RegisterToken(): %v", err)
		}
		probe := &plan368BackendProbe{delegate: store}
		probe.resolve = func(call int, route pushRouteLease) (*resolvedPushTarget, error) {
			if call == 1 {
				if err := store.UnregisterToken(peerID); err != nil {
					t.Errorf("opaque refresh UnregisterToken(): %v", err)
				}
			}
			return store.ResolveRoute(route)
		}
		push := NewPushServiceWithBackend(probe)
		recorder := newRecordingPushSender()
		push.sender = recorder.Send

		push.SendNotification(
			context.Background(),
			peerID,
			"plan368-stale-empty-refresh-sender-private",
			ordinaryChatCiphertextEnvelope(8, 16),
		)

		if recorder.SendCallCount() != 0 {
			t.Fatalf("empty stale refresh sent %d provider requests", recorder.SendCallCount())
		}
		if route, lookupErr := store.LookupRoute(peerID); lookupErr != nil || route != nil {
			t.Fatalf("empty stale refresh left route %#v err=%v", route, lookupErr)
		}
		plan368AssertCalls(t, probe, 2, 1, 0)
	})

	t.Run("second stale result terminates at the shared bound", func(t *testing.T) {
		store := newMemoryPushTokenStore()
		if err := store.RegisterToken(peerID, providerToken, platform, opaqueWakeCapability); err != nil {
			t.Fatalf("RegisterToken(): %v", err)
		}
		probe := &plan368BackendProbe{
			delegate: store,
			resolve: func(int, pushRouteLease) (*resolvedPushTarget, error) {
				return nil, ErrPushRouteStale
			},
		}
		push := NewPushServiceWithBackend(probe)
		recorder := newRecordingPushSender()
		push.sender = recorder.Send
		push.SendNotification(
			context.Background(),
			peerID,
			"plan368-second-stale-sender-private",
			ordinaryChatCiphertextEnvelope(8, 16),
		)
		if recorder.SendCallCount() != 0 {
			t.Fatalf("second stale sent %d provider requests", recorder.SendCallCount())
		}
		plan368AssertCalls(t, probe, 2, 2, 0)
	})

	t.Run("one resolver owner and four adapters plus outcome gateway", func(t *testing.T) {
		paths, err := filepath.Glob("*.go")
		if err != nil {
			t.Fatalf("glob production Go: %v", err)
		}
		fileSet := token.NewFileSet()
		var lookupOwners, resolveOwners, selectionCallers []string
		for _, path := range paths {
			if strings.HasSuffix(path, "_test.go") {
				continue
			}
			parsed, parseErr := parser.ParseFile(fileSet, path, nil, 0)
			if parseErr != nil {
				t.Fatalf("parse %s: %v", path, parseErr)
			}
			for _, declaration := range parsed.Decls {
				function, ok := declaration.(*ast.FuncDecl)
				if !ok || function.Body == nil {
					continue
				}
				ast.Inspect(function.Body, func(node ast.Node) bool {
					call, ok := node.(*ast.CallExpr)
					if !ok {
						return true
					}
					selector, ok := call.Fun.(*ast.SelectorExpr)
					if !ok {
						return true
					}
					switch selector.Sel.Name {
					case "LookupRoute":
						lookupOwners = append(lookupOwners, function.Name.Name)
					case "ResolveRoute":
						resolveOwners = append(resolveOwners, function.Name.Name)
					case "sendSelectedPushThroughGateway":
						selectionCallers = append(selectionCallers, function.Name.Name)
					}
					return true
				})
			}
		}
		if !reflect.DeepEqual(lookupOwners, []string{"selectPushRoute"}) {
			t.Fatalf("production LookupRoute owners = %#v, want shared selector only", lookupOwners)
		}
		if !reflect.DeepEqual(resolveOwners, []string{"sendPushRouteThroughGateway"}) {
			t.Fatalf("production ResolveRoute owners = %#v, want private gateway only", resolveOwners)
		}
		sort.Strings(selectionCallers)
		wantCallers := []string{
			"SendGroupNotification",
			"SendNotification",
			// G26: strict-authority group content never reaches the group
			// topic, so it needs its own adapter onto the shared gateway.
			"sendGroupContentNotificationForRoute",
			"sendGroupReactionNotificationForRoute",
			"sendOpaqueWakeThroughGateway",
			"sendReactionNotificationForRoute",
		}
		if !reflect.DeepEqual(selectionCallers, wantCallers) {
			t.Fatalf(
				"selection callers = %#v, want five adapters plus outcome gateway %#v",
				selectionCallers,
				wantCallers,
			)
		}
	})
}

type plan368ProviderCapture struct {
	mu       sync.Mutex
	requests []map[string]any
	raw      []string
	signal   chan struct{}
}

func (c *plan368ProviderCapture) handler(w http.ResponseWriter, request *http.Request) {
	raw, err := io.ReadAll(request.Body)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	var decoded map[string]any
	if err := json.Unmarshal(raw, &decoded); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	c.mu.Lock()
	c.requests = append(c.requests, decoded)
	c.raw = append(c.raw, string(raw))
	if c.signal != nil {
		select {
		case c.signal <- struct{}{}:
		default:
		}
	}
	c.mu.Unlock()
	w.Header().Set("Content-Type", "application/json")
	_, _ = fmt.Fprint(w, `{"name":"projects/plan368/messages/fixed"}`)
}

func (c *plan368ProviderCapture) snapshot() ([]map[string]any, []string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	requests := append([]map[string]any(nil), c.requests...)
	raw := append([]string(nil), c.raw...)
	return requests, raw
}

func (c *plan368ProviderCapture) waitForCount(t *testing.T, want int) {
	t.Helper()
	deadline := time.NewTimer(2 * time.Second)
	defer deadline.Stop()
	for {
		requests, _ := c.snapshot()
		if len(requests) >= want {
			return
		}
		select {
		case <-c.signal:
		case <-deadline.C:
			t.Fatalf("captured provider requests = %d, want at least %d", len(requests), want)
		}
	}
}

type plan368ProviderProducerCase struct {
	name          string
	privateValues []string
	invoke        func(push *PushService)
}

func plan368ProviderProducerCases(
	t *testing.T,
	recipientPeerID string,
) []plan368ProviderProducerCase {
	t.Helper()
	const (
		directSender = "plan368-provider-direct-sender-private"
		groupID      = "plan368-provider-group-private"
		groupSender  = "plan368-provider-group-sender-private"
	)

	cases := make([]plan368ProviderProducerCase, 0, 22)
	addDirect := func(name, message string, privateValues ...string) {
		t.Helper()
		if metadata := extractChatPushMetadata(message); !metadata.ShouldNotify {
			t.Fatalf("direct producer %q is not currently notification-eligible: %#v", name, metadata)
		}
		messageCopy := message
		valuesCopy := append([]string{directSender}, privateValues...)
		cases = append(cases, plan368ProviderProducerCase{
			name:          name,
			privateValues: valuesCopy,
			invoke: func(push *PushService) {
				push.SendNotification(
					context.Background(),
					recipientPeerID,
					directSender,
					messageCopy,
				)
			},
		})
	}
	addGroup := func(name, messageID, message string, privateValues ...string) {
		t.Helper()
		if probe := buildGroupPushMessage(
			"plan368-provider-probe-token",
			groupID,
			groupSender,
			messageID,
			message,
		); probe == nil {
			t.Fatalf("group producer %q does not currently build a provider request", name)
		}
		messageCopy := message
		valuesCopy := append([]string{groupID, groupSender, messageID}, privateValues...)
		cases = append(cases, plan368ProviderProducerCase{
			name:          name,
			privateValues: valuesCopy,
			invoke: func(push *PushService) {
				groupStore := NewGroupInboxStore(500, 7*24*time.Hour)
				groupStore.SetPush(push)
				if err := groupStore.StoreWithPushRecipients(
					groupID,
					groupSender,
					messageCopy,
					[]string{recipientPeerID},
				); err != nil {
					t.Fatalf("group producer %q real store admission: %v", name, err)
				}
			},
		})
	}

	addDirect(
		"direct chat text",
		`{"type":"chat_message","version":"2","id":"plan368-direct-chat-private","encrypted":{"kem":"plan368-chat-kem-private","ciphertext":"plan368-chat-cipher-private","nonce":"plan368-chat-nonce-private"}}`,
		"plan368-direct-chat-private",
		"plan368-chat-cipher-private",
	)
	addDirect(
		"direct media image",
		`{"type":"chat_message","version":"2","id":"plan368-direct-image-private","messageType":"image","mediaId":"plan368-image-media-private","encrypted":{"kem":"plan368-image-kem-private","ciphertext":"plan368-image-cipher-private","nonce":"plan368-image-nonce-private"}}`,
		"plan368-direct-image-private",
		"plan368-image-media-private",
	)
	addDirect(
		"direct voice",
		`{"type":"chat_message","version":"2","id":"plan368-direct-voice-private","messageType":"voice","durationMs":7319,"encrypted":{"kem":"plan368-voice-kem-private","ciphertext":"plan368-voice-cipher-private","nonce":"plan368-voice-nonce-private"}}`,
		"plan368-direct-voice-private",
		"plan368-voice-cipher-private",
	)
	addDirect(
		"direct private disappearing",
		`{"type":"chat_message","version":"2","id":"plan368-direct-disappearing-private","isPrivate":true,"expiresAtMs":1900000000000,"encrypted":{"kem":"plan368-private-kem-private","ciphertext":"plan368-private-cipher-private","nonce":"plan368-private-nonce-private"}}`,
		"plan368-direct-disappearing-private",
		"plan368-private-cipher-private",
	)
	addDirect(
		"direct edit",
		`{"type":"chat_message","version":"2","id":"plan368-direct-edit-target-private","eventId":"plan368-direct-edit-event-private","editedAt":"2026-08-15T12:00:00Z","senderPeerId":"plan368-provider-direct-sender-private","encrypted":{"kem":"plan368-edit-kem-private","ciphertext":"plan368-edit-cipher-private","nonce":"plan368-edit-nonce-private"}}`,
		"plan368-direct-edit-target-private",
		"plan368-direct-edit-event-private",
	)
	for _, action := range []string{"send", "accept", "pass"} {
		messageID := "plan368-introduction-private::" + action + "::plan368-introduction-sender-private"
		addDirect(
			"introduction "+action,
			fmt.Sprintf(
				`{"type":"introduction","version":"2","messageId":%q,"senderPeerId":"plan368-introduction-sender-private","encrypted":{"kem":"plan368-intro-kem-private","ciphertext":"plan368-intro-cipher-private","nonce":"plan368-intro-nonce-private"}}`,
				messageID,
			),
			messageID,
			"plan368-introduction-sender-private",
		)
	}
	addDirect(
		"contact request",
		`{"type":"contact_request","version":"2","msgId":"plan368-contact-request-private","senderUsername":"plan368-contact-name-private","encrypted":{"ephemeralPublicKey":"plan368-contact-key-private","ciphertext":"plan368-contact-cipher-private","nonce":"plan368-contact-nonce-private"}}`,
		"plan368-contact-request-private",
		"plan368-contact-name-private",
	)
	addDirect(
		"group invite",
		`{"type":"group_invite","version":"2","id":"plan368-group-invite-message-private","senderPeerId":"plan368-provider-direct-sender-private","senderUsername":"plan368-invite-name-private","groupId":"plan368-invite-group-private","groupName":"plan368-invite-group-name-private","encrypted":{"kem":"plan368-invite-kem-private","ciphertext":"plan368-invite-cipher-private","nonce":"plan368-invite-nonce-private"}}`,
		"plan368-group-invite-message-private",
		"plan368-invite-group-private",
		"plan368-invite-group-name-private",
	)
	addDirect(
		"oversized direct ciphertext",
		fmt.Sprintf(
			`{"type":"chat_message","version":"2","id":"plan368-direct-oversized-private","encrypted":{"kem":"%s","ciphertext":"%s","nonce":"plan368-direct-oversized-nonce-private"}}`,
			strings.Repeat("plan368-private-k", 350),
			strings.Repeat("plan368-private-c", 350),
		),
		"plan368-direct-oversized-private",
		"plan368-direct-oversized-nonce-private",
	)

	directReactionSender := "plan368-direct-reaction-sender-private"
	directReactionEvent := "plan368-direct-reaction-event-private"
	directReactionTarget := "plan368-direct-reaction-target-private"
	directReactionMessage := directReactionEnvelope(
		directReactionEvent,
		"add",
		directReactionTarget,
		directReactionSender,
	)
	if metadata, recognized, eligible := extractDirectReactionPushMetadata(directReactionMessage); !recognized || !eligible || metadata.EnvelopeSender != directReactionSender {
		t.Fatalf("direct reaction producer fixture is not eligible: %#v/%t/%t", metadata, recognized, eligible)
	}
	cases = append(cases, plan368ProviderProducerCase{
		name: "direct reaction add",
		privateValues: []string{
			directReactionSender,
			directReactionEvent,
			directReactionTarget,
			"fixture-ciphertext",
		},
		invoke: func(push *PushService) {
			push.SendReactionNotification(
				context.Background(),
				recipientPeerID,
				directReactionSender,
				directReactionMessage,
			)
		},
	})

	addGroup(
		"group discussion text",
		"plan368-group-text-private",
		`{"kind":"group_offline_replay","version":1,"payloadType":"group_message","messageId":"plan368-group-text-private","keyEpoch":7,"ciphertext":"plan368-group-text-cipher-private","nonce":"plan368-group-text-nonce-private"}`,
		"plan368-group-text-cipher-private",
	)
	addGroup(
		"group media",
		"plan368-group-media-private",
		`{"kind":"group_offline_replay","version":1,"payloadType":"group_message","messageId":"plan368-group-media-private","messageType":"image","mediaId":"plan368-group-media-id-private","keyEpoch":7,"ciphertext":"plan368-group-media-cipher-private","nonce":"plan368-group-media-nonce-private"}`,
		"plan368-group-media-id-private",
	)
	addGroup(
		"group voice",
		"plan368-group-voice-private",
		`{"kind":"group_offline_replay","version":1,"payloadType":"group_message","messageId":"plan368-group-voice-private","messageType":"voice","durationMs":9911,"keyEpoch":7,"ciphertext":"plan368-group-voice-cipher-private","nonce":"plan368-group-voice-nonce-private"}`,
		"plan368-group-voice-cipher-private",
	)
	addGroup(
		"group quote",
		"plan368-group-quote-private",
		`{"kind":"group_offline_replay","version":1,"payloadType":"group_message","messageId":"plan368-group-quote-private","quoteMessageId":"plan368-group-quoted-message-private","keyEpoch":7,"ciphertext":"plan368-group-quote-cipher-private","nonce":"plan368-group-quote-nonce-private"}`,
		"plan368-group-quoted-message-private",
	)
	addGroup(
		"group forward",
		"plan368-group-forward-private",
		`{"kind":"group_offline_replay","version":1,"payloadType":"group_message","messageId":"plan368-group-forward-private","forwardedMessageId":"plan368-group-forward-source-private","keyEpoch":7,"ciphertext":"plan368-group-forward-cipher-private","nonce":"plan368-group-forward-nonce-private"}`,
		"plan368-group-forward-source-private",
	)
	addGroup(
		"group announcement",
		"plan368-group-announcement-private",
		`{"version":"3","type":"group_message","groupId":"plan368-provider-group-private","messageId":"plan368-group-announcement-private","senderId":"plan368-announcement-sender-private","keyEpoch":7,"encrypted":{"ciphertext":"plan368-group-announcement-cipher-private","nonce":"plan368-group-announcement-nonce-private"}}`,
		"plan368-announcement-sender-private",
	)
	addGroup(
		"group ordinary deletion source-admitted",
		"plan368-group-ordinary-delete-private",
		`{"type":"message_deletion","version":"2","messageId":"plan368-group-ordinary-delete-private"}`,
	)
	addGroup(
		"group ordinary system source-admitted",
		"plan368-group-ordinary-system-private",
		`{"type":"group_system","version":"1","messageId":"plan368-group-ordinary-system-private"}`,
	)
	addGroup(
		"oversized group ciphertext",
		"plan368-group-oversized-private",
		fmt.Sprintf(
			`{"kind":"group_offline_replay","version":1,"payloadType":"group_message","messageId":"plan368-group-oversized-private","keyEpoch":7,"ciphertext":"%s","nonce":"plan368-group-oversized-nonce-private"}`,
			strings.Repeat("plan368-private-group-c", 400),
		),
		"plan368-group-oversized-nonce-private",
	)

	groupReactionFixture := newSignedGroupReactionFixture(
		t,
		groupID,
		"plan368-group-reactor-account-private",
		groupSender,
	)
	groupReactionEvent := "plan368-group-reaction-event-private"
	groupReactionMessage := groupReactionFixture.envelope(
		t,
		groupReactionEvent,
		"add",
		"plan368-group-reaction-base-private",
		"plan368-group-reaction-target-private",
		[]string{recipientPeerID},
		[]string{recipientPeerID},
	)
	groupReactionMetadata, recognized, valid := extractGroupReactionPushMetadata(
		groupReactionMessage,
		groupID,
		groupSender,
		[]string{recipientPeerID},
	)
	if !recognized || !valid {
		t.Fatalf("group reaction producer fixture is not eligible: %#v/%t/%t", groupReactionMetadata, recognized, valid)
	}
	cases = append(cases, plan368ProviderProducerCase{
		name: "group reaction add",
		privateValues: []string{
			groupID,
			groupSender,
			groupReactionEvent,
			"plan368-group-reaction-target-private",
			"plan368-group-reactor-account-private",
		},
		invoke: func(push *PushService) {
			push.SendGroupReactionNotification(
				context.Background(),
				recipientPeerID,
				groupID,
				groupReactionMessage,
				groupReactionMetadata,
			)
		},
	})

	wantNames := []string{
		"direct chat text",
		"direct media image",
		"direct voice",
		"direct private disappearing",
		"direct edit",
		"introduction send",
		"introduction accept",
		"introduction pass",
		"contact request",
		"group invite",
		"oversized direct ciphertext",
		"direct reaction add",
		"group discussion text",
		"group media",
		"group voice",
		"group quote",
		"group forward",
		"group announcement",
		"group ordinary deletion source-admitted",
		"group ordinary system source-admitted",
		"oversized group ciphertext",
		"group reaction add",
	}
	gotNames := make([]string, len(cases))
	for index, producer := range cases {
		gotNames[index] = producer.name
	}
	if len(cases) != 22 || !reflect.DeepEqual(gotNames, wantNames) {
		t.Fatalf("provider producer census = %d %#v, want exact 22 %#v", len(cases), gotNames, wantNames)
	}

	return cases
}

func plan368AssertExactProviderRequest(
	t *testing.T,
	caseName string,
	got,
	want map[string]any,
) {
	t.Helper()
	if reflect.DeepEqual(got, want) {
		return
	}
	gotJSON, _ := json.Marshal(got)
	wantJSON, _ := json.Marshal(want)
	t.Fatalf("%s Firebase request:\n got: %s\nwant: %s", caseName, gotJSON, wantJSON)
}

func plan368ExerciseProviderRequests(
	t *testing.T,
	platform string,
	now time.Time,
	want map[string]any,
) int {
	t.Helper()
	const (
		peerID        = "plan368-provider-recipient-peer-private"
		providerToken = "plan368-provider-token-visible"
	)
	store := newMemoryPushTokenStore()
	if err := store.RegisterToken(
		peerID,
		providerToken,
		platform,
		directReactionCapability,
		groupReactionCapability,
		opaqueWakeCapability,
	); err != nil {
		t.Fatalf("RegisterToken(): %v", err)
	}
	route := plan367Route(t, store, peerID)
	capture := &plan368ProviderCapture{signal: make(chan struct{}, 1)}
	push := NewPushServiceWithBackend(store)
	push.client = plan367FirebaseClient(t, http.HandlerFunc(capture.handler))
	push.retryDelays = nil
	clockCalls := 0
	push.now = func() time.Time {
		clockCalls++
		return now
	}

	producerCases := plan368ProviderProducerCases(t, peerID)
	allPrivateValues := []string{peerID, route.Handle}
	for _, producer := range producerCases {
		allPrivateValues = append(allPrivateValues, producer.privateValues...)
	}
	for index, producer := range producerCases {
		producer.invoke(push)
		capture.waitForCount(t, index+1)
		requests, rawRequests := capture.snapshot()
		if len(requests) != index+1 || len(rawRequests) != index+1 {
			t.Fatalf(
				"%s captured requests = %d/%d, want %d",
				producer.name,
				len(requests),
				len(rawRequests),
				index+1,
			)
		}
		plan368AssertExactProviderRequest(t, producer.name, requests[index], want)
		for _, privateValue := range allPrivateValues {
			if privateValue != "" && strings.Contains(rawRequests[index], privateValue) {
				t.Fatalf(
					"%s provider request leaked private value %q: %s",
					producer.name,
					privateValue,
					rawRequests[index],
				)
			}
		}
	}
	return clockCalls
}

func plan368AssertRealStoreZeroWake(t *testing.T, platform string) {
	t.Helper()
	t.Run("real store zero-wake controls", func(t *testing.T) {
		const (
			recipient = "plan368-zero-recipient-private"
			sender    = "plan368-zero-sender-private"
		)
		tokens := newMemoryPushTokenStore()
		if err := tokens.RegisterToken(
			recipient,
			"plan368-zero-provider-token",
			platform,
			directReactionCapability,
			groupReactionCapability,
			opaqueWakeCapability,
		); err != nil {
			t.Fatalf("RegisterToken(): %v", err)
		}
		push := NewPushServiceWithBackend(tokens)
		recorder := newRecordingPushSender()
		push.sender = recorder.Send
		inbox := NewInboxStore(push)
		inbox.SetDirectReactionPushEnabled(true)
		inbox.RegisterWakeTokens(recipient, []string{"plan368-zero-authorized-wake"})

		directRows := []struct {
			name      string
			message   string
			wakeToken string
		}{
			{
				name:    "unsupported envelope",
				message: `{"type":"presence_ping","id":"plan368-zero-presence-private","payload":{"status":"private"}}`,
			},
			{
				name:    "malformed envelope",
				message: `{"type":`,
			},
			{
				name:    "message deletion",
				message: `{"type":"message_deletion","version":"2","eventId":"plan368-zero-delete-private","senderPeerId":"plan368-zero-sender-private","encrypted":{"kem":"k","ciphertext":"plan368-zero-delete-cipher-private","nonce":"n"}}`,
			},
			{
				name:    "key exchange retry",
				message: `{"type":"contact_request","version":"2","intent":"key_exchange_retry","msgId":"plan368-zero-key-retry-private","senderUsername":"plan368-zero-name-private","encrypted":{"ephemeralPublicKey":"e","ciphertext":"plan368-zero-key-cipher-private","nonce":"n"}}`,
			},
			{
				name:      "direct reaction remove",
				message:   directReactionEnvelope("plan368-zero-remove-private", "remove", "plan368-zero-target-private", sender),
				wakeToken: "plan368-zero-authorized-wake",
			},
			{
				name:      "direct reaction unauthorized",
				message:   directReactionEnvelope("plan368-zero-unauthorized-private", "add", "plan368-zero-target-private", sender),
				wakeToken: "plan368-zero-wrong-wake",
			},
			{
				name:      "direct reaction ineligible sender mismatch",
				message:   directReactionEnvelope("plan368-zero-ineligible-private", "add", "plan368-zero-target-private", "plan368-zero-envelope-sender-private"),
				wakeToken: "plan368-zero-authorized-wake",
			},
		}
		for index, row := range directRows {
			result, err := inbox.Store(recipient, inboxMessage{
				ID:        fmt.Sprintf("plan368-zero-direct-row-%d", index),
				From:      sender,
				Message:   row.message,
				Timestamp: time.Now().UnixMilli() + int64(index),
				WakeToken: row.wakeToken,
			})
			if err != nil || result != InboxStoreResultStored {
				t.Fatalf("%s Store() = %q, %v; want stored, nil", row.name, result, err)
			}
		}
		assertNoRecordedPush(t, recorder)
		if recorder.SendCallCount() != 0 {
			t.Fatalf("direct zero-wake controls sent %d provider requests", recorder.SendCallCount())
		}

		t.Run("direct reaction duplicate adds no second wake", func(t *testing.T) {
			duplicateTokens := newMemoryPushTokenStore()
			if err := duplicateTokens.RegisterToken(
				recipient,
				"plan368-zero-direct-duplicate-provider-token",
				platform,
				directReactionCapability,
				opaqueWakeCapability,
			); err != nil {
				t.Fatalf("duplicate RegisterToken(): %v", err)
			}
			duplicatePush := NewPushServiceWithBackend(duplicateTokens)
			duplicateRecorder := newRecordingPushSender()
			duplicatePush.sender = duplicateRecorder.Send
			duplicateInbox := NewInboxStore(duplicatePush)
			duplicateInbox.SetDirectReactionPushEnabled(true)
			duplicateInbox.RegisterWakeTokens(recipient, []string{"plan368-zero-direct-duplicate-wake"})
			entry := inboxMessage{
				ID:        "plan368-zero-direct-duplicate-row",
				From:      sender,
				Message:   directReactionEnvelope("plan368-zero-direct-duplicate-event-private", "add", "plan368-zero-direct-duplicate-target-private", sender),
				Timestamp: time.Now().UnixMilli(),
				WakeToken: "plan368-zero-direct-duplicate-wake",
			}
			if result, err := duplicateInbox.Store(recipient, entry); err != nil || result != InboxStoreResultStored {
				t.Fatalf("first duplicate fixture Store() = %q, %v; want stored, nil", result, err)
			}
			waitForRecordedPush(t, duplicateRecorder)
			if result, err := duplicateInbox.Store(recipient, entry); err != nil || result != InboxStoreResultDuplicate {
				t.Fatalf("second duplicate fixture Store() = %q, %v; want duplicate, nil", result, err)
			}
			assertNoRecordedPush(t, duplicateRecorder)
			if duplicateRecorder.SendCallCount() != 1 {
				t.Fatalf("direct duplicate provider sends = %d, want exactly first wake", duplicateRecorder.SendCallCount())
			}
		})

		const (
			groupID     = "plan368-zero-group-private"
			groupSender = "plan368-zero-group-sender-private"
			incapable   = "plan368-zero-group-incapable-private"
		)
		if err := tokens.RegisterToken(
			incapable,
			"plan368-zero-incapable-provider-token",
			platform,
			opaqueWakeCapability,
		); err != nil {
			t.Fatalf("register incapable route: %v", err)
		}
		groupStore := NewGroupInboxStore(500, 7*24*time.Hour)
		groupStore.SetPush(push)
		groupStore.SetGroupReactionPushEnabled(true)
		fixture := newSignedGroupReactionFixture(
			t,
			groupID,
			"plan368-zero-reactor-account-private",
			groupSender,
		)
		groupRows := []struct {
			name      string
			eventID   string
			action    string
			replay    []string
			nominated []string
		}{
			{
				name:      "group reaction remove",
				eventID:   "plan368-zero-group-remove-private",
				action:    "remove",
				replay:    []string{recipient},
				nominated: []string{recipient},
			},
			{
				name:      "group reaction empty nomination",
				eventID:   "plan368-zero-group-empty-private",
				action:    "add",
				replay:    []string{recipient},
				nominated: nil,
			},
			{
				name:      "group reaction incapable",
				eventID:   "plan368-zero-group-incapable-event-private",
				action:    "add",
				replay:    []string{incapable},
				nominated: []string{incapable},
			},
			{
				name:      "group reaction ineligible action",
				eventID:   "plan368-zero-group-ineligible-private",
				action:    "toggle",
				replay:    []string{recipient},
				nominated: []string{recipient},
			},
		}
		for _, row := range groupRows {
			envelope := fixture.envelope(
				t,
				row.eventID,
				row.action,
				"state-"+row.eventID,
				"target-"+row.eventID,
				row.replay,
				row.nominated,
			)
			if err := groupStore.StoreWithPushRecipients(
				groupID,
				groupSender,
				envelope,
				row.replay,
			); err != nil {
				t.Fatalf("%s StoreWithPushRecipients(): %v", row.name, err)
			}
		}
		assertNoRecordedPush(t, recorder)
		if recorder.SendCallCount() != 0 {
			t.Fatalf("group zero-wake controls sent %d provider requests", recorder.SendCallCount())
		}

		t.Run("group reaction duplicate adds no second wake", func(t *testing.T) {
			envelope := fixture.envelope(
				t,
				"plan368-zero-group-duplicate-private",
				"add",
				"plan368-zero-group-duplicate-state-private",
				"plan368-zero-group-duplicate-target-private",
				[]string{recipient},
				[]string{recipient},
			)
			if err := groupStore.StoreWithPushRecipients(
				groupID,
				groupSender,
				envelope,
				[]string{recipient},
			); err != nil {
				t.Fatalf("first StoreWithPushRecipients(): %v", err)
			}
			waitForGroupReactionPushes(t, recorder, 1)
			for {
				select {
				case <-recorder.sentSignal:
					continue
				default:
				}
				break
			}
			if err := groupStore.StoreWithPushRecipients(
				groupID,
				groupSender,
				envelope,
				[]string{recipient},
			); err != nil {
				t.Fatalf("duplicate StoreWithPushRecipients(): %v", err)
			}
			assertNoAdditionalGroupReactionPush(t, recorder, 1)
		})

		t.Run("group ordinary self recipient remains zero", func(t *testing.T) {
			const (
				ordinaryGroupID = "plan368-group-ordinary-current-source-private"
				ordinaryToken   = "plan368-group-ordinary-provider-token"
			)
			ordinaryTokens := newMemoryPushTokenStore()
			if err := ordinaryTokens.RegisterToken(
				recipient,
				ordinaryToken,
				platform,
				opaqueWakeCapability,
			); err != nil {
				t.Fatalf("ordinary RegisterToken(): %v", err)
			}
			ordinaryPush := NewPushServiceWithBackend(ordinaryTokens)
			ordinaryRecorder := newRecordingPushSender()
			ordinaryPush.sender = ordinaryRecorder.Send
			ordinaryStore := NewGroupInboxStore(500, 7*24*time.Hour)
			ordinaryStore.SetPush(ordinaryPush)
			if err := ordinaryStore.StoreWithPushRecipients(
				ordinaryGroupID,
				recipient,
				`{"type":"group_system","version":"1","messageId":"plan368-group-ordinary-self-private"}`,
				[]string{recipient},
			); err != nil {
				t.Fatalf("self-only ordinary StoreWithPushRecipients(): %v", err)
			}
			assertNoAdditionalGroupReactionPush(t, ordinaryRecorder, 0)
		})
	})
}

func TestRelayNotificationClosure_OpaqueWakeAndroidProviderRequest(t *testing.T) {
	const providerToken = "plan368-provider-token-visible"
	want := map[string]any{
		"message": map[string]any{
			"token": providerToken,
			"data": map[string]any{
				"v": "1",
				"w": "1",
			},
			"android": map[string]any{
				"collapse_key": "mailbox",
				"priority":     "high",
				"ttl":          "300s",
			},
		},
	}
	plan368ExerciseProviderRequests(t, "android", time.Unix(1_800_000_000, 0).UTC(), want)
	plan368AssertRealStoreZeroWake(t, "android")
}

func TestRelayNotificationClosure_OpaqueWakeIOSProviderRequest(t *testing.T) {
	const providerToken = "plan368-provider-token-visible"
	now := time.Unix(1_800_000_000, 987_654_321).UTC()
	want := map[string]any{
		"message": map[string]any{
			"token": providerToken,
			"apns": map[string]any{
				"headers": map[string]any{
					"apns-push-type":   "alert",
					"apns-priority":    "10",
					"apns-topic":       "com.mknoon.app",
					"apns-expiration":  "1800000300",
					"apns-collapse-id": "mailbox",
				},
				"payload": map[string]any{
					"aps": map[string]any{
						"alert": map[string]any{
							"title-loc-key": "NEW_MESSAGE_TITLE",
							"loc-key":       "NEW_MESSAGE_BODY",
						},
						"mutable-content": float64(1),
						"sound":           "default",
						"category":        "MESSAGE_WAKE",
					},
					"v": "1",
				},
			},
		},
	}
	producerCount := len(plan368ProviderProducerCases(t, "plan368-provider-recipient-peer-private"))
	if clockCalls := plan368ExerciseProviderRequests(t, "ios", now, want); clockCalls != producerCount {
		t.Fatalf("injected clock calls = %d, want one per iOS request (%d)", clockCalls, producerCount)
	}
	plan368AssertRealStoreZeroWake(t, "ios")
}

func TestRelayNotificationClosure_OpaqueWakeFailureAndGenerationSafeRevoke(t *testing.T) {
	const (
		peerID        = "plan368-failure-recipient-private"
		providerToken = "plan368-failure-provider-token"
		platform      = "android"
		sender        = "plan368-failure-sender-private"
	)
	message := ordinaryChatCiphertextEnvelope(8, 16)
	wantFixed, err := plan368OpaqueMessage(providerToken, platform, time.Time{})
	if err != nil {
		t.Fatalf("build fixed request: %v", err)
	}

	t.Run("transient ladder retries only the identical fixed request", func(t *testing.T) {
		store := newMemoryPushTokenStore()
		if err := store.RegisterToken(peerID, providerToken, platform, opaqueWakeCapability); err != nil {
			t.Fatalf("RegisterToken(): %v", err)
		}
		original := plan367Route(t, store, peerID)
		probe := &plan368BackendProbe{delegate: store}
		push := NewPushServiceWithBackend(probe)
		push.retryDelays = []time.Duration{0, 0}
		recorder := newRecordingPushSender()
		recorder.onSend = func(context.Context, *messaging.Message) (string, error) {
			return "", errors.New("plan368-private-transient-provider-error")
		}
		push.sender = recorder.Send

		push.SendNotification(context.Background(), peerID, sender, message)

		if recorder.SendCallCount() != 3 {
			t.Fatalf("transient provider sends = %d, want full three-attempt ladder", recorder.SendCallCount())
		}
		for index, sent := range recorder.Messages() {
			plan367AssertMessageEquivalent(t, sent, wantFixed)
			if sent.Data["sender_id"] != "" || sent.Data["type"] != "" {
				t.Fatalf("attempt %d downgraded to a rich request: %#v", index+1, sent.Data)
			}
		}
		current := plan367Route(t, store, peerID)
		if !reflect.DeepEqual(current, original) {
			t.Fatalf("transient failure changed route: got %#v want %#v", current, original)
		}
		plan368AssertCalls(t, probe, 1, 1, 0)
	})

	t.Run("generic provider failure never constructs a rich fallback", func(t *testing.T) {
		store := newMemoryPushTokenStore()
		if err := store.RegisterToken(peerID, providerToken, platform, opaqueWakeCapability); err != nil {
			t.Fatalf("RegisterToken(): %v", err)
		}
		route := plan367Route(t, store, peerID)
		probe := &plan368BackendProbe{delegate: store}
		push := NewPushServiceWithBackend(probe)
		push.retryDelays = nil
		recorder := newRecordingPushSender()
		recorder.onSend = func(context.Context, *messaging.Message) (string, error) {
			return "", errors.New("plan368-private-generic-provider-error")
		}
		push.sender = recorder.Send
		richBuildCalls := 0

		push.sendSelectedPushThroughGateway(
			context.Background(),
			peerID,
			route,
			"",
			func() *messaging.Message {
				richBuildCalls++
				return buildPushMessage(providerToken, sender, message)
			},
		)

		if richBuildCalls != 0 {
			t.Fatalf("selected opaque route constructed rich fallback %d time(s)", richBuildCalls)
		}
		if recorder.SendCallCount() != 1 {
			t.Fatalf("generic opaque failure sends = %d, want one fixed attempt", recorder.SendCallCount())
		}
		plan367AssertMessageEquivalent(t, recorder.LastMessage(), wantFixed)
		plan368AssertCalls(t, probe, 0, 1, 0)
	})

	t.Run("typed Firebase permanent failure revokes the exact current generation", func(t *testing.T) {
		store := newMemoryPushTokenStore()
		if err := store.RegisterToken(peerID, providerToken, platform, opaqueWakeCapability); err != nil {
			t.Fatalf("RegisterToken(): %v", err)
		}
		original := plan367Route(t, store, peerID)
		probe := &plan368BackendProbe{delegate: store}
		push := NewPushServiceWithBackend(probe)
		push.retryDelays = []time.Duration{0, 0}
		var hits atomic.Int32
		var captureMu sync.Mutex
		var captured map[string]any
		var captureErr error
		push.client = plan367FirebaseClient(t, http.HandlerFunc(func(w http.ResponseWriter, request *http.Request) {
			raw, readErr := io.ReadAll(request.Body)
			var decoded map[string]any
			if readErr == nil {
				readErr = json.Unmarshal(raw, &decoded)
			}
			captureMu.Lock()
			captured = decoded
			captureErr = readErr
			captureMu.Unlock()
			hits.Add(1)
			plan367WritePermanentFCMError(w)
		}))

		push.SendNotification(context.Background(), peerID, sender, message)

		if got := hits.Load(); got != 1 {
			t.Fatalf("typed Firebase provider hits = %d, want exactly one", got)
		}
		captureMu.Lock()
		gotRequest := captured
		gotCaptureErr := captureErr
		captureMu.Unlock()
		if gotCaptureErr != nil {
			t.Fatalf("capture typed Firebase request: %v", gotCaptureErr)
		}
		plan368AssertExactProviderRequest(t, "typed Firebase permanent request", gotRequest, map[string]any{
			"message": map[string]any{
				"token": providerToken,
				"data":  map[string]any{"v": "1", "w": "1"},
				"android": map[string]any{
					"collapse_key": "mailbox",
					"priority":     "high",
					"ttl":          "300s",
				},
			},
		})
		if route, lookupErr := store.LookupRoute(peerID); lookupErr != nil || route != nil {
			t.Fatalf("exact permanent revoke left route %#v err=%v", route, lookupErr)
		}
		revoked := probe.revoked()
		if len(revoked) != 1 || !reflect.DeepEqual(revoked[0], original) {
			t.Fatalf("revoked routes = %#v, want exact original %#v", revoked, original)
		}
		plan368AssertCalls(t, probe, 1, 1, 1)
	})

	for _, row := range []struct {
		name              string
		refreshTokens     []string
		wantCurrentToken  string
		minimumGeneration uint64
	}{
		{
			name:              "concurrent refresh survives old permanent result",
			refreshTokens:     []string{"plan368-failure-refreshed-token"},
			wantCurrentToken:  "plan368-failure-refreshed-token",
			minimumGeneration: 2,
		},
		{
			name: "ABA token value still has a newer generation",
			refreshTokens: []string{
				"plan368-failure-intermediate-token",
				providerToken,
			},
			wantCurrentToken:  providerToken,
			minimumGeneration: 3,
		},
	} {
		row := row
		t.Run(row.name, func(t *testing.T) {
			store := newMemoryPushTokenStore()
			if err := store.RegisterToken(peerID, providerToken, platform, opaqueWakeCapability); err != nil {
				t.Fatalf("initial RegisterToken(): %v", err)
			}
			original := plan367Route(t, store, peerID)
			probe := &plan368BackendProbe{delegate: store}
			push := NewPushServiceWithBackend(probe)
			push.retryDelays = []time.Duration{0, 0}
			recorder := newRecordingPushSender()
			recorder.onSend = func(context.Context, *messaging.Message) (string, error) {
				for _, tokenValue := range row.refreshTokens {
					if registerErr := store.RegisterToken(
						peerID,
						tokenValue,
						platform,
						opaqueWakeCapability,
					); registerErr != nil {
						t.Errorf("concurrent RegisterToken(%q): %v", tokenValue, registerErr)
					}
				}
				return "", errors.New("registration-token-not-registered")
			}
			push.sender = recorder.Send

			push.SendNotification(context.Background(), peerID, sender, message)

			if recorder.SendCallCount() != 1 {
				t.Fatalf("permanent provider sends = %d, want exactly one", recorder.SendCallCount())
			}
			plan367AssertMessageEquivalent(t, recorder.LastMessage(), wantFixed)
			current := plan367Route(t, store, peerID)
			if current.Generation < row.minimumGeneration || current.Generation <= original.Generation {
				t.Fatalf("current generation = %d, original=%d minimum=%d", current.Generation, original.Generation, row.minimumGeneration)
			}
			target := plan367Target(t, store, current)
			if target.Token != row.wantCurrentToken {
				t.Fatalf("current provider token = %q, want %q", target.Token, row.wantCurrentToken)
			}
			revoked := probe.revoked()
			if len(revoked) != 1 || !reflect.DeepEqual(revoked[0], original) {
				t.Fatalf("revoked routes = %#v, want stale original %#v", revoked, original)
			}
			plan368AssertCalls(t, probe, 1, 1, 1)
		})
	}

	t.Run("fixed request refuses provider-size fallback", func(t *testing.T) {
		store := newMemoryPushTokenStore()
		if err := store.RegisterToken(peerID, providerToken, platform, opaqueWakeCapability); err != nil {
			t.Fatalf("RegisterToken(): %v", err)
		}
		original := plan367Route(t, store, peerID)
		probe := &plan368BackendProbe{delegate: store}
		push := NewPushServiceWithBackend(probe)
		push.retryDelays = []time.Duration{0, 0}
		recorder := newRecordingPushSender()
		recorder.onSend = func(context.Context, *messaging.Message) (string, error) {
			return "", errors.New("messaging/invalid-argument: Message is too large. The maximum is 4K")
		}
		push.sender = recorder.Send

		push.SendNotification(context.Background(), peerID, sender, message)

		if recorder.SendCallCount() != 1 {
			t.Fatalf("fixed size rejection sends = %d, want no strict fallback", recorder.SendCallCount())
		}
		plan367AssertMessageEquivalent(t, recorder.LastMessage(), wantFixed)
		if current := plan367Route(t, store, peerID); !reflect.DeepEqual(current, original) {
			t.Fatalf("size rejection changed opaque route: got %#v want %#v", current, original)
		}
		plan368AssertCalls(t, probe, 1, 1, 0)
	})

	t.Run("legacy rich request retains one strict provider-size fallback", func(t *testing.T) {
		store := newMemoryPushTokenStore()
		if err := store.RegisterToken(peerID, providerToken, platform); err != nil {
			t.Fatalf("RegisterToken(): %v", err)
		}
		original := plan367Route(t, store, peerID)
		probe := &plan368BackendProbe{delegate: store}
		push := NewPushServiceWithBackend(probe)
		push.retryDelays = []time.Duration{0, 0}
		recorder := newRecordingPushSender()
		recorder.onSend = func(context.Context, *messaging.Message) (string, error) {
			if recorder.SendCallCount() == 1 {
				return "", errors.New("messaging/invalid-argument: Message is too large. The maximum is 4K")
			}
			return "plan368-strict-fallback-success", nil
		}
		push.sender = recorder.Send

		push.SendNotification(context.Background(), peerID, sender, message)

		if recorder.SendCallCount() != 2 {
			t.Fatalf("legacy size rejection sends = %d, want original + one strict fallback", recorder.SendCallCount())
		}
		wantRich := projectPushMessageForPlatform(
			buildPushMessage(providerToken, sender, message),
			platform,
		)
		plan367AssertMessageEquivalent(t, recorder.Messages()[0], wantRich)
		wantStrict := buildStrictMinimalFallbackPushMessage(wantRich)
		if wantStrict == nil {
			t.Fatal("legacy rich fixture did not produce a strict fallback")
		}
		plan367AssertMessageEquivalent(t, recorder.Messages()[1], wantStrict)
		if reflect.DeepEqual(recorder.Messages()[0], wantFixed) || reflect.DeepEqual(recorder.Messages()[1], wantFixed) {
			t.Fatal("legacy fallback path was replaced by the opaque fixed request")
		}
		if current := plan367Route(t, store, peerID); !reflect.DeepEqual(current, original) {
			t.Fatalf("successful strict fallback changed route: got %#v want %#v", current, original)
		}
		plan368AssertCalls(t, probe, 1, 1, 0)
	})
}
