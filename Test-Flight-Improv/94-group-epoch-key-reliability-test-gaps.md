# 1. Title and Type

- Title: Group Messages Must Not Silently Disappear After Member Adds or Epoch Changes
- Issue type: `bug`
- Output doc path: `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps.md`
- Final program verdict: `residual_only` as of GEK-005 recovery on `2026-05-10`

# 2. Problem Statement

A group creator or member expects that, after friends are added to a group and the group continues chatting, every accepted eligible member can see the messages sent to that group.

The reported behavior is that after adding several friends, some users were unable to see messages sent by another group member. The suspected failure area is epoch-key reliability: a recipient may have stale, missing, or conflicting group key material, or may not have received the membership/config update needed to accept and decrypt the message.

From the user's perspective, this is a silent trust failure. The sender sees the message as sent, some recipients see it, and other recipients appear to miss it with no clear recovery or explanation.

# 3. Impact Analysis

- Affected users: group creators, admins, newly added members, existing members receiving messages after membership changes, and any member whose device misses or receives delayed epoch-key updates.
- Trigger moments: adding multiple friends, invite delivery degradation, a member joining or rejoining, key rotation after removal/leave, app resume after offline time, relay fallback after live delivery fails, and delayed direct P2P key-update delivery.
- Severity: high for group trust because the sender can believe the group received a message while only a subset of eligible members can read it.
- Frequency: not measurable from repo evidence alone. Existing tests now prove the host deterministic GEK-001 through GEK-004 slices, and GEK-005 added final gate/device reconciliation evidence.
- Remaining rollout state: GEK-005 writes the final program verdict `residual_only` because all repo-owned host, Go, named-gate, completeness, whitespace, generated-artifact, and configured device/relay checks are green. The remaining limitation is proof scope only: the available real-network evidence is supporting MD-004 device/relay proof, not an exact live three-party GEK stale-key/decrypt-repair split-delivery proof.
- Confusion cost: users have no reliable way to distinguish "not yet joined", "pending key repair", "offline but recoverable", and "silently missed due to key/config drift" unless the product records and verifies those states.

# 4. Current State

- Group creation with selected members can add members locally, update the local Go topic config, publish a `members_added` system message, and then send per-recipient P2P invites. The flow records degraded invite outcomes instead of always rolling back local member state. Evidence: `lib/features/groups/application/create_group_with_members_use_case.dart`, `test/features/groups/application/create_group_with_members_use_case_test.dart`, and `Test-Flight-Improv/91-group-invitation-status-visibility.md`.
- Group sends snapshot the latest local group key, bind the outgoing row and durable replay envelope to that epoch, then race live publish with durable inbox store. Evidence: `lib/features/groups/application/send_group_message_use_case.dart`.
- Key rotation generates a next key, distributes direct key updates to member devices, and then promotes the sender's Go key state after distribution completes or times out. Evidence: `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`.
- Direct key-update receive validates authorization, device binding, signatures, and audit data before calling `group:updateKey` and saving the key. Evidence: `lib/features/groups/application/group_key_update_listener.dart`.
- Existing key-update tests cover accepted sequential epoch 2 then epoch 3 updates, pending local key-update send behavior, and future-epoch replay repair after a key arrives. Evidence: `test/features/groups/application/group_key_update_listener_test.dart` and `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`.
- GEK-001 closed the direct listener/Go-boundary key-update monotonicity slice on `2026-05-09`: delayed older key updates no longer promote active key state after a newer accepted generation, conflicting same-generation key material no longer replaces the first accepted material, duplicate same-generation material is idempotent, and Go `UpdateGroupKey` has focused same-or-older epoch no-op proof. Evidence: `lib/features/groups/application/group_key_update_listener.dart`, `test/features/groups/application/group_key_update_listener_test.dart`, `go-mknoon/node/pubsub_key_rotation_grace_test.go`, and `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-GEK-001-plan.md`.
- The Go pubsub layer emits `group:decryption_failed` when a live group message cannot decrypt with the local key and suppresses the normal `group_message:received` event. Evidence: `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_decryption_failure_test.go`, and `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`.
- The Flutter bridge has diagnostic-stream coverage for `group:decryption_failed`, and `GroupMessageListener` can create a pending repair placeholder from that diagnostic. Evidence: `lib/core/bridge/go_bridge_client.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/group_pending_key_repair_service.dart`, `test/core/bridge/go_bridge_client_test.dart`, and `test/features/groups/application/group_message_listener_test.dart`.
- Offline future-epoch replay can queue a pending placeholder and later repair it when the missing key arrives. Evidence: `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`.
- GEK-002 closed the host app-layer live decrypt repair journey on `2026-05-09`: a live `group:decryption_failed` creates a safe pending state, durable replay for the same missing message supersedes the synthetic no-envelope live placeholder, duplicate replay stays exactly-once, later key arrival repairs the durable replay into one visible plaintext row, and repeated retry/replay does not duplicate the row. Evidence: `lib/features/groups/application/group_pending_key_repair_service.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, and `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-GEK-002-plan.md`.
- GEK-003 closed the deterministic host app-layer partial key-update rotation race on `2026-05-09`: one recipient can commit epoch 2 while another remains stale, an immediate epoch-2 send binds both the outgoing row and durable replay to epoch 2, the stale recipient records a pending-key state instead of a fake delivered row or disappearance, durable replay uses the signed replay account sender plus transport identity, and later key arrival repairs the real message exactly once. Evidence: `lib/features/groups/application/group_pending_key_repair_service.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, and `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-GEK-003-plan.md`.
- GEK-004 closed the host app-layer delayed membership/config replay-ordering gap on `2026-05-09`: signed durable group-message replays rejected as `unknown_sender` are deferred within a drain page, membership/config system replays can make a newly accepted sender locally known, and the deferred durable message is retried before cursor commit into exactly one delivered row. Evidence: `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`, and `Test-Flight-Improv/94-group-epoch-key-reliability-test-gaps-session-GEK-004-plan.md`.
- Guardrail preserved by the closure: unresolved unknown senders still reject before cursor advancement, and live unknown-sender handling remains fail-closed.
- Most Dart group integration tests use fake group networking or bridge behavior that does not perform real group cryptographic failure. Evidence: `test/shared/fakes/group_test_user.dart`, `test/shared/fakes/fake_group_pubsub_network.dart`, and `test/core/bridge/fake_bridge.dart`.
- Real Go-bridge onboarding coverage proves encrypted invite acceptance and first-add/re-add decrypt at the app boundary, but does not prove a multi-recipient live group delivery failure and recovery journey. Evidence: `integration_test/group_real_crypto_onboarding_test.dart`.
- GEK-005 final reconciliation reran on `2026-05-10`. All GEK-focused Dart selectors passed, full `group_key_update_listener_test.dart`, `group_message_listener_test.dart`, `drain_group_offline_inbox_use_case_test.dart`, and broad `flutter test --no-pub test/features/groups` passed, focused and broad Go passed, `./scripts/run_test_gates.sh groups` passed, `./scripts/run_test_gates.sh completeness-check` passed with `730/730` files classified, and `git diff --check` passed.
- GEK-005 also ran the configured iOS relay evidence. The required `iPhone Air` simulator `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD` and `iPhone 17` simulator `5BA69F1C-B112-47BE-B1FF-8C1003728C8F` were booted and used with the supplied relay addresses. The single-device `group-real-network-nightly` command passed as a self-contained device smoke because no CLI peer fixture was present; the paired `run_group_multi_device_real.dart` command passed its MD-004 primary/sibling relay proof. These runs are supporting real-network confidence, not an overclaim of full live three-party GEK split-delivery proof.
- Required broad host reconciliation is no longer blocked: direct `drain_followup_invariants_test.dart` reruns now prove local-delivered receipt re-derivation on dedup and `GROUP_MESSAGE_LISTENER_EMPTY_DROP` flow-event logging for malformed drained envelopes.
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` now records GEK-001 through GEK-004 as covered and GEK-005 as accepted/`residual_only`.
- The old GEK-002 fixed-date receipt-fixture follow-up is closed by deterministic retention clock control and full drain owner/broad group reruns.

# 5. Scope Clarification

In scope:

- User-visible reliability for group messages sent after member adds, invite acceptance, rejoin, removal/leave-driven rotation, and epoch-key changes.
- Accepted eligible members must not permanently miss a sent group message without a visible pending, repaired, or unrecoverable state.
- Partial delivery where some members can read a message and others cannot because of key/config drift.
- Durable recovery after live delivery fails because the recipient has stale or missing epoch-key material.
- Invite/add degradation where a locally visible member may not yet be a fully accepted message recipient.
- Acceptance evidence across unit, integration, smoke, and simulator layers where the behavior spans key rules, app-layer repositories/listeners, and device-context network recovery.

Non-goals:

- No claim that newly added members should receive pre-join history.
- No change to group membership policy, admin permissions, role rules, or removed-member access rules.
- No requirement for a new protocol-level delivery receipt or read receipt.
- No UI redesign requirement beyond the observable need to avoid silent message loss.
- No real-device/manual acceptance layer is required by this spec unless a later request explicitly adds it.
- No implementation seam, architecture change, file ownership, or rollout session split is chosen here.

Accepted ambiguities for a later implementation pass:

- Whether a recipient's degraded state is shown as pending repair, retrying, failed to decrypt, resend needed, or another product-approved state.
- How long degraded key/config states remain visible after successful repair.
- Whether a pending invitee becomes an eligible recipient at invite send, invite stored, invite accepted, or first successful group join.
- The exact timing window that separates post-join delivery from intentionally unavailable pre-join history.

# 6. Test Cases

## Happy Path

- After a creator adds multiple friends and those friends complete the accepted group-join flow, a message sent by an existing group member is visible exactly once to every accepted eligible member, with the expected sender identity, ordering, and group context. Required acceptance evidence: integration and simulator.
- After a newly added member joins, they receive only post-join text and media while pre-join history remains unavailable. Existing coverage partially covers this at the fake-network/app layer; the gap is proving the same outcome when real crypto or equivalent key failure behavior is active.
- After all remaining members receive the current epoch key, a post-rotation message is visible to every eligible remaining member and is not visible to removed or not-yet-accepted members. Required acceptance evidence: integration.
- When live delivery and durable inbox delivery both carry the same post-add message, eligible recipients see one message row, not a duplicate, and the row remains visible after reopening the group. Required acceptance evidence: integration and smoke.
- When an accepted member is offline during a post-add message, returning to the group recovers the missed message through the existing durable group recovery path without changing its sender, text/media identity, or epoch. Required acceptance evidence: integration and simulator.

## Edge Cases

- If one recipient misses a current epoch key update while other members receive it, a message sent on the new epoch is not silently lost for that recipient. GEK-003 now covers the deterministic host app-layer path where durable replay plus later key arrival repairs the real message exactly once; GEK-005 added supporting real-network evidence and leaves only an exact live three-party GEK proof residual.
- If a live group message fails to decrypt because the recipient has stale or wrong epoch-key material, the normal message is not falsely delivered, a degraded state is observable, and later durable replay plus key arrival can turn the same missing message into visible plaintext exactly once. GEK-002 now covers this combined host app-layer journey; GEK-005 did not find a focused or broad host regression.
- If a delayed older key update arrives after a newer key update, accepted recipients do not regress into a state where current-epoch messages become unreadable. GEK-001 covers the direct listener and Go active-key boundary; GEK-002 covers baseline live/durable repair convergence; GEK-003 covers the host partial-recipient rotation/send/repair path; GEK-005 confirmed the focused host/Go selectors and fixture-gated iOS relay commands are green.
- If two different key materials are observed for the same group epoch, users do not split into inconsistent subsets where each subset can read different messages for the same epoch with no visible error. GEK-001 covers direct key-update conflict rejection/ignore semantics; GEK-002 covers baseline live/durable repair convergence; GEK-003 covers the host partial-recipient rotation/send/repair path; GEK-005 confirmed no focused key-conflict regression.
- If an invite was attempted but not delivered, stored, or accepted, the invitee is not treated in user-visible message reliability as a confirmed recipient who silently missed later group messages. GEK-004 preserved this invite-truth boundary through existing invite/status safety selectors; it did not add new invite eligibility semantics.
- If an existing member has not yet received the membership/config update for a newly added sender, messages from that sender do not disappear permanently. GEK-004 covers the host app-layer path where delayed config catch-up plus durable recovery delivers the post-join message exactly once.
- GEK-005 final simulator/relay reconciliation completed with supporting device evidence; the Report 94 final program verdict is `residual_only` because exact live three-party GEK stale-key/decrypt-repair split-delivery proof remains outside the current evidence.
- If an existing member sends immediately after a member add reaches the active boundary, the newly added accepted member either receives the message exactly once or the product exposes a clear boundary state. Existing coverage pins a fake-network add/send boundary; remaining live-stack proof is reflected in the `residual_only` final program verdict.
- If the app restarts while a group message is pending key repair, reopening the group preserves the pending/recovered/unrecoverable state instead of making the message vanish.
- If relay fallback stores a replay for a subset of recipients, every accepted eligible recipient has a consistent visible outcome: delivered, pending repair, or unrecoverable. No recipient should silently lack both the message and a degraded state.

## Regressions To Preserve

- Bug regression: after a user adds several friends to a group and sends a message, accepted eligible members must not end up in a silent split where some see the message and others see nothing, with no pending, repaired, or unrecoverable state.
- Bug regression: a live decrypt failure must not create a fake delivered plaintext row and must not block later recovery of the same message through durable replay and key arrival.
- Bug regression: stale or conflicting key updates must not cause a recipient to lose access to future valid group messages without an observable degraded state.
- Existing no-backfill behavior must remain: newly added members do not receive messages sent before their join boundary.
- Existing removed-member behavior must remain: removed or left members do not gain access to post-removal/post-leave content.
- Existing duplicate suppression must remain: replay, retry, live delivery, and inbox recovery for the same group message do not create duplicate rows.
- Existing invite-degradation behavior must remain visible: local group/member state can exist while an invite still needs resend, is queued, is missing key material, or has not been accepted.
- Existing sender-side success semantics must remain truthful enough that a sent state is not the only evidence used to claim all recipients can read the message.

Existing coverage and gaps:

- Existing unit coverage partially proves epoch snapshotting, bridge key update calls, diagnostic event routing, and offline future-epoch repair.
- Existing integration coverage partially proves fake-network onboarding, post-join message/media delivery, add/send boundaries, and invite failure reporting.
- Existing Go coverage partially proves wrong-key decrypt failure events, key-rotation grace behavior, and validator rejection.
- Closed GEK-001 evidence: direct listener and Go-boundary tests now prove delayed older key updates and same-epoch conflicting key material cannot roll back or replace accepted local active key state.
- Covered GEK-002 evidence: the combined host app-layer regression now proves live `group:decryption_failed` plus durable replay plus later key arrival results in exactly one user-visible repaired plaintext message, with no fake delivered live row or duplicate durable replay row. The older `PREREQ-GROUP-SYNC-RECEIPTS` fixed-date fixtures are now clock-controlled and pass in the full drain owner plus broad group reruns.
- Closed GEK-003 evidence: the combined host app-layer regression now proves partial key-update delivery plus immediate post-rotation send recovers the stale recipient through live pending-key state, durable replay canonicalization under the signed replay sender/message identity, later key arrival, and exactly-once plaintext repair. Final multi-device relay timing remains GEK-005 scope.
- Closed GEK-004 evidence: the focused host app-layer regression now proves delayed membership/config propagation for a newly accepted sender recovers the affected durable message exactly once after config catch-up.
- Guardrail evidence: unresolved unknown senders still reject before cursor advancement and live unknown senders remain fail-closed.
- GEK-005 evidence: all focused GEK selectors, full owner/broad host suites, focused/broad Go, named gates, completeness, whitespace hygiene, generated-artifact cleanup, single-device configured nightly, and paired iOS relay MD-004 proof passed. The final program verdict is `residual_only` because the remaining gap is an exact live three-party GEK stale-key/decrypt-repair split-delivery proof, not a repo-owned host/Go blocker.
- Remaining acceptance residual: add or run the exact live three-party GEK proof before claiming final Report 94 `closed`. Do not reopen GEK-001 through GEK-004 unless their focused contracts regress.
