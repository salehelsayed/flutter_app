# iOS receiver bootstrap

`ios_receiver_bootstrap.py` captures the private receiver material required by
the APNs provider adapter without resetting or uninstalling the app. The
bootstrap-enabled `ios.device.production` app must already be installed as an
update over the existing `com.mknoon.app` installation so its identity and
secure storage remain intact.

The SIMS build is gated in two places:

- Dart publishes the current libp2p transport peer ID and identity ML-KEM
  public key only when `SIMS_BUILD_PROFILE_ID=ios.device.production`.
- Runner exposes the native channel only when compiled with
  `MKNOON_SIMS_IOS_RECEIVER_BOOTSTRAP`; native code also requires a fresh,
  nonce-bound request inside the app data container.

Configure owner-only output and a non-secret run nonce, then run the helper:

```sh
export SIMS_IOS_PHYSICAL_DEVICE_ID='<explicit-connected-iphone-id>'
export SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_NONCE='<run-nonce>'
export SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_PATH='<private-0600-json-path>'
integration_test/scripts/ios_receiver_bootstrap.py
```

The output schema is
`mknoon.sims.ios-provider-receiver-handoff.v2`. It binds the nonce, receiver
device ID, observed libp2p transport peer ID, bundle ID, `development` APNs
environment, raw APNs device token, receiver ML-KEM public key, and capture
time. It also binds native `notificationAuthorization`
(`authorized`/`provisional`/`ephemeral`) and `notificationAlertSetting`
(`enabled` only), plus `notificationBadgeSetting` (`enabled` only); capture
remains gated until settings are known and fails closed for denied,
undetermined, alert-disabled, or badge-disabled installations. The APNs
token appears only in this 0600 private input and the transient protected
app-container response. It is never printed or passed as a process argument.
The provider adapter consumes the file through
`SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_PATH` and validates the nonce from
`SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_NONCE`.

The helper always stages a cleanup request and removes its local transfer
directory. If app-container cleanup fails, it deletes the host output and
fails. The provider/outer campaign owns final removal of the designated output
after setup/cleanup completes.

## Disposable sender seed for the payload fast path

After the private APNs payload producer has written
`SIMS_IOS_NOTIFICATION_APNS_PAYLOAD_PATH`, the same helper can seed the exact
ephemeral sender into the app database and recipient-owned notification
projection:

```sh
export SIMS_IOS_NOTIFICATION_SENDER_PROJECTION_RECEIPT_PATH='<private-0600-receipt>'
integration_test/scripts/ios_receiver_bootstrap.py --action seed-sender
```

The helper derives `sender_id`, the visible alert title, and the raw payload
SHA-256 only from that owner-only payload file. Raw sender identity never
appears in argv, stdout/stderr, or the receipt. The app refuses to replace an
existing contact/projection entry, writes a digest-tagged nonblocked and
nonarchived fixture, and compensates partial cross-store failure. Cleanup is
exact-generation and idempotent:

```sh
integration_test/scripts/ios_receiver_bootstrap.py --action cleanup-sender
```

The receipt schema is
`mknoon.sims.ios-sender-projection-host-receipt.v1`; it contains only the
action/status, bundle ID, nonce/receiver/sender/payload hashes, fixture digest,
native status/result code, and completion time. Cleanup also removes the
transient protected app-container command/result files. Both actions use the
same receiver ID and handoff nonce environment variables as receiver capture.

## Exact notification-recovery proof

The same helper accepts `--action prove-recovery` after one real APNs card has
been observed on a fresh dedicated install. It privately stages a nonce-,
receiver-, account-, and payload-bound command. The bootstrap-enabled Runner
adds one unrelated local sentinel, executes the production exact-recovery
coordinator, and returns only counts and booleans: the sole delivered APNs
content had `badge == nil`, the absolute badge changed from one to zero, the
owned card was removed, and the unrelated sentinel survived. Raw account,
notification, token, and sentinel identities never enter the host receipt.

Set `SIMS_IOS_NOTIFICATION_RECOVERY_RECEIPT_PATH` to an owner-only output path.
The result schema is
`mknoon.sims.ios-notification-recovery-host-receipt.v1`; protected command and
result files are removed before the action reports PASS.
