# 397 - Physical iPhone Group-Chat Notification Verification

Status: blocked — terminal physical duplicate observed; staging rollback verified
Type: Modification
Spec: free-text intent — close physical-iPhone ordinary group-chat message and
reaction notification evidence after Plan 396
Classification: implementation-ready
Closure tier: device

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-22 20:18 CEST | Evidence collector | Plans 396 and 257; `go-relay-server/inbox.go`; `reaction_push.go`; `NotificationPreviewResolver.swift`; the Plan-257 runner, capture, criteria, proof, and XCUITest owners | Rich group-message and author-only group-reaction paths exist, but there is no ordinary chat-group physical-iPhone proof. The current iOS row is announcement-only, its token wait consumes relay vocabulary removed in v1.8.0, and iOS group-message retries lack a stable per-message collapse ID. | Define one representative ordinary group message plus one ADD reaction journey. |
| 2026-08-22 20:18 CEST | Scope arbiter | Existing Go/Dart/Swift sentinels; live device inventory; `GROUP_TESTS` | Announcement authority, strict custody, media modality, REMOVE, mute, killed state, sound, and OS-version permutations already have lower-tier owners or are outside this requested physical claim. | Use one scenario, one physical Android sender, one physical iPhone receiver, one PASS artifact, and at most one sealed causal-failure artifact. |
| 2026-08-22 20:35 CEST | Counterexample audit | Plan-396 source inventory; `IosNotificationRecoveryCoordinator.swift`; `IosReceiverBootstrapHandoff.swift`; central `ios.device.production` bundle; staging selector grammar; current `xctrace` output | SpringBoard title/body counts cannot establish producer ownership. Mandatory recent-remote suppression is also unsound because iOS may deliver the provider card without ever running a Flutter contender. The runner can currently accept an ID from the `Devices Offline` section and ignores its prebuilt Android input on the iOS branch. | Reuse the Plan-396 native inventory as a narrow group sibling; make contender evidence conditional; require both central artifacts; fix online selection and scenario-aware selectors. |
| 2026-08-22 20:35 CEST | Delivery simplifier | Candidate files and gate ownership | A new Sims capability, build profile, notification abstraction, SQLCipher device probe, or physical matrix would not add required evidence. One local iOS setup build plus the existing central production iOS bundle is sufficient. | Keep one plan, one affected `groups` gate, one campaign, and at most one source-backed rerun. |
| 2026-08-22 21:05 CEST | Final critical audit | Conditional rerun ordering; central bundle consumption; staging deployment/rollback; gate cadence | A repair after attempt one could otherwise reuse a stale iOS bundle, the early `groups` gate could certify a pre-repair tree, and rollback-on-any-failure would remove the candidate before the permitted rerun. Remote architecture and prior/candidate binary identity also needed fail-closed evidence. | Seal attempt one, rebuild/re-attest before attempt two, run `groups` once on the final passing tree, keep the candidate through the one causal rerun, and verify prior/candidate version plus SHA around automatic rollback. |
| 2026-08-22 21:21 CEST | Independent execution-readiness audit | Native recovery fence; read-only group observer; Sims cache reports/attestations; attempt freshness; relay rollback | The mutating exact-redrive probe could manufacture the duplicate under test, and changing the Android observer while accepting an old APK would make the new event hash unavailable. The structural iOS manifest also cannot prove a rebuilt binary. | Use one read-only outbox event hash, centrally rebuild/report-bind Android and iOS, require a new iOS input/artifact digest after repair, allow a valid Android platform-cache hit, and retain one final `groups` gate. No blocker/high finding remains. |
| 2026-08-22 23:05 CEST | TDD review correction | Combined Android identity shape; late-local duplicate counterexample; group fallback projection; strict production sentinel; interrupted staging rollback | The existing target-only probe grammar cannot bind both event windows, three early 500 ms samples can PASS before a delayed local sibling, one routing-only group projection branch was untested, the selected strict sentinel was the weaker path, and an interrupted deploy could recapture the candidate as prior while leaving the manifest mutated. | Keep one plan and one campaign. Add two read-only phase observations, a group-only full-horizon inventory oracle, one fallback Go subcase, replace the strict selector, and make binary plus manifest deployment state resumable and reversible. |

## Problem And Evidence

- Required behavior: while a physical iPhone is backgrounded in an ordinary
  chat group, one Android-sent text must yield one useful provider-owned card,
  and one Android ADD reaction to an iPhone-authored target must later yield one
  useful provider-owned reaction card. Each cold tap must open the exact group
  target.
- Plan 396 implemented stable `UNUserNotificationCenter` inventory for direct
  notifications, including trigger-derived provider/local classification,
  hashed request identifiers, and three stable samples. Its automated direct
  physical PASS was waived; it does not cover group messages or reactions.
- In `ios.device.production`, rich and fixed opaque wakes are mutually
  exclusive and fixed-wake admission remains disabled. This plan therefore
  tests the credible duplicate causes—provider retry and provider-versus-local
  presentation—rather than inventing an old-path-plus-new-path matrix.
- `buildGroupPushMessage` currently emits no iOS `apns-collapse-id`, while
  `sendWithRetry` may submit the same message twice
  (`go-relay-server/inbox.go:937-1014,1280-1311`). Group reactions already use a
  bounded per-event APNs identity. This is a real retry-duplicate implementation
  gap for ordinary and strict `group_message` sends.
- `TestRelayNotificationClosure_DirectMessageCustodyRetryCollapse` currently
  asserts that the group sibling has no collapse ID
  (`ordinary_push_projection_test.go:854-865`). That preservation assertion
  must change with the production behavior; it cannot remain selected as if it
  were already compatible.
- `_waitForRelayTokenRegistration` still waits for
  `[PUSH] Token registered for ... (ios)`, which relay v1.8.0 removed, and iOS
  syslog starts after that wait
  (`capture_group_reaction_notification_device.dart:5475-5491`). The recipient
  already emits the attributable
  `[PUSH_DIAG] relay_push_registration_success platform=ios` marker.
- The legacy iOS criteria also require deleted
  `[PUSH] Notification sent to` text and an announcement ADD/REMOVE/ADD grammar.
  It cannot validate the requested message-plus-one-ADD chat journey. Separate
  message and reaction metric/log windows are required.
- The incumbent XCUITest independently finds title/body text and later taps the
  first title match. That proves visible copy only weakly and cannot distinguish
  a provider card from a Flutter-local card. Plan 397 therefore keeps XCUITest
  responsible only for same-container copy and exact tap routing; the native
  delivered-notification inventory is the source/cardinality authority.
- Plan 396's bootstrap launches Runner again to clean protected recovery files,
  and `finishIosNotificationRecoveryProof` releases
  `iosNotificationRecoveryProofInFlight` as soon as it writes the receipt. That
  lifecycle is unsafe for group observation: foreground reconciliation may
  retire the still-untapped reaction card because canonical badge state
  intentionally excludes reactions. The group-only observation must hold the
  fence until the host pulls the receipt and terminates Runner, with no cleanup
  launch before the exact SpringBoard tap.
- The live group path has no Plan-396-style direct-payload file containing raw
  expected IDs, and sender logs expose only short prefixes. Exact native
  classification therefore must consume SHA-256 identities already emitted by
  the incumbent Android group observer: `groupIdSha256`, marker `idSha256`, and
  `reactionTargetIdSha256`. It lacks the provider reaction event, so extend the
  reaction-phase call to that same read-only action with one `reactionIdSha256`
  from the exact latest ADD outbox row filtered by the run-owned group and
  authored target. Do not
  invoke the existing exact-redrive action: it mutates
  delivery status and would contaminate a one-logical-reaction duplicate test.
  Raw dynamic IDs must never cross into the retained proof.
- The installed-app observer currently derives its marker grammar only from the
  `_message_unread_lifecycle` suffix. The new combined scenario would therefore
  be treated as target-only and could not emit the Android-sent message hash.
  It needs one explicit scenario contract and two calls to the same read-only
  action: a message-phase observation before ADD, then a reaction-phase
  observation after ADD. This is not a new database probe.
- The incumbent stable sampler can return after its third equal 500 ms sample.
  For this investigation that is too early: terminating Runner can hide a
  Flutter-local sibling that publishes later. The group-only observer must
  remain open through the existing 8,000 ms deadline and require its final
  three samples to be stable. Plan-396 direct sampling remains unchanged.
- `buildGroupPushMessage` has rich, unusable-envelope, and oversized routing-only
  exits. The same projection helper owns all three, but one representative
  `preview_unavailable` case is required so a rich-shape-only implementation
  cannot satisfy TC-397-01.
- Plan 396's `ios.device.production` build already compiles
  `MKNOON_SIMS_IOS_RECEIVER_BOOTSTRAP` and ships an attested signed app plus
  XCUITest bundle. Reusing it avoids a second normal iOS child build and avoids
  adding a build profile.
- The Plan-257 staging manifest exact-pins announcement selectors, while the
  capture hardcodes those selectors instead of consuming the manifest. The
  selector contract must become scenario-aware before a chat-group row can be
  honest.
- At planning time `xctrace` reported only
  `00008110-00184D622289801E` in the online section; the other visible iPhone
  IDs were under `Devices Offline`. Execution must rediscover the matrix and
  reject IDs found only after that section boundary.
- There is no accepted ordinary chat-group iPhone message artifact, reaction
  artifact, or combined source-qualified proof on HEAD.

Affected production/test owners are limited to:

- `go-relay-server/inbox.go`, `group_content_push.go`, their focused tests, and
  `ordinary_push_projection_test.go`;
- the existing Plan-257 runner/capture/criteria/proof and shell contract;
- `lib/core/debug/group_reaction_e2e_probe.dart` and its existing focused test;
- `ios/NotificationService/IosNotificationRecovery.swift`,
  `ios/Runner/IosNotificationRecoveryCoordinator.swift`,
  `ios/Runner/IosReceiverBootstrapHandoff.swift`, `ios/Runner/AppDelegate.swift`,
  their existing Runner tests, and `ios_receiver_bootstrap.py`;
- `ios/RunnerUITests/NotificationTapUITests.swift`;
- the shared SI-5 fixture and exact Dart/Swift consumers.

No DB schema, notification architecture, or new application is planned.

## Graph Grounding Snapshot

- Graph fingerprint: `e8a6ede57fe0fb85`.
- Production branch: `query_id=c24f54bf8c114c32`,
  `evidence_digest=1fc73cf63c9e94b8`.
- Harness branch: `query_id=883b86a3a22c48ec`,
  `evidence_digest=f8f3f147ccd33cef`.
- Source-inventory branch: `query_id=478583f4d76e4c21`,
  `evidence_digest=a8cc9e79036b2f92`.
- Bootstrap-lifecycle audit: `query_id=54d545c48b504ca6`,
  `evidence_digest=d4db911adf8982fb`.
- Exact anchors: `buildGroupPushMessage`,
  `_waitForRelayTokenRegistration`, `IosDirectNotificationInventory`,
  `IosDirectNotificationStableSampler`, `IosReceiverBootstrapHandoff`, and
  `NotificationTapUITests.testAnnouncementReactionNotificationTap`.
- The compact graph did not expose the whole Plan-257 manifest/validator chain
  or Go builder. Those were checked directly. Preserve these IDs during
  execution; use targeted source verification rather than a new broad search.

## Scope Contract And Guard

In scope:

- Add exactly one scenario:
  `ios_chat_group_message_and_reaction_recipient`.
- Use one live physical Android sender and one live physical iPhone receiver.
  Create one ordinary chat group, have the iPhone author one target, send one
  unique group text from Android, then send one ADD reaction from Android to
  the authored target.
- Grade an attempt only after deterministic fixture staging has created and
  joined the group, authored the target, installed the central production
  products, backgrounded the receiver, and opened the first provider/native
  baseline window. USB/DDI/CoreDevice/setup-XCUITest failures before that
  boundary are sealed as `environment_blocked` pre-grade runs, are never
  promoted to notification evidence, and do not consume the message/reaction
  attempt budget. An exact
  `Timed out while enabling automation mode.` during either setup selector may
  receive one setup-only warm retry after a DDI remount, in a distinct
  `.xcresult`; notification-prepare/tap selectors and both graded event windows
  remain non-retriable.
- Keep the incumbent local E2E iOS setup build only for deterministic group
  creation/target authoring. Install the centrally attested
  `ios.device.production` app in place, without uninstalling between setup and
  observation, so the same app container survives. Resolve its attested app,
  test-products, and `.xctestrun` entries with the existing
  `relocateIosXctestrun` / `iosTestWithoutBuildingArguments` helpers, then use
  `xcodebuild test-without-building -xctestrun ...` for every graded normal-app
  leg. A workspace/scheme `xcodebuild test` remains valid for focused simulator
  host tests and the ungraded setup product, but is forbidden for the central
  graded product.
- Rebuild and require the centrally attested `android.production_fcm` APK from
  the Plan-397 tree after adding the read-only reaction digest, and make the iOS
  branch actually consume it. Campaign build accounting is exact:
  `androidChildBuildCount=0`, `iosNormalChildBuildCount=0`, and
  `iosSetupBuildCount<=1`. The setup build is the incumbent ungraded fixture
  product and may be zero when a compatible setup product already exists. If it
  is built, the first setup selector builds once into one DerivedData directory
  and the later target-authoring selector reuses that exact product without a
  clean or rebuild. The profile-mode fallback may carry the unregistered local
  attestation ID `ios.device.group_reaction_notification_397` together with
  `E2E_TEST_MODE=true` solely to open the identity/config/setup-action channel.
  This is not added to Sims, does not create a central artifact/capability, and
  remains ineligible for P269 disposable behavior or production bootstrap.
- Pass the two retained central Sims build reports with the artifacts. The
  runner must resolve each cache-adjacent `attestation.json`, verify exact
  profile/input/artifact digests and artifact membership, and copy only redacted
  provenance into the attempt. A stale environment path, structural iOS bundle
  manifest alone, or report/artifact mismatch fails. After a client repair,
  attempt two must use new build reports and a different iOS input/artifact
  digest from sealed attempt one.
- Add a narrow `IosGroupNotificationInventory` and group source classifier
  beside the Plan-396 direct types; do not rename or generalize the direct
  production recovery API. For each event, derive origin from
  `UNPushNotificationTrigger`, never from payload claims.
- Classify an exact remote `group_message` by `type` and SHA-256 equality for
  `groupId` plus `message_id`; classify an exact remote `group_reaction` by
  `type`, `action=add`, and SHA-256 equality for `groupId`, `event_id`, and
  `target_message_id`. Expected hashes come from the existing redacted Android
  observer plus its one read-only reaction-event digest, not truncated logs,
  the mutating redrive action, or retained raw IDs. Classify a Flutter-local
  sibling only from a valid `NotificationId` plus the typed conversation-card
  envelope with the same hash-bound group route, conversation key, content
  kind, and event.
- Add the new scenario explicitly to the incumbent probe allow-list and marker
  validator; do not infer its combined shape from a suffix. Reuse the existing
  read-only observe action twice. The message-phase request carries one Android
  message marker plus the iPhone-authored target marker and returns group,
  message, and target hashes before any ADD exists. The reaction-phase request
  carries the same markers and returns the same identities plus exactly one
  latest matching ADD `reactionIdSha256`. Neither phase changes delivery
  status, and a receipt/cursor from one phase cannot satisfy the other.
- Extend the existing protected bootstrap handoff with one narrow
  `observe-group` request/result action carrying only phase and expected
  SHA-256 identities. After each card arrives and before its tap, launch the
  central app once and keep the native recovery fence held while sampling
  through the existing 8,000 ms observation deadline. A group observation may
  succeed only at that horizon and only when its final three 500 ms samples are
  equal; three early equal samples are insufficient. Latch any matching
  local/sanitized/unknown source or `matchingTotalCount>1` seen at any sample
  and fail even if it disappears before the final-three window. Retain only
  sticky counts/flags and hashed request IDs, not a raw sample trace. Then pull
  a secret-free receipt, terminate Runner, and return to SpringBoard. Do not
  launch Runner again or clean the protected request/result before the tap.
  After the exact tap and route assertion, perform bounded cleanup in `finally`.
  Retain the receipt on PASS and FAIL. Do not change Plan-396 direct sampling
  semantics.
- Require per event:
  `matchingRemoteCount=1`, `matchingLocalCount=0`,
  `matchingUsefulProviderCount=1`,
  `matchingSanitizedProviderCount=0`,
  `matchingFlutterLocalCount=0`, `matchingUnknownCount=0`,
  `matchingTotalCount=1`, `stableSampleCount=3`, sampled-through-deadline proof,
  zero latched bad-source/duplicate flags across the whole horizon, and only
  hashed request IDs.
- Use XCUITest only to associate the run-owned title/body in the same
  SpringBoard card container, expand the run-owned stack when SpringBoard
  groups it, and tap that exact container. It must not claim producer ownership
  or cardinality.
- Capture one complete recipient/NSE log stream before the normal app launch
  and keep fresh event cursors. No Flutter contender is a valid outcome. If a
  contender does run, retain its disposition. Any run-owned
  `NOTIFICATION_SHOWN` publication or any local source observed during the
  horizon fails, regardless of sound or whether the card later disappears; an exact
  `NOTIFICATION_SUPPRESSED reason=recent_remote_push` is accepted but is not
  mandatory.
- Use separate relay-metric windows. The message window accepts a bounded
  shared provider-result-family floor only when joined to exact
  sender/custody/NSE/native inventory evidence; it does not claim an observed
  retry count. The reaction window requires exactly one attributable
  `relay_group_reaction_wake_total{outcome="attempted"}` delta.
- After the message tap, assert the exact message/group and final cleared group
  unread UI. Explicitly re-background the iPhone before sending the reaction.
  After the reaction tap, assert the exact authored target/reaction and final
  cleared group unread UI. These are final UI claims, not an assertion that a
  reaction never transiently changed unread state.
- Add one bounded per-message iOS collapse identity at the existing
  group-message projection seam. Retry identity is stable; distinct message IDs
  differ; blank canonical identity produces no header; Android/unknown remain
  headerless. Exercise one representative `preview_unavailable` routing-only
  group message in the same Go test; do not add a media matrix.
- Make live-iPhone parsing fail closed at the `Devices Offline` boundary and
  make the staging selector grammar scenario-aware. The capture must consume
  the validated selector values. The new row pins exactly
  `testCreateChatGroupNotificationFixture`,
  `testAuthorChatGroupReactionTarget`, the existing
  `testPrepareWarmNotificationTap`, and one phase-parameterized
  `testChatGroupNotificationTap`; announcement rows retain their existing four
  selectors.
- Build and reversibly deploy the candidate relay only to the existing staging
  target. Before replacement, require `x86_64`, create or reuse one immutable
  run-scoped binary backup, derive prior version/SHA from that backup on resume,
  and back up the exact redacted staging manifest without overwriting either
  backup. Bind the resume receipt to hashes of the exact relay target and
  canonical manifest path before touching either backup; missing resume backups
  or any live identity other than prior/candidate stops without mutation.
  Compare-and-swap the live and uploaded binary SHAs immediately before
  install/restore. Bind the static candidate revision
  `relay-server v1.9.0` and its independently computed SHA to the manifest.
  Deployment-health/identity failure or terminal rollback restores and verifies
  both the prior binary and prior manifest. No production deployment is
  authorized.

Must preserve:

- Android/unknown group projection remains without APNs/Android collapse
  metadata.
- Strict, announcement, and media group-message projection remains unchanged
  apart from the same iOS per-message retry identity.
- Group-reaction delivery remains author-only and per-event; distinct reaction
  events never share an APNs identity.
- Direct message, invite, opaque-wake, and contact/public-send Plan-395/396
  behavior remains intact. The stale group assertion inside the direct test is
  the only intended change in that test.
- Existing six Plan-257 scenarios remain source-compatible and are not run by
  this plan.
- Shared NSE/Dart dedupe identity gains one `group_reaction` vector; the
  already-correct algorithms are not edited if the vector passes.
- Plan-396 direct `prove-recovery` / `observe-direct` fence and cleanup behavior
  remains byte-for-byte compatible; deferred cleanup applies only to the new
  group observation action.

Hard `Do not`:

- Do not create a new notification architecture, source service, registered or
  central Sims build profile/capability, general iPhone controller, artifact
  framework, DB probe, or second app. The exact unregistered local setup
  attestation described above is the only setup-product exception.
- Do not obtain exact IDs from short log prefixes or retain raw group, message,
  target, or reaction identifiers. Reuse the incumbent redacted Android
  observer and do not schedule an exact-redrive probe in this scenario.
- Do not run Plan 396's direct APNs campaign or cite its waived physical result
  as group evidence.
- Do not add physical announcement, strict, media, mute, killed/foreground,
  REMOVE, sound, retry, or iOS-version matrix cells.
- Do not manufacture an APNs retry on device. Host Go tests own deterministic
  retry/collapse; the phone owns one-logical-event presentation.
- Do not require a Flutter contender or a suppression marker. Absence of a
  contender is expected on valid iOS delivery paths.
- Do not edit client dedupe production code unless the first retained device
  failure proves an attributable in-scope local effect and a focused
  captured-shape RED reproduces it.
- Do not run `1to1`, `feature-host-all`, `core-host-all`, or full `host-all` in
  this plan.

Deferred / accepted difference:

- Announcement authority, strict custody, media, mute, killed-state, REMOVE,
  sound-count, and OS-version physical permutations remain lower-tier or
  release-scope evidence, not Plan-397 gaps.
- Plan 396's missing automated direct physical PASS remains documented there.
- TestFlight/production APNs and consolidated Apple/release acceptance remain
  outside this staging/device plan.
- The new scenario is an on-demand classified device proof. It is not a new
  recurring Sims capability; recurring Apple-lab scheduling can wrap it later
  only if explicitly requested.

Dependencies:

- Preserve the current dirty tree, including Plan-396 implementation and user
  changes. No reset/revert is allowed.
- Fresh centrally attested `android.production_fcm` and
  `ios.device.production` artifacts from the final Plan-397 tree are required.
- The dedicated iPhone must be online, unlocked/no-passcode, automation-enabled,
  notification-authorized, and configured in English for the incumbent
  SpringBoard selectors. A different locale is a typed prerequisite failure,
  not a reason to build a localization framework.
- The existing staging relay/APNs configuration and dedicated-device reset
  authorization must pass the Plan-257 manifest validator.
- No DB/Redis migration, production mutation, or third device is required.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-397-01 | Ordinary, strict, and one representative routing-only iOS `group_message` retry use one bounded per-message collapse identity; distinct messages differ; blank identity, Android, and unknown stay headerless. | New `go-relay-server/ordinary_push_projection_test.go::TestRelayNotificationClosure_GroupMessageRetryCollapse` covers both real ordinary and strict send call sites plus one `preview_unavailable` iOS fallback with a recording provider; extend `TestPushService_SendGroupNotification_RetriesTransientFailure`; update only the stale group subcase in `TestRelayNotificationClosure_DirectMessageCustodyRetryCollapse`; preserve the production strict Android sentinel `TestStoreAckCustody_StrictGroupContentWakesTheRecipient`. | Host Go / real projector plus recording provider | RED: group messages have no APNs collapse header -> GREEN stable/distinct/bounded/iOS-only identity at rich and routing-only ordinary/strict call sites. | Key by group, mutate attempts, omit the strict call site, implement only the rich shape, or add an Android key -> red. | Exact non-vacuous Go selector; later `groups`. |
| TC-397-02 | iOS registration and provider evidence use live recipient/metric grammar, not either deleted relay phrase. | `group_reaction_notification_device_criteria_test.dart::iOS registration parser accepts only recipient relay success`; `chat-group iOS provider evidence uses two metric windows`; source contract. | Host Dart/shell / raw log and Prometheus fixtures | RED: dead wait and dead provider grammar -> GREEN exact platform marker, message floor joined to causal evidence, exact reaction delta; journal-only fixtures reject. | Restore a deleted grep or share one window -> red. | Criteria test plus exact shell contract. |
| TC-397-03 | The one new scenario is fully linked, consumes both freshly central-built artifacts and their reports/adjacent attestations, performs no graded normal child build, reuses at most one local setup product, installs the central iOS app in place without an intervening uninstall, runs the attested central UI product only through relocated `test-without-building`, uses scenario-specific manifest selectors, and rejects offline-only iPhone IDs. | `lists the seven availability-bounded scenarios in stable order`; `chat-group iOS scenario rejects stale or unbound central build reports`; `chat-group attempt two rejects attempt-one iOS artifact digest after client repair`; `chat-group iOS setup selectors reuse one setup product`; `chat-group iOS normal install preserves setup container`; `chat-group central UI leg uses relocated xctestrun without building`; `chat-group iOS tap uses one card container and rejects independent text lookup`; `chat-group iOS selectors are scenario-aware`; `iOS inventory rejects identifiers listed only under Devices Offline`; named proof. | Host Dart/shell / synthetic build reports, attestations, artifacts, bundle members, command trace, XCUITest source, and `xctrace` fixtures | RED: row absent; hardcoded selectors; iOS branch ignores Android prebuilt; stale incoming APK, structural-only iOS manifest, report mismatch/reuse, repeated setup build, normal child build/uninstall, independent title/body lookup, and offline line are accepted -> GREEN exact links, final-source input/artifact digest binding, one reused setup product, in-place update, attested app/test-products/xctestrun resolution, same-container tap, and fail-closed preflight. | Remove a catalog/proof link, swap a report/artifact digest, reuse attempt one's iOS digest after a client repair, clean/rebuild between setup selectors, use workspace/scheme `xcodebuild test` for a graded leg, insert an uninstall, restore independent title/body selection, omit a bundle member, or move ID below offline heading -> red. | Existing runner classification, `--list-scenarios`, discovery, shell contract. |
| TC-397-04 | The combined scenario's installed-app observer accepts one message marker plus one target marker and runs two read-only phases: message returns group/message/target hashes before ADD; reaction returns the same identities plus exactly one matching `reactionIdSha256`, without changing outbox status or reusing a receipt/cursor. Group message/reaction inventories classify exact provider and Flutter-local shapes, sample through the existing 8,000 ms horizon, require the final three samples to be stable, and latch any bad source/duplicate observed earlier. Each observation holds the native recovery fence through receipt pull, terminates Runner without a pre-tap cleanup relaunch, and retains only protected sticky counts/flags/timing/phase/hashes on PASS/FAIL. | `group_reaction_e2e_probe_test.dart::combined iOS group journey observes message then reaction without mutation`; `IosNotificationRecoveryTests/testTC397GroupDeliveredInventoryClassifiesExactSources`; `testTC397GroupInventoryRequiresFullHorizonAndRejectsTransientLateLocalSibling`; `IosReceiverBootstrapHandoffTests/testTC397GroupObservationReceiptIsProtectedAndRedacted`; `IosReceiverBootstrapTest.test_group_observation_is_exact_source_bound_redacted_and_cleaned`; `test_group_observation_holds_fence_until_pull_and_terminates_without_pretap_relaunch`; updated `scripts/test/ios_receiver_bootstrap_contract_test.dart`. | Host Dart + Swift simulator fake scheduler + Python fake + Dart source contract | RED: scenario is absent/target-only; reaction event is unavailable before ADD; three early stable samples pass; a transient local sibling is forgotten; direct-only classifier/handoff, raw-ID expectation, immediate fence release, and second cleanup launch remain -> GREEN exact two-phase hash binding, unchanged outbox, no phase reuse, exact full-horizon projection with sticky bad-source/duplicate rejection, held fence, pull, termination, tap, then cleanup. | Reject the combined marker shape, require a reaction ID during message phase, mutate outbox status, source the ID through exact-redrive, reuse a phase receipt/cursor, claim remote origin from payload, accept a mismatched digest/target/action, emit a raw ID, publish then remove a local sibling after sample three, release the fence on receipt, or relaunch before tap -> red. | Exact Flutter/`xcodebuild`/unittest selectors and directly affected bootstrap contract. |
| TC-397-05 | One artifact contains two ordered, independent event windows. Each binds its phase-correct Android-probe identity hashes, metrics/log cursor, NSE kind, sampled-through-deadline native inventory plus sticky bad-source/duplicate flags, same-card copy/tap, route/final UI, complete diagnostics, and contender disposition without requiring a contender. | `accepts realistic chat-group iOS message and reaction evidence`; `chat-group iOS proof binds Android digest identities`; negatives `rejects duplicate or local group source`, `rejects early, transient-local, unstable, or unhashed inventory`, `rejects deleted or unattributed provider evidence`, `rejects any run-owned local publication`, and `rejects wrong route or final unread UI`. | Host Dart / redacted hash-bound fixture | RED: announcement ADD/REMOVE/ADD schema cannot express the journey and no exact live-ID provenance exists -> GREEN exact two-window grammar joined to phase-correct full SHA-256 identities and full-horizon sticky source evidence. | Reuse a cursor/receipt, require a reaction event during message phase, omit the reaction event during reaction phase, substitute a short log prefix, mismatch an Android/native hash, complete before the observation horizon, clear a latched transient duplicate, make a count 2, inject silent or audible `NOTIFICATION_SHOWN`, remove NSE kind, or alter route -> red. | Existing criteria file in `GROUP_TESTS`; standalone validator and named proof. |
| TC-397-06 | NSE/Dart recent-remote identity covers `group_reaction`; message/reaction projection remains exact. | Add one row to `test_fixtures/si5_dedupe_keys.json`; existing Dart/Swift shared-fixture tests; new exact `show_notification_use_case_test.dart::suppresses local group reaction when recent remote event matches`. | Host Dart + Swift simulator | GREEN sentinel: both sides already contain group reaction key logic -> shared vector locks parity. | Change group route, target, or event identity on either side -> red. | Exact Dart/Swift selectors; later `groups`. |
| TC-397-07 | Backgrounded physical iPhone receives exactly one stable useful provider-owned ordinary group-message card; exact cold tap opens the message/group and final unread UI is clear. | Device scenario message window; XCUITest `testChatGroupNotificationTap`; native group observation receipt; named proof. | Physical Pixel -> staging relay/FCM/APNs -> NSE/UserNotifications -> iPhone | No accepted artifact on HEAD -> PASS only on exact source inventory, copy/tap, route, and final UI with zero manual taps. | TC-397-05 duplicate/source/route mutations reject the retained shape. | Same single device command as TC-397-08. |
| TC-397-08 | After explicit re-background, one ADD reaction to an iPhone-authored target produces exactly one stable useful provider-owned reaction card; cold tap reconstructs the target/reaction and final unread UI remains clear. | Same scenario reaction window; parameterized `testChatGroupNotificationTap`; native group observation receipt; named proof. | Same physical two-peer fixture | No accepted ordinary chat-group reaction artifact -> exact author-only typed copy/source/route/UI PASS. | Wrong target/action/event, missing re-background, or local source -> red. | Same campaign, not a second device run. |
| TC-397-09 | A physical duplicate/local-effect failure is repaired only at its demonstrated existing seam; a clean run makes this row N/A. Attempt one remains sealed, and no pre-repair iOS artifact/report may satisfy attempt two. | One captured-shape focused test in the existing recent-remote/show owner selected by the retained failure signature; both central build reports/attestations; separate attempt-two proof. | Conditional host causal test + sole permitted campaign rerun | Conditional RED only after attributable first failure -> minimal repair -> focused GREEN -> rebuild/re-attest both central products -> new iOS input/artifact digest -> one rerun. Android may be an attested cache hit when an iOS-native repair leaves its source closure unchanged. | Reapply the captured mismatch/delay, reuse the attempt-one directory/iOS report or artifact digest, or supply a report that does not match its artifact -> red. | Exact conditional test only; final `groups` gate runs once after the passing attempt. |

### Test Notes

- TC-397-07 and TC-397-08 share one fixture/campaign but use different metric,
  log, source-inventory, and XCUITest cursors. One window cannot satisfy the
  other.
- The native inventory is authoritative for source and stable cardinality.
  XCUITest proves visible copy and taps the same container; it does not infer
  ownership from text.
- No-contender and exact recent-remote suppression are both valid. Any run-owned
  Flutter `NOTIFICATION_SHOWN` marker or any matching local source seen at any
  sample is a failure, even when silent or absent from the final samples.
- Only one ADD reaction is sent. REMOVE and ADD/REMOVE/ADD semantics remain
  deterministic host sentinels; extra phone alerts would weaken this duplicate
  investigation.
- Android identity collection uses two calls to the same read-only observation:
  message phase before ADD and reaction phase after ADD. The existing
  `group_reaction_exact_add_redrive` action is neither called nor accepted as
  identity provenance for this scenario.
- The device campaign does not claim that an APNs retry occurred. TC-397-01
  owns retry identity at host tier.

## Implementation Steps

1. Snapshot `git status --short`, the Plan-396 baseline, and live target matrix.
   Preserve every unrelated/user-owned change.
2. Author TC-397-01, run its non-vacuous RED, then add the smallest iOS-only
   group-message projection helper and call it from ordinary and strict send
   sites. Let the same new test exercise the strict iOS call site and one
   representative routing-only `preview_unavailable` result; update the
   transient retry assertion and the one stale group subcase while preserving
   the production `StoreAckCustody` strict Android sentinel.
3. Author TC-397-02/03 REDs. Start bounded iOS syslog before normal launch,
   replace dead registration/provider grammar, consume both central artifacts,
   parse only the online `xctrace` section, and consume scenario-specific
   manifest selectors. Build the ungraded setup product at most once and reuse
   it across both setup selectors. Keep all six incumbent rows compatible.
4. Add the narrow group inventory/classifier and protected `observe-group`
   handoff beside Plan 396. Add the scenario-specific combined marker contract
   to the existing Android observer. Call its read-only action after the message
   to obtain group/message/target hashes, then after ADD to obtain the same
   identities plus exactly one matching `reactionIdSha256`, preserving delivery
   status in both phases. Do not invoke or modify the exact-redrive action. Keep
   group sampling alive through the existing 8,000 ms deadline and require the
   final three samples to be stable while latching any bad source/duplicate seen
   earlier. Test message/reaction remote shapes, typed local shapes, wrong/short
   identities, phase/cursor reuse, a local sibling arriving after the third
   early sample and disappearing before the final three, PASS/FAIL retention,
   cleanup, and redaction before integrating it into the capture.
5. Parameterize the existing iOS fixture/XCUITest for chat-group creation,
   target authoring, same-container message tap, explicit re-background, and
   same-container reaction tap. Install the central normal app in place after
   setup; never uninstall between these phases. For each inventory phase, hold
   the recovery fence, pull the receipt, terminate Runner, and forbid another
   launch until XCUITest taps the same card. Clean protected files only after
   route assertion.
6. Replace only the new scenario's validator grammar with two ordered windows
   and the exact native inventory. Retain secret-free evidence on PASS and FAIL.
   Never retain tokens, ciphertext, private keys, peer IDs, raw notification
   identifiers, or user/private plaintext; synthetic run markers and hashes are
   allowed.
7. Add the shared `group_reaction` SI-5 vector and run the exact Dart/Swift
   sentinels. Do not edit production key algorithms if the vector is green.
8. Rebuild the existing central `android.production_fcm` APK and
   `ios.device.production` bundle from the final code. Resolve them through the
   central build-report/attestation digests rather than a stale environment
   path, and record APK plus iOS bundle/manifest/member hashes. Cross-build and
   deploy the relay to staging through the reversible commands below. Reuse
   immutable run-scoped binary and manifest backups on resume, classify live
   binary state before compare-and-swap replacement, verify candidate
   health/version/SHA, and update plus record the redacted manifest
   revision/SHA and scenario selectors.
9. Run attempt one into its own non-overwritable artifact directory. On a clean
   PASS, continue to the final gate. On one attributable in-scope failure, seal
   and retain attempt one, author and run the exact TC-397-09 RED/GREEN, make
   one minimal existing-seam repair, rebuild and re-attest both central
   artifacts, then run attempt two into a different directory. Keep the relay
   candidate deployed through this one repair. A second or unclassified
   failure restores and verifies the prior relay plus manifest and blocks; do
   not loop.
10. After the final physical PASS, run the affected `groups` gate exactly once
    on that final tree, then scoped non-mutating hygiene, Graphify
    impact/refresh, and update the two UI-23 coverage documents plus index with
    the exact claim earned. A gate failure cannot authorize another device
    cycle under this plan.

## Risks And Blind Spots

- SpringBoard can stack cards. Source/cardinality therefore comes from native
  delivered-notification samples held through the bounded 8,000 ms group
  observation horizon, with the final three samples stable, not independent
  title/body counts or three early equal samples.
- Bringing the app forward for the protected inventory must not consume the
  card. The group recovery fence remains held through receipt pull; the capture
  terminates Runner without a cleanup relaunch and the next app launch must be
  XCUITest's exact-card tap. Protected cleanup happens only after route proof.
  Otherwise the run fails rather than weakening the oracle.
- Short IDs in sender/relay logs are diagnostic only. Every exact group,
  message, target, and reaction join uses a full Android-probe SHA-256 digest;
  absence or mismatch fails closed.
- Complete logs can be lost if capture starts late. One bounded syslog process
  begins before central normal-app launch and spans both event windows.
- Shared relay message metrics are not recipient-attributable alone. They pass
  only when joined to sender action, custody, exact NSE event, native inventory,
  target IDs, and device IDs.
- Final UI proves reconstruction after each cold tap. This plan deliberately
  does not add a physical SQLCipher observer or claim an unobserved intermediate
  unread transition. Reaction non-unread behavior remains owned by
  `test/features/groups/integration/group_reaction_notification_pipeline_test.dart`
  through the existing final `groups` gate; do not add a device DB probe.
- The iPhone is a dedicated test device. Reset/reinstall is authorized, but the
  plan does not claim restoration of prior app data. Cleanup must stop syslog,
  remove protected request/result files, terminate the candidate, and clear
  run-owned cards in `finally`.
- Sound is not causally countable with the available iPhone automation. Any
  attributable Flutter local publication fails regardless of sound; the main
  claim is one provider-owned card across the full observation horizon, not an
  acoustic measurement.

## Gate Cadence

- Per-plan closure: exact Go, Dart, Python, shell, and Swift selectors; one
  central Android and one central iOS build (plus one replacement pair only
  after the permitted causal repair); one physical scenario; one affected
  `groups` gate after the final
  device PASS; scoped hygiene. Serialize central build/staging/device mutation;
  use concurrency 2 only for independent focused Flutter tests.
- Do not run full `host-all` here. The next consolidated Apple-notification wave
  or final rollout owns:
  `./scripts/run_host_test_gates.sh host-all --batch-flutter --concurrency 2 --reporter failures-only`.
- The new row remains discoverable through the existing classified runner. Do
  not run or modify `group_reaction_notification_sims_adapter_contract_test.sh`;
  that adapter is Android-oriented and this is not a new Sims capability.

## Acceptance Gates

```bash
# Preflight: rediscover and pin only currently online targets.
git status --short
flutter devices --machine
adb devices -l
xcrun xctrace list devices
xcrun simctl list devices available

export PLAN397_ANDROID_ID=21071FDF600CSC
export PLAN397_IPHONE_ID=00008110-00184D622289801E
export PLAN397_IOS_SIM_ID=DBE8C32E-9F19-4593-860A-B41113791D79
: "${MKNOON_257_STAGING_MANIFEST:?required}"
: "${MKNOON_257_RELAY_TARGET:?required}"
: "${MKNOON_257_RELAY_KEY:?required}"
: "${FIREBASE_SERVICE_ACCOUNT:?required}"
jq -e '
  .schema == "mknoon.plan257.staging-prerequisites.v1" and
  .environment == "staging" and
  .productionDeploymentPerformed == false and
  .allowAppDataReset == true
' "$MKNOON_257_STAGING_MANIFEST" >/dev/null
ideviceinfo -u "$PLAN397_IPHONE_ID" -q com.apple.international | \
  rg '^Language: en'

# First causal Go RED after authoring the exact test. The list assertion keeps
# a misspelled/absent Go test from returning a vacuous green.
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test . \
  -list '^TestRelayNotificationClosure_GroupMessageRetryCollapse$' | \
  rg -x 'TestRelayNotificationClosure_GroupMessageRetryCollapse')
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test . \
  -run '^TestRelayNotificationClosure_GroupMessageRetryCollapse$' -v -count=1)

# Harness/native REDs after their named tests are authored. Each must fail for
# its documented missing behavior, not because no test ran.
flutter test test/integration/group_reaction_notification_device_criteria_test.dart \
  --plain-name 'iOS registration parser accepts only recipient relay success'
flutter test test/integration/group_reaction_notification_device_criteria_test.dart \
  --plain-name 'chat-group iOS scenario requires central Android and iOS artifacts'
flutter test test/integration/group_reaction_notification_device_criteria_test.dart \
  --plain-name 'chat-group iOS scenario rejects stale or unbound central build reports'
flutter test test/integration/group_reaction_notification_device_criteria_test.dart \
  --plain-name 'chat-group attempt two rejects attempt-one iOS artifact digest after client repair'
flutter test test/integration/group_reaction_notification_device_criteria_test.dart \
  --plain-name 'chat-group central UI leg uses relocated xctestrun without building'
flutter test test/integration/group_reaction_notification_device_criteria_test.dart \
  --plain-name 'chat-group iOS setup selectors reuse one setup product'
flutter test test/integration/group_reaction_notification_device_criteria_test.dart \
  --plain-name 'chat-group iOS tap uses one card container and rejects independent text lookup'
flutter test test/integration/group_reaction_notification_device_criteria_test.dart \
  --plain-name 'iOS inventory rejects identifiers listed only under Devices Offline'
flutter test test/integration/group_reaction_notification_device_criteria_test.dart \
  --plain-name 'accepts realistic chat-group iOS message and reaction evidence'
flutter test test/integration/group_reaction_notification_device_criteria_test.dart \
  --plain-name 'chat-group iOS proof binds Android digest identities'
flutter test test/core/debug/group_reaction_e2e_probe_test.dart \
  --plain-name 'combined iOS group journey observes message then reaction without mutation'
python3 -m unittest \
  scripts.test.ios_receiver_bootstrap_test.IosReceiverBootstrapTest.test_group_observation_is_exact_source_bound_redacted_and_cleaned \
  scripts.test.ios_receiver_bootstrap_test.IosReceiverBootstrapTest.test_group_observation_holds_fence_until_pull_and_terminates_without_pretap_relaunch
dart run scripts/test/ios_receiver_bootstrap_contract_test.dart
xcodebuild test \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -destination "platform=iOS Simulator,id=$PLAN397_IOS_SIM_ID" \
  -only-testing:RunnerTests/IosNotificationRecoveryTests/testTC397GroupDeliveredInventoryClassifiesExactSources \
  -only-testing:RunnerTests/IosNotificationRecoveryTests/testTC397GroupInventoryRequiresFullHorizonAndRejectsTransientLateLocalSibling \
  -only-testing:RunnerTests/IosReceiverBootstrapHandoffTests/testTC397GroupObservationReceiptIsProtectedAndRedacted

# Focused Go GREEN. The exact regex has five expected names; assert the list
# count before executing so absence cannot pass.
export PLAN397_GO_TESTS='^(TestRelayNotificationClosure_GroupMessageRetryCollapse|TestPushService_SendGroupNotification_RetriesTransientFailure|TestRelayNotificationClosure_DirectMessageCustodyRetryCollapse|TestStoreAckCustody_StrictGroupContentWakesTheRecipient|TestRelayNotificationClosure_GroupReactionApnsCollapseIdRemainsPerGroup)$'
PLAN397_GO_LIST="$(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test . -list "$PLAN397_GO_TESTS")"
test "$(printf '%s\n' "$PLAN397_GO_LIST" | rg -c '^Test')" -eq 5
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test . \
  -run "$PLAN397_GO_TESTS" -v -count=1)

# Focused Dart/Python/shell GREEN only.
flutter test --concurrency=2 --reporter failures-only \
  test/integration/group_reaction_notification_device_criteria_test.dart \
  test/core/notifications/recent_remote_notification_gate_test.dart
flutter test test/features/push/application/show_notification_use_case_test.dart \
  --plain-name 'suppresses local group reaction when recent remote event matches'
python3 -m unittest \
  scripts.test.ios_receiver_bootstrap_test.IosReceiverBootstrapTest.test_group_observation_is_exact_source_bound_redacted_and_cleaned \
  scripts.test.ios_receiver_bootstrap_test.IosReceiverBootstrapTest.test_group_observation_holds_fence_until_pull_and_terminates_without_pretap_relaunch
dart run scripts/test/ios_receiver_bootstrap_contract_test.dart
flutter test test/core/debug/group_reaction_e2e_probe_test.dart \
  --plain-name 'combined iOS group journey observes message then reaction without mutation'
bash scripts/test/group_reaction_notification_device_contract_test.sh

# Exact native inventory, handoff, and group projection preservation.
xcodebuild test \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -destination "platform=iOS Simulator,id=$PLAN397_IOS_SIM_ID" \
  -only-testing:RunnerTests/IosNotificationRecoveryTests/testTC397GroupDeliveredInventoryClassifiesExactSources \
  -only-testing:RunnerTests/IosNotificationRecoveryTests/testTC397GroupInventoryRequiresFullHorizonAndRejectsTransientLateLocalSibling \
  -only-testing:RunnerTests/IosReceiverBootstrapHandoffTests/testTC397GroupObservationReceiptIsProtectedAndRedacted \
  -only-testing:RunnerTests/IosNotificationRecoveryTests/testTC396DeliveredInventoryClassifiesExactSources \
  -only-testing:RunnerTests/IosNotificationRecoveryTests/testTC396SameRequestDuplicateIsDistinctFromDifferentRequestDuplicate \
  -only-testing:RunnerTests/IosReceiverBootstrapHandoffTests/testTC396StableSamplerCompletesAtHardDeadlineWhenCallbackIsMissing \
  -only-testing:RunnerTests/IosReceiverBootstrapHandoffTests/testTC396StableSamplerIgnoresCallbackAfterHardDeadlineCompletion \
  -only-testing:RunnerTests/IosReceiverBootstrapHandoffTests/testTC396RecoveryResultPublishesBoundedSourceCounts \
  -only-testing:RunnerTests/NotificationPreviewResolverTests/testGateMessageKeyMatchesSharedDedupeFixture \
  -only-testing:RunnerTests/NotificationPreviewResolverTests/testDecryptsNativeV3GroupPreviewFromEncryptedExtra \
  -only-testing:RunnerTests/NotificationPreviewResolverTests/testGroupReactionUsesProjectedContextAndClaimsOnlyAfterExactParity \
  -only-testing:RunnerTests/NotificationPreviewResolverTests/testMessageNotificationProjectionMatrixCoversContextsAndModalities

# Registration/discovery: the new ID appears exactly once.
dart run integration_test/scripts/run_group_reaction_notification_device.dart \
  --scenario ios_chat_group_message_and_reaction_recipient --list-scenarios
./scripts/check_reliability_simulation_discovery.sh

# Rebuild both existing central profiles from the final Plan-397 tree. Resolve
# only the cache entries named by their retained reports and attestations; a
# pre-existing artifact environment variable cannot satisfy this gate.
: "${MKNOON_RELAY_ADDRESSES:?required for the staging-bound central build}"
mkdir -p build/plan397
export PLAN397_SIMS_CACHE="${SIMS_CACHE_DIR:-$PWD/build/sims/cache}"
export PLAN397_ANDROID_BUILD_REPORT="$PWD/build/plan397/android-attempt-1-build-report.json"
test ! -e "$PLAN397_ANDROID_BUILD_REPORT"
SIMS_REPORT_PATH="$PLAN397_ANDROID_BUILD_REPORT" \
  dart tool/sims/sims.dart major \
    --only build.android.production_fcm --prepare-builds
export PLAN397_ANDROID_BUILD_SHA="$(jq -er \
  '.builds.artifactDigests["android.production_fcm"]' \
  "$PLAN397_ANDROID_BUILD_REPORT")"
unset SIMS_ARTIFACT_ANDROID_PRODUCTION_FCM
while IFS= read -r PLAN397_ATTESTATION; do
  if jq -e --arg digest "$PLAN397_ANDROID_BUILD_SHA" '
    .profileId == "android.production_fcm" and .artifactDigest == $digest
  ' "$PLAN397_ATTESTATION" >/dev/null; then
    export SIMS_ARTIFACT_ANDROID_PRODUCTION_FCM="$(dirname "$PLAN397_ATTESTATION")/artifact.apk"
    export PLAN397_ANDROID_BUILD_INPUT_SHA="$(jq -r .inputDigest "$PLAN397_ATTESTATION")"
    break
  fi
done < <(find "$PLAN397_SIMS_CACHE/android.production_fcm" \
  -type f -name attestation.json -print)
: "${SIMS_ARTIFACT_ANDROID_PRODUCTION_FCM:?attested final-tree APK not found}"
test -f "$SIMS_ARTIFACT_ANDROID_PRODUCTION_FCM"
test "$(shasum -a 256 "$SIMS_ARTIFACT_ANDROID_PRODUCTION_FCM" | awk '{print $1}')" = \
  "$PLAN397_ANDROID_BUILD_SHA"

export PLAN397_IOS_BUILD_REPORT="$PWD/build/plan397/ios-attempt-1-build-report.json"
test ! -e "$PLAN397_IOS_BUILD_REPORT"
SIMS_REPORT_PATH="$PLAN397_IOS_BUILD_REPORT" \
  dart tool/sims/sims.dart major \
    --only build.ios.device.production --prepare-builds
export PLAN397_IOS_BUILD_SHA="$(jq -er \
  '.builds.artifactDigests["ios.device.production"]' \
  "$PLAN397_IOS_BUILD_REPORT")"
unset SIMS_ARTIFACT_IOS_DEVICE_PRODUCTION
while IFS= read -r PLAN397_ATTESTATION; do
  if jq -e --arg digest "$PLAN397_IOS_BUILD_SHA" '
    .profileId == "ios.device.production" and .artifactDigest == $digest
  ' "$PLAN397_ATTESTATION" >/dev/null; then
    export SIMS_ARTIFACT_IOS_DEVICE_PRODUCTION="$(dirname "$PLAN397_ATTESTATION")/ios.device.production.bundle"
    export PLAN397_IOS_BUILD_INPUT_SHA="$(jq -r .inputDigest "$PLAN397_ATTESTATION")"
    break
  fi
done < <(find "$PLAN397_SIMS_CACHE/ios.device.production" \
  -type f -name attestation.json -print)
: "${SIMS_ARTIFACT_IOS_DEVICE_PRODUCTION:?attested final-tree iOS bundle not found}"
test -d "$SIMS_ARTIFACT_IOS_DEVICE_PRODUCTION"
export PLAN397_IOS_MANIFEST="$SIMS_ARTIFACT_IOS_DEVICE_PRODUCTION/bundle_manifest.json"
test -f "$PLAN397_IOS_MANIFEST"
jq -e '
  .profileId == "ios.device.production" and
  (.applicationApp | type == "string") and
  (.xctestrun | type == "string") and
  (.testProducts | type == "string")
' "$PLAN397_IOS_MANIFEST" >/dev/null
export PLAN397_IOS_APPLICATION="$(jq -r .applicationApp "$PLAN397_IOS_MANIFEST")"
export PLAN397_IOS_XCTESTRUN="$(jq -r .xctestrun "$PLAN397_IOS_MANIFEST")"
export PLAN397_IOS_TEST_PRODUCTS="$(jq -r .testProducts "$PLAN397_IOS_MANIFEST")"
test -d "$SIMS_ARTIFACT_IOS_DEVICE_PRODUCTION/$PLAN397_IOS_APPLICATION"
test -s "$SIMS_ARTIFACT_IOS_DEVICE_PRODUCTION/$PLAN397_IOS_XCTESTRUN"
test -d "$SIMS_ARTIFACT_IOS_DEVICE_PRODUCTION/$PLAN397_IOS_TEST_PRODUCTS"
export PLAN397_IOS_MANIFEST_SHA="$(shasum -a 256 "$PLAN397_IOS_MANIFEST" | awk '{print $1}')"

# Reversible staging deployment. The immutable binary/manifest backups and one
# small redacted receipt are the resume authority; never recapture "prior" from
# a possibly-candidate live binary.
export PLAN397_RELAY_RUN_ID=plan397-20260823-02
export PLAN397_RELAY_BACKUP=/usr/local/bin/relay-server.plan397-20260823-02.bak
export PLAN397_RELAY_REMOTE_CANDIDATE=/tmp/relay-server.plan397-20260823-02
export PLAN397_RELAY_REVISION='relay-server v1.9.0'
export PLAN397_DEPLOYMENT_RECEIPT="$PWD/build/plan397/deployment-state-02.json"
export PLAN397_STAGING_MANIFEST_BACKUP="$PWD/build/plan397/staging-manifest.prior-02.json"
export PLAN397_STAGING_MANIFEST_CANDIDATE="$PWD/build/plan397/staging-manifest.candidate-02.json"
if ! mkdir -p build/plan397; then
  exit 1
fi
export MKNOON_257_STAGING_MANIFEST="$(cd \
  "$(dirname "$MKNOON_257_STAGING_MANIFEST")" && pwd -P)/$(basename \
  "$MKNOON_257_STAGING_MANIFEST")"
export PLAN397_RELAY_TARGET_SHA="$(printf '%s' "$MKNOON_257_RELAY_TARGET" | \
  shasum -a 256 | awk '{print $1}')"
export PLAN397_STAGING_MANIFEST_PATH_SHA="$(printf '%s' \
  "$MKNOON_257_STAGING_MANIFEST" | shasum -a 256 | awk '{print $1}')"

# A resume receipt must bind the target/path before this block touches either
# backup. Missing resume backups stop; they are never recreated from live.
export PLAN397_DEPLOYMENT_RESUME=0
if [ -e "$PLAN397_DEPLOYMENT_RECEIPT" ]; then
  if ! jq -e --arg runId "$PLAN397_RELAY_RUN_ID" \
        --arg relayTargetSha "$PLAN397_RELAY_TARGET_SHA" \
        --arg manifestPathSha "$PLAN397_STAGING_MANIFEST_PATH_SHA" '
    .schema == "mknoon.plan397.deployment-state.v1" and
    .runId == $runId and
    .relayTargetSha256 == $relayTargetSha and
    .stagingManifestPathSha256 == $manifestPathSha
  ' "$PLAN397_DEPLOYMENT_RECEIPT" >/dev/null; then
    exit 1
  fi
  if ! ssh -i "$MKNOON_257_RELAY_KEY" "$MKNOON_257_RELAY_TARGET" \
    "test -f '$PLAN397_RELAY_BACKUP'"; then
    exit 1
  fi
  if [ ! -f "$PLAN397_STAGING_MANIFEST_BACKUP" ]; then
    exit 1
  fi
  export PLAN397_DEPLOYMENT_RESUME=1
fi
if ! rg -x 'const version = "1\.9\.0"' go-relay-server/main.go; then
  exit 1
fi
export PLAN397_RELAY_ARCH="$(ssh -i "$MKNOON_257_RELAY_KEY" \
  "$MKNOON_257_RELAY_TARGET" 'uname -m')"
if [ "$PLAN397_RELAY_ARCH" != x86_64 ]; then
  exit 1
fi
if ! (cd go-relay-server && env GOTOOLCHAIN=go1.25.0 GOOS=linux GOARCH=amd64 \
  CGO_ENABLED=0 go build -trimpath \
  -o ../build/plan397/relay-server-linux-amd64 .); then
  exit 1
fi
export PLAN397_RELAY_SHA="$(shasum -a 256 build/plan397/relay-server-linux-amd64 | awk '{print $1}')"

# Resolve prior relay identity from the immutable backup on resume. Create the
# backup from live only when this run-scoped path does not exist.
if ssh -i "$MKNOON_257_RELAY_KEY" "$MKNOON_257_RELAY_TARGET" \
  "test -e '$PLAN397_RELAY_BACKUP'"; then
  export PLAN397_RELAY_PRIOR_SHA="$(ssh -i "$MKNOON_257_RELAY_KEY" \
    "$MKNOON_257_RELAY_TARGET" \
    "sha256sum '$PLAN397_RELAY_BACKUP' | awk '{print \$1}'")"
  export PLAN397_RELAY_PRIOR_VERSION="$(ssh -i "$MKNOON_257_RELAY_KEY" \
    "$MKNOON_257_RELAY_TARGET" "'$PLAN397_RELAY_BACKUP' version")"
else
  export PLAN397_RELAY_PRIOR_SHA="$(ssh -i "$MKNOON_257_RELAY_KEY" \
    "$MKNOON_257_RELAY_TARGET" \
    "sha256sum /usr/local/bin/relay-server | awk '{print \$1}'")"
  export PLAN397_RELAY_PRIOR_VERSION="$(ssh -i "$MKNOON_257_RELAY_KEY" \
    "$MKNOON_257_RELAY_TARGET" '/usr/local/bin/relay-server version')"
  if ! ssh -i "$MKNOON_257_RELAY_KEY" "$MKNOON_257_RELAY_TARGET" \
    "printf '%s  %s\n' '$PLAN397_RELAY_PRIOR_SHA' /usr/local/bin/relay-server | sha256sum -c - >/dev/null && sudo install -m0755 /usr/local/bin/relay-server '$PLAN397_RELAY_BACKUP'"; then
    exit 1
  fi
fi
if [ -z "$PLAN397_RELAY_PRIOR_VERSION" ] || \
   [ -z "$PLAN397_RELAY_PRIOR_SHA" ]; then
  exit 1
fi
export PLAN397_RELAY_BACKUP_SHA="$(ssh -i "$MKNOON_257_RELAY_KEY" \
  "$MKNOON_257_RELAY_TARGET" \
  "sha256sum '$PLAN397_RELAY_BACKUP' | awk '{print \$1}'")"
if [ "$PLAN397_RELAY_BACKUP_SHA" != "$PLAN397_RELAY_PRIOR_SHA" ]; then
  exit 1
fi

# Preserve the exact redacted manifest once and build the candidate manifest
# deterministically from that backup. This is one representative chat-group
# row, not a new manifest format.
if [ ! -f "$MKNOON_257_STAGING_MANIFEST" ] || \
   [ -L "$MKNOON_257_STAGING_MANIFEST" ]; then
  exit 1
fi
if [ ! -e "$PLAN397_STAGING_MANIFEST_BACKUP" ]; then
  if [ "$PLAN397_DEPLOYMENT_RESUME" = 1 ] || \
    ! cp -p "$MKNOON_257_STAGING_MANIFEST" \
      "$PLAN397_STAGING_MANIFEST_BACKUP"; then
    exit 1
  fi
fi
if [ ! -f "$PLAN397_STAGING_MANIFEST_BACKUP" ]; then
  exit 1
fi
export PLAN397_STAGING_MANIFEST_PRIOR_SHA="$(shasum -a 256 \
  "$PLAN397_STAGING_MANIFEST_BACKUP" | awk '{print $1}')"
if ! jq --arg revision "$PLAN397_RELAY_REVISION" \
   --arg relaySha "$PLAN397_RELAY_SHA" '
  .candidateRelayRevision = $revision |
  .candidateRelaySha256 = $relaySha |
  .provider = "apns" |
  .iosCapture.bundleId = "com.mknoon.app" |
  .iosCapture.workspace = "ios/Runner.xcworkspace" |
  .iosCapture.scheme = "Runner" |
  .iosCapture.systemLogExecutable = "idevicesyslog" |
  .iosCapture.fixtureCreateSelector =
    "RunnerUITests/NotificationTapUITests/testCreateChatGroupNotificationFixture" |
  .iosCapture.fixtureAuthorSelector =
    "RunnerUITests/NotificationTapUITests/testAuthorChatGroupReactionTarget" |
  .iosCapture.notificationPrepareSelector =
    "RunnerUITests/NotificationTapUITests/testPrepareWarmNotificationTap" |
  .iosCapture.notificationTapSelector =
    "RunnerUITests/NotificationTapUITests/testChatGroupNotificationTap"
' "$PLAN397_STAGING_MANIFEST_BACKUP" > "$PLAN397_STAGING_MANIFEST_CANDIDATE"; then
  exit 1
fi
if ! jq -e --arg revision "$PLAN397_RELAY_REVISION" \
      --arg relaySha "$PLAN397_RELAY_SHA" '
  .candidateRelayRevision == $revision and
  .candidateRelaySha256 == $relaySha and
  .productionDeploymentPerformed == false and
  .provider == "apns" and
  .iosCapture.bundleId == "com.mknoon.app" and
  .iosCapture.workspace == "ios/Runner.xcworkspace" and
  .iosCapture.scheme == "Runner" and
  .iosCapture.systemLogExecutable == "idevicesyslog" and
  .iosCapture.fixtureCreateSelector ==
    "RunnerUITests/NotificationTapUITests/testCreateChatGroupNotificationFixture" and
  .iosCapture.fixtureAuthorSelector ==
    "RunnerUITests/NotificationTapUITests/testAuthorChatGroupReactionTarget" and
  .iosCapture.notificationPrepareSelector ==
    "RunnerUITests/NotificationTapUITests/testPrepareWarmNotificationTap" and
  .iosCapture.notificationTapSelector ==
    "RunnerUITests/NotificationTapUITests/testChatGroupNotificationTap"
' "$PLAN397_STAGING_MANIFEST_CANDIDATE" >/dev/null; then
  exit 1
fi
export PLAN397_STAGING_MANIFEST_CANDIDATE_SHA="$(shasum -a 256 \
  "$PLAN397_STAGING_MANIFEST_CANDIDATE" | awk '{print $1}')"

# Persist or validate the tiny resume receipt before either external mutation.
if [ -e "$PLAN397_DEPLOYMENT_RECEIPT" ]; then
  if ! jq -e --arg runId "$PLAN397_RELAY_RUN_ID" \
        --arg relayTargetSha "$PLAN397_RELAY_TARGET_SHA" \
        --arg manifestPathSha "$PLAN397_STAGING_MANIFEST_PATH_SHA" \
        --arg priorRelayVersion "$PLAN397_RELAY_PRIOR_VERSION" \
        --arg priorRelaySha "$PLAN397_RELAY_PRIOR_SHA" \
        --arg candidateRelaySha "$PLAN397_RELAY_SHA" \
        --arg priorManifestSha "$PLAN397_STAGING_MANIFEST_PRIOR_SHA" \
        --arg candidateManifestSha "$PLAN397_STAGING_MANIFEST_CANDIDATE_SHA" '
    .schema == "mknoon.plan397.deployment-state.v1" and
    .runId == $runId and
    .relayTargetSha256 == $relayTargetSha and
    .stagingManifestPathSha256 == $manifestPathSha and
    .priorRelayVersion == $priorRelayVersion and
    .priorRelaySha256 == $priorRelaySha and
    .candidateRelaySha256 == $candidateRelaySha and
    .priorManifestSha256 == $priorManifestSha and
    .candidateManifestSha256 == $candidateManifestSha
  ' "$PLAN397_DEPLOYMENT_RECEIPT" >/dev/null; then
    exit 1
  fi
else
  umask 077
  export PLAN397_DEPLOYMENT_RECEIPT_TMP="$PLAN397_DEPLOYMENT_RECEIPT.tmp"
  if [ -e "$PLAN397_DEPLOYMENT_RECEIPT_TMP" ]; then
    exit 1
  fi
  if ! jq -n --arg runId "$PLAN397_RELAY_RUN_ID" \
        --arg relayTargetSha "$PLAN397_RELAY_TARGET_SHA" \
        --arg manifestPathSha "$PLAN397_STAGING_MANIFEST_PATH_SHA" \
        --arg priorRelayVersion "$PLAN397_RELAY_PRIOR_VERSION" \
        --arg priorRelaySha "$PLAN397_RELAY_PRIOR_SHA" \
        --arg candidateRelaySha "$PLAN397_RELAY_SHA" \
        --arg priorManifestSha "$PLAN397_STAGING_MANIFEST_PRIOR_SHA" \
        --arg candidateManifestSha "$PLAN397_STAGING_MANIFEST_CANDIDATE_SHA" '
    {
      schema: "mknoon.plan397.deployment-state.v1",
      runId: $runId,
      relayTargetSha256: $relayTargetSha,
      stagingManifestPathSha256: $manifestPathSha,
      priorRelayVersion: $priorRelayVersion,
      priorRelaySha256: $priorRelaySha,
      candidateRelaySha256: $candidateRelaySha,
      priorManifestSha256: $priorManifestSha,
      candidateManifestSha256: $candidateManifestSha
    }
  ' > "$PLAN397_DEPLOYMENT_RECEIPT_TMP"; then
    exit 1
  fi
  if ! mv "$PLAN397_DEPLOYMENT_RECEIPT_TMP" \
    "$PLAN397_DEPLOYMENT_RECEIPT"; then
    exit 1
  fi
fi

if ! scp -i "$MKNOON_257_RELAY_KEY" \
  build/plan397/relay-server-linux-amd64 \
  "$MKNOON_257_RELAY_TARGET:$PLAN397_RELAY_REMOTE_CANDIDATE"; then
  exit 1
fi
export PLAN397_RELAY_REMOTE_CANDIDATE_SHA="$(ssh -i \
  "$MKNOON_257_RELAY_KEY" "$MKNOON_257_RELAY_TARGET" \
  "sha256sum '$PLAN397_RELAY_REMOTE_CANDIDATE' | awk '{print \$1}'")"
if [ "$PLAN397_RELAY_REMOTE_CANDIDATE_SHA" != "$PLAN397_RELAY_SHA" ]; then
  exit 1
fi

plan397_restore_staging() {
  local live_sha current_manifest_sha restore_tmp
  if ! live_sha="$(ssh -i "$MKNOON_257_RELAY_KEY" \
    "$MKNOON_257_RELAY_TARGET" \
    "sha256sum /usr/local/bin/relay-server | awk '{print \$1}'")"; then
    return 1
  fi
  if ! current_manifest_sha="$(shasum -a 256 \
    "$MKNOON_257_STAGING_MANIFEST" | awk '{print $1}')"; then
    return 1
  fi
  if [ "$live_sha" != "$PLAN397_RELAY_PRIOR_SHA" ] && \
     [ "$live_sha" != "$PLAN397_RELAY_SHA" ]; then
    return 1
  fi
  if [ "$current_manifest_sha" != "$PLAN397_STAGING_MANIFEST_PRIOR_SHA" ] && \
     [ "$current_manifest_sha" != \
       "$PLAN397_STAGING_MANIFEST_CANDIDATE_SHA" ]; then
    return 1
  fi

  if [ "$live_sha" = "$PLAN397_RELAY_SHA" ]; then
    if ! ssh -i "$MKNOON_257_RELAY_KEY" "$MKNOON_257_RELAY_TARGET" \
      "printf '%s  %s\n' '$PLAN397_RELAY_SHA' /usr/local/bin/relay-server | sha256sum -c - >/dev/null && printf '%s  %s\n' '$PLAN397_RELAY_PRIOR_SHA' '$PLAN397_RELAY_BACKUP' | sha256sum -c - >/dev/null && sudo install -m0755 '$PLAN397_RELAY_BACKUP' /usr/local/bin/relay-server"; then
      return 1
    fi
  fi
  if ! ssh -i "$MKNOON_257_RELAY_KEY" "$MKNOON_257_RELAY_TARGET" '
    sudo systemctl restart relay-server || exit 1
    systemctl is-active --quiet relay-server || exit 1
    health_attempt=1
    while [ "$health_attempt" -le 20 ]; do
      if curl -fsS http://127.0.0.1:2112/metrics >/dev/null; then
        exit 0
      fi
      health_attempt=$((health_attempt + 1))
      sleep 1
    done
    exit 1
  '; then
    return 1
  fi
  if [ "$(ssh -i "$MKNOON_257_RELAY_KEY" "$MKNOON_257_RELAY_TARGET" \
    "sha256sum /usr/local/bin/relay-server | awk '{print \$1}'")" = \
    "$PLAN397_RELAY_PRIOR_SHA" ]; then :; else return 1; fi
  if [ "$(ssh -i "$MKNOON_257_RELAY_KEY" "$MKNOON_257_RELAY_TARGET" \
    '/usr/local/bin/relay-server version')" = \
    "$PLAN397_RELAY_PRIOR_VERSION" ]; then :; else return 1; fi

  if ! current_manifest_sha="$(shasum -a 256 \
    "$MKNOON_257_STAGING_MANIFEST" | awk '{print $1}')"; then
    return 1
  fi
  if [ "$current_manifest_sha" != "$PLAN397_STAGING_MANIFEST_PRIOR_SHA" ] && \
     [ "$current_manifest_sha" != \
       "$PLAN397_STAGING_MANIFEST_CANDIDATE_SHA" ]; then
    return 1
  fi
  if [ "$current_manifest_sha" = "$PLAN397_STAGING_MANIFEST_PRIOR_SHA" ]; then
    :
  elif [ "$current_manifest_sha" = \
    "$PLAN397_STAGING_MANIFEST_CANDIDATE_SHA" ]; then
    restore_tmp="$MKNOON_257_STAGING_MANIFEST.plan397-restore.tmp"
    if [ -e "$restore_tmp" ]; then
      if [ "$(shasum -a 256 "$restore_tmp" | awk '{print $1}')" != \
        "$PLAN397_STAGING_MANIFEST_PRIOR_SHA" ]; then
        return 1
      fi
    else
      if ! cp -p "$PLAN397_STAGING_MANIFEST_BACKUP" "$restore_tmp"; then
        return 1
      fi
    fi
    if ! mv "$restore_tmp" "$MKNOON_257_STAGING_MANIFEST"; then
      return 1
    fi
  fi
  if [ "$(shasum -a 256 "$MKNOON_257_STAGING_MANIFEST" | awk '{print $1}')" = \
    "$PLAN397_STAGING_MANIFEST_PRIOR_SHA" ]; then :; else return 1; fi
  return 0
}

# Resume-safe live classification followed by an immediate SHA CAS. A candidate
# already live is health-checked, never recaptured as prior or reinstalled.
export PLAN397_RELAY_LIVE_SHA="$(ssh -i "$MKNOON_257_RELAY_KEY" \
  "$MKNOON_257_RELAY_TARGET" \
  "sha256sum /usr/local/bin/relay-server | awk '{print \$1}'")"
export PLAN397_STAGING_MANIFEST_LIVE_SHA="$(shasum -a 256 \
  "$MKNOON_257_STAGING_MANIFEST" | awk '{print $1}')"
if [ "$PLAN397_RELAY_LIVE_SHA" != "$PLAN397_RELAY_PRIOR_SHA" ] && \
   [ "$PLAN397_RELAY_LIVE_SHA" != "$PLAN397_RELAY_SHA" ]; then
  exit 1
fi
if [ "$PLAN397_STAGING_MANIFEST_LIVE_SHA" != \
     "$PLAN397_STAGING_MANIFEST_PRIOR_SHA" ] && \
   [ "$PLAN397_STAGING_MANIFEST_LIVE_SHA" != \
     "$PLAN397_STAGING_MANIFEST_CANDIDATE_SHA" ]; then
  exit 1
fi
if [ "$PLAN397_RELAY_LIVE_SHA" = "$PLAN397_RELAY_PRIOR_SHA" ]; then
  if ! ssh -i "$MKNOON_257_RELAY_KEY" "$MKNOON_257_RELAY_TARGET" \
    "printf '%s  %s\n' '$PLAN397_RELAY_PRIOR_SHA' /usr/local/bin/relay-server | sha256sum -c - >/dev/null && printf '%s  %s\n' '$PLAN397_RELAY_SHA' '$PLAN397_RELAY_REMOTE_CANDIDATE' | sha256sum -c - >/dev/null && sudo install -m0755 '$PLAN397_RELAY_REMOTE_CANDIDATE' /usr/local/bin/relay-server && sudo systemctl restart relay-server"; then
    if ! plan397_restore_staging; then
      exit 1
    fi
    exit 1
  fi
elif [ "$PLAN397_RELAY_LIVE_SHA" = "$PLAN397_RELAY_SHA" ]; then
  :
else
  exit 1
fi
if ! ssh -i "$MKNOON_257_RELAY_KEY" "$MKNOON_257_RELAY_TARGET" '
  systemctl is-active --quiet relay-server || exit 1
  health_attempt=1
  while [ "$health_attempt" -le 20 ]; do
    if curl -fsS http://127.0.0.1:2112/metrics >/dev/null; then
      exit 0
    fi
    health_attempt=$((health_attempt + 1))
    sleep 1
  done
  exit 1
'; then
  if ! plan397_restore_staging; then
    exit 1
  fi
  exit 1
fi
export PLAN397_RELAY_DEPLOYED_VERSION="$(ssh -i "$MKNOON_257_RELAY_KEY" \
  "$MKNOON_257_RELAY_TARGET" '/usr/local/bin/relay-server version')"
export PLAN397_RELAY_DEPLOYED_SHA="$(ssh -i "$MKNOON_257_RELAY_KEY" \
  "$MKNOON_257_RELAY_TARGET" \
  "sha256sum /usr/local/bin/relay-server | awk '{print \$1}'")"
if [ "$PLAN397_RELAY_DEPLOYED_VERSION" != "$PLAN397_RELAY_REVISION" ] || \
   [ "$PLAN397_RELAY_DEPLOYED_SHA" != "$PLAN397_RELAY_SHA" ]; then
  if ! plan397_restore_staging; then
    exit 1
  fi
  exit 1
fi

# Atomically install the already-validated candidate manifest. Resume accepts
# only the immutable prior or exact candidate digest; an unrelated edit stops.
export PLAN397_STAGING_MANIFEST_LIVE_SHA="$(shasum -a 256 \
  "$MKNOON_257_STAGING_MANIFEST" | awk '{print $1}')"
if [ "$PLAN397_STAGING_MANIFEST_LIVE_SHA" != \
     "$PLAN397_STAGING_MANIFEST_PRIOR_SHA" ] && \
   [ "$PLAN397_STAGING_MANIFEST_LIVE_SHA" != \
     "$PLAN397_STAGING_MANIFEST_CANDIDATE_SHA" ]; then
  exit 1
fi
if [ "$PLAN397_STAGING_MANIFEST_LIVE_SHA" = \
  "$PLAN397_STAGING_MANIFEST_PRIOR_SHA" ]; then
  export PLAN397_STAGING_MANIFEST_SWAP="$MKNOON_257_STAGING_MANIFEST.plan397-candidate.tmp"
  if [ -e "$PLAN397_STAGING_MANIFEST_SWAP" ]; then
    if [ "$(shasum -a 256 "$PLAN397_STAGING_MANIFEST_SWAP" | awk '{print $1}')" != \
      "$PLAN397_STAGING_MANIFEST_CANDIDATE_SHA" ]; then
      exit 1
    fi
  else
    if ! cp -p "$PLAN397_STAGING_MANIFEST_CANDIDATE" \
      "$PLAN397_STAGING_MANIFEST_SWAP"; then
      exit 1
    fi
  fi
  if [ "$(shasum -a 256 "$PLAN397_STAGING_MANIFEST_SWAP" | awk '{print $1}')" != \
    "$PLAN397_STAGING_MANIFEST_CANDIDATE_SHA" ]; then
    exit 1
  fi
  if ! mv "$PLAN397_STAGING_MANIFEST_SWAP" \
    "$MKNOON_257_STAGING_MANIFEST"; then
    exit 1
  fi
elif [ "$PLAN397_STAGING_MANIFEST_LIVE_SHA" = \
  "$PLAN397_STAGING_MANIFEST_CANDIDATE_SHA" ]; then
  :
else
  exit 1
fi
if [ "$(shasum -a 256 "$MKNOON_257_STAGING_MANIFEST" | awk '{print $1}')" != \
  "$PLAN397_STAGING_MANIFEST_CANDIDATE_SHA" ]; then
  exit 1
fi

# The runner rechecks live service, SHA, revision, provider, selectors, and
# device IDs. The proof also binds both central build reports, their
# input/artifact digests, PLAN397_IOS_MANIFEST_SHA, the resolved iOS
# app/test-products/xctestrun member hashes, PLAN397_RELAY_SHA, and the candidate
# staging-manifest digest.
export PLAN397_ATTEMPT1_ANDROID_BUILD_SHA="$PLAN397_ANDROID_BUILD_SHA"
export PLAN397_ATTEMPT1_ANDROID_BUILD_INPUT_SHA="$PLAN397_ANDROID_BUILD_INPUT_SHA"
export PLAN397_ATTEMPT1_IOS_BUILD_SHA="$PLAN397_IOS_BUILD_SHA"
export PLAN397_ATTEMPT1_IOS_BUILD_INPUT_SHA="$PLAN397_IOS_BUILD_INPUT_SHA"

# Attempt one: one combined real-relay/APNs/NSE physical campaign. The runner
# creates and seals this directory and refuses to overwrite it.
export PLAN397_PROOF_ROOT=build/group_reaction_notification_proof/ios_chat_group_message_and_reaction_recipient
test ! -e "$PLAN397_PROOF_ROOT/attempt-1"
dart run integration_test/scripts/run_group_reaction_notification_device.dart \
  --scenario ios_chat_group_message_and_reaction_recipient \
  --sender "$PLAN397_ANDROID_ID" \
  --recipient "$PLAN397_IPHONE_ID" \
  --artifact-dir "$PLAN397_PROOF_ROOT/attempt-1" \
  --staging-manifest "$MKNOON_257_STAGING_MANIFEST" \
  --relay-target "$MKNOON_257_RELAY_TARGET" \
  --relay-key "$MKNOON_257_RELAY_KEY" \
  --service-account "$FIREBASE_SERVICE_ACCOUNT" \
  --prebuilt-android-apk "$SIMS_ARTIFACT_ANDROID_PRODUCTION_FCM" \
  --prebuilt-android-build-report "$PLAN397_ANDROID_BUILD_REPORT" \
  --prebuilt-ios-bundle "$SIMS_ARTIFACT_IOS_DEVICE_PRODUCTION" \
  --prebuilt-ios-build-report "$PLAN397_IOS_BUILD_REPORT"

# Revalidate the retained artifact independently.
dart run integration_test/scripts/run_group_reaction_notification_device.dart \
  --scenario ios_chat_group_message_and_reaction_recipient \
  --validate-artifacts "$PLAN397_PROOF_ROOT/attempt-1"
```

If attempt one is a clean PASS, skip directly to the final `groups` gate below.
If—and only if—it retained an attributable TC-397-09 client failure, keep the
candidate deployed, leave `attempt-1` sealed, author and non-vacuously run the
one captured-shape RED, make the minimal repair, and rerun that exact focused
test GREEN. Then rebuild both central artifacts from the repaired tree and
resolve them through new retained build reports/attestations. The iOS build
input and artifact digests must differ from sealed attempt one; stale reuse is
a failed gate. Run the sole permitted retry into a fresh directory:

```bash
test -d "$PLAN397_PROOF_ROOT/attempt-1"
test ! -e "$PLAN397_PROOF_ROOT/attempt-2"
export PLAN397_SIMS_CACHE="${SIMS_CACHE_DIR:-$PWD/build/sims/cache}"
: "${PLAN397_ATTEMPT1_IOS_BUILD_INPUT_SHA:?reload from sealed attempt one}"
: "${PLAN397_ATTEMPT1_IOS_BUILD_SHA:?reload from sealed attempt one}"

export PLAN397_ANDROID_BUILD_REPORT="$PWD/build/plan397/android-attempt-2-build-report.json"
test ! -e "$PLAN397_ANDROID_BUILD_REPORT"
SIMS_REPORT_PATH="$PLAN397_ANDROID_BUILD_REPORT" \
  dart tool/sims/sims.dart major \
    --only build.android.production_fcm --prepare-builds
export PLAN397_ANDROID_BUILD_SHA="$(jq -er \
  '.builds.artifactDigests["android.production_fcm"]' \
  "$PLAN397_ANDROID_BUILD_REPORT")"
unset SIMS_ARTIFACT_ANDROID_PRODUCTION_FCM
while IFS= read -r PLAN397_ATTESTATION; do
  if jq -e --arg digest "$PLAN397_ANDROID_BUILD_SHA" '
    .profileId == "android.production_fcm" and .artifactDigest == $digest
  ' "$PLAN397_ATTESTATION" >/dev/null; then
    export SIMS_ARTIFACT_ANDROID_PRODUCTION_FCM="$(dirname "$PLAN397_ATTESTATION")/artifact.apk"
    export PLAN397_ANDROID_BUILD_INPUT_SHA="$(jq -r .inputDigest "$PLAN397_ATTESTATION")"
    break
  fi
done < <(find "$PLAN397_SIMS_CACHE/android.production_fcm" \
  -type f -name attestation.json -print)
: "${SIMS_ARTIFACT_ANDROID_PRODUCTION_FCM:?attested attempt-two APK not found}"
test "$(shasum -a 256 "$SIMS_ARTIFACT_ANDROID_PRODUCTION_FCM" | awk '{print $1}')" = \
  "$PLAN397_ANDROID_BUILD_SHA"

export PLAN397_IOS_BUILD_REPORT="$PWD/build/plan397/ios-attempt-2-build-report.json"
test ! -e "$PLAN397_IOS_BUILD_REPORT"
SIMS_REPORT_PATH="$PLAN397_IOS_BUILD_REPORT" \
  dart tool/sims/sims.dart major \
    --only build.ios.device.production --prepare-builds
export PLAN397_IOS_BUILD_SHA="$(jq -er \
  '.builds.artifactDigests["ios.device.production"]' \
  "$PLAN397_IOS_BUILD_REPORT")"
unset SIMS_ARTIFACT_IOS_DEVICE_PRODUCTION
while IFS= read -r PLAN397_ATTESTATION; do
  if jq -e --arg digest "$PLAN397_IOS_BUILD_SHA" '
    .profileId == "ios.device.production" and .artifactDigest == $digest
  ' "$PLAN397_ATTESTATION" >/dev/null; then
    export SIMS_ARTIFACT_IOS_DEVICE_PRODUCTION="$(dirname "$PLAN397_ATTESTATION")/ios.device.production.bundle"
    export PLAN397_IOS_BUILD_INPUT_SHA="$(jq -r .inputDigest "$PLAN397_ATTESTATION")"
    break
  fi
done < <(find "$PLAN397_SIMS_CACHE/ios.device.production" \
  -type f -name attestation.json -print)
: "${SIMS_ARTIFACT_IOS_DEVICE_PRODUCTION:?attested attempt-two bundle not found}"
test "$PLAN397_IOS_BUILD_INPUT_SHA" != "$PLAN397_ATTEMPT1_IOS_BUILD_INPUT_SHA"
test "$PLAN397_IOS_BUILD_SHA" != "$PLAN397_ATTEMPT1_IOS_BUILD_SHA"
export PLAN397_IOS_MANIFEST="$SIMS_ARTIFACT_IOS_DEVICE_PRODUCTION/bundle_manifest.json"
test -f "$PLAN397_IOS_MANIFEST"
jq -e '.profileId == "ios.device.production"' "$PLAN397_IOS_MANIFEST" >/dev/null
export PLAN397_IOS_APPLICATION="$(jq -r .applicationApp "$PLAN397_IOS_MANIFEST")"
export PLAN397_IOS_XCTESTRUN="$(jq -r .xctestrun "$PLAN397_IOS_MANIFEST")"
export PLAN397_IOS_TEST_PRODUCTS="$(jq -r .testProducts "$PLAN397_IOS_MANIFEST")"
test -d "$SIMS_ARTIFACT_IOS_DEVICE_PRODUCTION/$PLAN397_IOS_APPLICATION"
test -s "$SIMS_ARTIFACT_IOS_DEVICE_PRODUCTION/$PLAN397_IOS_XCTESTRUN"
test -d "$SIMS_ARTIFACT_IOS_DEVICE_PRODUCTION/$PLAN397_IOS_TEST_PRODUCTS"
export PLAN397_IOS_ATTEMPT2_MANIFEST_SHA="$(shasum -a 256 \
  "$PLAN397_IOS_MANIFEST" | awk '{print $1}')"
dart run integration_test/scripts/run_group_reaction_notification_device.dart \
  --scenario ios_chat_group_message_and_reaction_recipient \
  --sender "$PLAN397_ANDROID_ID" \
  --recipient "$PLAN397_IPHONE_ID" \
  --artifact-dir "$PLAN397_PROOF_ROOT/attempt-2" \
  --staging-manifest "$MKNOON_257_STAGING_MANIFEST" \
  --relay-target "$MKNOON_257_RELAY_TARGET" \
  --relay-key "$MKNOON_257_RELAY_KEY" \
  --service-account "$FIREBASE_SERVICE_ACCOUNT" \
  --prebuilt-android-apk "$SIMS_ARTIFACT_ANDROID_PRODUCTION_FCM" \
  --prebuilt-android-build-report "$PLAN397_ANDROID_BUILD_REPORT" \
  --prebuilt-ios-bundle "$SIMS_ARTIFACT_IOS_DEVICE_PRODUCTION" \
  --prebuilt-ios-build-report "$PLAN397_IOS_BUILD_REPORT"
dart run integration_test/scripts/run_group_reaction_notification_device.dart \
  --scenario ios_chat_group_message_and_reaction_recipient \
  --validate-artifacts "$PLAN397_PROOF_ROOT/attempt-2"
```

After attempt one or attempt two has independently validated PASS on the final
implementation tree, run the one affected family gate. This command is common
to both paths and is not part of the conditional retry block:

```bash
./scripts/run_test_gates.sh groups
```

Terminal rollback — deployment-health/identity failure already invokes the
binary-plus-manifest restore function automatically. Run this self-contained
block only after a second or unclassified device failure, or when abandoning
execution. Do not roll back between an attributable attempt-one failure and its
permitted repair/rerun. On PASS, retain the candidate and verified backups and
do not run this block:

```bash
: "${MKNOON_257_STAGING_MANIFEST:?required}"
: "${MKNOON_257_RELAY_TARGET:?required}"
: "${MKNOON_257_RELAY_KEY:?required}"
export MKNOON_257_STAGING_MANIFEST="$(cd \
  "$(dirname "$MKNOON_257_STAGING_MANIFEST")" && pwd -P)/$(basename \
  "$MKNOON_257_STAGING_MANIFEST")"
export PLAN397_DEPLOYMENT_RECEIPT="$PWD/build/plan397/deployment-state-02.json"
export PLAN397_STAGING_MANIFEST_BACKUP="$PWD/build/plan397/staging-manifest.prior-02.json"
export PLAN397_RELAY_BACKUP=/usr/local/bin/relay-server.plan397-20260823-02.bak
export PLAN397_RELAY_TARGET_SHA="$(printf '%s' "$MKNOON_257_RELAY_TARGET" | \
  shasum -a 256 | awk '{print $1}')"
export PLAN397_STAGING_MANIFEST_PATH_SHA="$(printf '%s' \
  "$MKNOON_257_STAGING_MANIFEST" | shasum -a 256 | awk '{print $1}')"
if [ ! -f "$PLAN397_DEPLOYMENT_RECEIPT" ] || \
   [ ! -f "$PLAN397_STAGING_MANIFEST_BACKUP" ]; then
  exit 1
fi
if ! jq -e --arg relayTargetSha "$PLAN397_RELAY_TARGET_SHA" \
      --arg manifestPathSha "$PLAN397_STAGING_MANIFEST_PATH_SHA" '
  .schema == "mknoon.plan397.deployment-state.v1" and
  .runId == "plan397-20260823-02" and
  .relayTargetSha256 == $relayTargetSha and
  .stagingManifestPathSha256 == $manifestPathSha
' "$PLAN397_DEPLOYMENT_RECEIPT" >/dev/null; then
  exit 1
fi
export PLAN397_RELAY_PRIOR_SHA="$(jq -er .priorRelaySha256 \
  "$PLAN397_DEPLOYMENT_RECEIPT")"
export PLAN397_RELAY_PRIOR_VERSION="$(jq -er .priorRelayVersion \
  "$PLAN397_DEPLOYMENT_RECEIPT")"
export PLAN397_RELAY_SHA="$(jq -er .candidateRelaySha256 \
  "$PLAN397_DEPLOYMENT_RECEIPT")"
export PLAN397_STAGING_MANIFEST_PRIOR_SHA="$(jq -er .priorManifestSha256 \
  "$PLAN397_DEPLOYMENT_RECEIPT")"
export PLAN397_STAGING_MANIFEST_CANDIDATE_SHA="$(jq -er \
  .candidateManifestSha256 "$PLAN397_DEPLOYMENT_RECEIPT")"
if [ "$(ssh -i "$MKNOON_257_RELAY_KEY" "$MKNOON_257_RELAY_TARGET" \
  "sha256sum '$PLAN397_RELAY_BACKUP' | awk '{print \$1}'")" = \
  "$PLAN397_RELAY_PRIOR_SHA" ]; then :; else exit 1; fi
export PLAN397_RELAY_LIVE_SHA="$(ssh -i "$MKNOON_257_RELAY_KEY" \
  "$MKNOON_257_RELAY_TARGET" \
  "sha256sum /usr/local/bin/relay-server | awk '{print \$1}'")"
if [ "$(shasum -a 256 "$PLAN397_STAGING_MANIFEST_BACKUP" | awk '{print $1}')" != \
  "$PLAN397_STAGING_MANIFEST_PRIOR_SHA" ]; then
  exit 1
fi
export PLAN397_STAGING_MANIFEST_LIVE_SHA="$(shasum -a 256 \
  "$MKNOON_257_STAGING_MANIFEST" | awk '{print $1}')"
if [ "$PLAN397_RELAY_LIVE_SHA" != "$PLAN397_RELAY_PRIOR_SHA" ] && \
   [ "$PLAN397_RELAY_LIVE_SHA" != "$PLAN397_RELAY_SHA" ]; then
  exit 1
fi
if [ "$PLAN397_STAGING_MANIFEST_LIVE_SHA" != \
     "$PLAN397_STAGING_MANIFEST_PRIOR_SHA" ] && \
   [ "$PLAN397_STAGING_MANIFEST_LIVE_SHA" != \
     "$PLAN397_STAGING_MANIFEST_CANDIDATE_SHA" ]; then
  exit 1
fi
if [ "$PLAN397_RELAY_LIVE_SHA" = "$PLAN397_RELAY_PRIOR_SHA" ]; then
  :
elif [ "$PLAN397_RELAY_LIVE_SHA" = "$PLAN397_RELAY_SHA" ]; then
  if ! ssh -i "$MKNOON_257_RELAY_KEY" "$MKNOON_257_RELAY_TARGET" \
    "printf '%s  %s\n' '$PLAN397_RELAY_SHA' /usr/local/bin/relay-server | sha256sum -c - >/dev/null && printf '%s  %s\n' '$PLAN397_RELAY_PRIOR_SHA' '$PLAN397_RELAY_BACKUP' | sha256sum -c - >/dev/null && sudo install -m0755 '$PLAN397_RELAY_BACKUP' /usr/local/bin/relay-server"; then
    exit 1
  fi
else
  exit 1
fi
if ! ssh -i "$MKNOON_257_RELAY_KEY" "$MKNOON_257_RELAY_TARGET" '
  sudo systemctl restart relay-server || exit 1
  systemctl is-active --quiet relay-server || exit 1
  health_attempt=1
  while [ "$health_attempt" -le 20 ]; do
    if curl -fsS http://127.0.0.1:2112/metrics >/dev/null; then
      exit 0
    fi
    health_attempt=$((health_attempt + 1))
    sleep 1
  done
  exit 1
'; then
  exit 1
fi
if [ "$(ssh -i "$MKNOON_257_RELAY_KEY" "$MKNOON_257_RELAY_TARGET" \
  "sha256sum /usr/local/bin/relay-server | awk '{print \$1}'")" = \
  "$PLAN397_RELAY_PRIOR_SHA" ]; then :; else exit 1; fi
if [ "$(ssh -i "$MKNOON_257_RELAY_KEY" "$MKNOON_257_RELAY_TARGET" \
  '/usr/local/bin/relay-server version')" = \
  "$PLAN397_RELAY_PRIOR_VERSION" ]; then :; else exit 1; fi
if [ "$(shasum -a 256 "$PLAN397_STAGING_MANIFEST_BACKUP" | awk '{print $1}')" = \
  "$PLAN397_STAGING_MANIFEST_PRIOR_SHA" ]; then :; else exit 1; fi
export PLAN397_STAGING_MANIFEST_LIVE_SHA="$(shasum -a 256 \
  "$MKNOON_257_STAGING_MANIFEST" | awk '{print $1}')"
if [ "$PLAN397_STAGING_MANIFEST_LIVE_SHA" = \
  "$PLAN397_STAGING_MANIFEST_PRIOR_SHA" ]; then
  :
elif [ "$PLAN397_STAGING_MANIFEST_LIVE_SHA" = \
  "$PLAN397_STAGING_MANIFEST_CANDIDATE_SHA" ]; then
  export PLAN397_STAGING_MANIFEST_RESTORE_TMP="$MKNOON_257_STAGING_MANIFEST.plan397-restore.tmp"
  if [ -e "$PLAN397_STAGING_MANIFEST_RESTORE_TMP" ]; then
    if [ "$(shasum -a 256 "$PLAN397_STAGING_MANIFEST_RESTORE_TMP" | awk '{print $1}')" != \
      "$PLAN397_STAGING_MANIFEST_PRIOR_SHA" ]; then
      exit 1
    fi
  else
    if ! cp -p "$PLAN397_STAGING_MANIFEST_BACKUP" \
      "$PLAN397_STAGING_MANIFEST_RESTORE_TMP"; then
      exit 1
    fi
  fi
  if ! mv "$PLAN397_STAGING_MANIFEST_RESTORE_TMP" \
    "$MKNOON_257_STAGING_MANIFEST"; then
    exit 1
  fi
else
  exit 1
fi
if [ "$(shasum -a 256 "$MKNOON_257_STAGING_MANIFEST" | awk '{print $1}')" != \
  "$PLAN397_STAGING_MANIFEST_PRIOR_SHA" ]; then
  exit 1
fi
```

Scoped hygiene after the passing implementation/device batch:

```bash
test -z "$(gofmt -l \
  go-relay-server/inbox.go \
  go-relay-server/inbox_test.go \
  go-relay-server/group_content_push.go \
  go-relay-server/group_content_push_test.go \
  go-relay-server/ordinary_push_projection_test.go)"
dart format --output=none --set-exit-if-changed \
  lib/core/debug/group_reaction_e2e_probe.dart \
  lib/core/debug/group_reaction_notification_ios_setup_profile.dart \
  lib/core/debug/group_media_ios_background_e2e.dart \
  lib/core/debug/intro_e2e_runner.dart \
  lib/debug/debug_e2e_composition_root.dart \
  integration_test/scripts/group_reaction_notification_device_criteria.dart \
  integration_test/scripts/capture_group_reaction_notification_device.dart \
  integration_test/scripts/reaction_notification_proof_support.dart \
  integration_test/scripts/run_group_reaction_notification_device.dart \
  integration_test/group_announcement_reaction_notification_proof_test.dart \
  test/integration/group_reaction_notification_device_criteria_test.dart \
  test/core/debug/group_reaction_e2e_probe_test.dart \
  test/core/debug/group_reaction_notification_ios_setup_profile_test.dart \
  test/core/debug/group_media_ios_background_e2e_test.dart \
  test/core/debug/debug_e2e_composition_root_test.dart \
  scripts/test/ios_receiver_bootstrap_contract_test.dart
dart analyze \
  lib/core/debug/group_reaction_e2e_probe.dart \
  lib/core/debug/group_reaction_notification_ios_setup_profile.dart \
  lib/core/debug/group_media_ios_background_e2e.dart \
  lib/core/debug/intro_e2e_runner.dart \
  lib/debug/debug_e2e_composition_root.dart \
  integration_test/scripts/group_reaction_notification_device_criteria.dart \
  integration_test/scripts/capture_group_reaction_notification_device.dart \
  integration_test/scripts/reaction_notification_proof_support.dart \
  integration_test/scripts/run_group_reaction_notification_device.dart \
  integration_test/group_announcement_reaction_notification_proof_test.dart \
  test/integration/group_reaction_notification_device_criteria_test.dart \
  test/core/debug/group_reaction_e2e_probe_test.dart \
  test/core/debug/group_reaction_notification_ios_setup_profile_test.dart \
  test/core/debug/group_media_ios_background_e2e_test.dart \
  test/core/debug/debug_e2e_composition_root_test.dart \
  scripts/test/ios_receiver_bootstrap_contract_test.dart
python3 -m py_compile \
  integration_test/scripts/ios_receiver_bootstrap.py \
  scripts/test/ios_receiver_bootstrap_test.py
bash -n scripts/test/group_reaction_notification_device_contract_test.sh
# Stage only the Plan-397 paths enumerated by this plan; the shared worktree may
# contain unrelated user-owned changes that this closure must not inspect.
git diff --cached --check

# App-owned impact and one incremental Graphify refresh after implementation.
python3 graphify-arch/tdd_context.py affected \
  go-relay-server/inbox.go \
  go-relay-server/group_content_push.go \
  lib/core/debug/group_reaction_e2e_probe.dart \
  lib/core/debug/group_reaction_notification_ios_setup_profile.dart \
  lib/core/debug/group_media_ios_background_e2e.dart \
  lib/core/debug/intro_e2e_runner.dart \
  lib/debug/debug_e2e_composition_root.dart \
  integration_test/scripts/group_reaction_notification_device_criteria.dart \
  integration_test/scripts/capture_group_reaction_notification_device.dart \
  integration_test/scripts/reaction_notification_proof_support.dart \
  integration_test/scripts/run_group_reaction_notification_device.dart \
  integration_test/group_announcement_reaction_notification_proof_test.dart \
  ios/NotificationService/IosNotificationRecovery.swift \
  ios/Runner/IosNotificationRecoveryCoordinator.swift \
  ios/Runner/IosReceiverBootstrapHandoff.swift \
  ios/Runner/AppDelegate.swift \
  ios/RunnerUITests/NotificationTapUITests.swift \
  --budget 600
./graphify-arch/refresh_arch_graph.sh --incremental
```

Execution must either retain the passing candidate plus immutable binary and
manifest backups/receipt, or run terminal rollback after a
second/unclassified failure or abandonment and record the restored binary
version/SHA plus manifest SHA. An attributable first failure keeps the
candidate in place only through its one permitted repair/rerun.

## Device/Relay Proof Profile

- Profile: `os-notification-device-lab`.
- Boundary: physical Android group action -> real staging relay/FCM/APNs -> iOS
  NSE -> UserNotifications -> native source inventory -> exact SpringBoard tap
  -> cold Flutter group reconstruction.
- Live planning matrix: Pixel `21071FDF600CSC`, online physical iPhone
  `00008110-00184D622289801E`, and simulator
  `DBE8C32E-9F19-4593-860A-B41113791D79`. Execution must rediscover and pin
  live IDs. Unavailable versions/targets are N/A under project policy; an
  offline-listed ID is never accepted.
- The physical iPhone is justified because APNs/NSE/UserNotifications behavior
  is the test subject. An Android pair cannot substitute.
- Registration: existing `classify_path` ownership for the Plan-257 runner,
  plus one enumerated scenario and named proof. No new Sims manifest row.
- Manual action count: zero inside the campaign.
- Retry policy: after the first graded notification baseline opens, no
  automatic retry. Before that boundary, only the exact setup-XCUITest
  automation timeout may receive the one warm retry defined above. Retain the
  first graded product failure; permit at most one campaign rerun after an exact
  causal RED, repair, and fresh central iOS build. A second/unclassified graded
  failure blocks and restores the prior staging relay plus redacted manifest.

## Execution Interpretation And Done Criteria

- Expected REDs: missing group-message collapse identity including the
  representative routing-only case; dead iOS grammar; absent scenario/central
  artifact binding/offline guard; rejected combined observer markers/two-phase
  identity output; and an early-success group source inventory/two-window
  schema.
- Green preservation: direct/invite/opaque/contact behavior, strict and media
  projection, author-only reaction, per-event reaction collapse, and shared
  SI-5 parity.
- Missing/stale credentials, signing, central artifacts, staging health, or a
  live target produces a typed blocker/N/A result. It is never PASS.
- A need for a new registered/central Sims build profile or capability,
  DB/Redis migration, third device, general source abstraction, or notification
  redesign is scope drift and stops execution.

- [ ] TC-397-01 through TC-397-06 record causal RED/GREEN or explicit sentinel
      GREEN with their representative mutation re-reds.
- [ ] The scenario is cataloged, dispatched, discovered, independently
      validated, proof-bound, and preserves the six incumbent rows.
- [ ] Both central artifacts are attested; the campaign performs zero Android
      and zero normal-iOS child builds, at most one reused ungraded iOS setup
      build, and no uninstall between iOS setup and graded normal observation.
      The PASS artifact binds both retained Sims
      reports, adjacent input/artifact attestations, APK, iOS manifest/app/
      test-products/xctestrun, and relay hashes from the final tested tree; a
      stale incoming artifact path cannot pass.
- [ ] The message-phase Android observation emits full group/message/target
      SHA-256 identities before ADD; the reaction-phase observation repeats
      those identities plus exactly one matching ADD-event digest without
      mutating delivery state. A receipt/cursor from one phase cannot satisfy
      the other, and short log prefixes or raw retained identifiers cannot
      satisfy the proof.
- [ ] Message and reaction native receipts independently prove one stable
      useful provider source and zero local/sanitized/unknown sources with only
      hashed request identifiers after sampling through the existing 8,000 ms
      horizon. Sticky bad-source/duplicate flags prove that no transient local
      sibling appeared and disappeared; three early equal samples cannot PASS.
- [ ] Each native observation holds the recovery fence through receipt pull,
      terminates Runner without a pre-tap relaunch, and defers protected cleanup
      until after the same-container tap and route assertion.
- [ ] XCUITest associates and taps the exact message/reaction card container;
      both cold routes and final group UI/read states pass after explicit
      re-background between events.
- [ ] Complete diagnostic windows accept no-contender or exact suppression,
      reject any run-owned `NOTIFICATION_SHOWN` publication regardless of sound,
      and never use a log marker as a substitute for native source inventory.
- [ ] One physical campaign passes, or one retained causal failure is repaired
      against freshly rebuilt central products and the sole permitted
      attempt-two campaign passes with a new iOS build input/artifact digest.
      Attempt one is never overwritten; no waiver is promoted to technical PASS.
- [ ] The exact focused tests, one `groups` gate, scoped hygiene, Graphify
      impact, and one incremental refresh pass. The `groups` gate runs once only
      after the final device PASS; no per-plan `host-all` runs.
- [ ] No token, ciphertext, key, peer ID, raw notification identifier, or
      user/private plaintext is retained; PASS and FAIL retain bounded hashes
      and diagnostics.
- [ ] Staging architecture, immutable prior binary version/SHA, prior manifest
      SHA, candidate binary/manifest SHAs, static candidate revision, and the
      target/path-bound redacted deployment receipt are recorded. Resume never
      recaptures live as prior or recreates a missing backup; an unknown live
      identity stops without mutation. Automatic or terminal rollback
      compare-and-swaps and verifies both restored binary version/SHA and
      manifest SHA; no production deployment or DB/Redis migration occurs.
- [ ] UI-23 coverage documents and the index state exactly what device evidence
      passed and retain Apple/release residuals.
- [ ] Scope Contract And Guard is respected.

## Handoff

- First RED: author and non-vacuously run
  `TestRelayNotificationClosure_GroupMessageRetryCollapse`.
- Physical closure: one Pixel-to-iPhone
  `ios_chat_group_message_and_reaction_recipient` command, two independent
  event windows, one hash-bound PASS artifact plus at most one sealed causal
  failure artifact, zero manual taps.
- Conditional product work: only TC-397-09 after a retained attributable first
  failure; otherwise N/A.
- Manual registration: none. The existing classified runner owns discovery.
- Migration: none.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-08-23 | implementation | relay projection, iOS recovery/handoff, device capture/criteria, probe fixtures, and focused tests | TC-397 host/native implementation completed | two ordered message/reaction windows; independent provider, Android, NSE, native-inventory, and same-card tap evidence; central-build provenance and privacy validation | none for implementation | run focused closure gates |
| 2026-08-23 | focused verification | Plan 397 production/test surfaces | exact five Go sentinels PASS; paired Flutter lane 91 PASS; criteria suite 73 PASS; Python observer tests PASS; iOS bootstrap contracts PASS; exact 12-selector simulator XCUITest PASS; analysis/format/compile/syntax checks PASS | host and available-simulator causal coverage is green | physical notification delivery is not simulated or claimed | run availability-bounded physical preflight |
| 2026-08-23 | physical preflight | live device and staging matrix | rediscovered `flutter`, ADB, CoreDevice, `xctrace`, libimobiledevice, simulator, relay, manifest, and credential inputs after the two iPhones restarted; explicitly mounted the required iPhone DDI | Pixel 6 `21071FDF600CSC` is online; iPhone 13 `00008110-00184D622289801E` is paired, unlocked-since-boot, Developer Mode enabled, DDI-compatible, and moves into Xcode's online section after mount; all staging inputs are present and project-bound | no credential/device-selection blocker; iOS UI Automation remains a separate OS prerequisite | keep physical PASS, final `groups`, and UI-23 updates withheld until a graded run validates |
| 2026-08-23 | execution repair and central products | Plan-397 profile setup seam, CoreDevice/AFC file channel, DDI/timeouts, setup-only XCUITest warm retry, and criteria tests | causal RED/GREEN repairs; affected suites PASS (119 profile/intro/media/composition/criteria tests plus 14 fixture neighbors); latest criteria suite 82 PASS; scoped analysis clean; Graphify affected + incremental refresh PASS | latest final-tree central reports are `android-pregrade-11-build-report.json` and `ios-pregrade-11-build-report.json`; both were zero-build cache hits with Android input/artifact `8674a0c6…`/`2d3a5003…` and iOS input/artifact `cb1911be…`/`f25e01b2…`; relocated iOS bundle membership verified | none for host implementation; physical grade still required; regenerate only the reports if their validator freshness window expires before the next run | use these retained central artifacts and freshness-valid reports for the next fresh run |
| 2026-08-23 | reversible staging | immutable deployment run `plan397-20260823-02` | compare-and-swap deployed and rolled back around each pre-grade run; bounded 20×1-second metrics poll handles relay startup | prior/candidate relay SHAs `0ae5c7d7…`/`231e3074…`; prior/candidate manifest SHAs `8ea8ddf5…`/`9359ed84…`; receipt and immutable backups verified on every transition | staging is currently restored to the prior relay and prior manifest; service active and metrics healthy | redeploy only for a fresh physical run; retain candidate on PASS |
| 2026-08-23 | pre-grade physical setup | sealed `run-06` through `run-12` environment evidence | identity/file-channel/profile seams progressed fixture setup; `run-10` exposed Xcode automation warm-up timeout; `run-11` exposed a stale Mac CoreDevice launch timeout; restarting only the resolved stale CoreDevice processes made the same launch complete in about one second; `run-12` exercised the exact setup-only automation retry and both invocations ended with the same OS timeout | no run opened a provider/native message or reaction window; no graded notification attempt or retry was consumed; both Xcode-generated diagnostics ZIPs in `run-12` were absent after result finalization, and no ZIP/TAR/GZ is retained | required iPhone reports `Timed out while enabling automation mode.` even though it is unlocked, Developer Mode is enabled, DDI is usable, and the test runner launches | confirm Settings → Developer → Enable UI Automation on the required iPhone, keep it awake, then run a fresh sealed pre-grade directory |
| 2026-08-23 | physical blocker revalidation | sealed `run-13` and `run-14` environment evidence | `run-13` stopped at prepared-artifact validation because both retained reports had aged outside the freshness window; regenerated report pair `pregrade-10` hit the same attestations with zero child builds; `run-14` then rebuilt the one permitted setup product and ran the exact fixture selector plus its one setup-only retry | `run-14` again produced `Timed out while enabling automation mode.` for both invocations; neither run opened a provider/native baseline or consumed a graded attempt; Xcode mentioned diagnostics ZIPs while finalizing, but no ZIP/TAR/GZ exists in the sealed artifact; relay and manifest are restored to exact prior SHAs and metrics are healthy | the same iOS UI Automation prerequisite remains the sole physical blocker after three independently sealed goal turns | user must enable Settings → Developer → Enable UI Automation on `00008110-00184D622289801E`, accept the prompt, and leave the phone awake/unlocked before execution can continue |
| 2026-08-23 | resumed physical revalidation | sealed `run-15` and `run-16` environment evidence | refreshed report pair `pregrade-11` hit the same attestations with zero child builds; `run-15` exposed a seven-hour stale Mac `CoreDeviceService` after app launch, and terminating only resolved PID 39885 recreated the service as PID 16660 with a seconds-fast DDI query; `run-16` then reached the exact setup selector and its one warm retry | both `run-16` invocations again ended with `Timed out while enabling automation mode.`; neither run opened a provider/native baseline or consumed a graded attempt; Xcode diagnostics archives were absent after finalization; relay and manifest are restored to exact prior SHAs and metrics are healthy; CoreDevice reports `passcodeRequired=false` and `unlockedSinceBoot=true` | Xcode still cannot complete the iPhone automation handshake; [Apple's XCTest engineer](https://developer.apple.com/forums/thread/693273) says removing the passcode removes the recurring consent-entry requirement, so the unresolved boundary is the on-device Developer toggle taking effect or an iOS/XCTest defect | with the Developer page open, visually toggle Enable UI Automation off/on if necessary and accept any on-phone confirmation, then keep the phone awake/unlocked for a fresh pre-grade run |
| 2026-08-23 | resumed setup and first graded failure | sealed `run-17` and `run-18`; Android invite acceptance and message provider-window criteria | the restarted/toggled iPhone completed UI Automation; `run-17` exposed the valid direct-conversation destination after Android invite acceptance and the exact RED/GREEN now accepts either tested accepted-group surface; `run-18` then opened the first message window and retained the first graded failure because an ordinary group message has the shared provider-result family but no reaction-only `relay_group_content_wake_total` counter | relay journal recorded one successful provider outcome and Android stored the unique message with one expected recipient; the phase-aware causal RED/GREEN now uses the shared `relayPushSentCounter` floor for message and retains exact attempted/push cardinality for reaction; the full criteria suite is 84 PASS and its shell contract/analyze checks pass | `run-18` is the retained first graded failure; its directory is sealed and the plan permits only one fresh-product campaign rerun | rebuild/re-attest final-tree products and use only fresh sealed directories for the sole rerun |
| 2026-08-23 | pre-rerun environment repair | sealed `run-19` and `run-20`; `ios_receiver_bootstrap.py` plus its Python test | `run-19` stopped before fixture staging on a stale CoreDevice uninstall/DDI timeout; terminating only the resolved service recreated it as PID 35741 and restored seconds-fast DDI access; `run-20` reached and pulled the message native inventory but Xcode 26 `devicectl device process terminate` rejected the bundle-ID form because termination now requires `--pid` | causal RED proved the command contract; the bootstrap now captures the positive PID from the launch JSON and terminates that exact PID, never a bundle-name guess; exact RED/GREEN and all 11 bootstrap tests pass, Python compilation passes, and Graphify affected/incremental refresh pass | both verdicts are typed environment blocks and do not themselves consume the sole graded rerun | rebuild central products from the repaired final tree and run one fresh campaign |
| 2026-08-23 | fresh central products | `android-pregrade-13-build-report.json` and `ios-pregrade-13-build-report.json` | both profiles performed one actual final-tree build with no child build inside the campaign | Android input/artifact `b292d127…`/`8470277e…`; iOS input/artifact `8584cf86…`/`6717ab79…`; adjacent attestations and the structural iOS bundle were resolved by digest | fresh-product requirement satisfied for the sole campaign rerun | bind `run-21` to these reports and artifacts |
| 2026-08-23 | terminal physical verdict and rollback | sealed `run-21`, protected current-run native result, deployment receipt/backups | fixture creation, target authoring, and warm preparation passed with zero manual actions; the message observer published at `2026-08-23T11:14:43.125Z`, but CoreDevice did not return the file to the host before its 120-second timeout; a postmortem protected-container pull proved exact nonce/group/event/target hash binding to `run-21` | native source authority reports `matchingRemoteCount=2`, `matchingUsefulProviderCount=1`, `matchingUnknownCount=1`, `matchingTotalCount=2`, `badSourceSeen=true`, `duplicateSeen=true`, full-horizon sampling, three stable samples, zero child builds, and zero manual actions; the reaction/tap phases therefore did not run | this is the sole post-repair graded rerun and a second/unclassified physical failure under the plan; no further rerun is permitted; the post-PASS `groups` gate and UI-23 updates remain correctly withheld | terminal rollback restored relay SHA `0ae5c7d7…`, version `relay-server v1.9.0`, and manifest SHA `8ea8ddf5…`; service is active and metrics healthy; a new plan/authorization is required before another deployment or device campaign |
