package main

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"log"
	"sort"
	"time"

	"github.com/redis/go-redis/v9"
)

type redisWakeTokenStore struct {
	client *redis.Client
	prefix string
}

func (s *redisWakeTokenStore) key(peerID string) string {
	return s.prefix + "wake_auth:" + base64.RawURLEncoding.EncodeToString([]byte(peerID))
}

func wakeTokenDigest(peerID, token string) string {
	// A length-delimited encoding binds the high-entropy recipient-issued
	// bearer token to this recipient without retaining the usable token.
	encoded, _ := json.Marshal([]string{"wake-auth-v1", peerID, token})
	digest := sha256.Sum256(encoded)
	return hex.EncodeToString(digest[:])
}

func (s *redisWakeTokenStore) RegisterWakeTokens(peerID string, tokens []string) error {
	set := make(map[string]struct{}, len(tokens))
	for _, token := range tokens {
		if token != "" {
			set[wakeTokenDigest(peerID, token)] = struct{}{}
		}
	}
	if len(set) == 0 {
		return s.ClearWakeTokens(peerID)
	}
	digests := make([]string, 0, len(set))
	for digest := range set {
		digests = append(digests, digest)
	}
	sort.Strings(digests)
	payload, err := json.Marshal(digests)
	if err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	// SET atomically replaces the full set. No TTL: like the durable push
	// route, authorization must survive an arbitrarily long offline interval.
	return s.client.Set(ctx, s.key(peerID), payload, 0).Err()
}

func (s *redisWakeTokenStore) ClearWakeTokens(peerID string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	return s.client.Del(ctx, s.key(peerID)).Err()
}

func (s *redisWakeTokenStore) read(peerID string) ([]string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	payload, err := s.client.Get(ctx, s.key(peerID)).Bytes()
	if errors.Is(err, redis.Nil) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var digests []string
	if err := json.Unmarshal(payload, &digests); err != nil {
		return nil, err
	}
	if len(digests) == 0 {
		return nil, errors.New("empty persisted wake authorization")
	}
	for _, digest := range digests {
		decoded, err := hex.DecodeString(digest)
		if err != nil || len(decoded) != sha256.Size {
			return nil, errors.New("invalid persisted wake authorization")
		}
	}
	return digests, nil
}

func (s *redisWakeTokenStore) HasRegisteredSet(peerID string) bool {
	digests, err := s.read(peerID)
	// Failure must never be mistaken for an unregistered legacy recipient.
	return err != nil || len(digests) > 0
}

func (s *redisWakeTokenStore) IsAuthorized(peerID, token string) bool {
	return s.AuthorizesWake(peerID, token, false)
}

func (s *redisWakeTokenStore) AuthorizesWake(peerID, token string, requireRegistered bool) bool {
	digests, err := s.read(peerID)
	if err != nil {
		log.Printf("[WAKE_AUTH] outcome=lookup_failed")
		return false
	}
	if len(digests) == 0 {
		return !requireRegistered
	}
	digest := wakeTokenDigest(peerID, token)
	for _, authorized := range digests {
		if authorized == digest {
			return true
		}
	}
	return false
}
