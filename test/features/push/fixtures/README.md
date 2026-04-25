# Push Decrypt Fixtures

These fixtures describe the stable data payload shape used by the relay and
the platform notification decrypt handlers.

Fields:

- `fixtureVersion`: fixture schema version
- `kind`: human-readable fixture kind
- `messageId`: stable message id used for routing and dedupe
- `routeData`: push-visible data map; this must contain only routing metadata
  and encrypted envelope material
- `plaintext`: expected decrypted content for fake-bridge and parity tests

The `routeData` map must not contain plaintext preview fields such as sender
display names, group names, message text, or media descriptors.
