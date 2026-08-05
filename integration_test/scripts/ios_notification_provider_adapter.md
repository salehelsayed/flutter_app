# iOS notification provider adapter

`ios_notification_provider_adapter.py` is the fail-closed development-APNs
adapter invoked by `ios_notification_payload_xcui_driver.dart`. It has one
non-live pre-build action and three bounded runtime actions:

```text
probe | setup | cleanup | rollback
```

It never builds an app. `probe` makes no network, relay, or device call.
Runtime uses the centrally built app and the explicitly selected disposable
iPhone; it never derives a transport identity from a hardware UDID.

## Stable pre-build probe

Run `probe` before the central `ios.device.production` build so the complete
redacted staging manifest is available to the build-cache fingerprint:

```sh
export SIMS_IOS_APNS_AUTH_KEY_PATH='/private/AuthKey_KEYID.p8'
export SIMS_IOS_APNS_KEY_ID='ABCDEFGHIJ'
export SIMS_IOS_APNS_TEAM_ID='397R9Q4WMX'

(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go build \
  -o '/private/iospayloadproducer' ./cmd/iospayloadproducer)

integration_test/scripts/ios_notification_provider_adapter.py \
  --action probe \
  --receiver '<physical-iphone-id>' \
  --peer-device '<observed-receiver-libp2p-peer-id>' \
  --provisioning-profile '/private/development.mobileprovision' \
  --candidate-app-revision '<immutable-app-revision>' \
  --candidate-relay-revision '<immutable-relay-revision>' \
  --candidate-relay-sha256 '<lowercase-sha256>' \
  --relay-address '<attested-relay-address>' \
  --relay-fixture-driver integration_test/scripts/ios_notification_relay_fixture_driver.py \
  --payload-producer '/private/iospayloadproducer' \
  --output '/private/ios-staging-manifest.json'
```

The provisioning profile may instead come from
`SIMS_IOS_PROVISIONING_PROFILE_PATH`, and the fixture driver may come from
`SIMS_IOS_NOTIFICATION_RELAY_FIXTURE_DRIVER`.

The probe decodes the exact CMS with `security cms -D -i` and requires:

- team `397R9Q4WMX` (or the exact configured ten-character APNs team);
- application identifier `<team>.com.mknoon.app`;
- `aps-environment=development`;
- the exact receiver in `ProvisionedDevices`;
- a non-expired profile; and
- exactly one `DeveloperCertificates` leaf.

It hashes that leaf's DER bytes, hashes the complete provisioning profile and
local fixture driver, verifies that the prebuilt payload producer reports Go
1.25 build metadata, hashes that producer, and locally mints an ES256 JWT with
the owner-only `.p8` key. The JWT is discarded. No key ID, JWT, private key,
device token, payload, or ciphertext enters the manifest. Sorted relay
addresses and the absence of a capture timestamp make repeated probes over
unchanged inputs byte-stable. The output is atomically written as `0600`.

During runtime the adapter extracts the actual signed Runner leaf certificate
with `codesign --extract-certificates` and requires its SHA-256 to equal both
`signingIdentitySha256` and `signingCertificateSha256` in this manifest.

## Runtime private inputs

These inputs must be current-user-owned, non-symlink regular files with no
group/world permission:

- `SIMS_IOS_APNS_AUTH_KEY_PATH`: Apple `.p8` auth key.
- `SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_PATH`: `0600` receiver handoff
  produced after installing the exact candidate.
- `SIMS_IOS_NOTIFICATION_PAYLOAD_PRODUCER`: the prebuilt Go 1.25 producer whose
  SHA-256 equals `payloadProducerSha256` in the staging manifest.
- the provider request and relay SSH key passed on the command line.

The non-secret
`SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_NONCE` binds the handoff to this run.
The handoff schema is
`mknoon.sims.ios-provider-receiver-handoff.v2` with exactly:

```text
schema, captureNonce, receiverDeviceId, peerDeviceId, bundleId,
apnsEnvironment, apnsDeviceToken, mlKemPublicKey, notificationAuthorization,
notificationAlertSetting, notificationBadgeSetting, capturedAt
```

The adapter validates the exact receiver, observed transport peer, bundle,
nonce, freshness, enabled alert and badge settings, and `development`
environment. The raw APNs device token is
read only from this structured handoff. There is no standalone device-token
path or relay token input.

After the exact app is installed, the outer driver captures the handoff and
then invokes the attested producer with the private request, handoff, run ID,
and nonce. Its `0600` output becomes
`SIMS_IOS_NOTIFICATION_APNS_PAYLOAD_PATH`; it is never expected to exist before
the post-install handoff. The driver validates its bounded encrypted route and
deletes it in `finally`.

One outer campaign runs two isolated legs through this same stack. The first
retains the airplane-mode staged-envelope tap proof. After its full
relay/app/notification cleanup, the recovery leg reinstalls the same signed
app, sends one fresh real APNs payload, and uses the protected Runner proof to
observe delivered `badge == nil`, absolute badge convergence, exact owned-card
retirement, and unrelated local-card survival. This is not a generic
multi-payload provider API; each leg keeps the existing one-payload lifecycle.

The three expected display strings are canonical, trimmed printable ASCII so
Go, Python, Dart, Swift, and XCUITest count and compare identical bytes.
`expectedTitle` is limited to 30 characters because the producer binds it to
the ephemeral sender contact username. `expectedMessageText` is limited to
140 characters, matching the NSE preview cap. `expectedBody` is the
deliberately visible APNs fallback body and remains bound to the exact outgoing
`aps.alert`.
After successful NSE decryption, iOS replaces that fallback body with
`expectedMessageText`, so the Springboard/tap XCUITest expects the decrypted
message text while the payload validator continues to require—and plaintext
scan—the distinct fallback body.

The adapter decoder independently rejects duplicate JSON keys. The exact
source bytes are copied to an immutable private snapshot, bounded to 4096
bytes, and SHA-256 bound to every lifecycle/fixture receipt. Those same bytes
are given to the relay fixture and sent with curl `data-binary`; no re-encoding
occurs. A normalized recursive plaintext scan covers the whole payload,
including `aps`, except the exact allowed visible alert title and body. The
handoff token must hex-decode to exactly 32 bytes and the receiver ML-KEM public
key must base64-decode to exactly 1184 bytes.

Before APNs submission, the outer driver asks the bootstrap helper to seed the
ephemeral payload `sender_id` into both the app contact store and shared
Keychain projection. The helper consumes the immutable payload privately and
emits only a hash-bound
`mknoon.sims.ios-sender-projection-host-receipt.v1` receipt. A second XCUITest
readiness selector backgrounds the app after this setup. Cleanup is
idempotently attempted by the outer `finally` and by provider recovery before
the authorized app uninstall, so the fixture cannot survive a timeout.

## Development APNs and relay lifecycle

Only equal `apnsEnvironment=development` and
`signingEntitlementEnvironment=development` are accepted. The sole APNs host
is `https://api.sandbox.push.apple.com`. HTTP failures are classified from the
structured APNs `reason`: credential/handoff reasons produce a configuration
block, while malformed payload and service failures remain operational
failures. Alert submissions use a bounded 120-second `apns-expiration` window
so APNs can retry transient device-channel churn without leaving a stale test
notification after the driver's 155-second observation and cleanup window.

Before any fixture subprocess can mutate state, the adapter atomically writes
`fixture_spawn_pending`, `cleanup_spawn_pending`, or
`rollback_spawn_pending` to its private lifecycle journal. Fixture calls use a
new process session; timeouts and signals terminate the whole descendant
process group.

The deterministic journal includes the exact staging-manifest SHA. An existing
journal is validated before any snapshot write. Setup refuses run/nonce reuse;
cleanup and rollback use the already bound immutable payload snapshot (or
reconstruct it only when the exact hash matches), preventing a changed payload
from orphaning an earlier relay entry.

The relay fixture receives, without a shell:

```text
--action setup|cleanup|rollback
--apns-payload <private-exact-snapshot>
--apns-payload-sha256 <full-sha256>
--receiver-handoff-sha256 <full-sha256>
--lifecycle <private-journal>
--provider-receipt <exact-setup-receipt>  # cleanup only
--output <private-temporary-receipt>
```

It also receives `SIMS_CHILD_BUILDS_FORBIDDEN=1` and
`SIMS_MANUAL_ACTIONS_FORBIDDEN=1`. Every accepted receipt must bind the exact
run, receiver/peer hashes, request hash, payload hash, handoff hash, and action.

Any setup/cleanup exception after the mutation guard—including timeout,
signal, fixture failure, APNs rejection, or receipt/disk write failure—enters
the same idempotent recovery path. Public `--action rollback` exposes that path
to the outer driver. Recovery clears the relay fixture and uses exact
`xcrun devicectl device uninstall app --device <id> com.mknoon.app` arguments;
an already absent app is accepted only from an explicit devicectl absence
result. Incomplete recovery is always a failure.

The outer driver budgets six minutes for setup, four for cleanup, and three
for rollback. On timeout it gives the adapter twenty seconds after SIGTERM to
finish recovery before SIGKILL, then invokes public rollback and validates its
redacted recovery receipt.

## Focused tests

```sh
python3 -m unittest scripts.test.ios_notification_provider_adapter_test
flutter test test/integration/ios_notification_provider_adapter_contract_test.dart
flutter test test/integration/ios_notification_payload_xcui_contract_test.dart
```

The Python suite replaces `security`, `codesign`, curl, relay, and devicectl
with local fakes. It proves the local probe performs no live call and runtime
tests never contact APNs, a relay, or a device.
