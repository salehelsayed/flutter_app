package main

import (
	"context"
	"errors"
	"testing"
)

var errTestPushTokenPersistence = errors.New("test push token persistence failure")

type failingRegisterPushTokenBackend struct {
	*memoryPushTokenStore
	registerCalls int
	lastPeerID    string
	lastToken     string
	lastPlatform  string
}

func newFailingRegisterPushTokenBackend() *failingRegisterPushTokenBackend {
	return &failingRegisterPushTokenBackend{memoryPushTokenStore: newMemoryPushTokenStore()}
}

func (b *failingRegisterPushTokenBackend) RegisterToken(
	peerID string,
	token string,
	platform string,
	_ ...string,
) error {
	b.registerCalls++
	b.lastPeerID = peerID
	b.lastToken = token
	b.lastPlatform = platform
	return errTestPushTokenPersistence
}

func TestPushServiceRegisterTokenPropagatesBackendPersistenceFailure(t *testing.T) {
	backend := newFailingRegisterPushTokenBackend()
	push := NewPushServiceWithBackend(backend)

	err := push.RegisterToken("peer-1", "token-abc", "android")
	if !errors.Is(err, errTestPushTokenPersistence) {
		t.Fatalf("RegisterToken() error = %v, want wrapped persistence failure", err)
	}
	if backend.registerCalls != 1 || backend.lastPeerID != "peer-1" ||
		backend.lastToken != "token-abc" || backend.lastPlatform != "android" {
		t.Fatalf("backend call = (%d, %q, %q, %q), want exact registration",
			backend.registerCalls, backend.lastPeerID, backend.lastToken, backend.lastPlatform)
	}
	if entry := backend.LookupToken("peer-1"); entry != nil {
		t.Fatalf("failed registration persisted token: %#v", entry)
	}
}

func TestHandleInboxStreamRegisterTokenAcknowledgesOnlyPersistedWrite(t *testing.T) {
	t.Run("success", func(t *testing.T) {
		backend := newMemoryPushTokenStore()
		inbox := NewInboxStore(NewPushServiceWithBackend(backend))
		env := setupInboxStreamEnv(t, inbox, NewGroupInboxStore(500, 0))

		stream, err := env.sender.NewStream(context.Background(), env.server.ID(), InboxProtocol)
		if err != nil {
			t.Fatalf("open stream: %v", err)
		}
		defer stream.Close()
		sendInboxReq(t, stream, inboxRequest{
			Action:   "register_token",
			Token:    "token-success",
			Platform: "android",
		})
		resp := recvInboxResp(t, stream)
		if resp.Status != "OK" || resp.Error != "" {
			t.Fatalf("response = status %q error %q, want OK", resp.Status, resp.Error)
		}
		entry := backend.LookupToken(env.sender.ID().String())
		if entry == nil || entry.Token != "token-success" || entry.Platform != "android" {
			t.Fatalf("persisted token = %#v, want exact authenticated-peer registration", entry)
		}
	})

	t.Run("persistence failure", func(t *testing.T) {
		backend := newFailingRegisterPushTokenBackend()
		inbox := NewInboxStore(NewPushServiceWithBackend(backend))
		env := setupInboxStreamEnv(t, inbox, NewGroupInboxStore(500, 0))

		stream, err := env.sender.NewStream(context.Background(), env.server.ID(), InboxProtocol)
		if err != nil {
			t.Fatalf("open stream: %v", err)
		}
		defer stream.Close()
		sendInboxReq(t, stream, inboxRequest{
			Action:   "register_token",
			Token:    "token-failure",
			Platform: "android",
		})
		resp := recvInboxResp(t, stream)
		if resp.Status != "ERROR" || resp.Error != "Push token persistence failed" {
			t.Fatalf("response = status %q error %q, want finite persistence error",
				resp.Status, resp.Error)
		}
		if backend.registerCalls != 1 || backend.lastPeerID != env.sender.ID().String() ||
			backend.lastToken != "token-failure" || backend.lastPlatform != "android" {
			t.Fatalf("backend call = (%d, %q, %q, %q), want exact authenticated-peer registration",
				backend.registerCalls, backend.lastPeerID, backend.lastToken, backend.lastPlatform)
		}
		if entry := backend.LookupToken(env.sender.ID().String()); entry != nil {
			t.Fatalf("failed registration persisted token: %#v", entry)
		}
	})
}
