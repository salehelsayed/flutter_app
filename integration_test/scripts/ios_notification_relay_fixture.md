# Private iOS relay fixture

The physical-iPhone notification leg has two private fixture components:

1. Build and run `go-mknoon/cmd/iospayloadproducer` with Go 1.25. It consumes
   the owner-only receiver handoff and provider request, then writes an
   owner-only encrypted APNs payload. Its private fixture schema is
   `mknoon.sims.ios-payload-private-fixture.v1`; the bounded `sender_id` is the
   only sender setup binding an app-side fixture may consume. The APNs device
   token is validated from the handoff but is never copied into that payload.
2. Point `SIMS_IOS_NOTIFICATION_RELAY_FIXTURE_DRIVER` at the executable
   `ios_notification_relay_fixture_driver.py`. The provider adapter invokes it
   for setup, cleanup, and rollback.

Example producer build (before the no-child-build campaign starts):

```sh
cd go-mknoon
GOTOOLCHAIN=go1.25.0 go build -o ../build/sims/private/iospayloadproducer ./cmd/iospayloadproducer
chmod 0700 ../build/sims/private/iospayloadproducer
```

The producer accepts only paths and run bindings on its command line:

```text
iospayloadproducer \
  --provider-request <owner-only-json> \
  --receiver-handoff <owner-only-json> \
  --run-id <run-id> --nonce <nonce> \
  --output <owner-only-apns-payload-json>
```

The relay driver sends its helper and private request through SSH stdin. The
remote command is `sudo -n python3 -`; ciphertext, Redis credentials, and the
Redis URL never appear in process arguments. The helper reads
`/etc/mknoon/relay-server.env`, verifies the active relay binary revision and
SHA-256 against the staging manifest, and requires the production key shape
`relay:inbox:<base64url(peerId)>`.

The relay driver has no APNs-token or raw receiver-handoff input. APNs
submission reads the token directly from the standardized owner-only receiver
handoff at the provider boundary; relay setup receives only the encrypted
payload route and its secret-free handoff SHA-256 binding.

Before SSH, the relay driver requires the provider's owner-only lifecycle
journal, the exact APNs payload SHA-256, and the receiver-handoff SHA-256. The
journal must have the exact v1 schema and action-specific pending state
(`fixture_spawn_pending`, `cleanup_spawn_pending`, or
`rollback_spawn_pending`) and must bind the exact run, receiver, peer, provider
request, staging manifest, payload, handoff, and staged-envelope digests.

Setup is idempotent for the exact run ID, nonce, receiver, APNs payload, and v2
envelope. It refuses to append at the configured inbox capacity, because doing
so could evict unrelated custody. Cleanup and rollback use a watched Redis
transaction and remove at most one exact outer entry; an already-absent exact
entry is an idempotent success. Receipts contain only hashes and immutable run
bindings.

Focused local tests (no relay, APNs, or device access):

```sh
python3 -m unittest scripts.test.ios_notification_relay_fixture_driver_test
cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./cmd/iospayloadproducer
```
