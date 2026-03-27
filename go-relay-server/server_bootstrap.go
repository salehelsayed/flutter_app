package main

import (
	"context"
	"fmt"
	"os"
	"strings"
)

const (
	backendKindMemory = "memory"
	backendKindRedis  = "redis"
)

type backendConfig struct {
	Kind        string
	RedisURL    string
	RedisPrefix string
}

type controlPlaneStores struct {
	Rendezvous *RendezvousStore
	Inbox      *InboxStore
	GroupInbox *GroupInboxStore
	Push       *PushService

	RendezvousBackend RendezvousBackend
	InboxBackend      InboxBackend
	GroupInboxBackend GroupInboxBackend
	PushTokenBackend  PushTokenBackend

	closeFn func() error
}

func loadBackendConfigFromEnv() backendConfig {
	kind := strings.TrimSpace(strings.ToLower(os.Getenv("RELAY_BACKEND")))
	if kind == "" {
		kind = backendKindMemory
	}

	prefix := strings.TrimSpace(os.Getenv("REDIS_PREFIX"))
	if prefix == "" {
		prefix = "relay:"
	}
	if prefix != "" && !strings.HasSuffix(prefix, ":") {
		prefix += ":"
	}

	return backendConfig{
		Kind:        kind,
		RedisURL:    strings.TrimSpace(os.Getenv("REDIS_URL")),
		RedisPrefix: prefix,
	}
}

func newControlPlaneStores(
	ctx context.Context,
	cfg backendConfig,
	limits ServerLimits,
	serviceAccountPath string,
) (*controlPlaneStores, error) {
	switch cfg.Kind {
	case backendKindMemory:
		pushBackend := newMemoryPushTokenStore()
		push := newPushServiceWithTokenBackend(ctx, serviceAccountPath, pushBackend)
		rzBackend := newMemoryRendezvousBackend()
		inboxBackend := newMemoryInboxBackendWithLimits(limits.MaxInboxMessagesPerPeer)
		groupInboxBackend := newMemoryGroupInboxBackend(
			limits.MaxGroupInboxMessages,
			groupMessageTTL,
		)
		groupInbox := NewGroupInboxStoreWithBackend(groupInboxBackend)
		groupInbox.SetPush(push)
		return &controlPlaneStores{
			Rendezvous:        NewRendezvousStoreWithBackend(rzBackend),
			Inbox:             NewInboxStoreWithBackend(inboxBackend, push),
			GroupInbox:        groupInbox,
			Push:              push,
			RendezvousBackend: rzBackend,
			InboxBackend:      inboxBackend,
			GroupInboxBackend: groupInboxBackend,
			PushTokenBackend:  pushBackend,
		}, nil
	case backendKindRedis:
		if cfg.RedisURL == "" {
			return nil, fmt.Errorf("REDIS_URL is required when RELAY_BACKEND=redis")
		}

		client, err := newRedisClientFromURL(cfg.RedisURL)
		if err != nil {
			return nil, err
		}

		pushBackend := newRedisPushTokenBackend(client, cfg.RedisPrefix)
		push := newPushServiceWithTokenBackend(ctx, serviceAccountPath, pushBackend)
		rzBackend := newRedisRendezvousBackend(client, cfg.RedisPrefix)
		inboxBackend := newRedisInboxBackend(
			client,
			cfg.RedisPrefix,
			limits.MaxInboxMessagesPerPeer,
		)
		groupInboxBackend := newRedisGroupInboxBackend(
			client,
			cfg.RedisPrefix,
			limits.MaxGroupInboxMessages,
			groupMessageTTL,
		)
		groupInbox := NewGroupInboxStoreWithBackend(groupInboxBackend)
		groupInbox.SetPush(push)

		return &controlPlaneStores{
			Rendezvous:        NewRendezvousStoreWithBackend(rzBackend),
			Inbox:             NewInboxStoreWithBackend(inboxBackend, push),
			GroupInbox:        groupInbox,
			Push:              push,
			RendezvousBackend: rzBackend,
			InboxBackend:      inboxBackend,
			GroupInboxBackend: groupInboxBackend,
			PushTokenBackend:  pushBackend,
			closeFn:           client.Close,
		}, nil
	default:
		return nil, fmt.Errorf("unsupported relay backend: %s", cfg.Kind)
	}
}

func (s *controlPlaneStores) Close() error {
	if s == nil || s.closeFn == nil {
		return nil
	}
	return s.closeFn()
}
