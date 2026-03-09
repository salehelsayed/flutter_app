package main

// This file defines the Redis-backed implementations of the storage interfaces.
//
// For now, these are structural placeholders. They document the expected
// contract and will be implemented with a real Redis client when the
// deployment supports it.
//
// The in-memory backends in backend_memory.go are the default for tests
// and single-server deployments. Two relay instances can share state by
// pointing at the same in-memory backend (useful for integration tests)
// or by using a shared Redis backend in production.
//
// Expected Redis key layout:
//
//   rendezvous:
//     rz:{namespace}:{peerId} -> signed peer record (bytes)
//     TTL managed by Redis EXPIRE per key
//
//   inbox:
//     inbox:{peerId} -> LIST of JSON-serialized inboxMessage
//     FIFO: RPUSH to store, LPOP/LRANGE+LTRIM to retrieve
//
//   group_inbox:
//     ginbox:{groupId} -> SORTED SET (score=timestamp, member=JSON msg)
//     cursor: ZRANGEBYSCORE for sinceTimestamp, opaque cursor = last ID
//     TTL pruning: ZREMRANGEBYSCORE periodically
//
//   push_tokens:
//     push:{peerId} -> HASH { token, platform, updated_at }
//     No TTL (tokens survive server restart by design)
//
// Configuration would come from environment:
//   RELAY_BACKEND=redis
//   REDIS_URL=redis://localhost:6379
//   REDIS_PREFIX=relay:
//
// To add the real implementation:
//   1. Add go-redis/redis/v9 to go.mod
//   2. Implement each *Backend interface using the key layout above
//   3. Wire via config flag in main.go
