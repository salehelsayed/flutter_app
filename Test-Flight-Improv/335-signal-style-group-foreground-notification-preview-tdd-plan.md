# 335 - Signal-Style Group Foreground Notification Preview

Status: implemented — plan-green, Android device-verified
Type: Bug
Spec: free-text intent — group notifications must identify the group, sender, and message preview like Signal instead of showing generic copy
Classification: closed
Closure tier: host + paired Android device
Review: `$tdd-review` verdict `plan-fixes-required`; required deltas applied below

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-04 10:31 CEST | Evidence Collector | `background_push_notification_fallback.dart`, `push_decrypt_preview.dart`, `handle_foreground_remote_message_use_case.dart`, `application_root.dart`, focused tests and notification runners | Normal canonical/background group paths already format `group / sender: preview`; the anchored foreground drain-error fallback still hardcodes generic copy and its test requires that behavior | Design one trusted foreground resolver and make contextual copy mandatory for recoverable identities |
| 2026-08-04 10:31 CEST | Planner | group policy, roster/device model, group repository/key APIs, curated gates, live Android matrix | Reuse recipient-owned group state plus the existing encrypted-preview resolver; never trust FCM title/body. Keep private media and truly identity-free wakes conservative | Submit to `$tdd-review`, apply required deltas, then execute RED-first |
| 2026-08-04 10:47 CEST | Reviewer | plan plus foreground fallback, legacy payload route, formatter privacy behavior, ApplicationRoot wiring, Android S2 and simulator harness | Verdict `plan-fixes-required`: narrow suppression to typed authenticated/encrypted wakes, require nonblank local attribution, test privacy/race/wiring directly, and classify S2 as preservation rather than causal proof | Apply reviewed contract, then execute RED-first |

## Problem And Evidence

- Behavior to improve: an eligible incoming group message reaching foreground recovery must use the trusted group name as title and `sender: preview` as body.
- Impact: `New Message / You have a new message` or `Mknoon / Message` makes group alerts indistinguishable and hides sender and conversation.
- Confirmed root cause: `handleForegroundRemoteMessage` returns `notificationNeeded` after a group drain exception at `lib/features/push/application/handle_foreground_remote_message_use_case.dart:94-102`; `showForegroundPushFallbackNotificationIfNeeded` then supplies literal `senderUsername: 'Mknoon'` and localized generic `messageText` at `lib/features/push/application/background_push_notification_fallback.dart:412-529`.
- Existing correct mechanism: `resolveBackgroundPushNotification` routes `group_message` to `_resolveGroupPreview` at `lib/features/push/application/push_decrypt_preview.dart:362-393`; trusted state produces `title: groupName` and `body: '$senderUsername: $preview'` at lines `1073-1118` and `1210-1218`. Canonical listener presentation independently uses this contract at `lib/features/groups/application/group_message_listener.dart:1244-1264`.
- Existing coverage: `push_decrypt_preview_test.dart` covers decrypted group copy, authenticated-inner IDs, parity rejection, private-media redaction, and `preview_unavailable`; `background_push_notification_fallback_test.dart:1275-1315` currently locks the incorrect anchored generic copy; Android notification-sound S2 checks the real notification-service/OS projection.
- Missing coverage: no foreground resolver binds `sender_transport_peer_id` to exactly one active local roster member, selects the exact group key, and hands trusted copy to the drain-error presenter. No test forbids generic copy for a typed authenticated/encrypted `group_message` when trusted resolution fails.
- Confirmed: the relay already sends group ID, authenticated sender transport, message ID, key epoch, ciphertext, and nonce at `go-relay-server/inbox.go:555-600`; no wire change is needed.
- Refuted: adding another ordinary foreground presenter. A successful group drain remains owned by `GroupMessageListener`; this plan changes only the existing error-recovery presenter.
- Refuted: provider `title/body`, decrypted `groupName`, or decrypted `senderUsername` can be display authority. Names must come from local group/roster state.
- Unresolved: whether literal `New Message / You have a new message` came from an older deployed build or an unrewritten Apple placeholder. Current Android/Dart source reproduces `Mknoon / Message` at the confirmed foreground recovery gap. This plan fixes that source-confirmed gap but does not claim that Android S2 reproduces the reported literal or that it repairs iOS/deployment state.
- Affected files: new `lib/features/push/application/foreground_group_message_notification_resolver.dart`, `background_push_notification_fallback.dart`, `lib/app/application_root.dart`, focused push tests, and `scripts/run_test_gates.sh`.

## Graph Grounding Snapshot

- Graph fingerprint / freshness: `fdf1ddc265b71e51`; `stale:ios/Flutter/flutter_export_environment.sh`. The stale generated iOS path does not block current-source Android/Dart grounding.
- Query / profile: `python3 graphify-arch/tdd_context.py query "showForegroundPushFallbackNotificationIfNeeded group_message trusted group name senderUsername decrypted preview after PUSH_FOREGROUND_DRAIN_ERROR; preserve GroupMessageListener private media; background_push_notification_fallback_test.dart" --profile tdd --budget 700`.
- Anchors: `showForegroundPushFallbackNotificationIfNeeded` -> `background_push_notification_fallback.dart`; `senderUsername` -> `test/shared/fakes/fake_notification_service.dart`; caller -> `application_root.dart` verified by targeted search.
- Surfaced proof/gate files: `background_push_notification_fallback_test.dart`, `push_decrypt_preview_test.dart`, `scripts/run_test_gates.sh`, and the Android notification-sound harness/runner.
- Graph gaps requiring source search: ApplicationRoot composition, roster/key APIs, Android runner registration, and relay fields; each was verified in current source.
- Reuse rule: anchors may be handed to review/execution; conclusions still require current-source or command evidence.

## Scope Contract And Guard

In scope:

- Add one foreground group-message resolver that rechecks current group display policy, requires nonblank recipient-owned group and sender names, binds outer sender transport to exactly one active local roster member, enforces chat/announcement sender role, selects the exact requested local key generation, and delegates decryption/parity/copy formatting to `resolveBackgroundPushNotification`.
- Feed its trusted `BackgroundPushNotificationFallback` into the existing drain-error presenter from inside the keyed group presentation lane, after its final display-eligibility check. Use an authenticated inner message ID when the outer ID is absent. A typed authenticated/encrypted `group_message` with a recoverable canonical identity but no trusted result is suppressed instead of emitting generic copy.
- Wire the resolver at the sole production caller in `ApplicationRoot` using the existing Go bridge group decrypt operation.

Must preserve:

- Successful canonical delivery -> `group_message_listener_test.dart::shows notification for incoming group message`.
- Protected/private media remains generic -> `push_decrypt_preview_test.dart::group private policy at decrypted top level emits only generic localized copy`.
- Authorized `preview_unavailable` retains trusted group/sender and localized generic noun -> `push_decrypt_preview_test.dart::authorized preview_unavailable group wake returns localized generic copy`.
- Truly identity-free unanchored wake remains conservative, silent, and generic -> `background_push_notification_fallback_test.dart::unanchored group drain fallback is generic, bare-route, and always silent`.
- Legacy payload-only anchored group routes remain generic for current members -> `background_push_notification_fallback_test.dart::foreground fallback preserves payload-only group route for current members`.
- Missing/currently ineligible membership remains suppressed.

Hard `Do not`:

- Do not trust provider/decrypted display names or ambiguous/revoked device bindings.
- Do not add a second presenter after successful canonical drain.
- Do not change relay payloads, schema, IDs, tone ownership, read acknowledgement, iOS/NSE code, or private-media disclosure.
- Do not test on iPhone, iOS simulator, web, desktop, or any Android target other than the pinned USB device and emulator.

Deferred / accepted difference:

- Apple placeholder diagnosis/rollout -> Plan 333/release deployment; user constrained execution to Android.
- A wake with neither outer message ID nor authenticated inner ID remains silent/generic because no safe exact identity exists.
- A legacy payload-only route has no encrypted envelope from which to establish sender attribution and preserves its registered generic behavior. Trusted-resolution suppression applies only to typed `group_message` wakes.

Dependencies:

- Existing group policy, group repository roster/key state, encrypted push envelope, `resolveBackgroundPushNotification`, and `callGroupDecrypt`. No migration or relay change.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-335-01 | Anchored drain-error fallback shows trusted group title and sender preview, never provider copy | `background_push_notification_fallback_test.dart::anchored group drain fallback uses trusted group and sender preview` | application host / fake notification service and trusted result | HEAD hardcodes `Mknoon / Message`; new callback is intentional compile-RED -> `Team Chat / Alice: Hello secret`, attacker fields absent | replace resolved copy with generic/provider fields -> red | exact `flutter test --plain-name`; existing `GROUP_TESTS` |
| TC-335-02 | Typed anchored `group_message` with no trusted preview is suppressed after eligibility, not converted to generic | `background_push_notification_fallback_test.dart::typed anchored group drain fallback suppresses untrusted preview` | application host / null resolver plus flow-event capture | HEAD shows one generic card -> resolver called once, no card, exact suppression reason | restore generic-on-null or bypass resolver through an earlier return -> red | exact fallback suite; existing `GROUP_TESTS` |
| TC-335-03 | Trusted transport + current role + exact requested key generation + authenticated plaintext resolve `group / sender: preview` | `foreground_group_message_notification_resolver_test.dart::trusted roster transport and decrypted payload produce Signal-style copy` | application host / in-memory repository and fake decrypt | missing resolver is intentional compile-RED -> local group/sender, decrypted body, exact identity/comparand; captured decrypt key/ciphertext/nonce match requested generation | trust provider/decrypted names or latest/wrong key -> malicious fixture and captured-argument assertions red | exact new test file; AUTO feature glob + add once to `GROUP_TESTS` |
| TC-335-04 | Unknown, ambiguous, revoked, self, reader, non-admin announcement, blank group name, and null/blank sender username fail before decrypt | `foreground_group_message_notification_resolver_test.dart::untrusted sender bindings roles and attribution fail closed before decrypt` | application host / table-driven roster with otherwise-valid local names | compile-RED -> null and decrypt count zero | first-match, revoked-device, role, or missing-attribution bypass -> red | exact new test file; AUTO feature glob + `GROUP_TESTS` |
| TC-335-05 | `preview_unavailable=1` identifies trusted group and sender with localized noun without requiring ciphertext/key; provided malformed content is not laundered | `foreground_group_message_notification_resolver_test.dart::preview unavailable keeps trusted group and sender attribution` | application host / content-free envelope plus malformed-content negative | compile-RED -> `Trusted Team / Trusted Admin: Message`, no decrypt; malformed content -> null | require ciphertext/key for trusted degraded copy or admit malformed content -> red | exact new test file; AUTO feature glob + `GROUP_TESTS` |
| TC-335-06 | Missing outer ID uses authenticated inner ID instead of identity-free branch | `background_push_notification_fallback_test.dart::authenticated inner group id anchors rich foreground recovery copy` | application host / trusted inner identity | HEAD follows unanchored generic path -> anchored trusted copy and exact payload | ignore resolved inner identity -> red | exact fallback suite; existing `GROUP_TESTS` |
| TC-335-07 | Composition root supplies the named trusted resolver with identity, group repository, locale, and a decrypt closure that passes the resolver-selected key/ciphertext/nonce to `callGroupDecrypt` | `background_push_notification_fallback_test.dart::application root wires trusted foreground group message resolver` | host source-wiring contract plus TC-03 captured arguments | HEAD lacks wiring -> exact named delegation/callback present | closure always null, remove repository/identity/locale, or substitute decrypt arguments -> red | exact fallback suite; existing `GROUP_TESTS` |
| TC-335-08 | Private media traversing the new resolver remains generic/redacted, and truly identity-free wakes remain generic/silent | `foreground_group_message_notification_resolver_test.dart::private media remains generic through foreground resolver`; existing unanchored fallback sentinel | application host + GREEN sentinel | compile-RED/new privacy assertion -> no plaintext/local group/sender names for private media; unanchored remains green | bypass formatter/privacy or contextualize identity-free route -> red | exact resolver/fallback tests; `GROUP_TESTS` |
| TC-335-09 | Already-correct canonical group presentation still projects group title and `sender: text` through the Android plugin/OS | notification-sound runner row `S2` | paired Android / real bridge + live group listener + plugin/OS inspection | GREEN preservation proof -> programmatic and OS predicates remain green, one observed card | regress canonical copy/plugin projection -> S2 fails | `dart run integration_test/scripts/run_notification_sound_smoke.dart -d emulator-5554,21071FDF600CSC --rows S2 --non-interactive --artifact-dir build/sims/proofs/plan-335-group-preview`; already registered group runner |
| TC-335-10 | Legacy payload-only anchored group route remains generic for a current member | existing `background_push_notification_fallback_test.dart::foreground fallback preserves payload-only group route for current members` | GREEN sentinel / application host | green -> remains shown with legacy route | apply typed-envelope suppression to every group route -> red | exact fallback suite; existing `GROUP_TESTS` |
| TC-335-11 | Queued group presentation resolves only after entering the keyed lane and rechecking current policy | `background_push_notification_fallback_test.dart::queued group fallback rechecks policy before trusted preview resolution` | application host / blocked first keyed operation then membership revocation | compile-RED/new callback ordering assertion -> second request suppressed, resolver/show count zero | resolve before coordinator/final policy -> red | exact fallback suite; existing `GROUP_TESTS` |

### Test Notes

- TC-335-01 includes malicious provider copy; TC-335-03 also includes malicious decrypted names. Only local names may appear.
- TC-335-04 asserts null and zero decrypt calls, preventing decrypt-then-suppress from passing.
- TC-335-06 supplies `ResolvedPushEventIdentity.authenticatedInner` and asserts message-anchored routing.
- TC-335-09 is intentionally non-causal preservation evidence: S2 does not force `PUSH_FOREGROUND_DRAIN_ERROR`, FCM/relay transport, or repeated-card ID stability. TC-335-01..08/10/11 own causality for the changed seam.

## Implementation Steps

1. Snapshot `git status --short`; add TC-335-01..08/11 before production edits and record RED; run TC-335-10 as a GREEN baseline.
2. Add `resolveForegroundGroupMessageNotification` with current policy, exact active sender binding/role, requested key, trusted context, and existing decrypt/parity formatter. Stop-if the repository cannot return resolved key material or valid pushes omit sender transport/identity; replan rather than trust cleartext.
3. Add a foreground group-message resolver callback to the fallback presenter; from inside the keyed lane resolve after the final eligibility check, promote authenticated inner ID, use trusted copy, and suppress unresolved typed `group_message` copy. Leave payload-only legacy routes unchanged.
4. Wire it in `ApplicationRoot` with identity, group repository, locale, and `callGroupDecrypt`.
5. Register the new resolver test once in `GROUP_TESTS`.
6. Run focused GREEN, sentinels, representative mutation re-red, groups gate, hygiene, and pinned Android S2.

## Risks And Blind Spots

- Duplicated/stale transport -> TC-335-04 requires exactly one active match and no decrypt.
- Provider/decrypted names bypass local authority -> TC-335-01/03 use distinct malicious values.
- Missing local names fall back to non-Signal copy -> TC-335-04 rejects blank group/sender attribution before decrypt.
- Missing outer IDs stay generic -> TC-335-06 binds authenticated inner identity.
- Lifecycle / derived-state durability: resolver reloads group, roster, role, and requested key for each fallback; TC-335-03/04 use repository state.
- Sibling-surface consistency: successful canonical presentation is untouched; TC-335-08, group gate, and Android S2 protect it.
- Destructive-action side effects: N/A — no delete, cancel, schema, or storage mutation.
- Invariant re-verification: display eligibility runs before resolution and resolver independently reloads group/member state; TC-335-04 covers ineligible bindings.
- Queued-state race: resolution stays inside the keyed coordinator after the final policy check; TC-335-11 revokes eligibility while queued and requires zero resolver/show calls.

## Gate Cadence

- Per-plan closure: focused resolver/fallback suites, exact private/unanchored sentinels, `./scripts/run_test_gates.sh groups`, analyzer/diff hygiene, and focused paired-Android S2.
- Do not run full `host-all` for this plan. Run `./scripts/run_host_test_gates.sh host-all` once after the Plan 329-335 Android notification reliability wave and once at final rollout/release closure.
- Shared tests outside feature/core globs: run registered notification-sound S2 directly on the pinned pair.

## Acceptance Gates

```bash
# Snapshot; record unrelated changes
git status --short

# Causal RED before production edits; expect non-zero for missing trusted seam/generic behavior
flutter test test/features/push/application/background_push_notification_fallback_test.dart \
  --plain-name 'anchored group drain fallback uses trusted group and sender preview'

# Resolver causal RED/GREEN; GREEN = exit 0, zero failures
flutter test test/features/push/application/foreground_group_message_notification_resolver_test.dart

# Focused GREEN
flutter test \
  test/features/push/application/background_push_notification_fallback_test.dart \
  test/features/push/application/foreground_group_message_notification_resolver_test.dart \
  test/features/push/application/push_decrypt_preview_test.dart \
  test/features/push/application/handle_foreground_remote_message_use_case_test.dart

# Curated lane; target selected once, exit 0, zero failures
./scripts/run_test_gates.sh groups

# Existing runner row registration
./scripts/check_reliability_simulation_discovery.sh --checks-tsv | \
  awk -F '\t' '$1=="group" && $2=="integration_test/scripts/run_notification_sound_smoke.dart" && $3=="S2"'

# Live Android-only matrix
flutter devices --machine
adb devices -l

# Automated Android OS boundary, no taps
dart run integration_test/scripts/run_notification_sound_smoke.dart \
  -d emulator-5554,21071FDF600CSC \
  --rows S2 \
  --non-interactive \
  --artifact-dir build/sims/proofs/plan-335-group-preview

# Hygiene
flutter analyze
git diff --check
```

## Device/Relay Proof Profile

- Profile: paired-device.
- Boundary: actual Android notification-service/OS projection preserves the already-correct canonical group title and sender body after host seam changes.
- Live check: `flutter devices --machine` plus `adb devices -l` observed USB Pixel 6 `21071FDF600CSC` (Android 16/API 36) and emulator `emulator-5554` (Android 17/API 37), both `device`. iOS targets are excluded.
- Setup: emulator is Alice/sender; USB Pixel is Bob/receiver; existing relay config; runner grants notification permission; `--non-interactive` means no user taps.
- Two-peer default: one pinned USB physical Android plus one pinned Android emulator with automated setup, join, send, observation, and assertions.
- Closure role: required preservation evidence only; it does not trigger the changed drain-error seam. Host TC-335-01..08/10/11 are causal closure.
- `FLUTTER_DEVICE_ID`: host selector only; both IDs are explicit.
- Registration: already group-classified at `scripts/check_reliability_simulation_discovery.sh:442-445`.
- Discovery: the command above must list the runner.
- Closure: TC-335-09 command exits 0 with S2 programmatic/OS title/body predicates green and exactly one observed notification. No relay-delivery or multi-observation stability claim is made.
- Deferred device work: none for Android; iOS excluded by user direction.

## Execution Interpretation And Done Criteria

- Expected RED: TC-335-01/03 fail because the trusted resolver/callback does not exist and current presentation is generic.
- Green sentinels: TC-335-09/10 and the identity-free half of TC-335-08 remain unchanged and green.
- Pre-existing dirty tree / known failure: planning snapshot clean; repeat at execution start. No known focused failure.
- Environment blocker: none in live targets. Missing relay/runtime input blocks TC-335-09 and does not authorize iOS substitution.
- Scope drift: any relay/schema/iOS/private-media-policy change requires replanning.

- [x] Every behavior has a named test or justified proof.
- [x] Causal RED, focused GREEN, and representative mutation re-red are recorded.
- [x] Preservation and named gates pass.
- [x] New host test registration is selected exactly once.
- [x] Paired Android canonical-preservation S2 passes on only the pinned USB device and emulator.
- [x] `flutter analyze` has no issues; `git diff --check` is clean.
- [x] Scope Contract And Guard is respected.

## Handoff

- First RED: `flutter test test/features/push/application/background_push_notification_fallback_test.dart --plain-name 'anchored group drain fallback uses trusted group and sender preview'`.
- Preservation: `flutter test test/features/push/application/push_decrypt_preview_test.dart --plain-name 'group private policy at decrypted top level emits only generic localized copy'`.
- Manual registration: add new resolver test once to `GROUP_TESTS`; device runner already registered.
- Migration: none.
- Boundary: host causal seam plus automated canonical-preservation OS projection from emulator `emulator-5554` to USB Pixel `21071FDF600CSC` S2.
- Unresolved: literal iOS placeholder deployment origin only, outside Android execution.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-08-04 10:47 CEST | review applied | plan/index only | `$tdd-review`: `plan-fixes-required` | core bet confirmed; legacy-route conflict, non-causal S2, attribution/privacy/race/wiring gaps repaired in contract | none | write causal tests and record RED |
| 2026-08-04 10:51 CEST | causal RED | fallback and new resolver tests | exact fallback test failed because the callback did not exist; resolver suite failed because the file/function did not exist | both intended seams were red before production edits | none | implement the smallest trusted resolver and presenter wiring |
| 2026-08-04 11:01 CEST | host GREEN and mutation | resolver, fallback, composition root, gate registration | focused suites 117/117; generic-title mutation made TC-335-01 red and restoration returned green | trusted copy, fail-closed boundaries, inner identity, privacy, race, and preservation sentinels green | none | run curated groups lane and Android preservation proof |
| 2026-08-04 11:04 CEST | curated lane | group host/native/relay gates | `./scripts/run_test_gates.sh groups` exited 0: 4024 Flutter tests plus group bridge/node and relay Go tails passed | new resolver test selected exactly once; discovery listed group runner S2 | none | run the pinned Android pair |
| 2026-08-04 11:13 CEST | Android preservation | emulator `emulator-5554` -> USB Pixel `21071FDF600CSC` | focused S2 exited 0 with every harness/OS predicate true | one `mknoon_messages` card: `Notif Sound Discussion / AliceNotif: S2: notification sound discussion`; title/body visible in shade; stable group card ID | initial harness launch exposed pre-existing missing canonical-runtime attachment; a temporary test-only lease hookup enabled the proof and was then reverted | run final analyzer, hygiene, and graph refresh |
| 2026-08-04 11:17 CEST | closure | full affected tree and Graphify | `flutter analyze` clean; focused suites 117/117; `git diff --check` clean; incremental graph refresh succeeded | current graph fingerprint `f2c73d7ccf0c33f3`; all done criteria satisfied | none | complete |

## Closure Evidence

- RED: TC-335-01 first failed at compile time because `groupMessageNotificationResolver` was absent; the new resolver suite likewise failed because its production file/function did not exist.
- GREEN: the fallback, foreground resolver, shared decrypt-preview, and foreground-handler suites pass 117/117 together.
- Mutation: temporarily restoring the hardcoded `Mknoon` title made the exact anchored-copy test fail (`expected Team Chat`, `actual Mknoon`); restoration returned it to green.
- Curated lane: `./scripts/run_test_gates.sh groups` passed 4024 Flutter tests and its group bridge/node and relay Go proof tails. Full `host-all` was intentionally not run under the project cadence.
- Registration/discovery: the new resolver test occurs once in `GROUP_TESTS`; S2 remains discoverable as the group notification-sound runner row.
- Android-only proof: the only targets used were emulator `emulator-5554` (Alice) and USB Pixel 6 `21071FDF600CSC` (Bob). `build/sims/proofs/plan-335-group-preview-final/notification_sound_smoke_summary.json` records S2 programmatic/OS PASS, exactly one notification, matching channel/category/title/body/payload, visible shade copy, screenshot capture, and stable conversation-card identity.
- Harness note: the first device attempts stopped before S2 because the older integration harness had not attached Android's canonical runtime and native identity/ML-KEM calls returned `MISSING_PLUGIN`. A temporary test-only lease hookup, equivalent to production bootstrap ordering, was used only to unblock the proof and was reverted afterward; no harness or platform source is part of this change.
- Final hygiene: full `flutter analyze` reports no issues, `git diff --check` is clean, and Graphify incremental refresh/query reports current fingerprint `f2c73d7ccf0c33f3`.

## Reviewer Findings

Verdict: `plan-fixes-required`.

Core bet: confirmed. The typed foreground `group_message` drain-error path reaches an anchored presenter that hardcodes `Mknoon / Message`; the normal canonical listener and encrypted preview formatter already produce the requested Signal-style attribution.

Disposition: apply-plan-fixes, completed in this revision.

- Narrowed fail-closed behavior to typed authenticated/encrypted `group_message` wakes and explicitly preserved the registered payload-only legacy route.
- Required nonblank recipient-owned group/sender attribution and exact requested-generation key/decrypt arguments.
- Strengthened null-resolution, private-media, ApplicationRoot wiring, and queued policy-race tests so bypasses cannot pass vacuously.
- Reclassified Android notification-sound S2 as canonical/plugin/OS preservation evidence; it is not causal proof of the drain-error seam and makes no forced-relay or repeated-card-stability claim.
- Corrected discovery to the script's supported `--checks-tsv` interface and pinned its exact group/S2 row.
- Kept the reported literal `New Message / You have a new message` evidence-gated; closure is for the current-source Android/Dart recovery defect that emits `Mknoon / Message`.
