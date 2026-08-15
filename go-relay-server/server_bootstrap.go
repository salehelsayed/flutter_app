package main

import (
	"context"
	"fmt"
	"os"
	"strings"
	"time"
)

const (
	backendKindMemory = "memory"
	backendKindRedis  = "redis"
)

type backendConfig struct {
	Kind                       string
	RedisURL                   string
	RedisPrefix                string
	AckCustodyAdmissionEnabled bool
}

// IsDurable reports whether the selected control-plane backend persists state
// (inbox, push tokens, rendezvous, group inbox) across a relay process
// restart. Only the Redis backend is durable; the in-memory backend is wiped
// on restart. This is the single source of truth for the durability summary
// line and the relay_backend_durable gauge — never assume an unknown kind is
// durable (unknown kinds are rejected at newControlPlaneStores' default case).
func (c backendConfig) IsDurable() bool {
	return c.Kind == backendKindRedis
}

// backendStartupSummary renders a single operator-facing line describing the
// control-plane backend and whether it is durable. main.go logs this verbatim
// at boot and it is the human-readable companion to the relay_backend_durable
// gauge — the "is durability live?" hook ops relies on (the live env is
// gitignored, so durability silently regressing to memory is otherwise
// undetectable).
func backendStartupSummary(c backendConfig) string {
	return fmt.Sprintf("backend=%s durable=%v prefix=%s", c.Kind, c.IsDurable(), c.RedisPrefix)
}

type controlPlaneStores struct {
	Rendezvous *RendezvousStore
	Inbox      *InboxStore
	GroupInbox *GroupInboxStore
	Push       *PushService

	RendezvousBackend      RendezvousBackend
	InboxBackend           InboxBackend
	GroupInboxBackend      GroupInboxBackend
	PushTokenBackend       PushTokenBackend
	WakeOutcomeBackend     *redisWakeOutcomeStore
	WakeOutcomeCoordinator *wakeOutcomeCoordinator

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
		Kind:                       kind,
		RedisURL:                   strings.TrimSpace(os.Getenv("REDIS_URL")),
		RedisPrefix:                prefix,
		AckCustodyAdmissionEnabled: loadAckCustodyAdmissionEnabledFromEnv(),
	}
}

func newControlPlaneStores(
	ctx context.Context,
	cfg backendConfig,
	limits ServerLimits,
	serviceAccountPath string,
) (*controlPlaneStores, error) {
	if cfg.AckCustodyAdmissionEnabled && !cfg.IsDurable() {
		return nil, fmt.Errorf(
			"%s=true requires RELAY_BACKEND=redis",
			ackCustodyAdmissionEnabledEnv,
		)
	}
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
		stores := &controlPlaneStores{
			Rendezvous: NewRendezvousStoreWithBackend(rzBackend),
			Inbox: NewInboxStoreWithBackendAndCapacity(
				inboxBackend,
				push,
				limits.MaxInboxMessagesPerPeer,
			),
			GroupInbox:        groupInbox,
			Push:              push,
			RendezvousBackend: rzBackend,
			InboxBackend:      inboxBackend,
			GroupInboxBackend: groupInboxBackend,
			PushTokenBackend:  pushBackend,
		}
		stores.Inbox.SetAckCustodyAdmissionEnabled(cfg.AckCustodyAdmissionEnabled)
		stores.Inbox.SetWakeOutcomeAdmissionEnabled(false)
		stores.GroupInbox.SetWakeOutcomeAdmissionEnabled(false)
		return stores, nil
	case backendKindRedis:
		if cfg.RedisURL == "" {
			return nil, fmt.Errorf("REDIS_URL is required when RELAY_BACKEND=redis")
		}

		client, err := newRedisClientFromURL(cfg.RedisURL)
		if err != nil {
			return nil, err
		}

		pushBackend := newRedisPushTokenBackend(client, cfg.RedisPrefix)
		if err := pushBackend.ValidateStartup(); err != nil {
			_ = client.Close()
			return nil, fmt.Errorf("validate push token vault state: %w", err)
		}
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
		wakeOutcomeBackend := newRedisWakeOutcomeStore(client, cfg.RedisPrefix)
		inboxBackend.wakeOutcomes = wakeOutcomeBackend
		groupInboxBackend.wakeOutcomes = wakeOutcomeBackend
		groupInbox := NewGroupInboxStoreWithBackend(groupInboxBackend)
		groupInbox.SetPush(push)

		stores := &controlPlaneStores{
			Rendezvous: NewRendezvousStoreWithBackend(rzBackend),
			Inbox: NewInboxStoreWithBackendAndCapacity(
				inboxBackend,
				push,
				limits.MaxInboxMessagesPerPeer,
			),
			GroupInbox:         groupInbox,
			Push:               push,
			RendezvousBackend:  rzBackend,
			InboxBackend:       inboxBackend,
			GroupInboxBackend:  groupInboxBackend,
			PushTokenBackend:   pushBackend,
			WakeOutcomeBackend: wakeOutcomeBackend,
			WakeOutcomeCoordinator: newWakeOutcomeCoordinator(
				wakeOutcomeBackend,
				push.sendWakeOutcomeThroughGateway,
				time.Now,
			),
			closeFn: client.Close,
		}
		stores.Inbox.SetAckCustodyAdmissionEnabled(cfg.AckCustodyAdmissionEnabled)
		stores.Inbox.SetWakeOutcomeAdmissionEnabled(true)
		stores.GroupInbox.SetWakeOutcomeAdmissionEnabled(true)
		return stores, nil
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
