# 282 - Duplicate Dart group-message payload removal

Status: Plan-green; implementation-complete and closed
Type: Modification
Spec: free-text intent for `DTR-10` / `DTR08-COMP-009` in
`Test-Flight-Improv/dead-code-and-technical-debt-removal-roadmap.md`
Classification: implemented-and-verified
Closure tier: host
Roadmap ID / wave: `DTR-10` / Wave 3 — Compatibility-led groups cleanup
Date: 2026-07-26

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-26 | Evidence Collector / Planner | Dart `group_message_payload.dart` and test, runtime-root manifest, import/caller census, direct-forwarding boundary test, Go v3 envelope/parser/publish/receive sources and tests, gate scripts, DTR roadmap | The user's item 6 repeats item 5's rotation wording. The item label, prior discussion, and current source make the safe interpretation unambiguous: remove only the unused Dart `GroupMessagePayload` and its SUT-only test; preserve the live Go v3 protocol. The project owner explicitly authorized that leaf removal under this interpretation. | Add a removal contract, delete only the Dart pair, then close Go v3 and group-lane preservation. |
| 2026-07-26 | TDD-plan sufficiency cross-auditor | Review-profile Graphify context, whole-source import/token census, Dart/C4 ownership, exact Go v3 parser/publish/receive selectors, direct-forwarding sentinel, and runtime-root implementation | PASS WITH FIXES: the recorded copy/paste interpretation is the only non-duplicative source-grounded reading, and the Go v3 boundary is correctly excluded. Tighten exact C4 ownership, final-tree runtime inventory, graph refresh, and durable DTR bookkeeping. | Apply only the plan corrections below; implementation remains not started. |

## Problem And Evidence

- Behavior to improve: remove a standalone Dart model that claims to represent
  the v3 group-message wire payload even though production send/receive owns
  that payload in Go.
- Impact: the duplicate makes maintainers believe Dart and Go schemas must be
  evolved together, while its only real consumer is its own unit test. That
  ambiguity invites accidental changes to the wrong protocol type.
- Owner authorization and interpretation record:
  - the 2026-07-26 request explicitly asks for a separate plan for item 6,
    titled `Duplicate Dart group-message description`;
  - its action sentence accidentally repeats item 5's rotation-wrapper wording;
  - the prior item-by-item discussion defined item 6 as deletion of only the
    unused Dart duplicate and its test;
  - current source confirms that interpretation: no production Dart file
    imports this model, while Go owns the live v3 payload.
  Therefore this plan treats the repeated rotation wording as copy/paste,
  records the current project owner's leaf-only authorization as
  `DTR10-AUTH-06`, and preserves every rotation and Go wire surface. Stop for
  clarification if execution discovers any production Dart importer,
  serialization call, export facade, or other evidence that makes this
  interpretation unsafe.
- Confirmed current gap:
  - `GroupMessagePayload` is declared only at
    `lib/features/groups/domain/models/group_message_payload.dart:5-57`;
  - `group_message_payload_test.dart:2` is its sole positive Dart importer;
  - the current-source `lib` import census returns zero production importers.
- Confirmed live protocol:
  - `go-mknoon/internal/group_envelope.go:15-47` defines the v3 envelope and
    encrypted `GroupMessagePayload`;
  - `ParseGroupPayload` at `:96-117` validates and decodes the live payload;
  - `go-mknoon/node/pubsub.go:458-515` builds, marshals, encrypts, signs, and
    publishes it;
  - `buildGroupMessageReceivedEvent` at `:1914-1938` maps decrypted payloads
    into the event consumed by Dart.
- Existing obsolete-only coverage:
  `test/features/groups/domain/models/group_message_payload_test.dart:5-39`
  validates only the duplicate Dart model and is deleted with it.
- Existing live coverage:
  - `go-mknoon/internal/group_envelope_test.go` covers v3 envelope/payload
    round-trip, strict payload parsing, media extras, and quoted-message extras;
  - `TestGK030PublishGroupMessagePreservesExtraFieldsInReceivedEvent` and
    `TestGP023ReceivePathContinuesAfterMalformedPayload` exercise live publish
    and receive behavior;
  - `direct_media_forward_transport_boundary_test.dart:6-32` explicitly
    forbids direct-message forwarding from importing the group payload
    implementation.
- Missing coverage: no test requires the duplicate Dart file/test and its
  runtime-root/current-architecture claims to be absent while requiring the Go
  payload/parser/publish/receive sources to remain.
- Refuted findings:
  - Refuted: the Dart class is the production v3 wire contract. Production
    builds and parses it in Go.
  - Refuted: removing the Dart class is a wire-version retirement. No live Go,
    Dart event-consumer, platform, native, crypto, relay, or transport source is
    in scope.
  - Refuted: the user's repeated rotation wording should remove rotation code
    in this plan. Rotation has its own Plan 281; source ownership for item 6 is
    the Dart payload pair.
- Unresolved findings: the supported installed-client/mixed-version floor for
  v3 is unknown. It is deliberately irrelevant to deletion of an unimported
  Dart duplicate, but it blocks any Go schema/parser/publish/receive edit.
- Affected production, test, gate, inventory, and current-architecture files:
  delete the Dart model and its test; add one feature removal contract; remove
  the matching runtime-root declaration; add the contract to `GROUP_TESTS`;
  remove only current C4 claims that present the Dart model as live; update the
  DTR-10 registry/decision/`DTR08-COMP-009` disposition and plan index. No Go,
  native, platform, integration, database, or rotation file is affected.

## Graph Grounding Snapshot

- Graph fingerprint / freshness:
  `0c2b989ba6d96ada`; `freshness=current`.
- Query / profile:
  `python3 graphify-arch/tdd_context.py query "remove obsolete group_message_payload.dart GroupMessagePayload unit test while preserving go-mknoon internal group_envelope.go v3 parser pubsub publish receive" --profile tdd --budget 700`.
- Anchors:
  - Go `GroupMessagePayload` ->
    `go-mknoon/internal/group_envelope.go:42`;
  - Dart package/file anchor ->
    `lib/features/groups/domain/models/group_message_payload.dart`.
- Surfaced proof/gate files:
  `go-mknoon/internal/group_envelope_test.go`,
  `go-mknoon/node/pubsub_delivery_test.go`,
  `go-mknoon/node/pubsub_decryption_failure_test.go`, and
  `group_message_payload_test.dart`.
- Graph gaps requiring source search: the compact graph did not establish the
  zero-production-import census, the runtime-root declaration, current C4
  claims, the direct-forward transport boundary, or exact gate registration.
  Those were verified in current source.
- Reuse rule: anchors may be handed to review/execution; all conclusions still
  require current-source or command evidence.

## Scope Contract And Guard

In scope:

- Delete
  `lib/features/groups/domain/models/group_message_payload.dart`.
- Delete only
  `test/features/groups/domain/models/group_message_payload_test.dart`.
- Add
  `test/features/groups/domain/models/group_message_payload_removal_contract_test.dart`.
- Remove the deleted model's `runtime_roots.json` declaration, add the new
  contract to `GROUP_TESTS`, and remove only current C4 claims that describe the
  Dart class/file as a live wire model.
- In current C4 documentation, retire only the Dart file-tree row, the Dart
  `fromJson`/`toJson` model diagram, and the Flutter-model inventory row.
  Preserve the Go `internal/group_envelope.go` module diagram/table and the
  v3 publish/receive wire-flow documentation.
- Record the Dart-leaf result in the current DTR-10 registry, decision ledger,
  `DTR08-COMP-009`, and `00-INDEX.md`; do not rewrite historical execution
  records or imply that v3 was retired.

Must preserve:

- The complete Go v3 `GroupEnvelope`, `GroupEncryptedPayload`, and
  `GroupMessagePayload` schema, marshal/parse validation, encryption/signing,
  publish, receive, canonical-field protection, extras, and malformed-payload
  continuation.
- Dart event consumers, offline inbox v3 protected-field handling, group
  message models/repositories/listeners, all group-message actions, and direct
  media forwarding's no-Go/no-group-payload boundary.
- All group-key rotation code and tests, including both Plan 281's separately
  owned legacy scope and the live generate/distribute/promote/update path.
- Every database schema/table/migration and every native, platform, Go,
  generated, relay, simulator, and device artifact.
- Current C4 descriptions of the Go Group Envelope Module, its
  `GroupMessagePayload`, and the encrypted v3 publish/receive flow.

Hard `Do not`:

- Do not edit `go-mknoon/internal/group_envelope.go`,
  `go-mknoon/node/pubsub.go`, their tests, or any v3 version/type/field.
- Do not replace the Dart duplicate with another Dart wire schema, re-export
  the Go schema, or retarget production code merely to keep its unit test.
- Do not remove the forbidden string checks from
  `direct_media_forward_transport_boundary_test.dart`; their mention of
  `GroupMessagePayload` is a negative sentinel, not a consumer.
- Do not touch Plan 281's rotation files, group inbox parsing, Dart/native
  bridge mappings, platform handlers, generated bindings, schemas, or
  historical TDD records.

Deferred / accepted difference:

- Any v3 protocol cleanup or retirement -> owner Groups + Crypto + Release in a
  new TDD plan with supported-client evidence and availability-bounded
  mixed-client/two-peer proof.
- No replacement Dart model is created because production has no Dart need for
  this schema.

Dependencies:

- This plan is independent of Plan 281 and every other DTR-10 leaf. Its only
  product decision is `DTR10-AUTH-06`, the owner's explicit authorization to
  remove this unused Dart pair under the recorded copy/paste interpretation.

Stop-if:

- Stop and request clarification if an execution-time census finds any
  production Dart importer, constructor/parser/serializer call, export facade,
  code generation input, or need to change the live Go/Dart receive boundary.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-282-01 | The duplicate Dart model, its SUT-only test, runtime-root declaration, and current C4 live-model claims are absent; no production Dart importer exists; the removal contract is registered in `GROUP_TESTS`; the DTR registry, `DTR10-AUTH-06`, `DTR08-COMP-009`, and plan index record the implemented Dart-only result without invoking the deleted test; the live Go source allowlist remains. | `test/features/groups/domain/models/group_message_payload_removal_contract_test.dart::DTR10-PAYLOAD-01 removes only the duplicate Dart payload` | Host source-contract test / real repository tree | Causal RED on HEAD because the Dart model/test, manifest row, current C4 claims, missing gate registration, and planned/deferred DTR records exist -> GREEN after only those artifacts are removed or updated and exact protected Go sources remain present. | Restore the Dart file/test/manifest/current C4 claim, remove the `GROUP_TESTS` entry, restore stale planned/deferred DTR bookkeeping or its deleted-test command, add a production import, or remove a required Go source anchor -> TC-282-01 red. | `flutter test --no-pub test/features/groups/domain/models/group_message_payload_removal_contract_test.dart --plain-name 'DTR10-PAYLOAD-01 removes only the duplicate Dart payload'`; add path to `GROUP_TESTS`, then verify through `groups`. |
| TC-282-02 | The live Go v3 envelope and inner payload still round-trip, reject the wrong schema, and preserve media/quote extras. | `go-mknoon/internal/group_envelope_test.go::{TestMarshalParseGroupEnvelope_RoundTrip, TestGK014IsGroupEnvelopeAcceptsOnlyV3GroupMessageAndReaction, TestMarshalParseGroupPayload_RoundTrip, TestGK029ParseGroupPayloadRejectsWrongSchema, TestGroupMessagePayloadWithMediaExtra, TestGroupMessagePayloadWithQuotedMessageIdExtra}` | Real Go host unit / actual JSON schema and parser | GREEN sentinel on HEAD -> remains GREEN after Dart-only deletion with exact v3 envelope/type and payload validation/extras intact. | Change version/type, omit a required payload field check, or drop media/quote extras -> one of the named Go tests red or protected comparison fails. | Exact `GOTOOLCHAIN=go1.25.0 go test ./internal -run ... -count=1` below; manual exact registration. |
| TC-282-03 | Live Go publish creates the encrypted v3 payload, receive preserves safe extras/canonical fields, and malformed payloads do not poison later receive work. | `go-mknoon/node/pubsub_delivery_test.go::TestGK030PublishGroupMessagePreservesExtraFieldsInReceivedEvent`; `go-mknoon/node/pubsub_test.go::TestGK030BuildGroupMessageReceivedEventPreservesExtrasAndProtectsCanonicalFields`; `go-mknoon/node/pubsub_decryption_failure_test.go::{TestGP023ReceivePathContinuesAfterMalformedPayload, TestGK029MalformedPayloadJSONEmitsPayloadParseFailedOnly}` | Go host implementation tests / production payload builder, parser, and event mapping (preservation only; no end-to-end crypto claim) | GREEN sentinel on HEAD -> remains GREEN after Dart-only deletion with live publish/receive behavior unchanged. | Bypass `MarshalGroupPayload`, leak/overwrite a canonical event field, accept malformed payload as a message, or stop processing later valid payloads -> a named test red. | Exact `GOTOOLCHAIN=go1.25.0 go test ./node -run ... -count=1` below; manual exact registration. |
| TC-282-04 | Dart direct forwarding and group consumers remain independent of the removed duplicate and continue through their established production paths. | `test/features/conversation/application/direct_media_forward_transport_boundary_test.dart::direct forwarding imports no go bridge routing inbox or group payload implementation`; full `test/features/groups/integration/group_messaging_smoke_test.dart`; protected-source comparison | Host boundary + group integration fakes | GREEN sentinel on HEAD -> remains GREEN after deletion: direct forwarding has no group-payload dependency, and group messaging still sends/receives through the existing implementation. | Import a group payload implementation into direct forwarding, retarget a production Dart consumer to the removed class, or edit the protected live receive/send sources -> named test or protected comparison red. | Exact Flutter commands below; direct test AUTO (`test/features/**`), group smoke already in `GROUP_TESTS`; close with `groups` and `feature-host-all`. |

### Test Notes

- TC-282-01 must distinguish positive imports from negative sentinel strings.
  `direct_media_forward_transport_boundary_test.dart` intentionally contains
  both `group_message_payload.dart` and `GroupMessagePayload` in a forbidden
  list and must remain unchanged.
- TC-282-01 must inspect the exact Dart file/test/manifest/current C4 claims and
  scan `lib/**/*.dart` for an import/export of the deleted path. It must not ban
  Go's same-named type.
- Its C4 assertions remove only:
  `C4/file-structure.md`'s Dart file row, `C4/code.md`'s Dart
  `fromJson`/`toJson` payload block, and `C4/components.md`'s Flutter model
  inventory row. They positively require the
  `internal/group_envelope.go`/Go-module descriptions in
  `C4/components.md` and the v3 flow in `C4/infrastructure.md`; a global
  `GroupMessagePayload` text ban is forbidden.
- TC-282-01 must positively require its own `GROUP_TESTS` entry and the exact
  implemented Dart-only post-state in the current DTR-10 registry,
  `DTR10-AUTH-06` decision row, `DTR08-COMP-009` overlay/proof command, and
  `00-INDEX.md`. Restoring the deleted test command is a representative
  bookkeeping mutation and must re-red the contract.
- The protected Go comparison is against the executor's pre-edit baseline, not
  blindly against a clean `HEAD`, so unrelated pre-existing user work is not
  overwritten or misattributed.

## Implementation Steps

1. Snapshot `git status --short`. Capture a pre-edit `git diff HEAD` for all Go,
   native/platform/generated, rotation, group send/receive, offline-inbox,
   database, integration, and direct-forwarding protected paths.
2. Add TC-282-01 and register it in `GROUP_TESTS`.
3. Run TC-282-01 before deletion. It must fail only because the exact Dart
   file/test/manifest/current C4 artifacts exist. If it finds a production
   importer or export facade, stop for clarification instead of deleting.
4. Delete only `group_message_payload.dart` and its dedicated test. Remove only
   its matching runtime-root declaration. Correct current C4 file/symbol/model
   claims while retaining the Go v3 module/schema documentation. Update the
   current DTR-10 registry, decision ledger, `DTR08-COMP-009`, and plan index to
   record only the Dart-leaf disposition.
5. Run focused GREEN and restore either the Dart model or its manifest row as a
   representative mutation; TC-282-01 must re-red before the mutation is
   reverted.
6. Run exact Go schema/parser/publish/receive sentinels, the direct-forwarding
   boundary, full group messaging smoke test, runtime inventory,
   completeness, `groups`, and justified `feature-host-all`; refresh the
   architecture graph incrementally once after the coherent app-owned change.
7. Compare protected paths to their pre-edit baseline. Any protected delta is
   scope drift and requires rollback/replanning, not expansion of this plan.

## Risks And Blind Spots

- Same type name in Dart and Go could cause accidental Go deletion ->
  TC-282-01 requires Go anchors; TC-282-02/03 and protected comparison guard
  live Go behavior.
- The negative direct-forwarding test could be mistaken for a consumer ->
  TC-282-01 scans positive import/export syntax and TC-282-04 preserves the
  negative sentinel.
- The copy/paste interpretation could be wrong -> it is explicitly recorded
  and source-grounded; any contrary production evidence triggers the stop-if
  and user clarification.
- Current C4 cleanup could erase the live Go schema -> source contract and
  protected scope require Go documentation/anchors to remain.
- Lifecycle / derived-state durability: N/A — the Dart duplicate holds no state
  and has no production lifecycle; group messaging lifecycle remains under the
  `groups` gate.
- Sibling-surface consistency: TC-282-04 plus `groups` retains group text,
  media, quote, reaction, inbox, and direct-forwarding boundaries.
- Destructive-action side effects: TC-282-01 names the only two deletions and
  proves all protected live sources remain.
- Invariant re-verification under new transitions: N/A — no runtime transition
  changes.

## Gate Cadence

- Per-plan closure: causal removal contract, exact Go v3 sentinels, direct
  forwarding and group messaging preservation, isolated-final-tree
  `runtime-roots`, `completeness-check`, curated `groups`, justified
  `feature-host-all`, incremental Graphify refresh, strict analysis, and
  diff/protected-scope hygiene.
- Do not run full `host-all` for this individual plan. Run
  `./scripts/run_host_test_gates.sh host-all` once after the Wave 3 DTR-10 group
  legacy-cleanup batch is complete, and once at final DTR rollout/release
  closure.
- Shared tests outside feature/core globs: Go internal/node tests run by exact
  direct commands below.

## Acceptance Gates

```bash
# Snapshot before execution; record unrelated changes.
git status --short

# Capture the protected baseline before edits. Both commands must exit 0.
DTR10_PAYLOAD_PROTECTED_PATCH_BASELINE="$(mktemp)"
DTR10_PAYLOAD_PROTECTED_STATUS_BASELINE="$(mktemp)"
git diff --no-ext-diff HEAD -- \
  go-mknoon android ios macos linux windows \
  lib/core/bridge \
  lib/core/database \
  lib/features/groups/application \
  lib/features/groups/domain/repositories \
  lib/features/groups/domain/models/group_message.dart \
  lib/features/conversation/application \
  test/features/conversation/application/direct_media_forward_transport_boundary_test.dart \
  test/features/groups/integration/group_messaging_smoke_test.dart \
  C4/infrastructure.md \
  integration_test \
  >"$DTR10_PAYLOAD_PROTECTED_PATCH_BASELINE"
git status --short -- \
  go-mknoon android ios macos linux windows \
  lib/core/bridge \
  lib/core/database \
  lib/features/groups/application \
  lib/features/groups/domain/repositories \
  lib/features/groups/domain/models/group_message.dart \
  lib/features/conversation/application \
  test/features/conversation/application/direct_media_forward_transport_boundary_test.dart \
  test/features/groups/integration/group_messaging_smoke_test.dart \
  C4/infrastructure.md \
  integration_test \
  >"$DTR10_PAYLOAD_PROTECTED_STATUS_BASELINE"

# Causal RED before deletion: expect non-zero because the exact duplicate Dart
# artifacts still exist. Any production-import finding triggers stop/replan.
flutter test --no-pub \
  test/features/groups/domain/models/group_message_payload_removal_contract_test.dart \
  --plain-name 'DTR10-PAYLOAD-01 removes only the duplicate Dart payload'

# Focused GREEN after deletion: exit 0 and zero failed tests.
flutter test --no-pub \
  test/features/groups/domain/models/group_message_payload_removal_contract_test.dart

# Fail-closed positive-import/export census. rg status 1 with an empty report is
# the only successful no-match result; the negative sentinel is not scanned.
DTR10_PAYLOAD_CENSUS_REPORT="$(mktemp)"
DTR10_PAYLOAD_CENSUS_STATUS=0
rg -n \
  -e "(import|export) ['\\\"][^'\\\"]*group_message_payload\\.dart['\\\"]" \
  lib \
  >"$DTR10_PAYLOAD_CENSUS_REPORT" || DTR10_PAYLOAD_CENSUS_STATUS=$?
test "$DTR10_PAYLOAD_CENSUS_STATUS" -eq 1
test ! -s "$DTR10_PAYLOAD_CENSUS_REPORT"

# Live Go v3 envelope/payload schema and parser.
(
  cd go-mknoon
  GOTOOLCHAIN=go1.25.0 go test ./internal \
    -run '^(TestMarshalParseGroupEnvelope_RoundTrip|TestGK014IsGroupEnvelopeAcceptsOnlyV3GroupMessageAndReaction|TestMarshalParseGroupPayload_RoundTrip|TestGK029ParseGroupPayloadRejectsWrongSchema|TestGroupMessagePayloadWithMediaExtra|TestGroupMessagePayloadWithQuotedMessageIdExtra)$' \
    -count=1
)

# Live Go publish/receive protocol and malformed-payload recovery.
(
  cd go-mknoon
  GOTOOLCHAIN=go1.25.0 go test ./node \
    -run '^(TestGK030PublishGroupMessagePreservesExtraFieldsInReceivedEvent|TestGK030BuildGroupMessageReceivedEventPreservesExtrasAndProtectsCanonicalFields|TestGP023ReceivePathContinuesAfterMalformedPayload|TestGK029MalformedPayloadJSONEmitsPayloadParseFailedOnly)$' \
    -count=1
)

# Dart sibling-boundary and group behavior preservation.
flutter test --no-pub \
  test/features/conversation/application/direct_media_forward_transport_boundary_test.dart \
  --plain-name 'direct forwarding imports no go bridge routing inbox or group payload implementation'
flutter test --no-pub \
  test/features/groups/integration/group_messaging_smoke_test.dart

# Real final-tree runtime-root gate. The inventory deliberately flags ordinary
# unstaged tracked deletions, so stage only this plan's final tree in a
# disposable index and leave the user's real index untouched.
DTR10_PAYLOAD_INDEX_DIR="$(
  mktemp -d "${TMPDIR:-/tmp}/dtr10-payload-index.XXXXXX"
)"
trap 'rm -rf -- "${DTR10_PAYLOAD_INDEX_DIR:?}"' EXIT
GIT_INDEX_FILE="$DTR10_PAYLOAD_INDEX_DIR/index" git read-tree HEAD
GIT_INDEX_FILE="$DTR10_PAYLOAD_INDEX_DIR/index" git add -A -- \
  lib/features/groups/domain/models/group_message_payload.dart \
  test/features/groups/domain/models/group_message_payload_test.dart \
  test/features/groups/domain/models/group_message_payload_removal_contract_test.dart \
  tool/runtime_roots/runtime_roots.json \
  scripts/run_test_gates.sh \
  C4/file-structure.md \
  C4/code.md \
  C4/components.md \
  Test-Flight-Improv/dead-code-and-technical-debt-removal-roadmap.md \
  Test-Flight-Improv/00-INDEX.md
GIT_INDEX_FILE="$DTR10_PAYLOAD_INDEX_DIR/index" \
  ./scripts/run_test_gates.sh runtime-roots

# Curated group lane and changed feature surface.
./scripts/run_test_gates.sh completeness-check
./scripts/run_test_gates.sh groups
./scripts/run_host_test_gates.sh feature-host-all \
  --batch-flutter --concurrency 4 --reporter failures-only

# Hygiene and required architecture-graph refresh.
./scripts/check_flutter_analyze_strict.sh
./graphify-arch/refresh_arch_graph.sh --incremental
git diff --check

# Protected paths must be byte/status-identical to their pre-edit baseline.
DTR10_PAYLOAD_PROTECTED_PATCH_CURRENT="$(mktemp)"
DTR10_PAYLOAD_PROTECTED_STATUS_CURRENT="$(mktemp)"
git diff --no-ext-diff HEAD -- \
  go-mknoon android ios macos linux windows \
  lib/core/bridge \
  lib/core/database \
  lib/features/groups/application \
  lib/features/groups/domain/repositories \
  lib/features/groups/domain/models/group_message.dart \
  lib/features/conversation/application \
  test/features/conversation/application/direct_media_forward_transport_boundary_test.dart \
  test/features/groups/integration/group_messaging_smoke_test.dart \
  C4/infrastructure.md \
  integration_test \
  >"$DTR10_PAYLOAD_PROTECTED_PATCH_CURRENT"
git status --short -- \
  go-mknoon android ios macos linux windows \
  lib/core/bridge \
  lib/core/database \
  lib/features/groups/application \
  lib/features/groups/domain/repositories \
  lib/features/groups/domain/models/group_message.dart \
  lib/features/conversation/application \
  test/features/conversation/application/direct_media_forward_transport_boundary_test.dart \
  test/features/groups/integration/group_messaging_smoke_test.dart \
  C4/infrastructure.md \
  integration_test \
  >"$DTR10_PAYLOAD_PROTECTED_STATUS_CURRENT"
cmp "$DTR10_PAYLOAD_PROTECTED_PATCH_BASELINE" \
  "$DTR10_PAYLOAD_PROTECTED_PATCH_CURRENT"
cmp "$DTR10_PAYLOAD_PROTECTED_STATUS_BASELINE" \
  "$DTR10_PAYLOAD_PROTECTED_STATUS_CURRENT"
```

The executor must capture and compare a pre-edit `git diff HEAD` for these
protected paths; the post-edit bytes must match that baseline exactly:

```text
go-mknoon/
android/
ios/
macos/
linux/
windows/
lib/core/bridge/
lib/core/database/
lib/features/groups/application/
lib/features/groups/domain/repositories/
lib/features/groups/domain/models/group_message.dart
lib/features/conversation/application/
test/features/conversation/application/direct_media_forward_transport_boundary_test.dart
test/features/groups/integration/group_messaging_smoke_test.dart
C4/infrastructure.md
integration_test/
```

The protected comparison excludes only the newly added TC-282-01 test; it does
not exclude `direct_media_forward_transport_boundary_test.dart`.

## Execution Interpretation And Done Criteria

- Expected RED: TC-282-01 fails only for the duplicate Dart file/test,
  matching runtime-root row, or current C4 live-model claim. A production
  importer is a stop/replan result, not an accepted RED.
- Green sentinels: TC-282-02 through TC-282-04.
- Pre-existing dirty tree / known failure: execution records the live
  `git status --short` and protected baseline; unrelated changes are preserved.
- Environment blocker: none expected; host Flutter and Go 1.25 suffice.
- Runtime-root evidence: Plan 282 passed because the removed
  `group_message_payload.dart` path is absent from the report and no Plan 282
  finding occurred. The original repository-global warning was subsequently
  resolved: the post-run
  `integration_test/group_multi_party_device_real_android_harness.dart` now has
  an explicit `DTR-10 / QA` external-root registration, and the fully staged
  copied-index repository-manifest selector passed with exit 0 and
  `+1: All tests passed!`. The warning retained in the original execution row
  is historical, not a current Plan 282 or global inventory blocker.
- Scope drift: any Go/native/platform/generated/database/rotation/live
  send/receive edit, or contrary evidence about the copy/paste interpretation,
  blocks completion.

- [ ] Every declared behavior has a named automated test/proof.
- [ ] Causal RED, focused GREEN, and representative mutation re-red are
      recorded during execution.
- [x] Go v3 parser/publish/receive and focused Dart preservation smoke passed:
      88 Dart tests passed and all named Go internal/node selectors passed.
- [x] `completeness-check` passed 1,348/1,348.
- [x] `groups` passed with +3,235 tests.
- [x] `feature-host-all` passed all 815 paths with +8,485 tests and one skip.
- [ ] TC-282-01 is registered in `GROUP_TESTS`; existing host/Go registrations
      remain unchanged.
- [ ] No migration, schema, wire, crypto, native, relay, simulator, or device
      behavior changed.
- [x] Strict analysis completed with no issues.
- [ ] `git diff --check` is clean.
- [x] Plan 282's `runtime-roots` condition is closed: the removed payload path
      is absent, no Plan 282 finding occurred, and the later external-root
      registration plus copied-index repository-manifest selector supersede
      the historical repository-global warning.
- [ ] The architecture graph is refreshed incrementally once.
- [ ] Protected paths match the pre-edit baseline and the Scope Contract And
      Guard is respected.

## Handoff

- Plan path:
  `Test-Flight-Improv/282-duplicate-dart-group-message-payload-removal-tdd-plan.md`.
- Classification / status: `implemented-and-verified` /
  `Plan-green`; implementation is complete and the scoped plan is closed.
- Test Contract: four rows; one causal host RED and three preservation groups.
- Tiers / fixtures: host-only; repository-tree source contract, existing
  Flutter host fakes, and Go parser/node implementation tests used as
  preservation sentinels. No end-to-end crypto claim is made.
- First causal RED command:
  `flutter test --no-pub test/features/groups/domain/models/group_message_payload_removal_contract_test.dart --plain-name 'DTR10-PAYLOAD-01 removes only the duplicate Dart payload'`.
- Preservation command:
  `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./internal -run '^(TestMarshalParseGroupPayload_RoundTrip|TestGK029ParseGroupPayloadRejectsWrongSchema)$' -count=1)`.
- Manual registration: TC-282-01 is registered in `GROUP_TESTS`; existing Go
  proofs run by exact direct command.
- Migration: none.
- Boundary closure: host-only. The live Go v3 wire/crypto boundary is protected
  unchanged; no device claim is made. Any wire edit requires a separate
  availability-bounded mixed-client/two-peer plan.
- Gate cadence: exact tests + isolated-final-tree `runtime-roots` +
  completeness + `groups` + justified `feature-host-all` + incremental
  Graphify refresh; Wave 3 DTR-10 batch and final DTR release each own one full
  `host-all`.
- Confirmed: the Dart model is SUT-only; Go owns live v3 marshal/parse,
  publish, and receive; `DTR10-AUTH-06` applies only to the duplicate Dart
  pair.
- Refuted: deleting the Dart duplicate is not v3 protocol retirement and does
  not authorize rotation cleanup.
- Unresolved evidence: supported installed-client v3 retirement floor; deferred
  to Groups + Crypto + Release and not blocking this Dart-only deletion.
- Before implementation, `$tdd-review` is recommended as the independent
  counterexample audit because the duplicate's name overlaps a live wire type.

## Reviewer Findings

- Review type/date: independent `$tdd-review` counterexample audit, 2026-07-27.
- Initial verdict: `plan-fixes-required`; post-fix verdict: `ready`.
  Core bet: confirmed. Disposition: `execute`.
- Copy/paste interpretation: confirmed. Applying item 6's repeated
  rotation-wrapper sentence literally would duplicate Plan 281 and leave the
  separately named payload candidate undisposed. Current source and
  `DTR08-COMP-009` identify the bounded item-6 leaf as the unimported Dart
  `GroupMessagePayload` pair.
- Go v3 preservation: all six exact `./internal` selectors and all four exact
  `./node` publish/receive/malformed-payload selectors passed on the planning
  tree. The direct-forwarding boundary selector also passed.
- Required corrections applied:
  - extended TC-282-01 to lock its `GROUP_TESTS` registration and the current
    DTR registry, decision, compatibility, proof-command, and index post-state;
    without these assertions, stale planned/deferred records could pass;
  - added the direct-forwarding boundary and group messaging smoke tests to
    both protected baseline comparisons; the prior prose claimed the direct
    test was protected while neither preservation test path was listed;
  - made the removable Dart C4 claims and retained Go C4 claims exact, avoiding
    a same-name global deletion;
  - replaced the unusable ordinary runtime-root command with an isolated
    final-tree index;
  - added current DTR registry/compatibility bookkeeping and the required
    incremental Graphify refresh.
- Boundary verdict: host-only closure is honest because no production
  send/receive, schema, parser, crypto, bridge, native, or Go file changes. The
  Go tests are unchanged preservation sentinels, not a claim of new
  end-to-end/mixed-client protocol proof.
- Remaining uncertainty: the supported installed-client v3 retirement floor is
  still unknown and remains outside this Dart-only plan.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-07-27 | implementation applied | Dart duplicate pair; removal contract; runtime root; group gate; current C4 and DTR bookkeeping | edits applied; acceptance not yet recorded | independent review fixes and bounded Dart-only deletion are present | no implementation blocker; closure evidence pending | run focused and preservation acceptance gates |
| 2026-07-27 | closure rerun | Dart/Go preservation and host gates | Plan 282 scoped `runtime-roots` condition passed; at this original rerun, the repository-global command remained non-zero only for concurrent findings | Focused Dart smoke 88 passed; Go internal/node selectors passed; completeness 1,348/1,348; groups +3,235; feature-host-all +8,485, one skip, 815/815 paths; strict analysis clean; removed payload path absent and no Plan 282 finding occurred | Plan-green; implementation complete and scoped plan closed. The at-run integration harness and tracked deletions were outside Plan 282 and are reconciled below | Record the post-run runtime-root reconciliation |
| 2026-07-27 | post-run runtime-root reconciliation | external-root manifest and coherent copied-index repository inventory | Strict Android wrapper registered as `DTR-10 / QA`; fully staged copied-index repository-manifest selector: exit 0, `+1: All tests passed!` | The original repository-global warning is superseded; there is no current Plan 282 or global inventory blocker | Plan-green remains closed | No Plan 282 action |
