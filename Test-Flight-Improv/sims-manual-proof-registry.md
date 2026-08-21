# Sims manual and future proof registry

This file archives device/topology requirements that must not masquerade as
executable Flutter tests. It has no release-gate authority: active coverage is
owned by `tool/sims/critical_features.json`, and an unavailable driver,
credential, permission, or artifact remains `BLOCKED` rather than passing here.

## Android campaigns replaced by automated Sims drivers

| Capability | Automated owner | Required observations |
|---|---|---|
| `android.connectivity_restore_inbox_drain` | `integration_test/scripts/run_connectivity_restore_sims.dart` | With the receiver foregrounded, disconnect its Android network, queue exactly three run-bound messages, restore the network without an app resume, observe network-change drain plus peer re-warm, and render all three messages. |
| `android.keepalive_drop_skip_direct` | `integration_test/scripts/run_1to1_device_real.dart --scenario android.keepalive_drop_skip_direct` | Open a real 1:1 conversation, hard-drop the receiver, wait for two natural keepalive misses, prove the dropped send performs no discover/dial, obtains relay custody in under one second, then receives delivery and a post-recovery ping after the receiver returns. |
| `android.wake_token_directionality` | `integration_test/scripts/run_1to1_device_real.dart --scenario android.wake_token_directionality` | On the emission-enabled E2E profile, prove with hash-only evidence that A's relay-accepted registered token for B equals B's production received-token store entry for A and the token attached by B's accepted `inbox:store` back to A. Raw tokens must never leave the app processes. |
| `android.direct_media_blob_custody` | `integration_test/scripts/run_direct_media_blob_custody_sims.dart --mode major --scenario android.direct_media_blob_custody` | Start a disposable Redis/media-backed production-handler relay, inject its exact reachable address before central preparation of the selector-only APK, then use one USB physical Android sender and one Android emulator receiver to prove process-restart ciphertext reuse, exact receiver reopen, expiry coupling, and source-pinned ACK removal. |
| `notifications.android_recovery_completion` | `integration_test/scripts/run_android_notification_recovery_completion_sims.dart --mode major --scenario notifications.android_recovery_completion` | Start the shared disposable production-handler relay in encrypted-token, durable-wake-outcome mode with real FCM, inject its reachable address before central fixed-wake APK preparation, then prove distinct background-connected and killed direct-reaction recovery transitions, exact marker ACK, generic retirement, route removal, and teardown without mutating external Redis. |

The historical Flutter proof files for these rows are deliberately absent.
Host tests continue to own their pure logic; only the manifest-owned Android
campaign can satisfy each real OS/bridge/relay boundary.

## Inactive future Voice/Video DCUtR proofs

The following requirements are retained for
`Test-Flight-Improv/Voice-Video-Call-1to1-Feature/VC-02-dcutr-default-on-upgrade-tdd-plan.md`.
They remain inactive until VC-01 circuit holding and VC-02 production behavior
exist. Their absence from the current major plan is intentional and must not be
reported as `PASS`, `BLOCKED`, or an implemented current feature.

| Capability | Required future topology | Activation proof |
|---|---|---|
| `vc02.dcutr_upgrade` | Two real phones behind distinct NATs plus a real relay | Establish a relay circuit, run the real DCUtR hole punch, observe a non-circuit direct connection, and show the conversation transport indicator change from relay to direct. |
| `vc02.dcutr_symmetric_cgnat_negative` | A real symmetric-CGNAT pair plus a real relay | Attempt the upgrade, prove the punch cannot establish a direct connection, and keep the transport indicator on relay without a false direct state. |

Unavailable NAT topology is `N/A (target unavailable by project policy)` only
after these capabilities are activated and an automated driver exists. It is
not a reason to activate the unimplemented Voice/Video feature today.
