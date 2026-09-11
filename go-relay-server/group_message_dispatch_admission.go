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

type messageDispatchAdmissionIdentity struct {
	direct          bool
	senderPeerID    string
	contentDigest   string
	recipientPeerID string
	groupID         string
	messageID       string
	prehashedKey    string
}

// Group adapters keep their existing API and Redis identity while ordinary
// direct messages share the owner-checked, expiring provider claim mechanics.
type groupMessageDispatchAdmissionIdentity = messageDispatchAdmissionIdentity
type groupMessageDispatchAdmissionLease = messageDispatchAdmissionLease
type groupMessageDispatchAdmissionBackend = messageDispatchAdmissionBackend
type memoryGroupMessageDispatchAdmissionClaim = memoryMessageDispatchAdmissionClaim
type memoryGroupMessageDispatchAdmissionBackend = memoryMessageDispatchAdmissionBackend
type redisGroupMessageDispatchAdmissionBackend = redisMessageDispatchAdmissionBackend

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

func writeMessageDispatchAdmissionComponent(digest hash.Hash, value string) {
	var size [8]byte
	binary.BigEndian.PutUint64(size[:], uint64(len([]byte(value))))
	_, _ = digest.Write(size[:])
	_, _ = digest.Write([]byte(value))
}

func (identity messageDispatchAdmissionIdentity) storageKey() string {
	if identity.prehashedKey != "" {
		return identity.prehashedKey
	}
	digest := sha256.New()
	if identity.direct {
		writeMessageDispatchAdmissionComponent(digest, directMessageDispatchAdmissionDomain)
		writeMessageDispatchAdmissionComponent(digest, identity.recipientPeerID)
		writeMessageDispatchAdmissionComponent(digest, identity.senderPeerID)
		writeMessageDispatchAdmissionComponent(digest, identity.messageID)
		writeMessageDispatchAdmissionComponent(digest, identity.contentDigest)
	} else {
		writeMessageDispatchAdmissionComponent(digest, groupMessageDispatchAdmissionDomain)
		writeMessageDispatchAdmissionComponent(digest, identity.recipientPeerID)
		writeMessageDispatchAdmissionComponent(digest, identity.groupID)
		writeMessageDispatchAdmissionComponent(digest, identity.messageID)
	}
	return hex.EncodeToString(digest.Sum(nil))
}

type messageDispatchAdmissionLease struct {
	key   string
	owner string
}

type messageDispatchAdmissionBackend interface {
	TryAcquire(
		ctx context.Context,
		identity messageDispatchAdmissionIdentity,
	) (lease messageDispatchAdmissionLease, acquired bool, err error)
	Release(ctx context.Context, lease messageDispatchAdmissionLease) error
}

type memoryMessageDispatchAdmissionClaim struct {
	owner     string
	expiresAt time.Time
}

type memoryMessageDispatchAdmissionBackend struct {
	mu        sync.Mutex
	claims    map[string]memoryMessageDispatchAdmissionClaim
	ttl       time.Duration
	now       func() time.Time
	nextOwner uint64
}

func newMemoryGroupMessageDispatchAdmissionBackend(
	ttl time.Duration,
) *memoryGroupMessageDispatchAdmissionBackend {
	return newMemoryMessageDispatchAdmissionBackend(ttl)
}

func newMemoryMessageDispatchAdmissionBackend(ttl time.Duration) *memoryMessageDispatchAdmissionBackend {
	return &memoryMessageDispatchAdmissionBackend{
		claims: make(map[string]memoryMessageDispatchAdmissionClaim),
		ttl:    ttl,
		now:    time.Now,
	}
}

func (b *memoryMessageDispatchAdmissionBackend) nowTime() time.Time {
	if b != nil && b.now != nil {
		return b.now()
	}
	return time.Now()
}

func (b *memoryMessageDispatchAdmissionBackend) TryAcquire(
	_ context.Context,
	identity messageDispatchAdmissionIdentity,
) (messageDispatchAdmissionLease, bool, error) {
	if b == nil || b.ttl <= 0 {
		return messageDispatchAdmissionLease{}, false, errors.New("message dispatch admission backend unavailable")
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
		return messageDispatchAdmissionLease{}, false, nil
	}
	b.nextOwner++
	owner := strconv.FormatUint(b.nextOwner, 10)
	b.claims[key] = memoryMessageDispatchAdmissionClaim{
		owner:     owner,
		expiresAt: now.Add(b.ttl),
	}
	return messageDispatchAdmissionLease{key: key, owner: owner}, true, nil
}

func (b *memoryMessageDispatchAdmissionBackend) Release(
	_ context.Context,
	lease messageDispatchAdmissionLease,
) error {
	if b == nil {
		return errors.New("message dispatch admission backend unavailable")
	}
	b.mu.Lock()
	defer b.mu.Unlock()
	claim, exists := b.claims[lease.key]
	if exists && claim.owner == lease.owner {
		delete(b.claims, lease.key)
	}
	return nil
}

type redisMessageDispatchAdmissionBackend struct {
	namespace string
	client    *redis.Client
	prefix    string
	ttl       time.Duration
	newOwner  func() (string, error)
}

func newRedisGroupMessageDispatchAdmissionBackend(
	client *redis.Client,
	prefix string,
	ttl time.Duration,
) *redisGroupMessageDispatchAdmissionBackend {
	return newRedisMessageDispatchAdmissionBackend(client, prefix, "group-message-provider-dispatch:v1:", ttl)
}

func newRedisMessageDispatchAdmissionBackend(
	client *redis.Client,
	prefix string,
	namespace string,
	ttl time.Duration,
) *redisMessageDispatchAdmissionBackend {
	return &redisMessageDispatchAdmissionBackend{
		client:    client,
		prefix:    prefix,
		namespace: namespace,
		ttl:       ttl,
		newOwner: func() (string, error) {
			owner, err := uuid.NewRandom()
			if err != nil {
				return "", err
			}
			return owner.String(), nil
		},
	}
}

func (b *redisMessageDispatchAdmissionBackend) redisKey(storageKey string) string {
	namespace := b.namespace
	if namespace == "" {
		namespace = "group-message-provider-dispatch:v1:"
	}
	return b.prefix + namespace + storageKey
}

func (b *redisMessageDispatchAdmissionBackend) TryAcquire(
	ctx context.Context,
	identity messageDispatchAdmissionIdentity,
) (messageDispatchAdmissionLease, bool, error) {
	if b == nil || b.client == nil || b.ttl <= 0 || b.newOwner == nil {
		return messageDispatchAdmissionLease{}, false, errors.New("message dispatch admission backend unavailable")
	}
	owner, err := b.newOwner()
	if err != nil || owner == "" {
		return messageDispatchAdmissionLease{}, false, fmt.Errorf("create message dispatch admission owner: %w", err)
	}
	key := identity.storageKey()
	acquired, err := b.client.SetNX(ctx, b.redisKey(key), owner, b.ttl).Result()
	if err != nil {
		return messageDispatchAdmissionLease{}, false, fmt.Errorf("claim message provider dispatch: %w", err)
	}
	if !acquired {
		return messageDispatchAdmissionLease{}, false, nil
	}
	return messageDispatchAdmissionLease{key: key, owner: owner}, true, nil
}

var releaseRedisMessageDispatchAdmission = redis.NewScript(`
if redis.call("GET", KEYS[1]) == ARGV[1] then
  return redis.call("DEL", KEYS[1])
end
return 0
`)

func (b *redisMessageDispatchAdmissionBackend) Release(
	ctx context.Context,
	lease messageDispatchAdmissionLease,
) error {
	if b == nil || b.client == nil {
		return errors.New("message dispatch admission backend unavailable")
	}
	if lease.key == "" || lease.owner == "" {
		return nil
	}
	if err := releaseRedisMessageDispatchAdmission.Run(
		ctx,
		b.client,
		[]string{b.redisKey(lease.key)},
		lease.owner,
	).Err(); err != nil {
		return fmt.Errorf("release message provider dispatch: %w", err)
	}
	return nil
}
