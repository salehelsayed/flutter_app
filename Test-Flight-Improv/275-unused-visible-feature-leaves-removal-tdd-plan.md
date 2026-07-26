# 275 - DTR-04 unused visible feature leaves and obsolete SUT-only tests

Status: Plan-green
Type: Modification
Spec: `Test-Flight-Improv/dead-code-and-technical-debt-removal-roadmap.md` (`DTR-04`)
Classification: implementation-complete
Closure tier: host
Roadmap ID / wave: `DTR-04` / Wave 1 — Proven dependency leaves
Date: 2026-07-25

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-25 | Evidence Collector | DTR roadmap; architecture Graphify context; the ten DTR-04 anchors; current importers; `tool/runtime_roots/runtime_roots.json`; test and gate sources | Eight visible/UI paths have a bounded removal proof. The group cursor and post follow-on helper are not proven safe under their downstream owner conditions. | Contract the eight proposed removals and two explicit deferrals. |
| 2026-07-25 | Planner | Replacement widget/screen tests; l10n catalogs/generated API; `scripts/run_test_gates.sh`; `scripts/run_host_test_gates.sh`; current test inventory and plan index | Host tests can prove the deletion and preservation contracts, but the roadmap requires named-owner approval for every Wave 1 deletion and none is recorded. | Obtain and record the five owner-domain approvals before any implementation edit. |
| 2026-07-25 | Reviewer | Plan 275; Wave 1 exit contract; exact gate arrays; migration/helper fixtures; source-proof commands | Refuted `execution-ready`: five approvals are open. Corrected self-matching greps, SQLite-vs-SQLCipher wording, causal-vs-sentinel labels, source-cleanup coverage, and removed the unrelated `integration_test`-based Posts gate. | Keep the plan evidence-gated until every named approval is recorded, then re-ground before RED. |
| 2026-07-25 | `$tdd-review` | Plan 275; `DTR08-COMP-002`; facade/shared sources; all current imports; runtime-root records; recording UI tests and gates | Core removal bet confirmed, but TC-DTR04-08 did not prove migrate-before-delete ordering, UI-source immutability, or safe reverse-order rollback. Approval rows could also wrong-green by replacing `Open` with arbitrary text. | Apply the staged DTR08 checkpoint, exact ledger proof, UI no-delta guard, approval evidence schema, and rollback order; remain `not-ready` while five approvals are open. |
| 2026-07-25 | Sole repository owner | Direct authorization in this task thread; five domain-specific approval rows; reviewed technical contract | The requesting user affirmed sole ownership and approved modification of the plan. The single owner therefore authorizes all five bounded domain rows; the prior review's only blocker is resolved. | Treat the plan as `execution-ready`; re-ground the current importer/root census before the first RED and stop on drift. |

## Problem And Evidence

- Behavior to improve: retire app-visible widgets and compatibility surfaces that
  no current app path uses, plus tests whose only purpose is to preserve those
  retired implementations. Users should see no UI or behavior change.
- Impact: obsolete public-looking widgets, duplicated presentation code, stale
  localization API, and SUT-only tests make future changes look broader and
  riskier than the runtime app actually is.
- Confirmed root cause/current gap:
  - seven production widget files have no production importer; their current
    replacement screens/widgets and tests are named below;
  - `lib/features/conversation/presentation/widgets/recording_overlay.dart` is
    exactly a one-line export of
    `lib/shared/widgets/media/recording_overlay.dart`. `DTR08-COMP-002` records
    one production legacy importer (`compose_area.dart`) and two test importers;
    all three must move before deletion;
  - four widget tests import only the obsolete SUT and therefore must be removed
    atomically with it;
  - three settings localization keys are referenced only by retired cards.
- Existing coverage: the feed letter cards, shared compose/recording widgets,
  group conversation screen, settings screen/wiring, and identity progress
  screen already exercise the live replacement surfaces. The runtime-root
  manifest also records the compatibility facade and downstream owner gates.
- Missing coverage: HEAD has no single causal policy test requiring twelve
  owner-approved files to be absent, no migration policy test requiring all
  three DTR08-COMP-002 consumers to import the shared overlay directly, no
  sentinel requiring the two deferred candidates to remain owner-gated, and no
  l10n test preventing retired settings keys from returning.
- Refuted findings:
  - “all ten roadmap anchors are ordinary dead leaves” is refuted. The durable
    group inbox cursor tables/helpers/repository path is live and the exact model
    remains owned by `DTR-10 / groups`; the post follow-on helper remains behind
    the `DTR-06 / posts` product-decision condition.
  - “the recording overlay facade has zero importers” is refuted. One production
    and two test imports must move to the shared implementation first.
- Highest-risk bet and fallback: directly importing the shared overlay is
  behavior-preserving because the facade exports that exact symbol and contains
  no adapter logic. If the production-import checkpoint or recording parity
  suite fails while the facade still exists, restore only the import and stop;
  wrapper deletion is not authorized.
- Authorization resolution: the requesting user affirmed that they are the sole
  repository owner and directly authorized this plan on 2026-07-25. The same
  owner identity is recorded against the bounded Feed, Groups, Settings,
  Conversation, and Identity rows below. No authorization blocker remains;
  execution still must re-ground current source before RED.
- Affected production, test, and gate files: the eight production paths and four
  retired tests enumerated in the Scope Contract; active feed, groups, settings,
  identity, and conversation tests; `test/unit/runtime_root_inventory_test.dart`;
  `test/l10n/l10n_integrity_test.dart`; `tool/runtime_roots/runtime_roots.json`;
  l10n ARB/generated files; `Test-Flight-Improv/codebase-test-inventory.md`.
- Planning inventory only: the proposed deletion set is twelve files (eight
  production paths and four tests). Execution must derive current line/count
  totals rather than treating a planning count as an acceptance condition.

## Graph Grounding Snapshot

- Graph fingerprint / freshness: `fc333c615c1b3e10`;
  `stale:lib/features/conversation/presentation/screens/direct_private_media_viewer.dart`
  is unrelated to this deletion set.
- Query / profile:
  `python3 graphify-arch/tdd_context.py query "DTR-04 remove unused visible feature/UI leaves and obsolete SUT-only tests: feed_ring_avatar.dart, group_inbox_cursor.dart, group_compose_area.dart, post_pass_follow_on_support.dart, settings_move_account_card.dart, amplitude_bars.dart, settings_peer_id_card.dart, posts_nearby_settings_card.dart, identity_loading_card.dart, recording_overlay.dart; find current importers, replacement widgets/screens, tests, runtime-root inventory records, and run_test_gates.sh family registrations" --profile tdd --budget 700`.
- Review query / profile:
  `python3 graphify-arch/tdd_context.py query "DTR08-COMP-002 exact anchor package:flutter_app/features/conversation/presentation/widgets/recording_overlay.dart: list direct importers only, the exported shared target, ComposeArea RecordingOverlay call, recording_overlay_test and conversation_wired_test imports, and runtime-root restricted/required compatibility record" --profile review --budget 800`.
- Anchors:
  - `SettingsMoveAccountCard` ->
    `lib/features/settings/presentation/widgets/settings_move_account_card.dart:8`;
  - `unresolvedDeliveries` ->
    `lib/features/posts/application/post_pass_follow_on_support.dart:92`;
  - `_sendOpacity` ->
    `lib/features/groups/presentation/widgets/group_compose_area.dart:30`.
- Surfaced proof/gate files: the ten production anchors, live settings/group
  screens, shared media widgets, and adjacent application/repository paths.
- Graph gaps requiring source search: most exact widget-test names, the
  runtime-root manifest dispositions, l10n-only references, and family-array
  registration were not surfaced by compact context and were verified in
  current source. Review context also surfaced unrelated callers through
  conversation screens; exact source search proved that the old URI has only
  the three imports named above. Posts and the performance harness already
  import the shared overlay directly.
- Reuse rule: anchors may be handed to review/execution; all conclusions still
  require current-source or command evidence.

## Scope Contract And Guard

In scope:

- Under the recorded sole-owner approval, delete these eight production paths
  after their causal test is RED:
  1. `lib/features/feed/presentation/widgets/feed_ring_avatar.dart`;
  2. `lib/features/groups/presentation/widgets/group_compose_area.dart`;
  3. `lib/features/settings/presentation/widgets/settings_move_account_card.dart`;
  4. `lib/features/conversation/presentation/widgets/amplitude_bars.dart`;
  5. `lib/features/settings/presentation/widgets/settings_peer_id_card.dart`;
  6. `lib/features/settings/presentation/widgets/posts_nearby_settings_card.dart`;
  7. `lib/features/identity/presentation/widgets/identity_loading_card.dart`;
  8. `lib/features/conversation/presentation/widgets/recording_overlay.dart`.
- Delete these four obsolete SUT-only tests:
  `test/features/conversation/presentation/widgets/amplitude_bars_test.dart`,
  `test/features/settings/presentation/widgets/settings_peer_id_card_test.dart`,
  `test/features/settings/presentation/widgets/posts_nearby_settings_card_test.dart`,
  and
  `test/features/identity/presentation/widgets/identity_loading_card_test.dart`.
- Execute `DTR08-COMP-002` as the first destructive-risk checkpoint:
  1. require the one-line facade and both compatibility manifest records to
     remain present;
  2. change only the production import in
     `lib/features/conversation/presentation/widgets/compose_area.dart` to
     `package:flutter_app/shared/widgets/media/recording_overlay.dart`;
  3. while the facade still exists, run the production-import proof and
     recording UI parity sentinels;
  4. retarget the two test imports in
     `test/features/conversation/presentation/widgets/recording_overlay_test.dart`
     and
     `test/features/conversation/presentation/screens/conversation_wired_test.dart`;
  5. while the facade still exists, prove the roadmap-exact zero-old-import
     command and the full three-file DTR08 parity command green;
  6. only after that recorded checkpoint, delete the facade and remove
     `compatibility.recording-overlay-export` from both
     `requiredRestrictedRoots` and `restrictedRoots`.
- Reconcile the exact removed declaration/compatibility records and candidate
  expectations in `tool/runtime_roots/runtime_roots.json` and
  `test/unit/runtime_root_inventory_test.dart`. Recompute aggregate test-only
  counts from the execution baseline; do not pin a planning total.
- Remove `settings_move_account_desc`, `settings_move_account_action`, and
  `settings_peer_id_desc` from all three ARB catalogs, regenerate l10n output,
  and retain the live `settings_move_account_title` and
  `settings_peer_id_title` APIs.
- Remove the four deleted test entries from
  `Test-Flight-Improv/codebase-test-inventory.md`, and rewrite stale comments in
  the three feed replacement tests and `settings_screen.dart` so they no longer
  describe the retired widgets as HEAD behavior.

Authorization gate — the requesting user affirmed sole repository ownership and
approved this bounded plan directly on 2026-07-25. The same owner identity
covers every row; the rows remain separate so each domain scope stays explicit.
The acceptance check must still prove exactly one valid row per domain. A source
audit is not a substitute for this recorded owner authorization.

| Owner domain | Exact proposed retirement | Approver identity | Approval date | Evidence reference | State |
|---|---|---|---|---|---|
| Feed | `feed_ring_avatar.dart` and its stale replacement-test comments | Sole repository owner (requesting user) | 2026-07-25 | Direct task-thread authorization: “I'm the only owner, modify the plan.” | Approved |
| Groups | `group_compose_area.dart` | Sole repository owner (requesting user) | 2026-07-25 | Direct task-thread authorization: “I'm the only owner, modify the plan.” | Approved |
| Settings | `settings_move_account_card.dart`, `settings_peer_id_card.dart`, `posts_nearby_settings_card.dart`, their two SUT-only tests, and three orphan l10n keys | Sole repository owner (requesting user) | 2026-07-25 | Direct task-thread authorization: “I'm the only owner, modify the plan.” | Approved |
| Conversation | duplicate `amplitude_bars.dart` plus its SUT-only test, and the `DTR08-COMP-002` recording-overlay facade after its staged three-import retarget | Sole repository owner (requesting user) | 2026-07-25 | Direct task-thread authorization: “I'm the only owner, modify the plan.” | Approved |
| Identity | `identity_loading_card.dart` and its SUT-only test | Sole repository owner (requesting user) | 2026-07-25 | Direct task-thread authorization: “I'm the only owner, modify the plan.” | Approved |

Must preserve:

- Feed avatar rendering and refresh ->
  `letter_card_one_to_one_test.dart::renders a size-40 UserAvatar (no glow/frame), one LetterBubble per text, and no name header (B1/TC-16/TC-09)`,
  its existing-photo and invalidation tests, plus the corresponding group and
  system card avatar tests.
- Group write/read-only and send affordances ->
  `group_conversation_screen_test.dart::shows compose area when canWrite is true`,
  `::passes isSending through to the compose send affordance`,
  `::hides compose area for readers in announcement group`, and
  `group_conversation_wired_test.dart::non-admin in announcement group cannot write`.
- Settings identity, move-account routing, nearby-sharing writes, and interactive
  refresh -> the exact settings tests in TC-DTR04-03, TC-DTR04-05, and
  TC-DTR04-06.
- Shared recording visualization, cancel, tick, and auto-stop behavior -> the
  exact conversation tests in TC-DTR04-04, TC-DTR04-08A, and TC-DTR04-08B.
- DTR08-COMP-002 source identity -> the facade remains the exact one-line export
  until its pre-delete checkpoint, while
  `lib/shared/widgets/media/recording_overlay.dart`,
  `lib/shared/widgets/media/amplitude_bars.dart`, the `RecordingOverlay`
  constructor arguments in `ComposeArea`, and the already-direct Posts and
  performance-harness imports remain unchanged.
- Identity progress copy, transition, and back-navigation blocking -> the exact
  progress tests in TC-DTR04-07.
- The group inbox cursor model path, its manifest owner/condition, and all live
  durable cursor schema/helpers/repository/drain behavior -> TC-DTR04-09.
- The post follow-on helper path, its manifest owner/condition, the live post
  delivery retrier behavior, and migration `035` recognition of legacy
  `post_pass_along` rows -> TC-DTR04-10.

Hard `Do not`:

- Do not delete or edit
  `lib/features/groups/domain/models/group_inbox_cursor.dart` or
  `lib/features/posts/application/post_pass_follow_on_support.dart`.
- Do not remove, rename, or reinterpret group cursor tables, migration `066`,
  migration `035`, the `post_pass_along` persisted literal, or repository/drain
  wiring.
- Do not absorb the DTR-06 Posts presentation island rooted at
  `posts_wired.dart`, the DTR-07 group-list island, or any other runtime-root
  candidate.
- Do not change visible copy, navigation, permissions, persistence, native code,
  wire behavior, package dependencies, or database version.
- Do not edit `lib/shared/widgets/media/recording_overlay.dart` or
  `lib/shared/widgets/media/amplitude_bars.dart`. During DTR08-COMP-002, do not
  change `ComposeArea` recording state selection, `RecordingOverlay`
  construction, elapsed/cancel/amplitude arguments, or any recording logic;
  only the three import directives, facade, and its two manifest records may
  change.
- Do not delete the recording facade or either compatibility record before a
  recorded wrapper-present checkpoint proves all three consumers import the
  shared overlay, the roadmap-exact legacy-path search has zero matches, and
  the full parity command is green. A final diff cannot substitute for this
  ordering proof.
- Do not delete a test merely because its filename mentions a retired symbol;
  delete only the four exact SUT-only files listed above.

Deferred / accepted difference:

- `group_inbox_cursor.dart` -> owner `DTR-10 / groups`, because its manifest
  condition requires group compatibility ownership to be resolved before
  removal while the durable cursor boundary remains live.
- `post_pass_follow_on_support.dart` -> owner `DTR-06 / posts`, because its
  manifest condition requires the Posts product decision before removal.
- The retired feature-local `AmplitudeBarsPainter` was public only through the
  dead duplicate and its SUT-only test. Direct painter-construction/repaint tests
  are intentionally retired; the shared widget's private painter is preserved
  through composition, empty-values, cancel, and recording sentinels.

Dependencies:

- `DTR08-COMP-002` is the compatibility contract for the recording facade.
  Its source/API floor is zero old facade imports after production-plus-test
  retarget; no release, wire, device, or runtime telemetry floor applies.
- Wave 1 owner approval is a hard prerequisite and is satisfied by the sole
  repository owner's direct 2026-07-25 authorization recorded independently
  against the exact Feed, Groups, Settings, Conversation, and Identity scopes.
  Any scope expansion invalidates that approval and returns the plan to
  `evidence-gated`.
- DTR-01 supplies the runtime-root inventory and real admission test; DTR-02
  supplies the strict analyzer gate. Both prerequisite artifacts are present in
  the accepted but currently dirty Wave 0 working tree. Execution must snapshot
  and preserve that baseline and stop if either prerequisite disappears or its
  named gate fails for a non-DTR-04 reason.
- DTR-03, DTR-04, and DTR-05 form Wave 1. Their work may coexist, but DTR-04
  owns only the exact paths above.

## Test Contract

Classification rule, incorporated into every row: in TC-DTR04-01 through
TC-DTR04-07, the new absence policy proof (and, where named, the new l10n proof)
is the **causal RED**. TC-DTR04-08A and TC-DTR04-08B have separate causal
source/policy REDs so migrate-before-delete ordering cannot be inferred from a
final diff. Every pre-existing replacement test listed after a causal proof is
a **GREEN sentinel**: it passes on HEAD and must remain green after the import
move and deletion. The combined rows do not reclassify those replacement suites
as RED. TC-DTR04-09 and TC-DTR04-10 are preservation-only GREEN sentinels. The
word `approved` in the planned causal test name reflects the sole-owner
authorization recorded above; it does not waive execution-time source
re-grounding or any causal RED.

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-DTR04-01 | Retire `FeedRingAvatar`; the live feed cards continue using bare `UserAvatar` sizes/photos/invalidation. | `test/unit/runtime_root_inventory_test.dart::DTR-04 retires approved visible leaves and obsolete SUT-only tests`; `test/features/feed/presentation/widgets/letter_card_one_to_one_test.dart::renders a size-40 UserAvatar (no glow/frame), one LetterBubble per text, and no name header (B1/TC-16/TC-09)`; `::renders the contact photo when the avatar file exists (B1/TC-1)`; `::a card photo refreshes live when UserAvatar.invalidatePeer fires (B1/TC-4)`; `test/features/feed/presentation/widgets/letter_card_group_test.dart::per run renders a size-32 UserAvatar (no glow/frame), an accent-coloured sender name span, and all unread bubbles (B1/TC-17/TC-09)`; `::a sender run with a seeded avatar file renders its photo (B1/TC-2)`; `test/features/feed/presentation/widgets/letter_card_system_test.dart::system card renders the contact photo when the avatar file exists (B1/TC-3)` | Host file-policy unit + widget tests / filesystem inventory and WidgetTester fixtures | Causal RED: approved file exists on HEAD -> GREEN: file/manifest record are absent while all live card sentinels remain green | Restore the file/manifest record -> policy test re-reds; replace a live card's `UserAvatar` with the old wrapper -> size/photo sentinel re-reds | `./scripts/run_test_gates.sh runtime-roots` and `./scripts/run_test_gates.sh feed`; new policy test is in the existing `runtime-roots` unit file, feed files are already in `FEED_TESTS`, and all feature tests AUTO-glob into `feature-host-all` |
| TC-DTR04-02 | Retire `GroupComposeArea`; the group screen keeps the shared compose UI, send state, and read-only gate. | `test/unit/runtime_root_inventory_test.dart::DTR-04 retires approved visible leaves and obsolete SUT-only tests`; `test/features/groups/presentation/group_conversation_screen_test.dart::shows compose area when canWrite is true`; `::passes isSending through to the compose send affordance`; `::hides compose area for readers in announcement group`; `test/features/groups/presentation/group_conversation_wired_test.dart::non-admin in announcement group cannot write` | Host file-policy unit + widget tests / filesystem inventory and WidgetTester fakes | Causal RED: obsolete file exists -> GREEN: file/manifest record are absent and shared compose behavior remains green | Restore the obsolete file/record -> policy test re-reds; wire the old compose widget or drop `canWrite`/`isSending` -> named group sentinel re-reds | `./scripts/run_test_gates.sh runtime-roots` and `./scripts/run_test_gates.sh groups`; both group files are already in `GROUP_TESTS` and AUTO-globbed |
| TC-DTR04-03 | Retire `SettingsMoveAccountCard` and its two orphan copy keys while preserving the active settings row and migration route. | `test/unit/runtime_root_inventory_test.dart::DTR-04 retires approved visible leaves and obsolete SUT-only tests`; `test/l10n/l10n_integrity_test.dart::DTR-04 retired settings keys are absent from every locale and generated API`; `test/features/settings/presentation/screens/settings_screen_test.dart::renders move account row when callback is supplied`; `test/features/settings/presentation/screens/settings_wired_test.dart::move account action opens old-phone migration route`; `::TC-209-36 move-account double-tap pushes exactly one route`; `::move account route receives injected migration transfer runner` | Host file/l10n policy + widget tests / filesystem, generated API text, WidgetTester fakes | Causal RED: card and orphan keys exist -> GREEN: card/keys are absent, title remains, and the live row still opens exactly one injected route | Restore the card/key -> policy/l10n test re-reds; remove/debounce-bypass the active callback -> settings wiring sentinel re-reds | `flutter test --no-pub test/l10n/l10n_integrity_test.dart --plain-name 'DTR-04 retired settings keys are absent from every locale and generated API'`; `./scripts/run_test_gates.sh runtime-roots`; `./scripts/run_test_gates.sh feature-host-all`; l10n file is AUTO in `host-all` and run directly per-plan, feature tests AUTO-glob |
| TC-DTR04-04 | Retire the feature-local duplicate amplitude widget and its SUT-only painter suite; preserve the shared recording visualization. | `test/unit/runtime_root_inventory_test.dart::DTR-04 retires approved visible leaves and obsolete SUT-only tests`; `test/features/conversation/presentation/widgets/recording_overlay_test.dart::renders AmplitudeBars when amplitudeValues provided`; `::renders AmplitudeBars even with empty values`; `::red dot and cancel button still present with amplitude bars`; `test/features/conversation/presentation/widgets/compose_area_test.dart::recording overlay appears when isRecording is true` | Host file-policy unit + widget tests / filesystem inventory and WidgetTester | Causal RED: duplicate implementation and its test exist -> GREEN: both are absent and the shared widget renders populated/empty bars with controls | Restore either retired path -> policy test re-reds; remove shared bars/control composition -> overlay sentinel re-reds | `./scripts/run_test_gates.sh runtime-roots`; `flutter test --no-pub test/features/conversation/presentation/widgets/recording_overlay_test.dart test/features/conversation/presentation/widgets/compose_area_test.dart`; `./scripts/run_test_gates.sh 1to1`; `./scripts/run_test_gates.sh feature-host-all`; feature tests AUTO-glob |
| TC-DTR04-05 | Retire `SettingsPeerIdCard`, its SUT-only test, and `settings_peer_id_desc`; preserve live identity rows and clipboard feedback. | `test/unit/runtime_root_inventory_test.dart::DTR-04 retires approved visible leaves and obsolete SUT-only tests`; `test/l10n/l10n_integrity_test.dart::DTR-04 retired settings keys are absent from every locale and generated API`; `test/features/settings/presentation/screens/settings_screen_test.dart::renders profile section and identity rows`; `::hides peer ID row when peerId is null`; `::daylight full page includes every One-Screen section`; `test/features/settings/presentation/screens/settings_wired_test.dart::loads identity on init, displays peerId and username`; `::copy peer ID: full ID on clipboard, shows check for 2s then reverts` | Host file/l10n policy + widget tests / filesystem, generated API text, WidgetTester fakes | Causal RED: card/test/key exist -> GREEN: all three are absent while the live row retains null handling, full-ID copy, and timed feedback | Restore any retired path/key -> policy/l10n test re-reds; truncate clipboard data or remove feedback -> wired sentinel re-reds | `flutter test --no-pub test/l10n/l10n_integrity_test.dart --plain-name 'DTR-04 retired settings keys are absent from every locale and generated API'`; `flutter test --no-pub test/features/settings/presentation/screens/settings_screen_test.dart test/features/settings/presentation/screens/settings_wired_test.dart`; `./scripts/run_test_gates.sh runtime-roots`; `./scripts/run_test_gates.sh feature-host-all`; existing files retain AUTO registration |
| TC-DTR04-06 | Retire `PostsNearbySettingsCard` and its SUT-only test; preserve the active settings switch and repository/location transitions. | `test/unit/runtime_root_inventory_test.dart::DTR-04 retires approved visible leaves and obsolete SUT-only tests`; `test/features/settings/presentation/screens/settings_screen_test.dart::daylight full page includes every One-Screen section`; `test/features/settings/presentation/screens/settings_wired_posts_nearby_test.dart::toggle writes nearby sharing state through the repository`; `::enabling nearby sharing triggers interactive refresh`; `::disabling nearby sharing publishes inactive before clearing` | Host file-policy unit + widget tests / filesystem inventory, WidgetTester, repository/location fakes | Causal RED: card and SUT-only test exist -> GREEN: both are absent while enable/disable ordering remains green | Restore a retired path -> policy test re-reds; skip interactive refresh or clear before inactive publish -> nearby sentinel re-reds | `./scripts/run_test_gates.sh runtime-roots`; `flutter test --no-pub test/features/settings/presentation/screens/settings_screen_test.dart test/features/settings/presentation/screens/settings_wired_posts_nearby_test.dart`; `./scripts/run_test_gates.sh feature-host-all`; both feature files AUTO-glob; the unrelated `integration_test`-based `posts` gate is intentionally excluded |
| TC-DTR04-07 | Retire `IdentityLoadingCard` and its SUT-only test; preserve the routed progress screen and stage transition. | `test/unit/runtime_root_inventory_test.dart::DTR-04 retires approved visible leaves and obsolete SUT-only tests`; `test/features/identity/presentation/screens/identity_progress_screen_test.dart::renders generating progress surface with exact copy and spinner`; `::renders saving progress surface with exact copy and step state`; `::updates copy when stage changes from generating_keys to saving`; `::does not paint both stage copies on top of each other during transition`; `::prevents back navigation while progress is active`; `test/features/identity/presentation/screens/identity_choice_wired_test.dart::progress route advances from generating_keys to saving` | Host file-policy unit + widget tests / filesystem inventory and WidgetTester fakes | Causal RED: old card/test exist -> GREEN: both are absent while the active route renders and transitions without double copy or back navigation | Restore a retired path -> policy test re-reds; freeze stage mapping, overlap copies, or permit pop -> named progress sentinel re-reds | `./scripts/run_test_gates.sh runtime-roots`; `flutter test --no-pub test/features/identity/presentation/screens/identity_progress_screen_test.dart test/features/identity/presentation/screens/identity_choice_wired_test.dart`; `./scripts/run_test_gates.sh feature-host-all`; feature tests AUTO-glob |
| TC-DTR04-08A | `DTR08-COMP-002` production migration: move the sole production consumer to the shared overlay first while the facade and both manifest records remain recoverable; preserve all recording UI inputs and behavior. | Causal source proof: facade exists and is the exact shared export; `compose_area.dart` has the exact shared import directive; the roadmap legacy-path search has zero `lib` matches. GREEN sentinels: new `test/features/conversation/presentation/widgets/compose_area_test.dart::DTR08-COMP-002 shared recording overlay keeps elapsed amplitudes and cancel wiring`; existing `::recording overlay appears when isRecording is true`; `::recording overlay disappears when isRecording is false`; `::recording overlay cancel gesture forwards onRecordCancel`; `test/features/conversation/presentation/screens/conversation_wired_test.dart::recording ticks update composer without rebuilding header or message list`; `::recorder auto-stop resets the composer recording state` | Host source proof + widget tests / exact files, WidgetTester, local fakes | Causal RED on HEAD: `compose_area.dart` imports the facade -> GREEN checkpoint A: only its import points directly to shared, facade/records still exist, shared UI sources are clean, and all named sentinels remain GREEN | Keep the old production import or delete the facade/record early -> checkpoint A red; drop elapsed/amplitude/cancel forwarding -> the new ComposeArea sentinel re-reds | Exact checkpoint-A commands in Acceptance Gates; `compose_area_test.dart` AUTO-globs into `feature-host-all`; wired selectors are in the curated `1to1` file |
| TC-DTR04-08B | `DTR08-COMP-002` facade retirement: retarget both test imports, prove zero supported old imports and full UI parity while the wrapper still exists, then and only then delete the wrapper and its two compatibility records. | Causal policy test `test/unit/runtime_root_inventory_test.dart::DTR08-COMP-002 consumers import the shared recording overlay before facade retirement`; roadmap-exact source proof `! rg -n "features/conversation/presentation/widgets/recording_overlay\\.dart" lib test`; exact shared-directive proof over the three importer files; wrapper-present pre-delete proof; final `test/unit/runtime_root_inventory_test.dart::DTR-04 retires approved visible leaves and obsolete SUT-only tests`. GREEN parity command: full `recording_overlay_test.dart`, `compose_area_test.dart`, and `conversation_wired_test.dart` before and after deletion | Host policy/source + widget tests / filesystem, runtime-root manifest, WidgetTester fakes | Causal RED on HEAD: three legacy imports remain and final facade/records exist -> GREEN checkpoint B1: all consumers import shared, exact old-path search is empty, parity is green, and wrapper/records still exist -> GREEN B2: only then wrapper and both records are absent, with migration/parity still green | Reintroduce one old import -> migration policy/roadmap proof red; delete wrapper before B1 -> wrapper-present proof red; edit either shared UI file -> no-delta guard red; retain or restore one compatibility record -> final runtime-root proof red | Full three-file command before and after deletion; `./scripts/run_test_gates.sh runtime-roots`; `./scripts/run_test_gates.sh 1to1`; `./scripts/check_flutter_analyze_strict.sh`; `./scripts/run_host_test_gates.sh feature-host-all`; new policy test is registered by the existing `runtime-roots` gate |
| TC-DTR04-09 | GREEN sentinel: preserve the owner-gated `GroupInboxCursor` candidate and its live durable cursor boundary for DTR-10. | `test/unit/runtime_root_inventory_test.dart::DTR-04 preserves owner-gated group and posts candidates`; `test/core/database/migrations/066_group_sync_receipts_test.dart::PREREQ-GROUP-SYNC-RECEIPTS creates cursor and receipt tables idempotently`; `test/core/database/helpers/group_sync_receipts_db_helpers_test.dart::PREREQ-GROUP-SYNC-RECEIPTS persists cursor and receipts across reopen`; `test/features/groups/domain/repositories/group_message_repository_impl_test.dart::loads durable cursor and receipts through repository`; `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart::PREREQ-GROUP-SYNC-RECEIPTS loads durable cursor and advances only after page apply`; `::PREREQ-GROUP-SYNC-RECEIPTS failed page commit does not advance cursor or save receipts` | Host policy + SQLite FFI migration/helper/repository regression tests and application fake boundary; no SQLCipher claim | GREEN sentinel on HEAD -> GREEN after DTR-04: exact model file and `DTR-10 / groups` condition remain; SQLite regressions remain green and no persistence code changes | Delete the model/manifest condition -> policy sentinel re-reds; drop the table or advance before commit -> exact SQLite migration/drain sentinel re-reds | `flutter test --no-pub test/core/database/migrations/066_group_sync_receipts_test.dart`; `flutter test --no-pub test/core/database/helpers/group_sync_receipts_db_helpers_test.dart`; `flutter test --no-pub test/features/groups/domain/repositories/group_message_repository_impl_test.dart --plain-name 'loads durable cursor and receipts through repository'`; `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'PREREQ-GROUP-SYNC-RECEIPTS'`; `./scripts/run_test_gates.sh runtime-roots`; `./scripts/run_test_gates.sh groups`; core/feature tests are AUTO-registered and run directly without `core-host-all` |
| TC-DTR04-10 | GREEN sentinel: preserve the owner-gated post helper, live delivery-retry behavior, and legacy migration literal for DTR-06. | `test/unit/runtime_root_inventory_test.dart::DTR-04 preserves owner-gated group and posts candidates`; `test/features/posts/improvement/post_pass_retry_integration_test.dart::pass retry uses the post delivery retrier, preserves explicit recipient plus author notification, and does not duplicate pass records`; `test/core/database/migrations/035_posts_repost_delivery_state_test.dart::adds repost delivery ownership to post_recipients and migrates legacy pass outbox rows` | Host policy + application integration fakes + SQLite FFI migration regression fixture; no SQLCipher claim | GREEN sentinel on HEAD -> GREEN after DTR-04: helper and `DTR-06 / posts` condition remain, retry and SQLite migration regressions remain green, and no persistence code changes | Delete the helper/manifest condition -> policy sentinel re-reds; reroute retry or remove the persisted literal -> integration/migration sentinel re-reds | `flutter test --no-pub test/features/posts/improvement/post_pass_retry_integration_test.dart --plain-name 'pass retry uses the post delivery retrier, preserves explicit recipient plus author notification, and does not duplicate pass records'`; `flutter test --no-pub test/core/database/migrations/035_posts_repost_delivery_state_test.dart --plain-name 'adds repost delivery ownership to post_recipients and migrates legacy pass outbox rows'`; `./scripts/run_test_gates.sh runtime-roots`; feature/core files are AUTO-registered and the unrelated `integration_test`-based `posts` gate is intentionally excluded |
| TC-DTR04-11 | Remove only the four retired-test inventory entries and four stale symbol comments; current documentation must describe the live replacement surfaces. | Source proofs: `! rg -n -e "amplitude_bars_test\\.dart" -e "settings_peer_id_card_test\\.dart" -e "posts_nearby_settings_card_test\\.dart" -e "identity_loading_card_test\\.dart" Test-Flight-Improv/codebase-test-inventory.md`; `! rg -n "FeedRingAvatar" test/features/feed/presentation/widgets/letter_card_one_to_one_test.dart test/features/feed/presentation/widgets/letter_card_group_test.dart test/features/feed/presentation/widgets/letter_card_system_test.dart`; `! rg -n "SettingsPeerIdCard" lib/features/settings/presentation/screens/settings_screen.dart` | Host source proof / ripgrep over the exact current inventory and four comment-bearing files | Causal RED: all three proof commands fail on HEAD because the retired test entries/symbol comments exist -> GREEN: exact references are absent and no other inventory/comment content is swept | Restore any one retired inventory entry or stale symbol comment -> the corresponding TC-DTR04-11 proof re-reds | Run the three literal source commands in Acceptance Gates; N/A — documentation/comment source proof runs directly and needs no test-harness registration, while runtime replacement behavior is registered under TC-DTR04-01/05 |

## Implementation Steps

1. Before any test or production edit, run the exact five-row structural check
   and verify the direct sole-owner authorization recorded above. If any row is
   absent, duplicated, malformed, no longer approved, or scope-mismatched, stop.
   Rerun the compact Graphify query with `--ensure-fresh`, repeat the exact
   importer/root census, and stop on drift. The plan status/classification and
   roadmap summary are `execution-ready` as of the recorded authorization.
   Snapshot `git status --short`, retain the accepted DTR-01/DTR-02 Wave 0 delta
   plus the concurrent DTR-03 plan, confirm no Plan 275 collision, and begin the
   causal tests.
2. In `test/unit/runtime_root_inventory_test.dart`, add:
   - causal RED `DTR-04 retires approved visible leaves and obsolete SUT-only tests`,
     with exact arrays for the eight production and four test paths, plus the old
     recording-facade import URI. Require every path to be absent on disk, all
     seven declaration records to be absent, and the facade to be absent from
     both restricted/required compatibility-root records. Its causal absence
     assertion must emit
     `DTR04-RED: approved retirement paths or records remain`;
   - causal RED
     `DTR08-COMP-002 consumers import the shared recording overlay before facade retirement`,
     requiring the exact shared import directive in the production consumer and
     both test consumers and rejecting the old facade URI in those files. Its
     causal import assertion must emit
     `DTR08-COMP-002-RED: legacy recording overlay imports remain`;
   - GREEN sentinel `DTR-04 preserves owner-gated group and posts candidates`,
     requiring both deferred files and their exact manifest owner/condition
     values.
   Build the legacy wrapper path and import URI from split source literals in
   both new policy tests so the roadmap's exact unanchored `rg` command does not
   self-match the test source. Avoid an absolute aggregate inventory count;
   assert the exact DTR-04 delta.
3. In `test/l10n/l10n_integrity_test.dart`, add causal RED
   `DTR-04 retired settings keys are absent from every locale and generated API`.
   It must reject all three retired keys in every ARB catalog and generated API,
   while requiring both live title keys. Its causal absence assertion must emit
   `DTR04-L10N-RED: retired settings keys remain`. Inspect only ARB/generated
   declaration files; never include the policy test source that necessarily
   names the keys.
4. In `compose_area_test.dart`, import the shared `RecordingOverlay` directly
   and add GREEN sentinel
   `DTR08-COMP-002 shared recording overlay keeps elapsed amplitudes and cancel wiring`.
   Give `buildVoiceWidget` an amplitude-values input; inspect the rendered
   shared widget and assert the exact elapsed duration, amplitude list, and
   cancel callback. Run it green on HEAD before changing production.
5. Run every causal test/source proof named in the Test Contract on HEAD and
   record the documented non-zero reasons. Run the deferred-owner and active UI
   sentinels green. Require the facade to be the exact one-line shared export,
   both compatibility records to exist, and both shared UI files to be clean.
   Snapshot hashes for the shared UI files, `ComposeArea` with either recording
   import directive normalized away, and the already-direct Posts/performance
   importer files. Stop-if: a removal proof is already green, a deferred
   sentinel is red, a candidate has a new importer, or either shared UI file is
   dirty.
6. DTR08-COMP-002 checkpoint A — change only the production import in
   `compose_area.dart`. Keep the facade, both manifest records, and both test
   imports intact. Prove the exact shared directive in `compose_area.dart`, zero
   old-path matches under `lib`, and the new ComposeArea property sentinel plus
   named wired recording sentinels green. On any failure, restore only the
   production import and stop with the wrapper still present.
7. DTR08-COMP-002 checkpoint B1 — retarget only the two test imports. With the
   facade and both manifest records still present, require the exact shared
   directive independently in all three consumer files, run the roadmap-exact
   zero-old-path command over `lib test`, run the new migration policy test, and
   run the full three-file DTR08 parity command green. Recheck that both shared
   UI files, normalized `ComposeArea`, and the already-direct importers retain
   their baseline hashes. Append a timestamped Execution Progress row containing
   the facade hash, both manifest-record counts, exact source-proof exit status,
   and full parity result. Checkpoint B2 cannot start until that
   wrapper-present record exists; a final diff is not a substitute.
8. DTR08-COMP-002 checkpoint B2 — only after B1, delete the one-line facade and
   remove `compatibility.recording-overlay-export` from both
   `requiredRestrictedRoots` and `restrictedRoots`. Prove facade/records absent,
   rerun the migration policy and full three-file parity command, and leave the
   shared UI sources untouched.
9. Delete only the other seven approved production paths and four SUT-only tests
   in the Scope Contract. Reconcile their exact declaration records and
   canonical-candidate expectations; leave both downstream-deferred records
   byte-for-byte equivalent in owner and condition.
10. Remove the three orphan l10n keys from `app_en.arb`, `app_ar.arb`, and
   `app_de.arb`; run `flutter gen-l10n`; verify the live title getters remain.
11. Remove the four retired test entries from the current codebase test inventory
    and rewrite only the four stale comments named in scope.
12. Run focused GREEN and preservation commands, then `runtime-roots`,
    `completeness-check`, the affected curated gates (`1to1`, `feed`, `groups`),
    `feature-host-all`, and the strict analyzer. Re-run the DTR08 full three-file
    command and every recording no-delta hash at final closure. No new manual
    array registration is required.
13. After the coherent app-owned deletion, run
    `./graphify-arch/refresh_arch_graph.sh --incremental` exactly once. Inspect
    `git diff --name-status` against the pre-execution snapshot and confirm that
    deleted paths are exactly the twelve-path allowlist and both deferred files
    remain.

## Rollback

- Before DTR08 checkpoint B2, a parity or import failure leaves the wrapper and
  both manifest records present; restore only the affected import directive(s)
  and stop.
- After B2, restore the one-line facade and both
  `compatibility.recording-overlay-export` manifest records first. Verify the
  wrapper exists before optionally restoring any old import. Direct shared
  imports are themselves safe and need not be rolled back merely to restore
  compatibility.
- Reverse the remaining DTR-04 diff as one atomic unit: restore the other seven
  production files and four deleted tests; restore the three ARB keys and
  regenerate l10n; restore runtime inventory declarations/test expectations,
  current test-inventory entries, and rewritten comments.
- Do not roll back or rewrite the pre-existing Wave 0/DTR-03 working-tree
  changes.
- No user-data, database, native, wire, or package rollback exists because this
  plan changes none of those boundaries.

## Risks And Blind Spots

- A zero-import leaf could still be a manually rooted surface -> TC-DTR04-01
  through TC-DTR04-07 plus TC-DTR04-08A/B combine exact runtime-inventory
  removal with live replacement tests; execution stops on any new importer or
  root evidence.
- A final zero-import diff cannot prove that consumers moved before the facade
  disappeared -> checkpoint B1 records the exact roadmap search, three exact
  shared directives, both compatibility records, the still-present facade, and
  the full recording parity command before checkpoint B2 may delete anything.
- A direct import could accidentally be paired with a recording UI rewrite ->
  both shared media sources must start clean and retain their exact baseline
  hashes through checkpoints A, B1, B2, and closure; the ComposeArea property
  sentinel pins elapsed, amplitude, and cancel arguments.
- Posts or the performance harness could be swept despite already using the
  shared overlay -> both existing direct imports are outside the three-file
  retarget allowlist and any change to either stops execution.
- A failed retirement could be made unrecoverable by restoring old imports
  before the facade -> rollback restores the one-line facade and both manifest
  records first, verifies the wrapper exists, and only then permits an old
  import to return.
- Generated l10n output could retain a retired API after ARB edits ->
  TC-DTR04-03/05 inspect every catalog and generated API after
  `flutter gen-l10n`.
- A broad search-and-delete could absorb neighboring DTR work -> the causal
  policy uses an exact twelve-path allowlist, TC-DTR04-09/10 require the two
  sensitive paths and manifest conditions to survive, and final
  `git diff --name-status` is compared with the dirty-tree snapshot.
- Aggregate inventory counts may move concurrently under DTR-03/DTR-05 ->
  assertions use exact path membership and the observed execution delta, not a
  hard-coded planning total.
- Lifecycle / derived-state durability: N/A — this is deletion-only; active
  screen lifecycle remains owned and exercised by the existing settings,
  identity, group, and conversation wired tests.
- Sibling-surface consistency: TC-DTR04-01 through TC-DTR04-07 plus
  TC-DTR04-08A/B cover the parallel live feed, group, settings, identity,
  compose, and recording surfaces plausibly affected by import/file deletion.
- Destructive-action side effects: after approval, the exact absence array
  proves all owner-approved removals, while TC-DTR04-09/10 and live-title
  assertions prove neighboring files/state were preserved.
- Invariant re-verification under new transitions: N/A — no new transition,
  self-heal, reset, or re-entry behavior is introduced.

## Gate Cadence

- Per-plan closure after approval: every causal policy/source proof; the
  wrapper-present DTR08 full three-file parity command and its post-deletion
  repeat; exact replacement/preservation tests; `runtime-roots`;
  `completeness-check`; curated `1to1`, `feed`, and `groups`; one justified
  `feature-host-all` sweep; strict analyzer; Graphify incremental refresh; diff
  hygiene.
- Do not run full `host-all` for this individual plan. Run
  `./scripts/run_host_test_gates.sh host-all` once after Wave 1
  (`DTR-03`, `DTR-04`, and `DTR-05` are terminal, plan-green, or explicitly
  owner-deferred under the roadmap), and once at final rollout/release closure.
- Shared tests outside feature/core globs:
  `test/unit/runtime_root_inventory_test.dart` and
  `test/l10n/l10n_integrity_test.dart` run by exact direct command. Migration
  `035`/`066` preservation tests also run directly; registration under the later
  aggregate host gate does not create a per-plan `core-host-all` obligation.

## Acceptance Gates

All commands are run from the repository root. Record exit status and semantic
result; do not substitute pinned aggregate test counts for zero failures.

```bash
set -euo pipefail

# Structural authorization precondition: exactly one well-formed Approved row
# for each domain. The direct sole-owner statement above establishes authority;
# verify that identity, evidence, and scope still match before continuing.
for dtr04_owner in Feed Groups Settings Conversation Identity
do
  dtr04_owner_row_count="$(
    awk -F'|' -v owner="$dtr04_owner" '
      $2 == " " owner " " { count++ }
      END { print count + 0 }
    ' Test-Flight-Improv/275-unused-visible-feature-leaves-removal-tdd-plan.md
  )"
  dtr04_approved_owner_row_count="$(
    awk -F'|' -v owner="$dtr04_owner" '
      $2 == " " owner " " &&
      length($4) > 2 && $4 != " — " &&
      $5 ~ /^ 20[0-9][0-9]-[0-9][0-9]-[0-9][0-9] $/ &&
      length($6) > 2 && $6 != " — " &&
      $7 == " Approved " { count++ }
      END { print count + 0 }
    ' Test-Flight-Improv/275-unused-visible-feature-leaves-removal-tdd-plan.md
  )"
  test "$dtr04_owner_row_count" -eq 1
  test "$dtr04_approved_owner_row_count" -eq 1
done

# Snapshot before execution; preserve unrelated Wave 0/DTR-03 changes.
git status --short

# The actual recording UI is an immutable baseline for this plan. Run the
# staged DTR08 commands below in one shell so this hash remains available.
test -z "$(
  git status --porcelain=v1 -- \
    lib/shared/widgets/media/recording_overlay.dart \
    lib/shared/widgets/media/amplitude_bars.dart
)"
dtr04_shared_ui_hashes="$(
  git hash-object \
    lib/shared/widgets/media/recording_overlay.dart \
    lib/shared/widgets/media/amplitude_bars.dart
)"
dtr04_compose_non_import_hash="$(
  rg -v \
    "^import 'package:flutter_app/(features/conversation/presentation/widgets|shared/widgets/media)/recording_overlay\\.dart';$" \
    lib/features/conversation/presentation/widgets/compose_area.dart |
    git hash-object --stdin
)"
dtr04_existing_direct_importer_hashes="$(
  git hash-object \
    lib/features/posts/presentation/widgets/compose_post_sheet.dart \
    integration_test/conversation_wired_subscription_performance_harness.dart
)"
dtr04_assert_recording_ui_unchanged() {
  test "$(
    git hash-object \
      lib/shared/widgets/media/recording_overlay.dart \
      lib/shared/widgets/media/amplitude_bars.dart
  )" = "$dtr04_shared_ui_hashes" || return 1
  test "$(
    rg -v \
      "^import 'package:flutter_app/(features/conversation/presentation/widgets|shared/widgets/media)/recording_overlay\\.dart';$" \
      lib/features/conversation/presentation/widgets/compose_area.dart |
      git hash-object --stdin
  )" = "$dtr04_compose_non_import_hash" || return 1
  test "$(
    git hash-object \
      lib/features/posts/presentation/widgets/compose_post_sheet.dart \
      integration_test/conversation_wired_subscription_performance_harness.dart
  )" = "$dtr04_existing_direct_importer_hashes" || return 1
}
for dtr04_existing_consumer in \
  lib/features/posts/presentation/widgets/compose_post_sheet.dart \
  integration_test/conversation_wired_subscription_performance_harness.dart
do
  rg -n \
    "^import 'package:flutter_app/shared/widgets/media/recording_overlay\\.dart';$" \
    "$dtr04_existing_consumer" || exit 1
done

# DTR08-COMP-002 baseline: exact one-line facade and exact manifest records exist.
test -f lib/features/conversation/presentation/widgets/recording_overlay.dart
test "$(
  awk 'END { print NR }' \
    lib/features/conversation/presentation/widgets/recording_overlay.dart
)" -eq 1
rg -n \
  "^export 'package:flutter_app/shared/widgets/media/recording_overlay\\.dart';$" \
  lib/features/conversation/presentation/widgets/recording_overlay.dart
dtr04_facade_hash="$(
  git hash-object \
    lib/features/conversation/presentation/widgets/recording_overlay.dart
)"
jq -e '
  [.requiredRestrictedRoots[] |
    select(.id == "compatibility.recording-overlay-export")] ==
      [{
        "id": "compatibility.recording-overlay-export",
        "rootKind": "compatibility"
      }] and
  [.restrictedRoots[] |
    select(.id == "compatibility.recording-overlay-export")] ==
      [{
        "id": "compatibility.recording-overlay-export",
        "path": "lib/features/conversation/presentation/widgets/recording_overlay.dart",
        "rootKind": "compatibility",
        "owner": "conversation",
        "reason": "A production compatibility facade exports the shared widget.",
        "condition": "Remove only after every production importer migrates.",
        "evidence": [{
          "kind": "dart-directive",
          "source": "lib/features/conversation/presentation/widgets/recording_overlay.dart",
          "target": "lib/shared/widgets/media/recording_overlay.dart"
        }]
      }]
' tool/runtime_roots/runtime_roots.json
dtr04_compatibility_records_hash="$(
  jq -cS '[
    [.requiredRestrictedRoots[] |
      select(.id == "compatibility.recording-overlay-export")],
    [.restrictedRoots[] |
      select(.id == "compatibility.recording-overlay-export")]
  ]' tool/runtime_roots/runtime_roots.json |
    git hash-object --stdin
)"
dtr04_assert_compatibility_intact() {
  test -f lib/features/conversation/presentation/widgets/recording_overlay.dart
  test "$(
    awk 'END { print NR }' \
      lib/features/conversation/presentation/widgets/recording_overlay.dart
  )" -eq 1
  rg -q \
    "^export 'package:flutter_app/shared/widgets/media/recording_overlay\\.dart';$" \
    lib/features/conversation/presentation/widgets/recording_overlay.dart
  test "$(
    git hash-object \
      lib/features/conversation/presentation/widgets/recording_overlay.dart
  )" = "$dtr04_facade_hash"
  test "$(
    jq -cS '[
      [.requiredRestrictedRoots[] |
        select(.id == "compatibility.recording-overlay-export")],
      [.restrictedRoots[] |
        select(.id == "compatibility.recording-overlay-export")]
    ]' tool/runtime_roots/runtime_roots.json |
      git hash-object --stdin
  )" = "$dtr04_compatibility_records_hash"
}
dtr04_assert_compatibility_intact

# After approval and after adding the causal tests, expect each RED command to
# exit non-zero for the stated legacy path/key reason. The explicit conditionals
# preserve fail-fast execution while accepting only the planned RED disposition.
if dtr04_absence_red_output="$(
  flutter test --no-pub test/unit/runtime_root_inventory_test.dart \
    --plain-name 'DTR-04 retires approved visible leaves and obsolete SUT-only tests' \
    2>&1
)"
then
  printf 'ERROR: DTR-04 absence policy was unexpectedly GREEN on HEAD.\n' >&2
  exit 1
else
  printf '%s\n' "$dtr04_absence_red_output"
  rg -F 'DTR04-RED: approved retirement paths or records remain' \
    <<<"$dtr04_absence_red_output"
  printf 'EXPECTED RED: approved retirement paths/records still exist.\n'
fi
if dtr04_import_red_output="$(
  flutter test --no-pub test/unit/runtime_root_inventory_test.dart \
    --plain-name 'DTR08-COMP-002 consumers import the shared recording overlay before facade retirement' \
    2>&1
)"
then
  printf 'ERROR: DTR08 import-migration policy was unexpectedly GREEN on HEAD.\n' >&2
  exit 1
else
  printf '%s\n' "$dtr04_import_red_output"
  rg -F 'DTR08-COMP-002-RED: legacy recording overlay imports remain' \
    <<<"$dtr04_import_red_output"
  printf 'EXPECTED RED: three consumers still import the facade.\n'
fi
if dtr04_l10n_red_output="$(
  flutter test --no-pub test/l10n/l10n_integrity_test.dart \
    --plain-name 'DTR-04 retired settings keys are absent from every locale and generated API' \
    2>&1
)"
then
  printf 'ERROR: DTR-04 l10n policy was unexpectedly GREEN on HEAD.\n' >&2
  exit 1
else
  printf '%s\n' "$dtr04_l10n_red_output"
  rg -F 'DTR04-L10N-RED: retired settings keys remain' \
    <<<"$dtr04_l10n_red_output"
  printf 'EXPECTED RED: three retired settings keys still exist.\n'
fi
if rg -n \
  "features/conversation/presentation/widgets/recording_overlay\\.dart" \
  lib test
then
  printf 'EXPECTED RED: roadmap negated legacy-path proof has matches.\n'
else
  printf 'ERROR: roadmap legacy-path proof was unexpectedly GREEN on HEAD.\n' >&2
  exit 1
fi
if rg -n \
  -e "amplitude_bars_test\\.dart" \
  -e "settings_peer_id_card_test\\.dart" \
  -e "posts_nearby_settings_card_test\\.dart" \
  -e "identity_loading_card_test\\.dart" \
  Test-Flight-Improv/codebase-test-inventory.md
then
  printf 'EXPECTED RED: retired test inventory entries still exist.\n'
else
  printf 'ERROR: test-inventory proof was unexpectedly GREEN on HEAD.\n' >&2
  exit 1
fi
if rg -n "FeedRingAvatar" \
  test/features/feed/presentation/widgets/letter_card_one_to_one_test.dart \
  test/features/feed/presentation/widgets/letter_card_group_test.dart \
  test/features/feed/presentation/widgets/letter_card_system_test.dart
then
  printf 'EXPECTED RED: stale FeedRingAvatar comments still exist.\n'
else
  printf 'ERROR: feed-comment proof was unexpectedly GREEN on HEAD.\n' >&2
  exit 1
fi
if rg -n "SettingsPeerIdCard" \
  lib/features/settings/presentation/screens/settings_screen.dart
then
  printf 'EXPECTED RED: stale SettingsPeerIdCard comment still exists.\n'
else
  printf 'ERROR: settings-comment proof was unexpectedly GREEN on HEAD.\n' >&2
  exit 1
fi

# GREEN baseline before any production import/deletion.
flutter test --no-pub test/unit/runtime_root_inventory_test.dart \
  --plain-name 'DTR-04 preserves owner-gated group and posts candidates'
flutter test --no-pub \
  test/features/conversation/presentation/widgets/compose_area_test.dart \
  --plain-name 'DTR08-COMP-002 shared recording overlay keeps elapsed amplitudes and cancel wiring'
flutter test --no-pub \
  test/features/conversation/presentation/widgets/recording_overlay_test.dart \
  test/features/conversation/presentation/widgets/compose_area_test.dart \
  test/features/conversation/presentation/screens/conversation_wired_test.dart

# Checkpoint A, after changing only compose_area.dart: the production consumer
# is shared-direct, both test consumers are intentionally still legacy-direct,
# and the facade plus both records remain present and recoverable.
dtr04_assert_compatibility_intact
rg -n \
  "^import 'package:flutter_app/shared/widgets/media/recording_overlay\\.dart';$" \
  lib/features/conversation/presentation/widgets/compose_area.dart
for dtr04_test_consumer in \
  test/features/conversation/presentation/widgets/recording_overlay_test.dart \
  test/features/conversation/presentation/screens/conversation_wired_test.dart
do
  rg -n \
    "^import 'package:flutter_app/features/conversation/presentation/widgets/recording_overlay\\.dart';$" \
    "$dtr04_test_consumer" || exit 1
done
! rg -n \
  "features/conversation/presentation/widgets/recording_overlay\\.dart" \
  lib
flutter test --no-pub \
  test/features/conversation/presentation/widgets/compose_area_test.dart \
  --plain-name 'DTR08-COMP-002 shared recording overlay keeps elapsed amplitudes and cancel wiring'
flutter test --no-pub \
  test/features/conversation/presentation/widgets/recording_overlay_test.dart \
  test/features/conversation/presentation/widgets/compose_area_test.dart
flutter test --no-pub \
  test/features/conversation/presentation/screens/conversation_wired_test.dart \
  --plain-name 'recording ticks update composer without rebuilding header or message list'
flutter test --no-pub \
  test/features/conversation/presentation/screens/conversation_wired_test.dart \
  --plain-name 'recorder auto-stop resets the composer recording state'
dtr04_assert_recording_ui_unchanged

# Checkpoint B1, after retargeting both test imports but BEFORE deleting the
# facade or either manifest record. Archive this wrapper-present command record.
dtr04_assert_compatibility_intact
printf 'facade-hash=%s\n' "$dtr04_facade_hash"
printf 'compatibility-records-hash=%s\n' "$dtr04_compatibility_records_hash"
jq -c '{
  requiredRestrictedRoots:
    ([.requiredRestrictedRoots[] |
      select(.id == "compatibility.recording-overlay-export")] | length),
  restrictedRoots:
    ([.restrictedRoots[] |
      select(.id == "compatibility.recording-overlay-export")] | length)
}' tool/runtime_roots/runtime_roots.json
for dtr04_consumer in \
  lib/features/conversation/presentation/widgets/compose_area.dart \
  test/features/conversation/presentation/widgets/recording_overlay_test.dart \
  test/features/conversation/presentation/screens/conversation_wired_test.dart
do
  rg -n \
    "^import 'package:flutter_app/shared/widgets/media/recording_overlay\\.dart';$" \
    "$dtr04_consumer" || exit 1
done
! rg -n "features/conversation/presentation/widgets/recording_overlay\\.dart" lib test
flutter test --no-pub test/unit/runtime_root_inventory_test.dart \
  --plain-name 'DTR08-COMP-002 consumers import the shared recording overlay before facade retirement'
flutter test --no-pub \
  test/features/conversation/presentation/widgets/recording_overlay_test.dart \
  test/features/conversation/presentation/widgets/compose_area_test.dart \
  test/features/conversation/presentation/screens/conversation_wired_test.dart
dtr04_assert_recording_ui_unchanged

# Checkpoint B2 is permitted only after B1 is recorded green. Delete the facade
# and both compatibility records, then repeat migration and full UI parity.
test ! -e lib/features/conversation/presentation/widgets/recording_overlay.dart
jq -e '
  ([.requiredRestrictedRoots[] |
    select(.id == "compatibility.recording-overlay-export")] | length) == 0 and
  ([.restrictedRoots[] |
    select(.id == "compatibility.recording-overlay-export")] | length) == 0
' tool/runtime_roots/runtime_roots.json
! rg -n "features/conversation/presentation/widgets/recording_overlay\\.dart" lib test
for dtr04_consumer in \
  lib/features/conversation/presentation/widgets/compose_area.dart \
  test/features/conversation/presentation/widgets/recording_overlay_test.dart \
  test/features/conversation/presentation/screens/conversation_wired_test.dart
do
  rg -n \
    "^import 'package:flutter_app/shared/widgets/media/recording_overlay\\.dart';$" \
    "$dtr04_consumer" || exit 1
done
flutter test --no-pub test/unit/runtime_root_inventory_test.dart \
  --plain-name 'DTR08-COMP-002 consumers import the shared recording overlay before facade retirement'
flutter test --no-pub \
  test/features/conversation/presentation/widgets/recording_overlay_test.dart \
  test/features/conversation/presentation/widgets/compose_area_test.dart \
  test/features/conversation/presentation/screens/conversation_wired_test.dart
dtr04_assert_recording_ui_unchanged

# Complete the other approved removals and regenerate after the ARB edits.
flutter gen-l10n

# Final causal GREEN and inventory admission.
flutter test --no-pub test/unit/runtime_root_inventory_test.dart \
  --plain-name 'DTR-04 retires approved visible leaves and obsolete SUT-only tests'
flutter test --no-pub test/unit/runtime_root_inventory_test.dart \
  --plain-name 'DTR08-COMP-002 consumers import the shared recording overlay before facade retirement'
flutter test --no-pub test/l10n/l10n_integrity_test.dart \
  --plain-name 'DTR-04 retired settings keys are absent from every locale and generated API'
./scripts/run_test_gates.sh runtime-roots
./scripts/run_test_gates.sh completeness-check

# Exact deletion allowlist: expect every test to see an absent path.
for dtr04_path in \
  lib/features/feed/presentation/widgets/feed_ring_avatar.dart \
  lib/features/groups/presentation/widgets/group_compose_area.dart \
  lib/features/settings/presentation/widgets/settings_move_account_card.dart \
  lib/features/conversation/presentation/widgets/amplitude_bars.dart \
  lib/features/settings/presentation/widgets/settings_peer_id_card.dart \
  lib/features/settings/presentation/widgets/posts_nearby_settings_card.dart \
  lib/features/identity/presentation/widgets/identity_loading_card.dart \
  lib/features/conversation/presentation/widgets/recording_overlay.dart \
  test/features/conversation/presentation/widgets/amplitude_bars_test.dart \
  test/features/settings/presentation/widgets/settings_peer_id_card_test.dart \
  test/features/settings/presentation/widgets/posts_nearby_settings_card_test.dart \
  test/features/identity/presentation/widgets/identity_loading_card_test.dart
do
  test ! -e "$dtr04_path" || exit 1
done

# Import/copy proof: exact roadmap search and exact directives in every consumer.
! rg -n "features/conversation/presentation/widgets/recording_overlay\\.dart" lib test
for dtr04_consumer in \
  lib/features/conversation/presentation/widgets/compose_area.dart \
  test/features/conversation/presentation/widgets/recording_overlay_test.dart \
  test/features/conversation/presentation/screens/conversation_wired_test.dart
do
  rg -n \
    "^import 'package:flutter_app/shared/widgets/media/recording_overlay\\.dart';$" \
    "$dtr04_consumer" || exit 1
done
! rg -n \
  '"settings_move_account_(desc|action)"[[:space:]]*:|"settings_peer_id_desc"[[:space:]]*:|String get settings_move_account_(desc|action)|String get settings_peer_id_desc' \
  lib/l10n/app_*.arb lib/l10n/app_localizations*.dart
rg -n "settings_move_account_title|settings_peer_id_title" \
  lib/l10n/app_*.arb lib/l10n/app_localizations*.dart
dtr04_assert_recording_ui_unchanged
test -z "$(
  git status --porcelain=v1 -- \
    lib/shared/widgets/media/recording_overlay.dart \
    lib/shared/widgets/media/amplitude_bars.dart
)"

# Current inventory/comments: all searches expect zero matches.
! rg -n \
  "amplitude_bars_test\\.dart|settings_peer_id_card_test\\.dart|posts_nearby_settings_card_test\\.dart|identity_loading_card_test\\.dart" \
  Test-Flight-Improv/codebase-test-inventory.md
! rg -n "FeedRingAvatar" \
  test/features/feed/presentation/widgets/letter_card_one_to_one_test.dart \
  test/features/feed/presentation/widgets/letter_card_group_test.dart \
  test/features/feed/presentation/widgets/letter_card_system_test.dart
! rg -n "SettingsPeerIdCard" \
  lib/features/settings/presentation/screens/settings_screen.dart

# Feed replacement sentinels; expect exit 0 and zero failed tests.
flutter test --no-pub \
  test/features/feed/presentation/widgets/letter_card_one_to_one_test.dart \
  test/features/feed/presentation/widgets/letter_card_group_test.dart \
  test/features/feed/presentation/widgets/letter_card_system_test.dart

# Group replacement sentinels; expect exit 0 and zero failed tests.
flutter test --no-pub \
  test/features/groups/presentation/group_conversation_screen_test.dart \
  test/features/groups/presentation/group_conversation_wired_test.dart

# Settings replacement sentinels; expect exit 0 and zero failed tests.
flutter test --no-pub \
  test/features/settings/presentation/screens/settings_screen_test.dart \
  test/features/settings/presentation/screens/settings_wired_test.dart \
  test/features/settings/presentation/screens/settings_wired_posts_nearby_test.dart

# Identity replacement sentinels; expect exit 0 and zero failed tests.
flutter test --no-pub \
  test/features/identity/presentation/screens/identity_progress_screen_test.dart \
  test/features/identity/presentation/screens/identity_choice_wired_test.dart

# Full DTR08 recording parity at closure; this is the roadmap-exact file set.
flutter test --no-pub \
  test/features/conversation/presentation/widgets/recording_overlay_test.dart \
  test/features/conversation/presentation/widgets/compose_area_test.dart \
  test/features/conversation/presentation/screens/conversation_wired_test.dart

# Deferred group-cursor boundary; expect exit 0 and named tests selected.
flutter test --no-pub test/core/database/migrations/066_group_sync_receipts_test.dart \
  --plain-name 'PREREQ-GROUP-SYNC-RECEIPTS creates cursor and receipt tables idempotently'
flutter test --no-pub test/core/database/helpers/group_sync_receipts_db_helpers_test.dart \
  --plain-name 'PREREQ-GROUP-SYNC-RECEIPTS persists cursor and receipts across reopen'
flutter test --no-pub \
  test/features/groups/domain/repositories/group_message_repository_impl_test.dart \
  --plain-name 'loads durable cursor and receipts through repository'
flutter test --no-pub \
  test/features/groups/application/drain_group_offline_inbox_use_case_test.dart \
  --plain-name 'PREREQ-GROUP-SYNC-RECEIPTS loads durable cursor and advances only after page apply'
flutter test --no-pub \
  test/features/groups/application/drain_group_offline_inbox_use_case_test.dart \
  --plain-name 'PREREQ-GROUP-SYNC-RECEIPTS failed page commit does not advance cursor or save receipts'

# Deferred post boundary; expect exit 0 and named tests selected.
flutter test --no-pub \
  test/features/posts/improvement/post_pass_retry_integration_test.dart \
  --plain-name 'pass retry uses the post delivery retrier, preserves explicit recipient plus author notification, and does not duplicate pass records'
flutter test --no-pub \
  test/core/database/migrations/035_posts_repost_delivery_state_test.dart \
  --plain-name 'adds repost delivery ownership to post_recipients and migrates legacy pass outbox rows'

# Affected curated and family gates; expect exit 0 and zero failed tests.
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh feed
./scripts/run_test_gates.sh groups
./scripts/run_host_test_gates.sh feature-host-all

# Static/hygiene closure; expect no new analyzer findings or whitespace errors.
./scripts/check_flutter_analyze_strict.sh
./graphify-arch/refresh_arch_graph.sh --incremental
git diff --check
git diff --name-status
```

## Execution Interpretation And Done Criteria

- Expected RED after authorization re-grounding: the DTR08 migration policy
  fails because the
  production and two test consumers still import the facade; the broader
  runtime-inventory test fails because the twelve
  owner-approved-at-execution paths and compatibility records exist; the l10n
  test fails because the three retired keys exist. Any different failure is not
  the required causal RED.
- DTR08 transition interpretation:
  - checkpoint A is green only with the production import shared-direct, both
    test imports still facade-direct, the wrapper/records present, and recording
    sentinels green;
  - checkpoint B1 is green only with all three imports shared-direct, the exact
    roadmap search empty, the wrapper/records still present, the shared UI
    hashes unchanged, and the full three-file parity command green;
  - checkpoint B2 is authorized only by a recorded B1; it is green only when
    the wrapper and both records are then absent and every B1 migration/parity
    property remains green.
- Green sentinel: the owner-gated policy test, migration `035`/`066`, group
  durable-cursor tests, post retry test, and all active replacement widget tests
  pass before/after as applicable. The shared recording overlay and amplitude
  implementation remain byte-identical to their clean execution baseline.
- Pre-existing dirty tree / known failure: accepted uncommitted DTR-01/DTR-02
  Wave 0 work and the concurrent DTR-03 plan are baseline, not DTR-04 output.
  The real runtime-root admission test was green during planning. Re-snapshot
  rather than overwriting or attributing those changes.
- Authorization status: resolved. The sole repository owner directly approved
  all five bounded rows on 2026-07-25. Scope expansion, duplicate/malformed
  rows, or changed ownership returns the plan to `evidence-gated`.
- Environment blocker: none expected at execution; host-only tests and local
  SQLite FFI regression fixtures need no device, simulator, relay, or user
  interaction. They make no SQLCipher durability or encryption claim.
- Scope drift: any new importer/root for a proposed leaf, edit to the two
  deferred paths/conditions, DB/native/wire/package change, removal outside the
  twelve-path allowlist, or failure in a prerequisite/adjacent behavior that is
  not caused by DTR-04 stops closure and requires replanning.

- [x] Every contract row has its named test/proof, HEAD disposition, mutation,
      and registration recorded.
- [x] Every causal test/source proof is observed RED for the documented reason
      before its production change and GREEN after it; representative restore
      mutations re-red.
- [x] DTR08 checkpoints A and B1 are recorded while the exact one-line wrapper
      and both compatibility records still exist; B1 includes the roadmap-exact
      zero-import command and full three-file parity result.
- [x] Only after B1, the wrapper and both manifest records are deleted; the
      migration policy and full three-file parity command pass again at B2 and
      final closure.
- [x] Exactly the twelve owner-approved-at-execution paths are deleted; the old
      recording path has zero `lib test` matches; all three consumer files have
      the exact direct shared import; Posts and the performance-harness imports
      are unchanged.
- [x] `lib/shared/widgets/media/recording_overlay.dart` and
      `lib/shared/widgets/media/amplitude_bars.dart` remain clean and
      byte-identical to baseline; elapsed, amplitude, cancel, tick, and
      auto-stop behavior remain green.
- [x] The two deferred files and their exact manifest owners/conditions remain.
- [x] Retired l10n keys and test-inventory entries are absent; live title keys
      remain.
- [x] All five domain approval rows record the sole repository owner's direct
      authorization before implementation.
- [x] Focused sentinels, runtime/completeness checks, three curated gates,
      `feature-host-all`, and strict analyzer pass with zero failures/new issues.
- [x] No manual harness registration, migration, device, native, relay, wire,
      persistence, package, or visible behavior change was introduced.
- [x] Graphify is refreshed once; `git diff --check` is clean; the Scope
      Contract and dirty-tree boundary are respected.

## Handoff

- First causal RED command after the required source re-grounding:
  `flutter test --no-pub test/unit/runtime_root_inventory_test.dart --plain-name 'DTR08-COMP-002 consumers import the shared recording overlay before facade retirement'`.
- Preservation command:
  `flutter test --no-pub test/features/conversation/presentation/widgets/recording_overlay_test.dart test/features/conversation/presentation/widgets/compose_area_test.dart test/features/conversation/presentation/screens/conversation_wired_test.dart`.
- Manual registration: none. The new runtime policy tests enter the existing
  `runtime-roots` file/gate; the l10n test is discovered by aggregate `host-all`
  and run directly per-plan; feature/core tests retain AUTO registration and
  existing curated membership.
- Migration: none. Migrations `035` and `066` are preservation sentinels only
  and must not change.
- Boundary closure: host-only; widget/local fakes plus existing SQLite FFI
  regression sentinels are sufficient because no persistence implementation
  changes and no SQLCipher durability/encryption claim is made.
- Authorization evidence: resolved by the direct sole-owner statement recorded
  in all five rows. The group cursor model and post helper remain separate
  explicit downstream deferrals, not evidence gaps to resolve inside DTR-04.

## Reviewer Findings

- Review date / method: 2026-07-25, `$tdd-review`, Graphify review profile plus
  exact current-source, manifest, test-registration, and roadmap verification.
- Verdict: **ready**. The original review was `not-ready` solely because five
  owner-domain approvals were open; the requesting user's direct affirmation of
  sole repository ownership now authorizes all five bounded rows. Classification
  is `execution-ready`.
- Disposition: re-ground current source/import/root evidence, then execute the
  fail-fast contract if the evidence remains stable.
- Corrected before disposition:
  - split the old combined recording case into production-first checkpoint A,
    wrapper-present checkpoint B1, and facade-retirement checkpoint B2;
  - adopted `DTR08-COMP-002`'s exact unanchored zero-import proof and full
    three-file parity command;
  - added exact shared-directive proofs, split-literal policy-test guidance,
    immutable shared-UI hashes, a ComposeArea property sentinel, and
    reverse-order recovery;
  - made the staged shell fail-fast while matching each expected RED to its
    causal diagnostic, and pinned the exact facade plus full content of both
    wrapper-present manifest records;
  - made authorization require exactly one total row and one structurally valid
    `Approved` row per domain, including approver identity, date, and evidence
    reference, while retaining direct-authority verification.
- Lens result after correction and authorization: L1 contract closure, L2 scope
  boundaries, L3 failure/recovery, L4 verification integrity, and L5
  operability are clear.
- Evergreen audit: B-3 scoped mutation, B-4 error/recovery, B-5 derived
  recording state, and B-9 destructive ordering are now explicit. B-1, B-6,
  B-8, and B-10 are not applicable to this host-only source/API deletion; no
  unresolved B-2 or B-7 identity/sibling delta remains because the facade
  exports the exact shared symbol and the shared UI is a no-edit surface.
- Review baseline evidence: the combined
  `recording_overlay_test.dart`/`compose_area_test.dart` run passed 49/49; the
  wired tick and auto-stop selectors each passed. These establish the current
  UI baseline but do not waive the execution-time pre-delete and post-delete
  repeats.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-07-25 | ready before execution | Plan 275; roadmap summary | sole-owner authorization recorded; structural approval gate expected green | source/test contract and five bounded approvals complete | none; stop only if re-grounding finds drift | run `--ensure-fresh` Graphify/importer/root census, snapshot the dirty tree, then begin the first causal RED |
| 2026-07-25T13:04:04+02:00 | DTR08 checkpoint B1 | `compose_area.dart`; `recording_overlay_test.dart`; `conversation_wired_test.dart`; facade and manifest records | exact zero-old-import proof exit 0; full three-file parity 180/180 green | facade hash `31ac89f37c2bdc1339d08fabceeaca4595c1e860`; required record count 1; restricted record count 1; shared UI and existing direct-importer hashes unchanged | checkpoint B1 green with wrapper and both records present | proceed to B2 facade/record retirement |
| 2026-07-25T14:10:00+02:00 | plan closure | twelve retired paths; direct imports; runtime/l10n policy; replacement/deferred surfaces; gates | causal policies green; runtime-roots 16/16 and trustworthy/no-drift under isolated final-tree index; completeness 1354/1354; `1to1`, `feed`, `groups`, 821-file `feature-host-all`, and strict analysis green | shared recording sources and existing Posts/performance direct importers retain baseline hashes; exact deferred owner/condition rows remain; Graphify incremental refresh reports 12 deletions | Plan 275 complete with no scope blocker | Wave 1 aggregate `host-all` remains deferred to wave closure by cadence policy |
