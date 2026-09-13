package main

import (
	"context"
	"encoding/json"
	"errors"
	"sort"
	"strings"
	"sync"
	"time"

	"firebase.google.com/go/v4/messaging"
	"github.com/redis/go-redis/v9"
)

// Quiet recovery is sender notification intent, never delivery/read authority.
// Its independent history survives custody ACK so an older delayed wake cannot
// turn a recovered message into an alert. A normal explicit retry clears it.
type directQuietRecoveryBackend interface {
	DirectQuietRecovery(context.Context, string) (bool, error)
}

type directRecoveryDispatchLock struct {
	sync.Mutex
	references int
}

var directRecoveryDispatchLocks = struct {
	sync.Mutex
	entries map[string]*directRecoveryDispatchLock
}{entries: make(map[string]*directRecoveryDispatchLock)}

func lockDirectRecovery(identity messageDispatchAdmissionIdentity) func() {
	key := identity.storageKey()
	directRecoveryDispatchLocks.Lock()
	lock := directRecoveryDispatchLocks.entries[key]
	if lock == nil {
		lock = &directRecoveryDispatchLock{}
		directRecoveryDispatchLocks.entries[key] = lock
	}
	lock.references++
	directRecoveryDispatchLocks.Unlock()
	lock.Lock()
	return func() {
		lock.Unlock()
		directRecoveryDispatchLocks.Lock()
		lock.references--
		if lock.references == 0 {
			delete(directRecoveryDispatchLocks.entries, key)
		}
		directRecoveryDispatchLocks.Unlock()
	}
}

func (is *InboxStore) prepareDirectRecoveryStore(recipient string, entry *inboxMessage) (bool, func(), error) {
	identity, valid := newDirectMessageDispatchAdmissionIdentity(recipient, entry.From, entry.Message)
	if !valid {
		entry.QuietRecovery = false
		return false, func() {}, nil
	}
	unlock := lockDirectRecovery(identity)
	prior := false
	if backend, ok := is.backend.(directQuietRecoveryBackend); ok {
		var err error
		prior, err = backend.DirectQuietRecovery(context.Background(), identity.storageKey())
		if err != nil {
			// Do not acknowledge an explicit retry after guessing its previous
			// intent. The sender retains custody and can retry this failed store.
			return false, unlock, err
		}
	}
	return prior, unlock, nil
}

func (b *memoryInboxBackend) DirectQuietRecovery(_ context.Context, identity string) (bool, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	expires := b.quietRecovery[identity]
	if !expires.After(time.Now()) {
		delete(b.quietRecovery, identity)
		return false, nil
	}
	return true, nil
}

func (b *memoryInboxBackend) rememberQuietRecoveryLocked(recipient string, entry inboxMessage) {
	now := time.Now()
	if !now.Before(b.quietRecoveryCleanupAfter) {
		for identity, expiry := range b.quietRecovery {
			if !expiry.After(now) {
				delete(b.quietRecovery, identity)
			}
		}
		b.quietRecoveryCleanupAfter = now.Add(time.Hour)
	}
	identity, valid := newDirectMessageDispatchAdmissionIdentity(recipient, entry.From, entry.Message)
	if !valid {
		return
	}
	if entry.QuietRecovery {
		if b.quietRecovery == nil {
			b.quietRecovery = make(map[string]time.Time)
		}
		b.quietRecovery[identity.storageKey()] = now.Add(maxMessageAge)
	} else {
		delete(b.quietRecovery, identity.storageKey())
	}
}

func (b *redisInboxBackend) quietRecoveryKey(identity string) string {
	return b.prefix + "direct-quiet-recovery:v1:" + identity
}

func (b *redisInboxBackend) DirectQuietRecovery(ctx context.Context, identity string) (bool, error) {
	value, err := b.client.Get(ctx, b.quietRecoveryKey(identity)).Result()
	if err == redis.Nil {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	if value != "1" {
		return false, errors.New("invalid direct quiet recovery policy")
	}
	return true, nil
}

func (b *redisInboxBackend) replaceListsWithQuietRecovery(tx *redis.Tx, replacements map[string][]string, recipient string, entry inboxMessage) error {
	ctx := context.Background()
	_, err := tx.TxPipelined(ctx, func(pipe redis.Pipeliner) error {
		keys := make([]string, 0, len(replacements))
		for key := range replacements {
			keys = append(keys, key)
		}
		sort.Strings(keys)
		for _, key := range keys {
			queueRedisListReplacement(ctx, pipe, key, replacements[key])
		}
		if identity, valid := newDirectMessageDispatchAdmissionIdentity(recipient, entry.From, entry.Message); valid {
			key := b.quietRecoveryKey(identity.storageKey())
			if entry.QuietRecovery {
				pipe.Set(ctx, key, "1", maxMessageAge)
			} else {
				pipe.Del(ctx, key)
			}
		}
		return nil
	})
	return err
}

// Changes only the transport sidecar on the exact authenticated immutable row.
func updateQuietRecoveryRows(raw []string, entry inboxMessage) []string {
	for i, value := range raw {
		var old inboxMessage
		if json.Unmarshal([]byte(value), &old) != nil || old.From != entry.From || old.Message != entry.Message {
			continue
		}
		old.QuietRecovery = entry.QuietRecovery
		encoded, err := json.Marshal(old)
		if err == nil {
			raw[i] = string(encoded)
		}
	}
	return raw
}

func buildQuietRecoveryPush(platform string) (*messaging.Message, error) {
	message := &messaging.Message{Data: map[string]string{"v": "1", "w": "1", "quietRecovery": "1"}}
	switch strings.ToLower(strings.TrimSpace(platform)) {
	case "ios":
		message.APNS = &messaging.APNSConfig{
			Headers: map[string]string{"apns-push-type": "background", "apns-priority": "5", "apns-collapse-id": "mknoon-quiet-recovery"},
			Payload: &messaging.APNSPayload{Aps: &messaging.Aps{ContentAvailable: true}},
		}
	case "android":
		message.Android = &messaging.AndroidConfig{Priority: "normal"}
	default:
		return nil, errOpaqueWakeUnsupportedPlatform
	}
	return message, nil
}

func (ps *PushService) sendQuietRecoveryWake(ctx context.Context, recipient string) {
	for attempt := 0; attempt < 2; attempt++ {
		route, err := ps.selectPushRoute(recipient, "")
		if err != nil || route == nil {
			return
		}
		// Never use the visible routing-only size fallback or acquire visible
		// admission. A background wake is advisory; custody remains available.
		err = ps.sendPushRouteThroughGateway(ctx, *route, buildQuietRecoveryPush, false)
		if !errors.Is(err, ErrPushRouteStale) {
			return
		}
	}
}

func (is *InboxStore) launchQuietRecoveryWake(recipient string, entry inboxMessage) {
	if is.push != nil && (is.wakeTokens == nil || !wakeTokenGateEnforced || is.wakeTokens.IsAuthorized(recipient, entry.WakeToken)) {
		go is.push.sendQuietRecoveryWake(context.Background(), recipient)
	}
}
