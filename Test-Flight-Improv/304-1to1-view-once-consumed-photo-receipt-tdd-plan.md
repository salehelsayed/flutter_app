# 304 - 1:1 View-Once Consumed Photo Receipt

Status: completed
Type: Modification
Spec: free-text intent with reference screenshot — user request 2026-07-30
Classification: implementation-ready
Closure tier: host
Review verdict: ready after in-place `$tdd-review` corrections (2026-07-30)

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-30 | Evidence Collector | `direct_private_media_viewer.dart`, `conversation_screen.dart`, `conversation_message.dart`, owning widget tests, `run_test_gates.sh`, Plan 303 | The consumed receipt is a presentation seam; secure cleanup deliberately removes attachment kind, while completed Plan 303 makes newly composed direct view-once media image-only | Define the truthful fixed-label compatibility boundary |
| 2026-07-30 | Planner | Current source plus two focused baseline probes | Render a mode-scoped consumed branch as eye-off + localized `Photo`; remove only its inline action row; preserve other private terminal states and existing lifecycle | Hand off six-row host contract |
| 2026-07-30 | TDD Reviewer | Review-profile graph query, sole production caller, constructor census, lifecycle mode predicate, owning tests, and gate implementation | Core bet confirmed. Apply only five material deltas: stage required-mode plumbing before behavioral RED, add a protected-consumed caller sentinel, prove bounded adjacency, correct registration language, and drop the unrelated restart-DB command | Execute revised contract |

## Problem And Evidence

- Behavior to improve: after either participant has exhausted a direct 1:1
  view-once photo, the terminal bubble currently shows a vertically stacked
  eye-off icon, generic `Private media`/lifecycle copy, and inline Reply, Info,
  and Delete buttons. The requested receipt is only the eye-off icon with
  `Photo` beside it.
- Impact: the current bubble is visually heavy and presents actions/copy the
  user explicitly does not want on a consumed one-view receipt.
- Confirmed current gap: `DirectPrivateMediaTerminalPlaceholder.build` at
  `lib/features/conversation/presentation/screens/direct_private_media_viewer.dart:385-443`
  derives generic/direction-specific copy, conditionally adds the `Private
  media` title, then always builds the three-button action row. The production
  call site at
  `lib/features/conversation/presentation/screens/conversation_screen.dart:1063-1094`
  supplies those callbacks for both consumed and expired terminal states.
- Confirmed mode seam: the parent retains `PrivateMediaMode` after cleanup, so
  the call site can pass `message.privateMediaMode` and the widget can select
  only `viewOnce + consumed`. The attachment list cannot supply a truthful
  terminal kind: `ConversationMessage.mustClearTransientMedia` at
  `lib/features/conversation/domain/models/conversation_message.dart:308-312`
  clears every terminal projection, enforced during load and wired upsert at
  `load_conversation_use_case.dart:90-113` and
  `conversation_wired.dart:2253-2263,5361-5363`.
- Confirmed label source: the existing localized
  `AppLocalizations.shared_media_kind_photo` is exactly `Photo` in English and
  already has Arabic/German values
  (`lib/l10n/app_en.arb:1154`, `app_ar.arb:1105`, `app_de.arb:1105`);
  no ARB or generated-localization edit is required.
- Confirmed upstream dependency: completed Plan 303 constrains new direct
  view-once composition to images at
  `lib/core/media/private_media_policy.dart:300-307`. The fixed terminal word
  is therefore the current product label, not a reconstruction of deleted
  attachment metadata. The pre-304 baseline is the current workspace (Git
  `HEAD` plus the completed but uncommitted Plan-303 changes), not clean Git
  `HEAD`; execution must preserve and record that dependency.
- Existing coverage: the passing baseline
  `direct_private_media_viewer_test.dart::sender-consumed terminal is generic
  after attachment cleanup` explicitly locks the unwanted copy; the passing
  `direct_private_media_card_test.dart::terminal and unsupported cards keep
  action rows in-bubble` explicitly locks the unwanted inline buttons. Both
  tests were run during planning and passed on the current workspace.
- Missing coverage: no test requires a horizontal icon/word layout, mode-scopes
  the minimal branch, or proves the consumed view-once receipt has no inline
  action controls in both the live row and lifted context snapshot.
- Confirmed preservation surface: whole-message long press and swipe-to-reply
  wrap the `LetterCard` outside the private content slot at
  `conversation_screen.dart:1364-1405`; the plain context menu still derives
  Reply/Delete at `:1607-1675,:1728-1735`.
- Refuted findings:
  - “The original photo/video kind can be read after consumption” is refuted by
    the terminal media-clearing boundaries above.
  - “Removing inline Reply/Delete makes those actions unreachable” is refuted
    by the outer swipe and whole-message long-press surfaces. Attachmentless
    terminal Info has no equivalent context-menu surface and is intentionally
    removed by this request.
  - “A new localization key is required for `Photo`” is refuted by the existing
    exact localized key.
- Unresolved findings: none. The legacy view-once-video display difference is
  accepted explicitly below rather than represented as exact-kind behavior.
- Affected production files:
  - `lib/features/conversation/presentation/screens/direct_private_media_viewer.dart`
  - `lib/features/conversation/presentation/screens/conversation_screen.dart`
- Affected test/gate files:
  - `test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart`
  - `test/features/conversation/presentation/screens/direct_private_media_card_test.dart`
  - the preservation-only composer test already registered in
    `scripts/run_test_gates.sh`.

## Graph Grounding Snapshot

- Graph fingerprint / freshness:
  `9e089faf3622abdb`; `stale:ios/Flutter/flutter_export_environment.sh`.
  The stale path is generated iOS environment state outside this host-widget
  seam; every conclusion above was verified in current source.
- Query / profile:
  `python3 graphify-arch/tdd_context.py query "1:1 received view-once media terminal consumed widget eye slash Photo label in conversation_wired compose_area private media lifecycle tests ONE_TO_ONE_TESTS" --profile tdd --budget 700`.
- Anchors: `ONE_TO_ONE_TESTS` ->
  `scripts/run_test_gates.sh:25`.
- Surfaced proof/gate files: `scripts/run_test_gates.sh`.
- Graph gaps requiring source search: the deterministic overlay surfaced no
  terminal widget or direct proof candidate. Targeted source search located
  `DirectPrivateMediaTerminalPlaceholder`, its `ConversationScreen` call site,
  terminal projection clearing, and the two owning widget tests.
- Reuse rule: these anchors may be handed to review/execution; all conclusions
  still require current-source or command evidence.

## Scope Contract And Guard

In scope:

- Add a required terminal `mode` input and render only
  `mode == PrivateMediaMode.viewOnce &&
  state == PrivateMediaLifecycleState.consumed` as one compact horizontal row:
  `Icons.visibility_off_outlined`, a small gap, then localized `Photo`.
- Apply the same visual to incoming and outgoing consumed view-once receipts.
- Keep the visible branch non-interactive: no Reply, Info, Delete, Open, media
  image, generic title, or lifecycle sentence inside the receipt.
- Retain a useful nonvisual accessibility label that combines localized
  `Photo` with the existing consumed-state meaning, while exposing one semantic
  node rather than separate icon/text nodes.
- Keep Reply/Delete available only through the existing outer swipe/long-press
  conversation interactions.

Must preserve:

- Expired, unsupported, protected-consumed legacy, protected, and disappearing
  private presentations keep their current copy/actions/layout ->
  `TC-304-03`.
- Direct view-once creation remains image-only -> `TC-304-05`.
- Consumption, cleanup, no-second-open, route ordering, and screenshot
  protection remain unchanged -> `TC-304-06`.
- The stable `private-terminal-<state>` container keys and no-pixel terminal
  privacy boundary remain unchanged -> `TC-304-01/02`.
- Arabic RTL, German, English, and 1.3x text scale remain overflow-free ->
  `TC-304-01`.

Hard `Do not`:

- Do not persist terminal media kind, add a database column/migration, change
  wire policy/version, retain attachment rows, or weaken terminal cleanup.
- Do not change viewer lifecycle/controller/protection code, private-media
  action eligibility, group/announcement private media, or received-media
  context-menu policy.
- Do not remove or rename generic private-media localization keys; they remain
  used by other states, notification/privacy copy, and Info surfaces.
- Do not restyle `expired`, `unsupported`, or non-view-once consumed terminals.

Deferred / accepted difference:

- Legacy version-1 view-once videos that were created before Plan 303 lose
  their attachment kind on secure terminal cleanup and will display the
  localized product receipt `Photo` after consumption. The current request
  explicitly selects `Photo`; recovering exact legacy kind is deferred to an
  unallocated future compatibility/schema plan because it would require new
  persisted/wire metadata solely for a terminal label.
- Attachmentless consumed-terminal Info becomes unavailable after its inline
  button is removed. Reply/Delete retain their existing outer surfaces. A new
  parent-only Info surface is deferred to an unallocated future terminal-Info
  UX plan because it is outside the requested two-element receipt.

Dependencies:

- Plan 303's completed image-only new-view-once rule is the upstream product
  contract. Execution must preserve its existing dirty/coherent changes,
  record the Plan-303 diff/commit boundary, and stop for re-grounding if that
  rule is absent or reverted before Plan 304 lands.

## Test Contract

`HEAD` in this table means the recorded pre-304 workspace: repository `HEAD`
plus the completed Plan-303 change set. The mode-plumbing preparation below is
a behavior-preserving GREEN refactor; causal RED is recorded only afterward.

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-304-01 | Incoming and outgoing consumed view-once receipts show one horizontal eye-off + localized `Photo` row in en/de/ar, with one consumed semantic label and no inline copy/actions/open/media | After the GREEN mode-plumbing preparation, rewrite `test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart::sender-consumed terminal is generic after attachment cleanup` as `consumed view-once terminal is eye-off plus localized Photo only` using direction × locale at 1.3x text scale | widget / `WidgetTester`, no repository fake | causal assertion RED after seam preparation: unchanged rendering still shows generic/lifecycle text and three action keys with the icon above copy -> GREEN finds one keyed `MainAxisSize.min` row, direction-correct non-overlapping icon/text with a small bounded gap, exact localized word, one semantic node, and zero forbidden controls/copy/images | restore the current consumed column/action row or expose child semantics -> TC-304-01 red; remove the mode guard -> TC-304-03 red | `flutter test test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart --plain-name 'consumed view-once terminal is eye-off plus localized Photo only'`; existing `ONE_TO_ONE_TESTS` entry, no registration edit |
| TC-304-02 | The live `ConversationScreen` row and lifted long-press snapshot both use the minimal receipt, while outer Reply/Delete remain reachable and Info is absent | After the GREEN mode-plumbing preparation, replace the consumed half of `test/features/conversation/presentation/screens/direct_private_media_card_test.dart::terminal and unsupported cards keep action rows in-bubble` with `consumed view-once receipt is minimal in live and lifted cards while outer reply and delete remain reachable` | widget / existing `pumpConversation` and fake callbacks | causal assertion RED: unchanged rendering still exposes `private-action-*` inside the consumed slot -> GREEN finds only the minimal summary in both card instances, then long press exposes context Reply/Delete but no Info and dispatches the existing callbacks | re-add inline actions or remove an outer context action -> TC-304-02 red; pass a constant/wrong mode -> TC-304-03 red | `flutter test test/features/conversation/presentation/screens/direct_private_media_card_test.dart --plain-name 'consumed view-once receipt is minimal in live and lifted cards while outer reply and delete remain reachable'`; existing `ONE_TO_ONE_TESTS` entry |
| TC-304-03 | Expired, unsupported, and outgoing protected-consumed terminals retain current generic/state copy and action behavior through the real `ConversationScreen` caller | Split/retain `direct_private_media_viewer_test.dart::attachmentless expired and non-view-once consumed parents retain generic terminal actions` and add `direct_private_media_card_test.dart::non-view-once terminal cards retain generic copy and actions`, including an outgoing `PrivateMediaPolicy.protected()` + `consumed` parent alongside expired/unsupported cases | widget / local model fixtures through `pumpConversation` | GREEN sentinel before and after the minimal branch -> protected-consumed and expired keep generic/state copy plus inline actions; unsupported keeps its separate guidance/actions | hard-code `PrivateMediaMode.viewOnce` at `conversation_screen.dart:1067` or branch on `state == consumed` without mode -> protected-consumed card minimizes and TC-304-03 reds | `flutter test test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart --plain-name 'attachmentless expired and non-view-once consumed parents retain generic terminal actions'` and `flutter test test/features/conversation/presentation/screens/direct_private_media_card_test.dart --plain-name 'non-view-once terminal cards retain generic copy and actions'`; both existing `ONE_TO_ONE_TESTS` entries |
| TC-304-04 | The receipt stays pixel-free, non-openable, and direction/RTL safe | Fold assertions into TC-304-01 plus retain `direct_private_media_viewer_test.dart::private open opening viewing terminal unsupported and capture copy are localized small and RTL safe` for sibling states | widget / locale and constrained viewport matrix | GREEN sentinel for privacy/no-open and sibling layout -> GREEN with no `Image`, `private-media-open`, overflow, or exception | render cached pixels, add tap/open callback, or break RTL constraints -> TC-304-04 red | `flutter test test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart --plain-name 'private open opening viewing terminal unsupported and capture copy are localized small and RTL safe'`; existing `ONE_TO_ONE_TESTS` entry |
| TC-304-05 | New direct view-once remains image-only, which is the source-backed contract behind the fixed `Photo` receipt | Existing `test/features/conversation/presentation/screens/conversation_private_media_composer_test.dart::every stale or ineligible composer shape resets private policy` | host unit / pure eligibility matrix | GREEN sentinel on the completed Plan-303 workspace -> view-once image retained and view-once video normalized to ordinary | weaken `isPrivateMediaComposerPolicyEligible` to admit view-once video -> TC-304-05 red | `flutter test test/features/conversation/presentation/screens/conversation_private_media_composer_test.dart --plain-name 'every stale or ineligible composer shape resets private policy'`; existing `ONE_TO_ONE_TESTS` entry |
| TC-304-06 | Back still consumes/cleans once and the terminal receipt remains non-openable; presentation edits do not touch lifecycle | Existing `direct_private_media_viewer_test.dart::view-once image Back consumes and cleans exactly once` plus TC-304-01's zero-open-control assertion | widget / fake lifecycle lane | GREEN sentinel on the completed Plan-303 workspace -> one consume/cleanup, no rollback, attachment clearing, and no terminal open control remain true | bypass settlement, retain the terminal attachment, or add an open control -> TC-304-06/01 red | `flutter test test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart --plain-name 'view-once image Back consumes and cleans exactly once'`; existing `ONE_TO_ONE_TESTS` entry |

### Test Notes

- TC-304-01 must scope absence assertions to the terminal receipt so unrelated
  page chrome cannot satisfy or fail the contract. Give the compact row a
  stable key such as `private-terminal-view-once-consumed-summary`; assert
  direction-aware logical order, non-overlap, and a bounded small gap rather
  than a brittle exact pixel value.
- TC-304-02 distinguishes inline controls from the intentional context menu:
  before long press there are no `private-action-*` controls in either receipt;
  after long press, only `MessageContextOverlay.replyActionKey` and
  `deleteActionKey` are expected.
- Required-mode plumbing is introduced and proven behavior-preserving before
  TC-304-01/02 are authored. This prevents a missing-symbol compile failure
  from masquerading as their behavioral RED.
- TC-304-05 is a preservation sentinel, not a causal RED for this plan.

## Implementation Steps

1. Snapshot `git status --short` and record Plan 303's pre-existing dirty
   changes. Do not revert, reformat, or absorb unrelated files into Plan 304.
2. GREEN seam preparation: add a required `PrivateMediaMode mode` to
   `DirectPrivateMediaTerminalPlaceholder`, pass `message.privateMediaMode`
   from the sole production caller, and update the four direct test
   constructors with truthful modes. Do not change rendering. Run the two
   existing terminal/card baseline tests and require exit 0. Stop-if: another
   production caller appears, a caller lacks a durable mode, or the preparation
   changes any rendered widget.
3. Add TC-304-01/02 and the production-path protected-consumed sentinel in
   TC-304-03. Run the two causal commands and record assertion REDs only for
   the current generic copy/action mechanisms; TC-304-03 must remain GREEN.
4. In `DirectPrivateMediaTerminalPlaceholder.build`, add the narrow
   `viewOnce + consumed` early branch. Render one keyed `Row` with
   `MainAxisSize.min`, `Icons.visibility_off_outlined`, bounded spacing, and
   `l10n.shared_media_kind_photo`; merge descendants into one localized
   consumed semantic label. Leave the existing terminal implementation as the
   fallback for every other mode/state.
5. Make no gate-array edit because all changed tests stay in files already
   listed in `ONE_TO_ONE_TESTS`; the literal `1to1` run verifies that curated
   registration.
6. Run focused GREEN, Graphify affected discovery, preservation tests, the
   curated `1to1` lane, hygiene, and one incremental architecture refresh.

## Risks And Blind Spots

- Overbroad state-only branching could restyle protected consumed/expired
  receipts -> guarded by TC-304-03 and the required mode input.
- “Photo” cannot describe a legacy terminal video exactly -> explicitly
  accepted above and guarded against accidental persistence/wire expansion.
- Removing the inline row could accidentally remove all Reply/Delete access ->
  TC-304-02 drives the existing outer interactions.
- A two-widget row can regress RTL, text scaling, or semantics duplication ->
  TC-304-01/04 use locale, scale, bounded adjacency, and merged-semantics
  assertions.
- Lifecycle / derived-state durability: unchanged and guarded by TC-304-06.
- Sibling-surface consistency: expired/unsupported/protected and group surfaces
  are outside the mode guard; TC-304-03 plus the `1to1` lane protect direct
  siblings. No group production file changes.
- Destructive-action side effects: no delete/cleanup implementation changes;
  TC-304-02/06 preserve both user Delete dispatch and lifecycle cleanup.
- Invariant re-verification under new transitions: N/A — the plan adds no state
  transition; it only changes projection of an existing terminal state.

## Gate Cadence

- Per-plan closure: the two focused causal widget files, exact composer and
  viewer-lifecycle sentinels, tests surfaced by Graphify affected analysis,
  and `./scripts/run_test_gates.sh 1to1`.
- No `feature-host-all`, `core-host-all`, or performance sweep is justified:
  the production delta is two direct-conversation presentation files with an
  already curated lane.
- Do not run full `host-all` for this individual plan. Run
  `./scripts/run_host_test_gates.sh host-all` once after the Plans 303-304
  direct view-once presentation batch is integrated, and once at final
  rollout/release closure.
- Shared tests outside feature/core globs: N/A — all host tests are under
  `test/features/**` and already registered.

## Acceptance Gates

```bash
# Snapshot before execution; preserve unrelated and completed Plan-303 changes.
git status --short

# GREEN behavior-preserving seam preparation. After adding the required `mode`
# input and truthful caller/test plumbing but before changing rendering, both
# existing baselines must still exit 0.
flutter test \
  test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart \
  --plain-name 'sender-consumed terminal is generic after attachment cleanup'
flutter test \
  test/features/conversation/presentation/screens/direct_private_media_card_test.dart \
  --plain-name 'terminal and unsupported cards keep action rows in-bubble'

# Causal RED after seam preparation; each must be non-zero for the documented
# generic-copy/inline-action assertion, not compilation or fixture failure.
flutter test \
  test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart \
  --plain-name 'consumed view-once terminal is eye-off plus localized Photo only'
flutter test \
  test/features/conversation/presentation/screens/direct_private_media_card_test.dart \
  --plain-name 'consumed view-once receipt is minimal in live and lifted cards while outer reply and delete remain reachable'

# At RED, the mode discriminator remains GREEN; a constant `viewOnce` caller
# or state-only branch must fail the protected-consumed case.
flutter test \
  test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart \
  --plain-name 'attachmentless expired and non-view-once consumed parents retain generic terminal actions'
flutter test \
  test/features/conversation/presentation/screens/direct_private_media_card_test.dart \
  --plain-name 'non-view-once terminal cards retain generic copy and actions'

# Focused GREEN; each exits 0 with zero failed tests.
flutter test \
  test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart
flutter test \
  test/features/conversation/presentation/screens/direct_private_media_card_test.dart

# Exact preservation sentinels; each exits 0.
flutter test \
  test/features/conversation/presentation/screens/conversation_private_media_composer_test.dart \
  --plain-name 'every stale or ineligible composer shape resets private policy'

# Affected dependents. Run every test file named by `affected` before the
# curated lane; the lane itself executes the existing ONE_TO_ONE_TESTS entries.
python3 graphify-arch/tdd_context.py affected \
  lib/features/conversation/presentation/screens/direct_private_media_viewer.dart \
  lib/features/conversation/presentation/screens/conversation_screen.dart \
  --budget 600
./scripts/run_test_gates.sh 1to1

# Hygiene; no new analyzer issue or whitespace error.
flutter analyze
git diff --check
./graphify-arch/refresh_arch_graph.sh --incremental
```

Semantic outcomes:

- The seam-preparation baselines stay GREEN, proving the required mode plumbing
  is behavior-preserving before any causal test is introduced.
- TC-304-01/02 fail on the pre-production-edit workspace only because the
  generic title/lifecycle copy and inline action row still render.
- TC-304-03 stays GREEN at RED and re-reds if the sole production caller
  hard-codes `viewOnce` or the widget branches on consumed state alone.
- Focused GREEN proves exact localized `Photo`, horizontal adjacency, one
  semantic receipt, and absence of inline Reply/Info/Delete/Open/pixels for
  consumed view-once in live and lifted cards.
- Preservation commands keep image-only creation, terminal cleanup, and the
  terminal receipt's non-openable projection green.
- Source membership plus the actual `1to1` run verifies curated registration;
  the gate completes with zero failed legs, analysis adds no issue, and diff
  hygiene is clean.

## Execution Interpretation And Done Criteria

- Expected RED: TC-304-01 and TC-304-02 assertion failures for current generic
  copy/action controls after the required-mode seam is GREEN.
- Green sentinel: TC-304-03 through TC-304-06.
- Pre-existing dirty tree / known failure: Plan 303 and its implementation files
  are already dirty and recorded as completed/green; preserve and record that
  upstream change set. No product baseline failure is known.
- Environment blocker: none; host-only closure requires no simulator, device,
  relay, SQLCipher, native callback, or real crypto.
- Scope drift: any proposal to retain terminal attachment kind, add schema/wire
  metadata, restyle non-view-once terminal states, or edit lifecycle/protection
  blocks completion and requires re-planning.

- [x] Every behavior has a named test or justified proof.
- [x] Causal RED, focused GREEN, and representative mutation re-red are
      recorded.
- [x] Seam preparation, preservation tests, affected tests, and `1to1` pass
      with their semantic outcomes.
- [x] Existing harness registration is verified; no duplicate array entry is
      added.
- [x] No migration or device/relay proof is introduced.
- [x] `flutter analyze` has no new issues; `git diff --check` is clean.
- [x] Scope Contract And Guard is respected.

## Reviewer Findings

- Initial verdict: `plan-fixes-required`; core bet confirmed.
- Applied R1: staged the required-mode API as a behavior-preserving GREEN seam
  so the causal tests fail by assertion rather than compilation.
- Applied R2: added an outgoing protected-consumed `ConversationScreen`
  sentinel; hard-coding `viewOnce` at the sole production caller now re-reds.
- Applied R3: strengthened “next to” from vertical alignment alone to logical
  order, non-overlap, and a bounded small gap without pinning a brittle pixel.
- Applied R4: corrected `completeness-check` overclaim. It classifies paths;
  source membership plus the actual `1to1` run proves curated registration.
- Applied R5: removed the unrelated restart-DB command. The focused viewer
  suite retains the adjacent consume/cleanup sentinel; the change has no DB or
  recovery seam.
- Final five-lens result: evidence truth `clear`; test causality `clear`;
  bypass/scope `clear` (one production caller); gate integrity `clear`;
  boundary/reversibility `N/A` (host-only presentation, no state or data
  transition).
- Final verdict: `ready`; disposition: `execute`.

## Handoff

- First causal RED command:
  `flutter test test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart --plain-name 'consumed view-once terminal is eye-off plus localized Photo only'`.
- Preservation command:
  `flutter test test/features/conversation/presentation/screens/conversation_private_media_composer_test.dart --plain-name 'every stale or ineligible composer shape resets private policy'`.
- Manual registration: none; viewer/card/composer files are already in
  `ONE_TO_ONE_TESTS`; verify by executing `./scripts/run_test_gates.sh 1to1`.
- Migration: none.
- Boundary closure: host-only widget/unit/integration proof; no device,
  simulator, relay, real crypto, OS callback, or SQLCipher claim.
- Unresolved evidence: none.

## Execution Progress

| Stage | State | Evidence |
|---|---|---|
| Seam | complete | Added the required `mode` input, passed `message.privateMediaMode` from the sole production caller, and kept both pre-render baselines green. |
| RED | complete | TC-304-01 and TC-304-02 failed only because the compact summary was absent; both TC-304-03 mode sentinels remained green. |
| GREEN | complete | Viewer and card suites passed 30 and 5 tests. Exact composer and Back-cleanup preservation sentinels passed. A consumed-only guard mutation re-red the protected-consumed production-path test, then the restored mode guard returned it to green. |
| Closure | complete | The `1to1` lane passed 2517 Flutter tests plus the relay Go contract/test gate. `flutter analyze` reported no issues, formatting and `git diff --check` were clean, and the incremental architecture graph refresh completed. |
