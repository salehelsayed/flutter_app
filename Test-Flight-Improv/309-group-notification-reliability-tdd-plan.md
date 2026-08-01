# 309 - Group Notification Reliability: Archived-Reaction Guard, Per-Event Reaction Collapse, Fresh-Join Projection Atomicity

Status: execution-ready
Type: Bug
Spec: free-text intent (no formal spec) — derived from a session review of the group notification pipeline, then adversarially verified twice (see Problem And Evidence and Reviewer Findings)
Classification: implementation-ready
Closure tier: host (Dart host + Swift XCTest + Go host); relay leg additionally needs an EC2 deploy to reach users

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-31 | Evidence Collector | Full pipeline: `send_group_message_use_case.dart`, `pubsub.go`, `group_inbox.go`, `inbox.go`, `reaction_push.go`, `background_message_handler.dart`, `NotificationPreviewResolver.swift`, `group_message_listener.dart`, `drain_group_offline_inbox_use_case.dart` | 9 candidate findings raised | 13-agent verify→refute pass |
| 2026-07-31 | Verify/Refute (12 auditors + 1 skeptic) | Same + `identity.go`, `node.go`, `start_node_use_case.dart`, `multi_device_sync_flag.dart`, `handle_incoming_group_invite_use_case.dart`, all gate scripts, `tool/sims/critical_features.json` | **5 of 9 refuted**; 1 confirmed-but-deferred; 3 confirmed and scheduled here | Build Test Contract for the 3 scheduled |
| 2026-07-31 | Planner | `group_reaction_notification_projection.dart`, `group_repository_impl.dart`, `run_test_gates.sh` | `background_message_handler_test.dart` is in **zero** curated arrays — must register | Emit plan v1 |
| 2026-07-31 | `/tdd-review` (4 workers + lead self-verification) | Same + `group_message_listener_reaction_ingress_processor.dart`, `group_reaction_push_test.go`, `tool/sims/critical_features.json`, `metrics.go`, `main.go`, FCM/APNs official docs | **2 blockers**: C1's surface census was incomplete (6, not 4); C3's fix as written was a **no-op**. Plus 9 plan-fixes | Plan v2 (this document) — all deltas applied |

## Problem And Evidence

- **Behavior to improve:** three independent, source-confirmed defects that silently drop group notifications a user should receive.
- **Impact:** each produces a missing (or wrongly-present) banner with no error, no retry, and no later correction. The underlying messages/reactions are not lost (they materialize on next drain) — the *alert* is.

### Confirmed root causes (survived two refute passes)

**C1 — The `archived` guard exists on exactly one of six notification-decision surfaces.**
The push-path **message** resolvers check it: `groupMessageLocalStateFromRows` computes `groupArchived` (`lib/features/push/application/background_message_handler.dart:1284`) and rejects on it (`:1298`); iOS `resolveGroup` guards `!group.archived` (`ios/NotificationService/NotificationPreviewResolver.swift:1000`). **Nothing else does.** The full census (re-derived during review, not inherited):

| # | Surface | Location | Checks archived? |
|---|---|---|---|
| 1 | Push group message (Dart) | `background_message_handler.dart:1284,1298` | **yes** |
| 2 | Push group message (Swift) | `NotificationPreviewResolver.swift:1000` | **yes** |
| 3 | Push group reaction (Dart) | `groupReactionLocalStateFromRows:1543`, reject block `:1611-1646` | no |
| 4 | Push group reaction (Swift) | `resolveGroupReaction:701-953` | no |
| 5 | Push 1:1 reaction (Dart) | `directReactionLocalStateFromRows:1424` | no |
| 6 | Push 1:1 reaction (Swift) | `resolveReaction:550-676` | no |
| 7 | **Live in-app group message (Dart)** | `group_message_listener.dart:1172-1173,1185` — reads `group?.isMuted` only | **no** |
| 8 | **Live in-app group reaction (Dart)** | `group_message_listener_reaction_ingress_processor.dart:352-355` — `if (group == null \|\| group.isMuted) return;` | **no** |

Surfaces 7 and 8 were **missed by plan v1 and found in review**; both were self-verified in source by the review lead. `GroupModel.isArchived` is already in hand at both sites (`group_model.dart:96`) and simply never read. So the real shape of the defect is *not* "messages vs reactions" — it is **"the two push-path message resolvers vs everything else."** A user who archives a still-active group gets: no push banner for messages, but a full push banner for reactions, **and** a live in-app banner for both whenever the app is foregrounded.
Archiving is local-only (`archive_group_use_case.dart:18` → `groups_db_helpers.dart:345`, no wire call), so nothing upstream prevents any of it.
**Signature of a dropped guard, not an exclusion:** the Swift snapshot structs parse `archived` as a *required, fail-closed* field (`GroupReactionProjectedGroup.archived` `:1420/1424`, enforced `:1600`) — the plumbing was built for a guard that never landed. Plans 256 and 257, which designed the reaction pipeline and meticulously enumerate mute/dissolved/self/bystander/stale/deleted-target/active-view suppression, contain **zero** occurrences of "archiv".

**C2 — Group reaction pushes collapse per group, so concurrent reactions overwrite each other in transit.**
`boundedGroupReactionIdentity(groupID)` = `sha256(groupID)` (`go-relay-server/reaction_push.go:409-412`), assigned at `:459` and consumed as FCM `Android.CollapseKey` (`:475`) and `apns-collapse-id` (`:481`). Every ADD-reaction push to a group carries the same identity regardless of reactor, target message, or transition. The 1:1 lane instead hashes the event (`boundedReactionEventIdentity`, `:518-522`, consumed `:547/:564/:570`).
**Provider semantics, verified against official docs during review:**
- **FCM (Android leg):** collapsible messages are coalesced while the token's connection is inactive; only the most-recently-enqueued message per key survives. But FCM also stores **at most four different collapse keys per registration token**, and "if you exceed this number, FCM only keeps four collapse keys, **with no determining factor on which keys are kept**" ([Firebase: non-collapsible and collapsible messages](https://firebase.google.com/docs/cloud-messaging/customize-messages/collapsible-message-types)). Non-collapsible messages instead use a **100-message** per-device queue, and overflow raises `onDeletedMessages()` ([Firebase: receive messages in an Android app](https://firebase.google.com/docs/cloud-messaging/android/receive)).
- **APNs (iOS leg):** `apns-collapse-id` merges requests into a single notification, 64-byte limit ([Apple: sending notification requests to APNs](https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns)). It collapses notifications **still queued/undelivered** at APNs — so keeping it per-group genuinely **discards** earlier undelivered reactions for an offline recipient; it does not merely replace a displayed card. **Note the attribution:** the discard on the iOS leg is performed by APNs, not FCM — the Firebase Admin SDK only forwards the header.
**Nothing recovers the discarded ones.** The silent offline drain calls `handleIncomingGroupReaction` for every `group_reaction` payload (`drain_group_offline_inbox_use_case.dart:654-677`) — state self-heals — but never calls `_maybeNotifyGroupReaction`. Relay fan-out is fire-and-forget with no retry (`inbox.go:1522-1544`).
**Not deliberate:** zero "collapse" mentions in Plan 257 (whose single commit `491ad6d91` introduced this file) or Plan 292. Plan 257 *does* deliberately design "one stable card per group, updated not stacked" — but that is the client-side **display** identity (`ThreadID: groupID` `:463`, `contactPeerId: 'group:$groupId'`), a different mechanism from the provider collapse key. Plan 256, same author and wave, treats collapse identity as an explicitly per-event cross-language concept.
**Zero Dart/Swift analog exists:** `grep -rn` for `boundedGroupReactionIdentity`/`group-reaction:` returns empty across `lib/` and `ios/`; all Dart consumers call `boundedReactionEventIdentity` — per-event — for groups too.

**C3 — A freshly joined group is invisible to the iOS NSE for the duration of the roster loop.**
`OrdinaryNotificationProjectionSnapshot.init?` requires `exactJSONInteger(value["keyEpoch"])` and `continue`s past any group lacking it (`NotificationPreviewResolver.swift:1499-1500`) — the group is dropped from `parsedGroups` entirely, so `resolveGroup`'s lookup fails (`:997`) → `suppressOrdinary("group_recipient_policy_rejected")` → `markAsShown:false` → `sanitizeNotificationContentForUnresolvedExpiry` (`:148-172`) blanks title/body/sound. The reaction-side parser `GroupReactionProjectionSnapshot` (`:1547-1605`) duplicates the same fail-closed requirement at `:1602-1603`.
`upsertGroup` only carries an epoch forward `if (previous?['keyEpoch'] is int)` (`lib/core/notifications/group_reaction_notification_projection.dart:173-174`); for a brand-new group `previous` is null, so no `keyEpoch` key is written.
**The window, precisely (corrected in review):** `materializeAcceptedGroupInvitePayload` calls `saveGroup(groupModel)` (`handle_incoming_group_invite_use_case.dart:1081`) → a roster loop containing **network I/O** (`triggerDeferredDistributionDrainForPeer`, `:1084-1102`) → `saveKey(keyInfo)` (`:1105`). Each of these already fires its own **incremental** projection write: `saveGroup` → `_projectAuthoritativeGroup` (`group_repository_impl.dart:1781-1790`) → `upsertGroup` (no keyEpoch); each `saveMember` → `upsertMember` (`:1127-1129`); `saveKey` → `upsertKeyEpoch` (`:1324`). So a join publishes **N+2 separate writes**, and the group sits in the projection *without* a keyEpoch from the moment `saveGroup` returns until `saveKey` returns — the roster loop's network I/O is the exposure. The admin's side already registered the member server-side (`add_group_member_use_case.dart:364-369`), so the relay can fan out into that window.
**Post-removal reentry is already immune** — `commitAcceptedReentry` (`group_repository_impl.dart:619-730`) uses bypass raw-DB functions that never call `saveGroup`/`saveMember`/`saveKey`, so `_projectAcceptedReentry` (`:1983-2009`) → `replaceAcceptedGroupContextStrict` (`group_reaction_notification_projection.dart:301-352`) is the *only* projection write on that path.
**Why a simple reorder is not enough:** moving `saveKey` before `saveGroup` fails, because `upsertKeyEpoch` early-returns when the group is absent (`:276`). Moving `saveKey` to immediately after `saveGroup` closes the keyEpoch window but leaves the **member** window — the NSE also requires `localMember` (`.swift:1004`), so a push arriving before the roster loop finishes is still rejected, and for a legitimately-joined invitee that is a false negative, not a correct fail-closed.

### Existing coverage
- Group-message archived suppression **is** locked on the push path, both platforms: `background_message_handler_test.dart:1823`; `NotificationPreviewResolverTests.swift:1357-1367`.
- Post-removal atomic reentry projection: `group_notification_projection_lifecycle_test.dart:222-260`.
- **An end-to-end device lane for group reaction notifications already exists** (found in review): sims-major row `groups.reaction_notification_campaign` (`tool/sims/critical_features.json:677-697`, `proofBoundary: device.group-reaction-notification-provider-lifecycle`, `buildProfile: android.production_fcm`, real FCM, physical-Android + emulator + staging relay mutation), with fixture `integration_test/scripts/group_reaction_notification_device_criteria.dart` (5 schema-validated Plan-257 scenarios) and host contract test `scripts/test/group_reaction_notification_device_contract_test.sh`. Its host-side criteria test `test/integration/group_reaction_notification_device_criteria_test.dart` is **already curated** at `run_test_gates.sh:528`, so it runs under this plan's own `groups` gate. **None of the 5 scenarios exercises concurrent reactions / collapse uniqueness**, so it does not close C2 — but the lane exists and must be named rather than declared unreachable.

### Missing coverage
- **C1:** none, on any of the six unguarded surfaces. The push group-reaction test (`background_message_handler_test.dart` ~`:2054`) exercises `is_muted:1` (`:2131`) but its fixture group row (`:2065-2071`) carries no `is_archived` key. Swift `groupReactionProjectionValues` (`:3314`) exposes `muted`/`dissolved` as parameters but **hardcodes** `"archived": false` at `:3363`. The two live surfaces have no archived case at all. **Review confirmed the fixtures are non-vacuous:** the baseline group and contact fixtures return non-null today, and neither resolver reads `is_archived` anywhere, so `{...group, 'is_archived': 1}` is a genuine causal RED, not a pass-for-another-reason.
- **C2:** none. `group_reaction_push_test.go:227,288` assert only `!= "" && len <= 64`; both pass unchanged under the fix.
- **C3:** none. `NotificationPreviewResolverTests.swift:1340-1488` has no missing-`keyEpoch` case; `ordinaryGroupContextsJSON` (`:3416-3474`) always seeds it. No test reads projection state *between* the incremental writes.
- **Gate reachability gap:** `test/features/push/application/background_message_handler_test.dart` has **0 hits** in both gate scripts (verified by `grep -c`). Auto-globbed by `feature-host-all` only; labeled "Optional / manual direct suite" in `test-gate-definitions.md:1244`. This plan curates it.

### Refuted findings (do NOT re-introduce)

| Finding | Why refuted |
|---|---|
| **Multi-device group push/custody uses account instead of transport peer id** | The two identifiers cannot diverge in a shipped build. The libp2p peer id is derived deterministically from the mnemonic-derived Ed25519 key (`go-mknoon/identity/identity.go:110-131`); `Node.Start` uses whatever key started the node (`node.go:317-322,418`); the **only** call site always starts it with the account key (`start_node_use_case.dart:70-73`). `admit_sibling_device_use_case.dart:140-161` treats a same-peerId announce as `alreadyPresent`. Corroborated by `Group-Chat-Feature/Improvement-Review-2026-06/12-P2-multi-device-honesty.md:66-68,153`. Additionally gated by `kMultiDeviceSyncEnabled` (`multi_device_sync_flag.dart:17-19`), default false, set by no build config. **Caveat:** `lib/core/debug/group_media_disposable_transport_start.dart:31-105` *does* mint a distinct transport identity, but only under `SIMS_BUILD_PROFILE_ID ∈ {ios.device.group_media_269, android.e2e.group_media_269}`. Do not use P269 sims device evidence to reason about production identity binding in either direction. |
| **Sender-device-roster uniqueness gate silently drops notifications** | Same root: no production path produces a roster device whose `transportPeerId` differs from the member's `peerId`. Latent behind the same flag. Loosening it would weaken an impersonation defense for zero present benefit. |
| **Offline drain produces no notifications (messages)** | Backwards. `drain:709/793` route to `groupMessageListener.handleReplayEnvelope` → `_handleQueuedUserMessage(deliverySource:'replay')` → `_handleMessage`, whose notification block never inspects `deliverySource` — a comment at `group_message_listener.dart:1114-1117` says the site deliberately serves both. The `:850` direct branch executes only when `groupMessageListener == null`, which no production wiring produces (`application_root.dart:246,357`). Locked by `group_message_listener_test.dart:13666-13742`. The real asymmetry runs the other way: **1:1** drain is unconditionally suppressed (`production_application_bootstrap.dart:3228-3233`). **The reaction branch is the true residue — see D4.** |
| **Both platforms fail-closed to nothing on render failure** | Deliberate, documented, test-guarded on iOS — the blanking exists to stop provider-supplied text surfacing, locked by the `"FORGED TITLE"` assertion. Android's data-only shape carries an explicit rationale (`inbox.go:655-660`). Changing either is a privacy-policy reversal. |
| **Reaction push env flag / capability can silently disable notifications** | Default-off is a *tested kill-switch*: `group_reaction_push_test.go:524-527` fails if the default flips. The deploy procedure never rewrites the env file. The client re-registers `group_reaction_v1` on every cold start. |
| **`shouldFanoutPush` capacity eviction can suppress a push** | Trigger unreachable: eviction is oldest-first inside the same atomic store; TTL arithmetic cannot expire a just-written entry. Already an accepted backlog item in `appendix-findings.md`. |
| **Old clients could break when the relay changes the collapse key** | Refuted in review. `grep -rn 'boundedGroupReactionIdentity'`/`'group-reaction:'` across `lib/` and `ios/` returns zero. The only client read of a collapse key is `message.collapseKey` folded into a composite fallback dedupe string (`background_push_notification_fallback.dart:330-380`), where `id=$eventId` already differentiates reactions before and after. `apns-collapse-id` never reaches the device. |

### Unresolved findings
None. Every candidate reached confirmed or refuted with source evidence.

### Affected production / test / gate files
- `lib/features/push/application/background_message_handler.dart` (C1, ×2 functions)
- `ios/NotificationService/NotificationPreviewResolver.swift` (C1, ×2 functions)
- `lib/features/groups/application/group_message_listener.dart` (C1, live message surface)
- `lib/features/groups/application/group_message_listener_reaction_ingress_processor.dart` (C1, live reaction surface)
- `go-relay-server/reaction_push.go` (C2) and `go-relay-server/main.go` (C2 version bump)
- `lib/features/groups/application/handle_incoming_group_invite_use_case.dart` + `lib/features/groups/data/repositories/group_repository_impl.dart` (C3)
  *(`lib/features/groups/domain/repositories/group_repository.dart` is deliberately **not** touched — Step 5 uses a capability check, not an interface method.)*
- Tests: `background_message_handler_test.dart`, `NotificationPreviewResolverTests.swift`, `group_reaction_push_test.go`, `group_notification_projection_lifecycle_test.dart`, `group_message_listener_test.dart`
- Gate: `scripts/run_test_gates.sh` (`GROUP_TESTS`, lines 375-688)

## Graph Grounding Snapshot
- Graph fingerprint / freshness: `6f47d12c12806538` (planning) / `fe988d87225d0a2c` (review counterexample query), current after `/claude-host-bin/host-run bash ./graphify-arch/refresh_arch_graph.sh --incremental` (0 changed code, 2917 unchanged). Residual `stale:ios/Flutter/flutter_export_environment.sh` is a generated non-code file. **The `graphify` CLI is absent inside the container — refreshes must go through the host bridge.**
- Query / profile: `python3 graphify-arch/tdd_context.py query "groupMessageLocalStateFromRows background_message_handler.dart group notification display eligibility" --profile tdd --budget 700` → `confidence=anchored`; review pass used `--profile review --budget 800` on the archived-guard anchors.
- Anchors: `groupMessageLocalStateFromRows` → `background_message_handler.dart:1260`; `groupReactionLocalStateFromRows` → `:1543`.
- Surfaced proof/gate files: `background_message_handler_test.dart` (AUTO_FEATURE_HOST), `push_decrypt_preview.dart`, `durable_notification_tone_lease.dart`.
- Graph gaps that required raw source search: the arch graph is app-owned Dart only — **all** Go relay, Go native, and Swift NSE evidence came from direct source reads. Gate-array registration facts came from `grep` on the gate scripts. **The graph did not surface either live-path surface (7 or 8); those were found only by an explicit call-site census.**
- Reuse rule: anchors may be handed to review/execution as search starting points; every conclusion still needs current-source or command evidence.

## Scope Contract And Guard

**In scope:**
- C1: add the archived guard to **all six** unguarded surfaces — `groupReactionLocalStateFromRows`, `directReactionLocalStateFromRows`, Swift `resolveGroupReaction`, Swift `resolveReaction`, and the two live in-app paths (`group_message_listener.dart` message block, `group_message_listener_reaction_ingress_processor.dart` reaction block).
- C2: make the group-reaction **FCM `Android.CollapseKey`** per-event, or omit it — see D1. Bump `const version` in `go-relay-server/main.go` so deploy provenance is checkable.
- C3: publish the fresh-join projection as **one complete document**, by suppressing the incremental mirrors for that call path — not by appending a fourth write.
- Register `background_message_handler_test.dart` in `GROUP_TESTS`.

**Must preserve:**
- Push group **message** archived suppression, both platforms → `TC-05` (GREEN sentinel).
- A non-archived, non-muted group reaction still notifies → `TC-06` (GREEN sentinel).
- Mute suppression on both live paths keeps working after the archived clause is added → `TC-16` (GREEN sentinel).
- Collapse identity stays non-empty and ≤64 bytes → `TC-09` (GREEN sentinel).
- Post-removal reentry keeps its single atomic strict write → `TC-12` (GREEN sentinel).
- `GROUP_REACTION_PUSH_ENABLED` stays default-false → existing `group_reaction_push_test.go:524-527`, untouched.

**Hard `Do not`:**
- Do not relax the iOS exact-epoch gate (D2), the announcement role gate (D3), the iOS NSE content blanking, or the Android data-only push shape.
- Do not widen `RecipientPeerIds` — it is the relay retrieval ACL (`inbox.go:1874-1879`), not a routing hint. That belongs to the deferred F7 plan.
- Do not add notification emission to the drain reaction branch here (D4).
- Do not touch `GroupType.qa` behaviour in either direction — owned by the separate removal plan.
- Do not add a `GroupRepository` interface method for C3 — the interface has a large fake-implementor population; use the precedented capability check.

**Deferred / accepted difference:**
- **D4 — drain never notifies for group reactions** (`drain_group_offline_inbox_use_case.dart:654-677`): confirmed, but a fix must not storm on backlog drain and must respect the per-event durable claim and per-conversation tone lease. Owner: its own plan.
- **F7 — later-joined admin permanently drops earlier members from custody** (`_isMissingInviteStatusInTrackedGroup`, `send_group_message_use_case.dart:310-329`): **confirmed with a live reproduction** during verification (Dave, a second admin who joined after Eve, produced `recipientPeerIds: [alice, frank]` — Eve silently dropped). This is *message loss*, not a missed banner, and is the most severe finding in the review. Deliberately **not** here: the obvious `joinedAt` exemption is unsound (`joinedAt` is stage-time on the inviter, `add_group_member_use_case.dart:281`, but accept-time on the joiner, `accept_pending_group_invite_use_case.dart:1354`) and would re-admit exactly the staged never-accepted invitees INV-106 excludes — into the relay ACL. Owner: a dedicated plan with a design step and its own Go ACL test.
- **Announcement stale-role message drop** (`handle_incoming_group_message_use_case.dart:566-585`): a stale-role announcement sender's message is dropped from *storage*, not merely un-notified. Owner: same plan as D3 if D3 is taken.
- **Pre-existing, un-instrumented: the FCM 4-collapse-key cap applies to the 1:1 reaction lane today** (`reaction_push.go:524,547`). A user with >4 pending distinct 1:1 reaction events already risks non-deterministic eviction. Recorded so a future incident is not mis-diagnosed as novel to this plan. No sentinel — nothing in this plan changes it.
- **Stale App-Group projection across uninstall/restore** (`replaceLocalIdentity` same-account branch preserves `current.groups` verbatim, `group_reaction_notification_projection.dart:88-107`; Keychain items survive uninstall). Pre-existing, untouched by C1/C2/C3; separate hardening item.

**Dependencies:**
- C2 reaches users only after an EC2 relay redeploy. C1 and C3 are client-only (confirmed in review: neither touches a relay file or a wire field).

## User-Owned Decisions (resolve before execution; defaults are what this plan assumes)

| ID | Decision | Default assumed here | Consequence of the alternatives |
|---|---|---|---|
| **D1** | Group-reaction collapse strategy on **Android**. Three options, not two. | **(a) Per-event `Android.CollapseKey`** | **(b) Omit `Android.CollapseKey` entirely** — makes reaction pushes non-collapsible, so they use FCM's 100-message queue instead of the 4-key cap, with `onDeletedMessages()` on overflow. Strictly more robust above 4 pending reactions, and it matches what the **ordinary group-message** builders already do (`inbox.go:404-421,523-557` set no `CollapseKey` at all). **(c) Keep per-group** — status quo, loses reactions from 2 onward. Per-event (a) fixes the 2-4 case but above four distinct keys FCM keeps four "with no determining factor on which keys are kept" — trading a deterministic loss for a non-deterministic one. **Recommendation: (b).** |
| **D1b** | `apns-collapse-id` for group reactions (iOS). | **Keep per-group** | Per-event stacks N reaction banners per group instead of merging one, reversing Plan 257's "one stable card" design. **But be explicit: keeping per-group means the iOS half of C2 is NOT fixed** — APNs discards earlier *undelivered* reactions for an offline recipient, which is the exact defect described. This plan closes C2 on Android only unless D1b flips. |
| **D2** | iOS `keyEpoch == group.keyEpoch` exact-current gate (`.swift:1058`) | **Leave unchanged** | Dropping it matches Android's lookup-by-generation model and recovers notifications for delayed pushes referencing a still-retained older epoch, but contradicts the codebase's own named `isCurrentGroupReactionKeyEpoch` policy. |
| **D3** | Announcement writer→admin role-lag suppression | **Leave unchanged** | A fix reverses two explicit fail-closed *security* assertions (`background_message_handler_test.dart:1713`; `NotificationPreviewResolverTests.swift:1340`). Should be decided with the strictly-worse storage-drop sibling. |
| **D4** | Should the offline drain notify for group reactions? | **Defer** (own plan) | Closes the residual reaction-alert loss that C2 does not cover, at the cost of storm risk on backlog drain. Note: plan v1 justified this deferral with "C2 removes the dominant cause"; review downgraded that to **"C2 narrows the collapse-driven loss window"** — there is no production telemetry supporting a comparative severity claim. |

## Test Contract

Zero empty cells. `HEAD state` is one of `causal RED` · `GREEN sentinel` · `manual/device-only proof`.

| Case | Behavior | Named test/proof | Tier / fixture | HEAD state → GREEN | Mutation that re-reds | Gate / registration |
|---|---|---|---|---|---|---|
| TC-01 | Archived group suppresses a push group-reaction notification (Dart) | `test/features/push/application/background_message_handler_test.dart::group reaction local state is ineligible when the group is archived` | unit host / plain maps, mirrors the `is_muted:1` case at `:2131`; baseline fixture proven non-vacuous in review | causal RED (`groupReactionLocalStateFromRows` has no archived term; returns non-null for `is_archived:1`) → returns `null` | revert the `groupArchived \|\|` clause in `:1611-1646` → TC-01 red | `flutter test <path>`; **add path to `GROUP_TESTS` (grep-verify)** |
| TC-02 | Archived group suppresses a push group-reaction notification (iOS NSE) | `ios/RunnerTests/NotificationPreviewResolverTests.swift::testGroupReactionSuppressedWhenGroupArchived` | Swift XCTest / `groupReactionProjectionValues` extended with an `archived` parameter (hardcoded `false` at `:3363` today) | causal RED (`resolveGroupReaction` never reads `.archived`) → `suppress == true`, `markAsShown == false`, reason `group_reaction_archived` | revert the `guard !group.archived` → TC-02 red | `xcodebuild … -only-testing:RunnerTests/NotificationPreviewResolverTests`; sims-major `native.ios.runner_tests` (`critical_features.json:200-217`) |
| TC-03 | Archived contact suppresses a push 1:1 reaction notification (Dart) | `background_message_handler_test.dart::direct reaction local state is ineligible when the contact is archived` | unit host / plain maps; `contacts.is_archived` exists (migration `007_archive_columns.dart:33`) and `dbLoadContact` selects all columns — the v1 stop-if will not fire | causal RED (`directReactionLocalStateFromRows:1424` has no archived term) → returns `null` | revert the archived clause → TC-03 red | same file/gate as TC-01 |
| TC-04 | Archived contact suppresses a push 1:1 reaction notification (iOS) | `NotificationPreviewResolverTests.swift::testDirectReactionSuppressedWhenContactArchived` | Swift XCTest / direct-reaction projection fixture | causal RED (`resolveReaction:550-676` never reads `.archived`) → `suppress == true` | revert the `guard !contact.archived` → TC-04 red | same as TC-02 |
| TC-05 | Push group **message** archived suppression unchanged, both platforms | `background_message_handler_test.dart:1823` + `NotificationPreviewResolverTests.swift:1357-1367` (existing) | unit host + Swift XCTest | GREEN sentinel → still passes | delete `groupArchived` from `groupMessageLocalStateFromRows:1298` → TC-05 red. Guards against moving the guard instead of adding one | same as TC-01/TC-02; already registered |
| TC-06 | A non-archived, non-muted group reaction still notifies | `background_message_handler_test.dart` existing group-reaction happy path (~`:2054`) | unit host | GREEN sentinel → still passes | invert the new guard to `!groupArchived \|\|` → TC-06 red | same as TC-01 |
| TC-07 | Two distinct reactions in one group do not share an FCM collapse key | `go-relay-server/group_reaction_push_test.go::TestRelayNotificationClosure_GroupReactionCollapseKeyIsPerEvent` | Go host / two `groupReactionPushMetadata`, same `groupID`, different `TransitionID` | causal RED (`boundedGroupReactionIdentity(groupID)` returns the same value → keys equal) → under D1(a) the two `Android.CollapseKey`s differ and each equals `boundedReactionEventIdentity(TransitionID)`; **under D1(b) `Android.CollapseKey` is empty on both** | revert `:459`/`:475` to the per-group identity → TC-07 red | `(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... -run '^TestRelayNotificationClosure_' -count=1)`. **The `TestRelayNotificationClosure_` prefix is load-bearing** — it is the only relay filter `./scripts/run_test_gates.sh groups` applies (`run_test_gates.sh:1035-1039`) |
| TC-08 | `apns-collapse-id` stays per-group and now differs from the Android key (D1b default) | `group_reaction_push_test.go::TestRelayNotificationClosure_GroupReactionApnsCollapseIdRemainsPerGroup` | Go host / same two metadata values | causal RED — **but only on its second half**: (a) "both builds share one `apns-collapse-id`" is a *preserved* property, unchanged by the fix; (b) "and it differs from the Android key" is red on HEAD because both currently share `identity` at `:459`. Assert both; label honestly | change `:481` to the per-event identity → TC-08 red. **If D1b flips to per-event, this row inverts to assert difference** | same as TC-07 |
| TC-09 | Collapse identities remain non-empty and ≤64 bytes | `group_reaction_push_test.go:227` and `:288` (existing) | Go host | GREEN sentinel → still passes | return a raw un-hashed `TransitionID` → TC-09 red | **NOT reachable from the `groups` gate** — these live in `TestGroupReactionPushProjectsOnlyTheRecipientPlatformPayload` (`:145`) and `TestGroupInboxStore_ReactionAddPushesAllAuthorDevicesOnly` (`:235`), neither matching `^TestRelayNotificationClosure_`. Run explicitly: `(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... -count=1)` |
| TC-10 | A fresh join never exposes a group without its keyEpoch | `test/features/groups/integration/group_notification_projection_lifecycle_test.dart::fresh accepted join never publishes a group without keyEpoch` | integration host / **in-memory fake repo (`_MemoryGroupPersistence.repository()` `:1488-1564`) + `_MemorySecureKeyStore.writeKeys` (`:1417-1466`)** — this file contains zero `sqflite` | causal RED (drive the real fresh-join sequence with an instrumented store; **every** intermediate document that contains the group also contains `keyEpoch`) → holds for every write | restore the `saveGroup` → roster-loop → `saveKey` incremental sequence → TC-10 red | `flutter test <path>`; already in `GROUP_TESTS:468` |
| TC-11 | The NSE message parser drops a projected group with no `keyEpoch` | `NotificationPreviewResolverTests.swift::testProjectionSnapshotDropsGroupMissingKeyEpoch` | Swift XCTest / `ordinaryGroupContextsJSON` extended to omit `keyEpoch` (always seeded today, `:3416-3474`) | causal RED (the helper cannot express the case) → the group is absent from `projection.groups` | delete the guard at `:1499-1500` → TC-11 red | same as TC-02 |
| TC-11b | The NSE **reaction** parser applies the same requirement | `NotificationPreviewResolverTests.swift::testGroupReactionProjectionSnapshotDropsGroupMissingKeyEpoch` | Swift XCTest / `groupReactionProjectionValues` with `keyEpoch` omitted | causal RED (no row exercises `GroupReactionProjectionSnapshot`) → the group is absent | delete the duplicated guard at `:1602-1603` → TC-11b red. Guards the two parsers staying in sync | same as TC-02 |
| TC-12 | Post-removal reentry keeps its single atomic strict write | `group_notification_projection_lifecycle_test.dart:222-260` (existing) | integration host | GREEN sentinel → still passes | make `_projectAcceptedReentry` call `upsertGroup` + `upsertKeyEpoch` separately → TC-12 red | same as TC-10; already registered |
| TC-13 | Every **push-path** reaction eligibility resolver consults `archived` | `background_message_handler_test.dart::every reaction local-state resolver rejects an archived conversation` | unit host / table over both Dart push resolvers | causal RED (both rows fail today) → both reject | remove the guard from either resolver → TC-13 red | same as TC-01 |
| TC-14 | The live in-app **group message** banner is suppressed for an archived group | `test/features/groups/application/group_message_listener_test.dart::does not show a notification for an archived group` | unit host / existing listener harness + `FakeNotificationService`, mirroring the mute cases at `:14317`/`:14358` | causal RED (`:1173,1185` read `isMuted` only; an archived group still calls `maybeShowNotification`) → `notifService.shown` is empty | revert the `isArchived` clause at `:1185` → TC-14 red | `flutter test <path>`; already in `GROUP_TESTS:563` |
| TC-15 | The live in-app **group reaction** banner is suppressed for an archived group | `group_message_listener_test.dart::does not show a reaction notification for an archived group` | unit host / same harness, reaction path | causal RED (`group_message_listener_reaction_ingress_processor.dart:352-355` reads `isMuted` only) → no notification shown | revert the `\|\| group.isArchived` at `:355` → TC-15 red | same as TC-14 |
| TC-16 | Mute suppression still works on both live paths after the archived clause lands | existing mute cases `group_message_listener_test.dart:14317`, `:14358` | unit host | GREEN sentinel → still passes | replace `group.isMuted \|\| group.isArchived` with `group.isArchived` alone → TC-16 red | same as TC-14 |

### PROD-CRITICAL leg and its epistemic limit
- **C2's provider leg is not provable by any host tier.** TC-07 proves the relay *emits* the intended collapse metadata. Whether FCM then stops discarding queued reaction pushes is third-party server behaviour. **Do NOT treat TC-07 as end-to-end proof.**
- **An end-to-end device lane already exists and must be named, not invented:** sims-major `groups.reaction_notification_campaign` (`tool/sims/critical_features.json:677-697`) runs real FCM against a physical Android + emulator with a staging relay mutation. **It has no concurrent-reaction scenario**, so closing C2 end-to-end means adding a 6th `GroupReactionNotificationScenario` to `integration_test/scripts/group_reaction_notification_device_criteria.dart` and its host criteria test — not an ad-hoc manual procedure. Whether to add it is a scoping call; if skipped, say so and accept that C2 closes at the emit layer only.
- **C1 and C3 close at the decision layer, not the OS layer.** TC-02/TC-04/TC-11/TC-11b exercise `NotificationPreviewResolver`'s pure functions under XCTest — the correct tier, since the defect is in the decision. They do not prove APNs delivery or NSE process launch, and nothing here claims they do.
- **Device topology:** no paired-device row is required by this contract, so the `AGENTS.md` two-peer default does not apply unless the C2 device scenario above is taken — in which case the existing lane already pins physical-Android + emulator.
- **No new test files are created.** Every row extends an existing file, so `classify_path()` has no new path to categorise. `completeness-check` still runs because the `GROUP_TESTS` edit changes gate membership.

### Test Notes
- **TC-01/TC-03/TC-13 fixtures:** copy the shape of the `is_muted:1` row (`:2131`) and add `is_archived: 1`. The current group fixture (`:2065-2071`) and contact fixture (`:1966-1970`) carry no such key, so the test must add it. Review verified the baselines return non-null today, so this is a genuine RED.
- **TC-02/TC-04/TC-11/TC-11b fixtures:** `groupReactionProjectionValues` (`:3314-3363`) hardcodes `"archived": false` at `:3363`; `ordinaryGroupContextsJSON` (`:3416-3474`) always seeds `keyEpoch`. Thread parameters through **before** writing the assertions — otherwise the cases cannot be expressed and the "RED" is a compile error for the wrong reason.
- **TC-10 is the row v1 got wrong.** The acceptance bar is **not** "exactly one write" — a join legitimately performs N+2 projection writes (`upsertGroup`, N×`upsertMember`, `upsertKeyEpoch`), and `saveKey` publishes the epoch internally at `group_repository_impl.dart:1324` *before* any appended call could run. The correct invariant is: **no intermediate projection document ever contains this group without a `keyEpoch`.** Instrument the store to capture every written document and assert the invariant across all of them.
- **TC-10 fake fidelity:** `_MemorySecureKeyStore` already records `writeKeys`; extend it to capture written *values* so the invariant can be checked per write, and make sure it reproduces read-back (`_readContexts` → mutate → `_writeContexts`) rather than returning an empty document on every read.
- **TC-07/TC-08 discriminator:** both rows build the same two messages and differ only in the field asserted. Assert `Android.CollapseKey` in TC-07 and `APNS.Headers["apns-collapse-id"]` in TC-08 explicitly.
- **Null-row behaviour (verified safe, no row required):** a null `groupRow`/`contactRow` is already rejected by the pre-existing `storedGroupId != groupId` / `actorUsername == null` conditions before the new archived term, which safely evaluates to `false` on a null row. Swift mirrors this with `guard let group = …` firing before the new guards. Recorded so a future reorder of the OR-chain is known to be load-bearing.

## Implementation Steps

1. Snapshot `git status --short`. **The tree is already dirty from unrelated in-flight work (plans 301-303)** — record the baseline. Add all causal rows **before** any production edit (INV-RED-FIRST) and record each RED.
2. **C1 (Dart push):** in `groupReactionLocalStateFromRows` (`:1543`) add `final groupArchived = (groupRow?['is_archived'] as num?)?.toInt() == 1;` beside `:1571` and add `groupArchived ||` to the reject block (`:1611-1646`). Apply the identical change to `directReactionLocalStateFromRows` (`:1424`) using its contact row (`contacts.is_archived` confirmed present).
3. **C1 (Swift push):** in `resolveGroupReaction` (`:701`) add `guard !group.archived else { return groupReactionFallback(..., reason: "group_reaction_archived") }` beside the muted (`:783`) and dissolved (`:790`) guards — `group.archived` is already parsed (`:1420/1424`). Same for `resolveReaction` (`:550-676`) using `contact.archived`.
4. **C1 (live paths):** in `group_message_listener.dart`, change `:1173` to also read `group?.isArchived ?? false` and gate `:1185` on both. In `group_message_listener_reaction_ingress_processor.dart:355`, change `if (group == null || group.isMuted) return;` to also test `group.isArchived`.
5. **C2:** apply the D1 decision at `reaction_push.go:459-481`. Under D1(b) — the recommendation — omit `Android.CollapseKey` for reactions entirely, matching the ordinary group-message builders (`inbox.go:404-421,523-557`), and keep `apns-collapse-id` on the per-group identity per D1b. Under D1(a), compute a separate per-event identity for `Android.CollapseKey` and leave `:481` on the per-group one; note the two now differ, so they can no longer share one `identity` variable. **`boundedGroupReactionIdentity` currently has exactly 2 occurrences** (definition `:409`, call `:459`; zero test references — v1's "≥3" was wrong); it survives under both options because `apns-collapse-id` keeps it.
6. **C2 provenance:** bump `const version` in `go-relay-server/main.go:25` (currently `"1.6.0"`). Without this, the journal line `Starting relay-server v%s` (`main.go:186`) is byte-identical before and after the deploy and cannot prove the new binary is running.
7. **C3:** the fix is **not** an appended write. Suppress the incremental projection mirrors for the fresh-join call path and publish once at the end:
   - Add an internal skip-mirror mode to `GroupRepositoryImpl.saveGroup`/`saveMember`/`saveKey` (or route the fresh join through the raw `db*` writers the way `commitAcceptedReentry` does at `group_repository_impl.dart:619-730`), so `materializeAcceptedGroupInvitePayload` performs zero partial projection writes.
   - Then call a single atomic projector — a capability interface (e.g. `AcceptedGroupContextProjector`) implemented by `GroupRepositoryImpl` and delegating to the existing `_projectAcceptedReentry` (`:1983-2009`) → `replaceAcceptedGroupContextStrict`. Use the `is`-check idiom (`msgRepo is GroupInboxStoreRetryCompletionRepository`, `retry_failed_group_inbox_stores_use_case.dart:244-246`), **not** a `GroupRepository` interface method.
   - **Wrap the new call in its own try/catch (log-and-no-op).** `GroupReactionNotificationProjection._enqueue` (`:650-678`) catches any action failure and unconditionally calls `_deleteAllDocuments()` (`:848-866`), wiping the contexts, authored-targets, and reaction-comparand documents for **every** group — and `replaceAcceptedGroupContextStrict` runs with `propagateError: true` (`:345`). A fresh-join-specific failure must not blank the projection for unrelated groups. This blast radius is the reason v1's "just add a fourth call" shape was unsafe as well as ineffective.
   Stop-if: suppressing the mirrors turns out to require changing a shared repository signature used by many callers — then stop and replan C3 rather than widening the seam mid-execution.
8. Register `background_message_handler_test.dart` in `GROUP_TESTS` (`scripts/run_test_gates.sh:375-688`).
9. Run focused GREEN → preservation sentinels → graph-affected dependents → the `groups` lane → the Swift and Go legs → the deploy provenance check.

## Risks And Blind Spots

- **A "fix" that moves rather than adds the archived guard** → guarded by TC-05.
- **An over-broad archived edit that silences healthy reactions** → guarded by TC-06; on the live paths by TC-16.
- **C2 changing iOS card semantics unintentionally** → guarded by TC-08, gated behind D1b.
- **C3's new call wiping every group's projection on failure** → mitigated by the mandatory try/catch in Step 7; the hazard is `_enqueue:650-678` + `_deleteAllDocuments:848-866`.
- **C3 regressing the already-correct reentry path** → guarded by TC-12.
- **Lifecycle / derived-state durability:** C3 *is* this class — the NSE projection is derived state that must reconstruct. TC-10 asserts the invariant across every write of the join. The cold-start rebuild (`mirrorAllGroupReactionNotificationContexts`, `:1614-1653`) republishes a complete context but only heals the *next* launch, which is why TC-10 asserts the live sequence.
- **Sibling-surface consistency:** the archived guard has **six** unguarded surfaces (see the C1 census table) — all six are in scope (TC-01…TC-04, TC-14, TC-15). Plan v1 claimed four and missed both live paths; that error is the single best argument for re-deriving the census at execution time rather than trusting this table.
- **Destructive-action side effects:** no delete/cleanup/cancel path changes. The only removal risk is the projection wipe covered above.
- **Invariant re-verification under new transitions:** C3 introduces a suppress-then-publish transition. TC-10 therefore asserts the **full document** on every write (name, type, muted, archived, dissolved, keyEpoch, members) — a partial assertion would let a regression publish a group whose `muted`/`archived` flags were dropped, silently re-opening C1 from the other direction.
- **Construction/call-site census (re-derive at execution; counts drift):** verified during review — `_projectAcceptedReentry` has 3 call sites (`group_repository_impl.dart:723,858,1946`), all reentry; C3 adds a 4th. `boundedGroupReactionIdentity` has exactly 2 occurrences. Re-run `grep -rn 'ReactionLocalStateFromRows\|resolveReaction\|resolveGroupReaction\|_maybeNotifyGroupReaction' lib ios` and `grep -rn 'upsertGroup(' lib` before editing; the live-path surfaces were invisible to the knowledge graph and only a raw census found them.
- **Build-artifact provenance:** C2 ships only via the relay binary, and the gate is not "the Go test passed." Step 6's version bump is what makes the journal check discriminating. `relay_backend_durable` was removed from the provenance check in review — it is set once at boot from env config (`metrics.go:15-23`, `main.go:128`) and reads `1` before and after any deploy, including one that failed to restart.
- **Permission / ACL verb symmetry:** N/A here — this plan changes no ACL. Recorded because the adjacent F7 finding *is* an ACL defect gating three verbs through one predicate (`inbox.go:1714,1874-1879`).
- **Fake side-effect fidelity:** covered in Test Notes for TC-10.
- **Composite-node / relationship assertions:** TC-10 asserts a property *across* a sequence of writes rather than on one; that is the relationship under test, and it is why "one write" was the wrong bar.

## Gate Cadence

- **Per-plan closure:** the focused causal rows, the preservation sentinels, and `./scripts/run_test_gates.sh groups` — which after step 8 covers `background_message_handler_test.dart`, `group_message_listener_test.dart` (`:563`), `group_notification_projection_lifecycle_test.dart` (`:468`), the already-curated device-criteria test (`:528`), and the `TestRelayNotificationClosure_*` relay rows. **Plus one explicit unfiltered relay run** for TC-09 (see below). No `feature-host-all` sweep is justified.
- **TC-09 is not reachable from the `groups` gate.** `run_relay_notification_go_gate` filters on `^TestRelayNotificationClosure_` (`run_test_gates.sh:1035-1039`), and TC-09's two assertions live in tests named `TestGroupReactionPushProjectsOnlyTheRecipientPlatformPayload` (`:145`) and `TestGroupInboxStore_ReactionAddPushesAllAuthorDevicesOnly` (`:235`). Run `(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... -count=1)` explicitly — the same command `run_relay_all_go_gate` (`:1041-1045`) uses under the `all` gate.
- **Graph-affected first:** after the production edits and before the curated lane, run `python3 graphify-arch/tdd_context.py affected lib/features/push/application/background_message_handler.dart lib/features/groups/application/group_message_listener.dart lib/features/groups/application/group_message_listener_reaction_ingress_processor.dart lib/features/groups/application/handle_incoming_group_invite_use_case.dart lib/features/groups/data/repositories/group_repository_impl.dart --budget 600` and `flutter test` the files it names.
- **Full `host-all` is not a per-plan gate.** It runs once after the group-notification dependency wave (this plan + the deferred D4/F7 plans) and again at final rollout/release closure.
- **Shared tests outside the feature/core globs:** none. Every Dart test here is under `test/features/**`.
- **Non-Dart legs have no fast gate of their own.** The iOS `RunnerTests` target has no standalone runner script; the only automated path is sims-major `native.ios.runner_tests` (`critical_features.json:200-217`), which runs the entire target. Budget for that or run the single class manually and record it as a manual gate — do not claim automated coverage that does not exist.

## Acceptance Gates  (literal — copy/paste)

```bash
# Dirty-tree snapshot before execution (tree is ALREADY dirty from plans 301-303 — record, do not revert)
git status --short

# --- Causal REDs (before production edits) — each must FAIL for its documented reason ---
flutter test test/features/push/application/background_message_handler_test.dart \
  --plain-name 'group reaction local state is ineligible when the group is archived'
flutter test test/features/groups/application/group_message_listener_test.dart \
  --plain-name 'does not show a notification for an archived group'
flutter test test/features/groups/integration/group_notification_projection_lifecycle_test.dart \
  --plain-name 'fresh accepted join never publishes a group without keyEpoch'

# Go leg — regex must cover BOTH new relay rows (v1's narrower pattern silently matched zero
# for TC-08, and `go test -run` with no matches exits 0 — a false pass).
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... \
  -run '^TestRelayNotificationClosure_GroupReaction' -count=1)

# Swift leg (resolve a live simulator id first: xcrun simctl list devices available)
xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner \
  -destination "platform=iOS Simulator,id=${SIMS_IOS_SIMULATOR_ID}" \
  CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO \
  -only-testing:RunnerTests/NotificationPreviewResolverTests

# --- Focused GREEN (after the fix) — exit 0, zero failures ---
flutter test test/features/push/application/background_message_handler_test.dart
flutter test test/features/groups/application/group_message_listener_test.dart
flutter test test/features/groups/integration/group_notification_projection_lifecycle_test.dart

# --- Graph-affected dependents BEFORE the lane ---
python3 graphify-arch/tdd_context.py affected \
  lib/features/push/application/background_message_handler.dart \
  lib/features/groups/application/group_message_listener.dart \
  lib/features/groups/application/group_message_listener_reaction_ingress_processor.dart \
  lib/features/groups/application/handle_incoming_group_invite_use_case.dart \
  lib/features/groups/data/repositories/group_repository_impl.dart --budget 600
flutter test <exact test files named by the command above>

# --- Preservation sentinels + the affected curated lane — exit 0 ---
./scripts/run_test_gates.sh groups

# --- TC-09 is NOT covered by the groups gate — run the relay suite unfiltered ---
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... -count=1)

# --- Registration is grep-verified, never run-verified (family gates swallow --list) ---
grep -c 'test/features/push/application/background_message_handler_test.dart' scripts/run_test_gates.sh   # expect: 1
grep -c 'test/features/groups/application/group_message_listener_test.dart' scripts/run_test_gates.sh     # expect: 1 (already at :563)
./scripts/run_test_gates.sh completeness-check    # expect: PASS, 0 unmatched

# --- Relay deploy provenance (C2 reaches users only here) ---
# Step 6 MUST have bumped `const version` in go-relay-server/main.go, or this check is inert.
ssh <relay> 'sudo journalctl -u relay-server -n 20 | grep "Starting relay-server v<NEW_VERSION>"'
ssh <relay> '/usr/local/bin/relay-server version'    # expect: <NEW_VERSION>

# --- Hygiene ---
flutter analyze     # 0 new issues
git diff --check
```

**Semantic outcomes.** Each causal RED must fail with the documented mechanism. Each GREEN must exit 0 with zero failures. `run_test_gates.sh groups` must exit 0 across the Dart array, the go-mknoon bridge gate, and the relay notification Go gate. The unfiltered relay run must exit 0. `completeness-check` must report zero unmatched paths. Both `grep -c` checks must return exactly 1. The journal must name the **newly bumped** version string — a green Go test on an undeployed relay does not close C2.

**Environment note (not a product blocker):** this container has no `go` binary, and the host bridge only accepts script files inside the repo, so the Go and `xcodebuild` legs run on the Mac (directly, or via `/claude-host-bin/host-run bash ./scripts/<script>.sh`). `flutter` resolves to the host shim at `/claude-host-bin/flutter` (3.41.4).

## Execution Interpretation And Done Criteria

- **Expected RED:** TC-01/TC-03/TC-13 fail because no push reaction resolver reads `is_archived`; TC-14/TC-15 fail because both live paths read only `isMuted`; TC-02/TC-04/TC-11/TC-11b fail because the Swift fixtures cannot express the case (fixture-parameter compile-RED is the intentional contract); TC-07 fails because both collapse keys are equal; TC-10 fails because the join publishes the group before the key.
- **GREEN sentinel:** TC-05, TC-06, TC-09, TC-12, TC-16 pass before and after.
- **Pre-existing dirty tree:** unrelated uncommitted changes from plans 301-303. Baseline them in step 1; failures there are not this plan's REDs.
- **Known pre-existing failure:** none identified for the group lane at planning time — record the `groups` lane baseline before the first edit.
- **Environment blocker (NOT a product blocker):** no `go` toolchain and no `xcodebuild` in the container; an unavailable iOS simulator is `N/A (target unavailable by project policy)`.
- **Scope drift (BLOCKING):** any change to the iOS epoch gate, the announcement role gate, the NSE blanking, the Android data-only push shape, `RecipientPeerIds`, the drain reaction branch, `GroupType.qa`, or the `GroupRepository` interface.

- [ ] Every behavior has a named test or a justified proof.
- [ ] Causal RED, focused GREEN, and representative mutation re-red are recorded.
- [ ] Preservation sentinels and named gates pass with semantic outcomes.
- [ ] Harness registration implemented AND grep-verified; `completeness-check` passes.
- [ ] The unfiltered relay run covering TC-09 passed.
- [ ] D1/D1b/D2/D3/D4 were resolved before execution, and the resolution is recorded.
- [ ] `const version` was bumped and the deployed relay reports it, or C2 is explicitly recorded as landed-but-undeployed.
- [ ] `flutter analyze` has no new issues; `git diff --check` is clean.
- [ ] The Scope Contract And Guard is respected.

## Rollback

- **Reversible by:** `git revert` of the client commit (C1, C3) and the relay commit (C2), plus redeploying the prior relay binary — the deploy runbook keeps a timestamped `.bak`.
- **What a PRIOR shipped build does with post-change data:** nothing changes on the wire. `CollapseKey`/`apns-collapse-id` are relay→provider metadata, never in the signed envelope and never parsed by a client (verified: zero client references to the per-group scheme; the only collapse-key read is a composite dedupe string where `event_id` already differentiates). The archived guards are local reads. **The C3 document shape is byte-identical** to what `replaceAcceptedGroupContextStrict` already writes for reentry — same key set (`name`, `type`, `muted`, `archived`, `dissolved`, `keyEpoch`, `members`), same types (`group_reaction_notification_projection.dart:167-176` vs `:336-344`) — and Swift parses both identically, so a rolled-back NSE reads a new-client document exactly as it reads today's reentry documents.
- **NOT recoverable once landed:** nothing. No schema, migration, key material, identity, file, or status value is touched. `DB v##`: none.
- **One transient hazard, mitigated not eliminated:** if the C3 projector throws, `_enqueue` wipes all three shared projection documents for every group until the next cold-start rebuild. Step 7's try/catch prevents the fresh-join path from triggering it; the pre-existing reentry paths retain the original behaviour.
- **Staging:** land C1 and C3 with the client release; land C2 with an independently rollback-able relay deploy. If D1b later flips `apns-collapse-id`, that is a separate relay-only change.

## Handoff

- **First causal RED command:** `flutter test test/features/push/application/background_message_handler_test.dart --plain-name 'group reaction local state is ineligible when the group is archived'`
- **Preservation command:** `./scripts/run_test_gates.sh groups`
- **Manual registration:** one — add `test/features/push/application/background_message_handler_test.dart` to `GROUP_TESTS`, then `grep -c`.
- **Migration:** none.
- **Boundary closure:** host-tier for all three defects. Swift rows have no fast automated gate. C2 additionally needs the deploy-provenance check, and optionally a 6th scenario on the existing `groups.reaction_notification_campaign` device lane for true end-to-end closure.
- **Unresolved evidence:** none. Five user-owned decisions (D1, D1b, D2, D3, D4) are open by design, with defaults and a recommendation for D1.
- **Deferred with named owners:** D4 (drain notifies for reactions) and F7 (later-joined admin drops earlier members from relay custody — *message loss*, needs its own plan).

## Reviewer Findings

`/tdd-review`, 2026-07-31 — 4 workers (factual, counterexample, domain/provider-semantics, boundary/reversibility) plus lead self-verification in source. Verdict on plan v1: **plan-fixes-required**. All deltas below are applied in this v2 document.

**Blockers (2)**
1. **C1's surface census was incomplete.** Plan v1 claimed "four surfaces" and built TC-13 to guard against a hypothetical fifth. Two unguarded surfaces exist *today*: the live in-app group-message block (`group_message_listener.dart:1172-1173,1185`) and the live group-reaction block (`group_message_listener_reaction_ingress_processor.dart:352-355`), both reading `isMuted` only while `GroupModel.isArchived` sits in hand. Self-verified by the lead. → C1 scope now covers six surfaces; TC-14/TC-15/TC-16 added; the census table replaces the prose claim.
2. **C3's fix as written was a no-op.** `saveKey` already calls `upsertKeyEpoch` internally (`group_repository_impl.dart:1324`), and `saveGroup` already ran `upsertGroup`, so the epoch is published the moment `saveKey` returns — strictly *before* any appended Step-5 call. The real window is the roster loop between them, and a join legitimately performs N+2 writes, making TC-10's "exactly one write" bar unreachable. Independently found by two workers; self-verified by the lead. → Step 7 rewritten to suppress the incremental mirrors and publish once; TC-10's invariant restated as "no intermediate document contains the group without a keyEpoch".

**Plan-fixes (9)**
3. **`_enqueue` wipes every projection document on any failure** (`group_reaction_notification_projection.dart:650-678` → `_deleteAllDocuments:848-866`), and `replaceAcceptedGroupContextStrict` runs `propagateError: true`. Adding a structurally different call site risks blanking unrelated groups. → mandatory try/catch in Step 7; hazard recorded in Risks and Rollback.
4. **The causal-RED regex could not match TC-08.** `-run '^TestRelayNotificationClosure_GroupReactionCollapse'` does not match `…GroupReactionApnsCollapseIdRemainsPerGroup`, and `go test -run` with zero matches exits 0 — a silent false pass defeating INV-RED-FIRST. → broadened to `^TestRelayNotificationClosure_GroupReaction`.
5. **TC-09's tests never run in the `groups` gate.** They live in `TestGroupReactionPushProjectsOnlyTheRecipientPlatformPayload` (`:145`) and `TestGroupInboxStore_ReactionAddPushesAllAuthorDevicesOnly` (`:235`), neither matching `^TestRelayNotificationClosure_`. v1 claimed they did. → an explicit unfiltered relay run added to Gate Cadence and Acceptance Gates.
6. **FCM caps a token at four distinct collapse keys**, keeping four "with no determining factor on which keys are kept". Per-event keys are unbounded, so D1(a) trades a deterministic loss for a non-deterministic one above four. Omitting the key uses the 100-message queue instead — and matches what the ordinary group-message builders already do. → D1 now has three options with **(b) omit** as the recommendation.
7. **The APNs half of C2 is not fixed under the D1b default**, and v1's framing understated it: `apns-collapse-id` discards earlier *undelivered* notifications, so keeping it per-group leaves the exact described defect live on iOS. → stated plainly in C2 and in D1b.
8. **Relay deploy provenance was inert.** No step bumped `const version` (`main.go:25`), so the journal line is byte-identical before and after; and `relay_backend_durable` is set once at boot from env config, reading `1` regardless of which binary runs. → Step 6 adds the version bump; the gauge check is replaced with a version-string + `relay-server version` check.
9. **An end-to-end device lane already exists** — sims-major `groups.reaction_notification_campaign` (`critical_features.json:677-697`), with its host criteria test already curated at `run_test_gates.sh:528`. v1 declared the boundary unreachable. → named in Existing coverage and PROD-CRITICAL; noted that it lacks a concurrent-reaction scenario.
10. **TC-10's fixture was wrong.** `group_notification_projection_lifecycle_test.dart` contains zero `sqflite`; it uses an in-memory fake repository and `_MemorySecureKeyStore`. → tier/fixture cell corrected.
11. **Line drift and count corrections:** `upsertKeyEpoch` early-return is `:276` not `:275`; `saveKey` is `:1105` not `:1104`; `boundedReactionEventIdentity` is called at `background_push_notification_fallback.dart:219` not `:191-192`; `boundedGroupReactionIdentity` has 2 occurrences, not "≥3"; `group_repository.dart` removed from the C3 affected-files list (Step 5/7 deliberately avoids the interface).

**Confirmed sound (kept as-is)**
- TC-01/TC-03/TC-13 fixtures are non-vacuous — the baseline group and contact fixtures return non-null today and neither resolver reads `is_archived`, so the REDs are genuine.
- TC-05/TC-06 are real sentinels with mutations that actually re-red them.
- The C3 document shape is byte-identical to the reentry document, so there is no rollback/parse risk in either direction.
- No client depends on the collapse-key scheme, so C2 is safe for old installs.
- C1 and C3 are genuinely client-only.
- A null group/contact row is already rejected before the new archived term — no extra row needed.

**Also added in review:** TC-11b, guarding the second Swift parser (`GroupReactionProjectionSnapshot:1547-1605`) whose duplicated keyEpoch requirement (`:1602-1603`) no row previously exercised.

## Execution Progress
| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-08-01 | STAGED RE-LAND (user go) | C1 (all six surfaces) + C2 under D1(b); **C3 DROPPED** — review-proven no-op in v1 shape AND lead suspect for the unrecovered 07-31 breakage; owner: dedicated hardened plan | commit `23ea69632`. REDs: 4 Dart (TC-01/03/14/15, documented mechanisms) + 2 Go (shared per-group key). Greens: 46+214 Dart, relay module unfiltered `ok` (the `:288` D1(a) collapse-identity sentinel renegotiated to the non-collapsible contract — the ONLY collateral), Swift RunnerTests SUCCEEDED (TC-02/04 as rejection-table cases; both new reasons `group_reaction_archived`/`reaction_archived_contact`), groups lane `LANE_EXIT=0` with `background_message_handler_test.dart` newly curated, completeness PASS, analyzer/diff clean | **STAGE 1 PASS**: Pixel-only deploy (`1.0.0-23ea69632.d3.t260801162654`, provenance-verified) + the exact 07-31 breakage repro passes (launch loads; background→reopen loads) — `docker-ws/deploy_pixel_only_309_result.txt` | Stage 2 fleet campaign running; then iOS (targeted two-phone script — deploy_all_phones would hit the app-less 17 Pro Max), then relay v1.7.3 |
| 2026-08-01 | **RE-LAND COMPLETE (all stages)** | — | **Stage 2 PASS**: full campaign aggregate green (assertions=5) on the re-land client, both Android targets + guard restore. **Stage 2b PASS**: iOS `1.0.0-23ea69632.d7.t260801164945` installed/launched/verified on iPhone 13 + iPhone 11 (targeted script; binary gate `BridgeGenerateIdentity` present). **Stage 3 DEPLOYED**: relay v1.7.3 (embedded go1.25.0 verified pre-upload, backup `relay-server.pre-309-reland-*`, `Starting relay-server v1.7.3` 14:55:11Z, active t+92s NRestarts=0 zero panics; post-deploy: 190 traffic lines in minutes, iOS token registered at +1s, Refusing-oversized=0) | C1 live on all platforms; C2 Android half live in production; D1b iOS half open by decision; C3 → dedicated hardened plan (owner recorded); D4/F3/F5 remain deferred | wave closure: full `host-all` after F3/F5 |
| 2026-07-31 | executed then FULLY ROLLED BACK | client edits (C1/C3) + relay (C2) | relay deployed as v1.7.0 at 18:32:49Z; rolled back to v1.6.0 at 19:28:41Z (`relay-server.pre-plan309-20260731T183248Z` backup); client edits reverted uncommitted | user report: the app broke on device after implementation (Android: backgrounded→reopened app "unable to load anything"); the executed diff is unrecoverable | root cause of the breakage not established — leading suspect is the C3 `group_repository_impl.dart` seam (the plan's own flagged wipe hazard); post-rollback relay forensics attributed the notification symptoms to defects OUTSIDE this plan's scope (see plan 315) | re-land only under a staged protocol (one device + on-device smoke BEFORE fleet deploy, client proven BEFORE relay deploy), after the plan-315 wave |
