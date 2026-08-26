package main

import (
	"context"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"errors"
	"fmt"
	"hash"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
)

const (
	groupMessageDispatchAdmissionDomain = "mknoon.group-message-provider-dispatch.v1"
	// Match the durable wake/custody horizon so a coordinator outage cannot
	// outlive an accepted/ambiguous provider claim and later re-send the event.
	groupMessageDispatchAdmissionTTL = 7 * 24 * time.Hour
)

type groupMessageDispatchAdmissionIdentity struct {
	recipientPeerID string
	groupID         string
	messageID       string
	prehashedKey    string
}

func newGroupMessageDispatchAdmissionIdentity(
	recipientPeerID string,
	groupID string,
	messageID string,
) (groupMessageDispatchAdmissionIdentity, bool) {
	for _, component := range []string{recipientPeerID, groupID, messageID} {
		if component == "" || component != strings.TrimSpace(component) {
			return groupMessageDispatchAdmissionIdentity{}, false
		}
	}
	return groupMessageDispatchAdmissionIdentity{
		recipientPeerID: recipientPeerID,
		groupID:         groupID,
		messageID:       messageID,
	}, true
}

func canonicalGroupMessageDispatchAdmissionStorageKey(value string) bool {
	if len(value) != sha256.Size*2 || value != strings.ToLower(value) ||
		value != strings.TrimSpace(value) {
		return false
	}
	decoded, err := hex.DecodeString(value)
	return err == nil && len(decoded) == sha256.Size
}

func groupMessageDispatchAdmissionIdentityFromStorageKey(
	storageKey string,
) (groupMessageDispatchAdmissionIdentity, bool) {
	if !canonicalGroupMessageDispatchAdmissionStorageKey(storageKey) {
		return groupMessageDispatchAdmissionIdentity{}, false
	}
	return groupMessageDispatchAdmissionIdentity{prehashedKey: storageKey}, true
}

func writeGroupMessageDispatchAdmissionComponent(digest hash.Hash, value string) {
	var size [8]byte
	binary.BigEndian.PutUint64(size[:], uint64(len([]byte(value))))
	_, _ = digest.Write(size[:])
	_, _ = digest.Write([]byte(value))
}

func (identity groupMessageDispatchAdmissionIdentity) storageKey() string {
	if identity.prehashedKey != "" {
		return identity.prehashedKey
	}
	digest := sha256.New()
	writeGroupMessageDispatchAdmissionComponent(digest, groupMessageDispatchAdmissionDomain)
	writeGroupMessageDispatchAdmissionComponent(digest, identity.recipientPeerID)
	writeGroupMessageDispatchAdmissionComponent(digest, identity.groupID)
	writeGroupMessageDispatchAdmissionComponent(digest, identity.messageID)
	return hex.EncodeToString(digest.Sum(nil))
}

type groupMessageDispatchAdmissionLease struct {
	key   string
	owner string
}

type groupMessageDispatchAdmissionBackend interface {
	TryAcquire(
		ctx context.Context,
		identity groupMessageDispatchAdmissionIdentity,
	) (lease groupMessageDispatchAdmissionLease, acquired bool, err error)
	Release(ctx context.Context, lease groupMessageDispatchAdmissionLease) error
}

type memoryGroupMessageDispatchAdmissionClaim struct {
	owner     string
	expiresAt time.Time
}

type memoryGroupMessageDispatchAdmissionBackend struct {
	mu        sync.Mutex
	claims    map[string]memoryGroupMessageDispatchAdmissionClaim
	ttl       time.Duration
	now       func() time.Time
	nextOwner uint64
}

func newMemoryGroupMessageDispatchAdmissionBackend(
	ttl time.Duration,
) *memoryGroupMessageDispatchAdmissionBackend {
	return &memoryGroupMessageDispatchAdmissionBackend{
		claims: make(map[string]memoryGroupMessageDispatchAdmissionClaim),
		ttl:    ttl,
		now:    time.Now,
	}
}

func (b *memoryGroupMessageDispatchAdmissionBackend) nowTime() time.Time {
	if b != nil && b.now != nil {
		return b.now()
	}
	return time.Now()
}

func (b *memoryGroupMessageDispatchAdmissionBackend) TryAcquire(
	_ context.Context,
	identity groupMessageDispatchAdmissionIdentity,
) (groupMessageDispatchAdmissionLease, bool, error) {
	if b == nil || b.ttl <= 0 {
		return groupMessageDispatchAdmissionLease{}, false, errors.New("group message admission backend unavailable")
	}
	key := identity.storageKey()
	now := b.nowTime()
	b.mu.Lock()
	defer b.mu.Unlock()
	for existingKey, claim := range b.claims {
		if !now.Before(claim.expiresAt) {
			delete(b.claims, existingKey)
		}
	}
	if claim, exists := b.claims[key]; exists && now.Before(claim.expiresAt) {
		return groupMessageDispatchAdmissionLease{}, false, nil
	}
	b.nextOwner++
	owner := strconv.FormatUint(b.nextOwner, 10)
	b.claims[key] = memoryGroupMessageDispatchAdmissionClaim{
		owner:     owner,
		expiresAt: now.Add(b.ttl),
	}
	return groupMessageDispatchAdmissionLease{key: key, owner: owner}, true, nil
}

func (b *memoryGroupMessageDispatchAdmissionBackend) Release(
	_ context.Context,
	lease groupMessageDispatchAdmissionLease,
) error {
	if b == nil {
		return errors.New("group message admission backend unavailable")
	}
	b.mu.Lock()
	defer b.mu.Unlock()
	claim, exists := b.claims[lease.key]
	if exists && claim.owner == lease.owner {
		delete(b.claims, lease.key)
	}
	return nil
}

type redisGroupMessageDispatchAdmissionBackend struct {
	client   *redis.Client
	prefix   string
	ttl      time.Duration
	newOwner func() (string, error)
}

func newRedisGroupMessageDispatchAdmissionBackend(
	client *redis.Client,
	prefix string,
	ttl time.Duration,
) *redisGroupMessageDispatchAdmissionBackend {
	return &redisGroupMessageDispatchAdmissionBackend{
		client: client,
		prefix: prefix,
		ttl:    ttl,
		newOwner: func() (string, error) {
			owner, err := uuid.NewRandom()
			if err != nil {
				return "", err
			}
			return owner.String(), nil
		},
	}
}

func (b *redisGroupMessageDispatchAdmissionBackend) redisKey(storageKey string) string {
	return b.prefix + "group-message-provider-dispatch:v1:" + storageKey
}

func (b *redisGroupMessageDispatchAdmissionBackend) TryAcquire(
	ctx context.Context,
	identity groupMessageDispatchAdmissionIdentity,
) (groupMessageDispatchAdmissionLease, bool, error) {
	if b == nil || b.client == nil || b.ttl <= 0 || b.newOwner == nil {
		return groupMessageDispatchAdmissionLease{}, false, errors.New("group message admission backend unavailable")
	}
	owner, err := b.newOwner()
	if err != nil || owner == "" {
		return groupMessageDispatchAdmissionLease{}, false, fmt.Errorf("create group message admission owner: %w", err)
	}
	key := identity.storageKey()
	acquired, err := b.client.SetNX(ctx, b.redisKey(key), owner, b.ttl).Result()
	if err != nil {
		return groupMessageDispatchAdmissionLease{}, false, fmt.Errorf("claim group message provider dispatch: %w", err)
	}
	if !acquired {
		return groupMessageDispatchAdmissionLease{}, false, nil
	}
	return groupMessageDispatchAdmissionLease{key: key, owner: owner}, true, nil
}

var releaseRedisGroupMessageDispatchAdmission = redis.NewScript(`
if redis.call("GET", KEYS[1]) == ARGV[1] then
  return redis.call("DEL", KEYS[1])
end
return 0
`)

func (b *redisGroupMessageDispatchAdmissionBackend) Release(
	ctx context.Context,
	lease groupMessageDispatchAdmissionLease,
) error {
	if b == nil || b.client == nil {
		return errors.New("group message admission backend unavailable")
	}
	if lease.key == "" || lease.owner == "" {
		return nil
	}
	if err := releaseRedisGroupMessageDispatchAdmission.Run(
		ctx,
		b.client,
		[]string{b.redisKey(lease.key)},
		lease.owner,
	).Err(); err != nil {
		return fmt.Errorf("release group message provider dispatch: %w", err)
	}
	return nil
}
