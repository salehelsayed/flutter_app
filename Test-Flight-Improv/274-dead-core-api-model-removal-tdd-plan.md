# 274 - DTR-03 dead core API and model removal

Status: Plan-green
Type: Modification
Spec: `Test-Flight-Improv/dead-code-and-technical-debt-removal-roadmap.md`
(`DTR-03`)
Classification: implementation-complete
Closure tier: host
Roadmap ID / wave: `DTR-03` / Wave 1 — Proven dependency leaves
Date: 2026-07-25

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-25 | Evidence Collector — graph | `graphify-arch/tdd_context.py`; architecture graph | The anchored TDD query surfaced `callGroupJoin`, its core bridge tests, and gate candidates. It did not surface either path-isolated core service file, and the graph is stale only for an unrelated private-media file. | Verify all three anchors, replacements, runtime roots, and registrations in current source. |
| 2026-07-25 | Evidence Collector — source/runtime census | the three DTR-03 anchors; Dart/native/tool roots; DTR-01 manifest and inventory implementation | `chat_message.dart` is unrooted with no incoming edge; the core contact listener is reachable only from its own test; `callGroupJoin` has no production/native/tool caller and refuses locally. Missing importers remain shortlist evidence, not deletion authorization. | Freeze path-specific causal assertions and replacement sentinels. |
| 2026-07-25 | Baseline verifier | runtime-root gate; core contact-listener suite; live P2P model/LAN tests; legacy/full-config bridge, MethodChannel, join/rejoin/hydrate selectors; four exact Go join tests | Every current-HEAD command passed. These runs establish the current mechanisms and adjacent preservation baseline; they are not RED/GREEN execution evidence for this plan. | Build the canonical Test Contract and literal gates. |
| 2026-07-25 | Independent refute pass | roadmap decision ledger; `DTR08-COMP-004`; live Dart/native/Go `group:join` chain | “The whole `group:join` path is dead” is refuted. Only the deprecated Dart refusal wrapper is isolated; full-config joins and native dispatch are live. The Groups decision remains `Open`, its supported-caller floor is `UNKNOWN`, and the roadmap says no compatibility row is deletion-ready. | Keep the plan evidence-gated until owner-approved floors are durable. |
| 2026-07-25 | Planner | tier matrix; plan template; gate runners; current dirty worktree | Lowest causal tier is a real-repository host source/API contract plus DTR-01 inventory reconciliation. No schema, crypto, relay, OS callback, simulator, or device behavior changes. | Run the blocking sufficiency checklist and patch structural gaps once. |
| 2026-07-25 | Independent sufficiency audit | Plan 274; sufficiency checklist; `classify_path`; existing payload assertions | Initial review found the proposed contract-test directory was not classified by `completeness-check`, and TC-DTR03-09 overstated the existing payload proof. The contract test is now under recognized `test/core/services/`, and the claim is narrowed to required fields/method selection. Structural execution details are sufficient; only the two explicit authorization records keep the plan evidence-gated. | Obtain both authorization records, then hand off for a formal `$tdd-review` before execution. |
| 2026-07-25 | `$tdd-review` counterexample audit | Plan 274; review-profile Graphify query; all caller roots; Dart/native/generated/Go join chain; gate scripts | Core bet confirmed, but the first revision was not execution-safe: `! rg` could hide operational errors, the call-pattern search missed tear-offs/exports and root/test-driver Dart, the source contract was under-specified, the “live” sentinel led with a test-only wrapper, native/generated preservation was prose-only, and the Go admission claim exceeded the selected tests. | Applied fail-closed exact-token census, explicit `DTR03-CALLER-01`, live invite/rejoin/startup sentinels, protected no-diff scope, gomobile verification, honest Go validation claims, and detailed contract construction. Verdict remains `not-ready` only because `DTR03-AUTH-01/02` are absent. |
| 2026-07-25 | Execution preflight | execution HEAD/worktree; 28 protected paths; exact owned-source caller roots; legacy refusal selector | `DTR03-CALLER-01` passed against `a68aacee7482f910f966d33d16d3c7598489f059`: one declaration token, four SUT-only calls, six test tokens, zero other owned/current Dart or native/Go/platform tokens, zero export facades, `publish_to: none`; protected paths and real index are clean; the legacy refusal selector passed. | Keep production and causal-test edits stopped until named `DTR03-AUTH-01/02` records are supplied and the readiness audit is rerun. |
| 2026-07-25 | Authorization recorder | current authenticated project-owner thread approval; `DTR03-CALLER-01`; exact scope/retention/rollback contract | The current authenticated thread user identified themself as the authorized Core Services and Groups owner, approved both exact DTR-03 removals, and confirmed that the old group-join function has no supported external users. `DTR03-AUTH-01` and `DTR03-AUTH-02` below now bind that statement to the exact plan boundaries; AUTH-02 accepts the recorded execution source set as the complete supported external/path/git/raw caller floor. | Authorization blocker cleared. Begin causal RED and scoped implementation; do not claim Plan-green until every implementation and verification gate passes. |

## Problem And Evidence

- Behavior to improve: remove the three behind-the-scenes DTR-03 surfaces that
  current source no longer uses, while keeping the real P2P message model,
  contact-request processing, and full-config group-join path unchanged.
- Impact: the duplicate model claims to be canonical, the hollow listener and
  its SUT-only tests describe behavior the production app does not use, and the
  deprecated topic-only wrapper leaves an invalid public API available. These
  surfaces misdirect maintenance and preserve obsolete test/code weight.
- Confirmed pre-removal gaps:
  - `lib/core/services/chat_message.dart:8-47` defines a second `ChatMessage`
    with `DateTime` timestamps and unused `fromEventData`/`fromLocal` factories.
    It has no incoming Dart edge. DTR-01 records it as an unrooted `candidate`
    at `tool/runtime_roots/runtime_roots.json:417-423`.
  - The live model is instead
    `lib/features/p2p/domain/models/chat_message.dart:2-117`.
    `P2PServiceImpl` constructs it directly for LAN receive at
    `lib/core/services/p2p_service_impl.dart:482-508`; the obsolete core
    `fromLocal` factory is not part of that path.
  - `lib/core/services/contact_request_listener.dart:15-47` is a raw
    pass-through with unfinished persistence/key/feed TODOs at `:36-38`.
    Its sole importer is
    `test/core/services/contact_request_listener_test.dart:3`; DTR-01 therefore
    records it as test/integration-reachable at
    `tool/runtime_roots/runtime_roots.json:426-437`.
  - Production imports the feature listener at `lib/main.dart:100`, constructs
    it at `:3443-3469`, starts it at `:4819-4822`, and disposes it at
    `:7016-7017`. That implementation owns typed models, persistence, replay,
    error handling, and explicit lifecycle at
    `lib/features/contact_request/application/contact_request_listener.dart:62-190`.
  - Deprecated `callGroupJoin` at
    `lib/core/bridge/bridge_group_helpers.dart:104-134` ignores `topicName` and
    `timeout`, never sends to the bridge, and always throws
    `LEGACY_JOIN_UNSUPPORTED`. Its only four invocations are legacy-only
    assertions in `test/core/bridge/bridge_group_helpers_test.dart`.
    The review census found one declaration token in the helper, four call
    expressions plus one group label and one comment in that test, and zero
    exact-symbol references in every other owned/current Dart, native, Go,
    tool, root-level, or `test_driver` source. In this plan, “no callers” means
    zero supported/runtime callers; the four SUT-only test calls are removed
    atomically with their obsolete SUT.
  - Live `callGroupJoinWithConfig` is declared at
    `lib/core/bridge/bridge_group_helpers.dart:140` and its implementation sends
    `groupId`, `groupConfig`, `groupKey`, and `keyEpoch`. Current callers include
    accepted/incoming invite flows and `rejoinGroupTopics`; the Dart dispatch
    remains `group:join -> groupJoinTopic` at
    `lib/core/bridge/go_bridge_client.dart:173-176`, with live Android, iOS,
    macOS, and Go handlers.
- Pre-removal coverage baseline:
  - `test/features/p2p/domain/models/chat_message_test.dart` covers the active
    model; its current full run passed.
  - `test/core/services/p2p_service_inbound_transport_test.dart::T5: local WiFi
    messages surface as wifi and are censused` covers the active LAN conversion;
    the current selector passed.
  - The obsolete contact-listener suite currently passes six tests, confirming
    it is a self-contained SUT-only island rather than replacement proof.
  - `test/features/contact_request/application/contact_request_listener_test.dart::emits
    ContactRequestModel for valid v2` covers the live replacement and passed on
    current HEAD.
  - The exact full-config helper, MethodChannel BB-007, application BB-006, and
    rejoin/hydrate selectors named below all passed on current HEAD; the four
    exact Go join tests also passed.
  - The formal review additionally passed the live incoming-invite and pending-
    invite selectors, both direct rejoin selectors, the cold-start
    `PB264-18` rejoin/inbox ordering selector, all four adjacent Go validation
    tests named below, and `./scripts/verify_gomobile_bindings.sh all`.
  - `./scripts/run_test_gates.sh runtime-roots` passed its current unit suite and
    trustworthy/no-drift real-tree check.
- Resolved coverage gap: the added causal contract now requires the retired
  files, SUT-only suite, manifest declarations, legacy wrapper/tests, and
  current architecture-document claims to disappear together.
- Refuted findings:
  - “`lib/core/services/chat_message.dart` is the canonical or re-exported
    model” is refuted by its separate class definition and zero incoming edge.
  - “The core contact listener is production contact-request handling” is
    refuted by the feature listener's `main.dart` lifecycle and the core file's
    sole test importer.
  - “Removing `callGroupJoin` retires `group:join`” is refuted by live
    `callGroupJoinWithConfig`, Dart/native dispatch, and Go full-config
    validation.
  - “DTR-08 completion authorizes deletion” is refuted by roadmap lines
    `218`, `565`, `570`, `594`, and `603-605`.
- Authorization findings:
  - `DTR03-AUTH-01` is approved by the current authenticated project owner
    acting as Core Services owner for the exact two service paths and their
    obsolete test/metadata/current-doc claims.
  - `DTR03-AUTH-02` is approved by the same project owner acting as Groups
    owner for only the deprecated Dart wrapper and its legacy test fragments.
    It explicitly accepts `DTR03-CALLER-01` as the complete supported
    external/path/git/raw caller floor and confirms that the old group-join
    function has no supported external users.
  - The authorization blocker is resolved. The authorized implementation and
    causal/closure verification completed on 2026-07-25; the receipts remain
    authorization evidence rather than substitutes for the execution evidence
    recorded below.
- Affected production, test, metadata, and current-architecture files:
  - delete `lib/core/services/chat_message.dart`;
  - delete `lib/core/services/contact_request_listener.dart`;
  - edit `lib/core/bridge/bridge_group_helpers.dart`;
  - delete `test/core/services/contact_request_listener_test.dart`;
  - edit `test/core/bridge/bridge_group_helpers_test.dart`;
  - add
    `test/core/services/dtr03_dead_core_surface_contract_test.dart`;
  - edit `test/unit/runtime_root_inventory_test.dart` and
    `tool/runtime_roots/runtime_roots.json`;
  - reconcile `file-structure.md`, `C4_MODEL.md`, `C4/file-structure.md`,
    `C4/code.md`, and `C4/components.md`;
  - update this plan and the DTR roadmap/index ledgers.

## Graph Grounding Snapshot (Pre-removal)

- Graph fingerprint / freshness:
  `fc333c615c1b3e10`;
  `stale:lib/features/conversation/presentation/screens/direct_private_media_viewer.dart`.
- Query / profile:
  `python3 graphify-arch/tdd_context.py query "DTR-03 remove dead core APIs/models: lib/core/services/chat_message.dart, lib/core/services/contact_request_listener.dart, callGroupJoin in lib/core/bridge/bridge_group_helpers.dart; find runtime roots, callers, tests, DTR-01 classifier inventory, core-host-all and focused gate registrations" --profile tdd --budget 700`.
- Review query / profile:
  `python3 graphify-arch/tdd_context.py query "Plan 274 DTR-03 counterexample audit: prove deprecated callGroupJoin has no callers, exports, reflection/string/native/generated entrypoints; preserve callGroupJoinWithConfig callers, rejoinGroupTopics lifecycle, group:join to groupJoinTopic native Android iOS macOS and Go GroupJoinTopic mapping; verify DTR08-COMP-004 exact tests and gates" --profile review --budget 800`.
  It returned `confidence=anchored` with the same fingerprint/freshness,
  anchored `callGroupJoinWithConfig` and `rejoinGroupTopics`, and produced
  noisy shared-import bypass candidates; current-source census, not graph
  absence, carries the caller conclusion.
- Anchors:
  `callGroupJoin -> lib/core/bridge/bridge_group_helpers.dart:109`
  (`lib_core_bridge_bridge_group_helpers_callgroupjoin`).
- Surfaced proof/gate files:
  `test/core/bridge/bridge_group_helpers_test.dart`,
  `test/core/bridge/go_bridge_client_test.dart`,
  `scripts/run_host_test_gates.sh`, and `scripts/run_test_gates.sh`.
- Graph gaps requiring source search: neither path-isolated service file was
  surfaced by the compact result; DTR-01 declarations, the live feature
  replacements, exact source/native callers, obsolete SUT-only tests, and
  current architecture docs were verified directly.
- Reuse rule: anchors may be handed to review/execution; all conclusions still
  require current-source or command evidence.

### Closure Graph Snapshot

- The required incremental refresh completed once after the coherent deletion.
- The refreshed architecture graph is current at fingerprint
  `06cfd529b61c6e10`.
- The closure review query anchors retained `callGroupJoinWithConfig`,
  `rejoinGroupTopics`, the feature P2P `ChatMessage`, and feature
  contact-request coverage. It does not surface the retired Core service nodes
  or the exact deprecated wrapper.

### DTR03-CALLER-01 Execution Transcript

- Date: 2026-07-25.
- Execution baseline:
  `a68aacee7482f910f966d33d16d3c7598489f059` plus the recorded dirty
  Wave 0/planning worktree; the real Git index had no staged changes.
- Protected baseline: all 28 `DTR03_PROTECTED_GROUP_PATHS` were byte-for-byte
  clean against execution HEAD.
- Exact-token result:
  `declaration_tokens=1`, `test_calls=4`, `test_tokens=6`,
  `other_owned_current_dart_tokens=0`, `native_go_platform_tokens=0`, and
  `dart_export_facades=0`.
- Publication/caller floor evidence: `pubspec.yaml` contains
  `publish_to: 'none'`; the declaration is at
  `lib/core/bridge/bridge_group_helpers.dart:109`; all six test tokens are
  confined to `test/core/bridge/bridge_group_helpers_test.dart`.
- Behavioral floor:
  `BB-006 rejects topic-name-only helper before bridge send` passed and
  observed `LEGACY_JOIN_UNSUPPORTED`.
- Interpretation: the fail-closed repository census is complete and green.
  `DTR03-AUTH-02` below now accepts this execution source set as the complete
  supported external/path/git/raw caller floor, so it authorizes only the
  wrapper removal bounded by that receipt. It does not authorize any live
  full-config, native, Go, wire, or DTR-10 change.

### Authorization Receipts — Approved 2026-07-25

Sanitized evidence reference for both receipts: the current authenticated
project-owner thread user stated on 2026-07-25, “I am the authorized Core
Services and Groups owner. I approve both DTR03 removals and confirm the old
group-join function has no supported external users.” The records below bind
that approval to the exact scopes, retentions, caller floor, and rollback
boundaries reviewed in this plan.

#### `DTR03-AUTH-01` — Approved

- Approver: current authenticated thread user, identified as project owner and
  acting as the authorized Core Services owner.
- Approval date: 2026-07-25.
- Decision: approve deletion of exactly
  `lib/core/services/chat_message.dart`,
  `lib/core/services/contact_request_listener.dart`,
  `test/core/services/contact_request_listener_test.dart`, their two DTR-01
  declarations/expectations, and only their stale claims in `file-structure.md`,
  `C4_MODEL.md`, `C4/file-structure.md`, `C4/code.md`, and
  `C4/components.md`.
- Retain exactly the feature P2P model at
  `lib/features/p2p/domain/models/chat_message.dart`, the feature
  contact-request listener and its production lifecycle at
  `lib/features/contact_request/application/contact_request_listener.dart` and
  `lib/main.dart`, and `test/core/services/fake_p2p_service.dart`.
- Rollback: restore the exact two retired sources, their SUT-only test, both
  inventory rows/expectations, and their current-architecture claims together.
  Do not substitute a compatibility export or alter the retained feature
  implementations.

#### `DTR03-AUTH-02` — Approved

- Approver: current authenticated thread user, identified as project owner and
  acting as the authorized Groups owner.
- Approval date: 2026-07-25.
- Decision: approve removal of only the deprecated Dart `callGroupJoin`
  refusal wrapper and its four SUT-only call assertions/associated legacy test
  fragments.
- Caller-floor decision: accept `DTR03-CALLER-01`'s recorded execution source
  set as the complete supported external/path/git/raw caller floor and confirm
  that `callGroupJoin` has no supported external users.
- Retain exactly `callGroupJoinWithConfig`, `rejoinGroupTopics`,
  `group:join`, `groupJoinTopic`, all generated bindings/native handlers, Go
  `GroupJoinTopic`, and DTR-10-owned `joinGroup`/`hydrateGroupsFromPeers`.
- Rollback: restore only the exact refusal wrapper and its legacy test
  fragments. No storage, wire, native, generated-binding, Go, protocol, or
  DTR-10 rollback applies to this wrapper-only leaf removal.

## Scope Contract And Guard

In scope:

- Delete the duplicate core `ChatMessage` definition, not replace it with a
  compatibility export.
- Delete the hollow core `ContactRequestListener` and its six-case SUT-only test
  atomically.
- Remove both retired paths from DTR-01 declarations and make the real-tree
  inventory test assert exact absence without pinning a new aggregate
  test/integration-reachable count.
- After `DTR03-CALLER-01` and `DTR03-AUTH-02` are accepted, remove only the
  deprecated production symbol `callGroupJoin` and the four legacy-only
  invocations/assertions that test its local refusal.
- Add a real-repository source/API contract that detects restoration of any
  retired surface while pinning the active replacement paths.
- Remove stale claims about these exact surfaces from the current architecture
  files named above. Historical Test-Flight plans/audits remain historical.
- Refresh the architecture graph incrementally once after the coherent
  app-owned deletion.

Must preserve:

- Active P2P `ChatMessage` parse/serialization/privacy behavior ->
  `test/features/p2p/domain/models/chat_message_test.dart`.
- Local WiFi conversion into the active model with `transport == 'wifi'` ->
  `p2p_service_inbound_transport_test.dart::T5`.
- Production feature contact-request parsing/persistence/emission ->
  `contact_request_listener_test.dart::emits ContactRequestModel for valid v2`.
- Every other DTR-01 candidate, retained root, computed origin, restricted root,
  and the advisory/non-deletion semantics -> the real-tree inventory test and
  `runtime-roots`.
- Full-config group-join payload and MethodChannel method ->
  `bridge_group_helpers_test.dart::sends group:join with groupId, groupConfig,
  groupKey, keyEpoch` and `go_bridge_client_test.dart::BB-007
  callGroupJoinWithConfig forwards exact full config payload to groupJoinTopic`.
- Live accepted/incoming invite materialization, `rejoinGroupTopics` payloads,
  and cold-start rejoin ordering -> the exact tests in TC-DTR03-10.
- Dart `group:join -> groupJoinTopic`, Android/iOS/macOS wrapper routing,
  generated gomobile exports, and Go rejection/round-trip/validation/
  idempotence/newer-key refresh -> protected no-diff paths,
  `verify_gomobile_bindings.sh all`, and TC-DTR03-11.
- DTR-10-owned test-only `joinGroup` and `hydrateGroupsFromPeers` islands ->
  TC-DTR03-12.

Hard `Do not`:

- Do not delete, export through the retired paths, or otherwise edit the live
  feature P2P model or feature contact-request listener.
- Do not change `group:join`, `groupJoinTopic`, `GroupJoinTopic`, any native
  registration/generated binding, full-config payload fields, error/timeout
  behavior, group persistence, or wire/crypto semantics.
- Do not delete or disposition test-only `joinGroup` or
  `hydrateGroupsFromPeers`; DTR-10 owns those separate decisions.
- Do not remove `test/core/services/fake_p2p_service.dart`; other tests use it.
- Do not treat Graphify output, analyzer cleanliness, zero importers, DTR-01
  `candidate`, or test-only reachability as owner approval.
- Do not edit the harmless
  `integration_test/group_multi_party_device_real_harness.dart` compatibility
  event set in this host-only leaf plan; it accepts the live config event and
  its extra retired label is not a caller or producer.
- Do not add a schema migration, dependency change, device/relay proof, broad
  refactor, or per-plan full `host-all`.

Deferred / accepted difference:

- `joinGroup`, `hydrateGroupsFromPeers`, and their test-only islands remain
  decision-blocked under DTR-10 / Groups.
- The group multi-party device harness may keep the never-produced
  `GROUP_FL_BRIDGE_JOIN_REQUEST` compatibility label; owner Groups QA / device
  harness maintenance may remove it with that harness's own proof, not this
  deletion.
- Historical reports may continue to name retired surfaces as historical
  evidence. Current architecture docs must not.

Dependencies:

- DTR-01 and DTR-02 are Wave-accepted; DTR-08 is Ledger-complete but explicitly
  non-authorizing.
- `DTR03-AUTH-01` and `DTR03-AUTH-02` are satisfied prerequisites. Their exact
  receipts above authorize only this plan's bounded deletions; any withdrawn
  or broadened decision requires a retained/deferred disposition and plan
  revision rather than partial execution under a different contract.

### DTR08-COMP-004 Closure Contract

- `DTR08-COMP-004` is resolved for only the DTR-03 `callGroupJoin` refusal
  wrapper: `DTR03-AUTH-02` accepts the recorded source set as its complete
  supported external/path/git/raw caller floor. The row remains `Open /
  UNKNOWN` for DTR-10-owned `joinGroup` and `hydrateGroupsFromPeers`; the live
  full-config join path is retained rather than dispositioned.
- `DTR03-CALLER-01` is a durable pre-edit transcript tied to the execution
  commit/worktree. It must prove one helper declaration, exactly four SUT-only
  call expressions in `bridge_group_helpers_test.dart`, and exact-token absence
  from every other owned/current Dart, root-level Dart, `test_driver`, native,
  Go, tool, and package source. It must also prove `publish_to: none` and no
  export facade for `bridge_group_helpers.dart`.
- The census was necessary but not self-authorizing. `DTR03-AUTH-02` now names
  the Groups approver identity/role, date/evidence, exact `callGroupJoin`
  symbol, supported external/path/git/raw caller set, rollback, and explicit
  retention of `callGroupJoinWithConfig`, `rejoinGroupTopics`, `group:join`,
  `groupJoinTopic`, generated bindings, native handlers, and Go
  `GroupJoinTopic`.
- The platform-dispatch test requested by `DTR08-COMP-004` is conditional on a
  mapping change. This plan forbids such a change, checks protected files
  against `HEAD`, verifies generated exports, and stops rather than broadening
  into native/platform work.
- `joinGroup` and `hydrateGroupsFromPeers` remain separate DTR-10 decisions.
  Approval for the deprecated refusal helper never authorizes their deletion.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-DTR03-01 | The duplicate core `ChatMessage` file, DTR-01 declaration, and current-doc claims are absent. | `test/core/services/dtr03_dead_core_surface_contract_test.dart::DTR03-01 duplicate core ChatMessage model and declaration are absent` | Host source/API contract / real repository | Scaffolded assertion RED: HEAD contains the file, manifest row, and current-doc claims -> GREEN: all are absent and the active feature model path exists. | Restore the file or manifest/doc entry -> TC-DTR03-01 red; restoring only the file also makes `runtime-roots` report an unreviewed non-main source. | `flutter test --no-pub test/core/services/dtr03_dead_core_surface_contract_test.dart --plain-name 'DTR03-01 duplicate core ChatMessage model and declaration are absent'`; AUTO (`test/core/**/*_test.dart`) in `core-host-all` and classified as core services by `completeness-check`. |
| TC-DTR03-02 | The active feature `ChatMessage` remains the canonical parse/serialization/privacy type. | `test/features/p2p/domain/models/chat_message_test.dart::round-trips through fromJson and toJson`; `test/features/p2p/domain/models/chat_message_test.dart::fromJson never parses predecryptedText (not a wire field)`; `test/features/p2p/domain/models/chat_message_test.dart::toJson excludes predecryptedText (never serialized to wire/DB)` | Unit host / no fake | GREEN sentinel on HEAD -> the named active-model contracts remain green after deletion. | Stop preserving the parsed timestamp or parse/serialize `predecryptedText` -> the corresponding named test red. | `flutter test --no-pub test/features/p2p/domain/models/chat_message_test.dart`; AUTO (`test/features/**`) for later `feature-host-all`/`host-all`; exact direct per-plan command. |
| TC-DTR03-03 | Local WiFi messages still convert directly to the active model with truthful transport telemetry. | `test/core/services/p2p_service_inbound_transport_test.dart::T5: local WiFi messages surface as wifi and are censused` | Core host integration / fake local P2P service | GREEN sentinel on HEAD -> one active `ChatMessage`, `wifi` transport, exact census after deletion. | Remove `transport: 'wifi'` or bypass the active model in `P2PServiceImpl` -> TC-DTR03-03 red. | `flutter test --no-pub test/core/services/p2p_service_inbound_transport_test.dart --plain-name 'T5: local WiFi messages surface as wifi and are censused'`; AUTO core; already in `ONE_TO_ONE_TESTS`. |
| TC-DTR03-04 | The hollow core contact listener, its SUT-only suite, DTR-01 declaration, and current-doc claims are absent while `main.dart` retains the feature import. | `test/core/services/dtr03_dead_core_surface_contract_test.dart::DTR03-02 hollow core contact listener and SUT-only suite are absent` | Host source/API contract / real repository | Scaffolded assertion RED: all retired artifacts exist on HEAD -> GREEN: source/test/metadata/docs are absent and `main.dart` still imports the feature listener. | Restore the source, core package import, test, manifest row, or stale current-doc entry -> TC-DTR03-04 red. | `flutter test --no-pub test/core/services/dtr03_dead_core_surface_contract_test.dart --plain-name 'DTR03-02 hollow core contact listener and SUT-only suite are absent'`; AUTO core and classified as core services. |
| TC-DTR03-05 | The production feature listener still processes a valid encrypted request and emits the typed model. | `test/features/contact_request/application/contact_request_listener_test.dart::emits ContactRequestModel for valid v2` | Application host / stream, repository, bridge fakes | GREEN sentinel on HEAD -> one valid typed request remains emitted after deletion. | Skip the feature subscription/processor or import the retired core listener -> selector or strict analysis red. | `flutter test --no-pub test/features/contact_request/application/contact_request_listener_test.dart --plain-name 'emits ContactRequestModel for valid v2'`; explicit `ONE_TO_ONE_TESTS` registration at `scripts/run_test_gates.sh:75`. |
| TC-DTR03-06 | DTR-01 accounts for the final tree, drops only the two retired declarations/candidate expectation, and preserves every other reviewed/restricted root. | `test/unit/runtime_root_inventory_test.dart::repository manifest accounts for current non-main sources and keeps known candidates advisory` | Tool/unit host plus real Git-visible tree | Causal assertion RED after expectations are changed first: HEAD still reports the retired paths -> GREEN: no retired path, no drift, all restricted roots valid, other exact candidates preserved; no new fixed aggregate count. | Restore either source/declaration or drop another candidate/restricted-root record -> named test or real check red. | After the literal isolated-index setup below: `GIT_INDEX_FILE="$DTR03_INDEX_DIR/index" ./scripts/run_test_gates.sh runtime-roots`; existing manual `runtime-roots` registration runs the unit suite and real check. |
| TC-DTR03-07 | The execution commit has a fail-closed zero-runtime-caller record, and named owners approve only the exact deletion scope without authorizing live group protocol removal. | `DTR03-CALLER-01` plus `DTR03-AUTH-01` Core services approval and `DTR03-AUTH-02` Groups / `DTR08-COMP-004` decision record | Governance/source evidence / real owned-source census | HEAD census: one declaration, four SUT-only calls, zero other owned-source references -> accepted 2026-07-25 records bind that transcript to the execution source set and name approver identity/role, date/evidence, supported caller floor, rollback, and retained full-config/native behavior. | N/A for approvals; add a tear-off/export/runtime call or make `rg` fail -> `DTR03-CALLER-01` fails before deletion. Missing, ambiguous, withdrawn, or broader approval stops execution. | MANUAL + literal fail-closed census below; roadmap decision/compatibility ledger and sanitized approval evidence are recorded before production deletion. |
| TC-DTR03-08 | After the pre-edit caller floor is accepted, the deprecated topic-name-only Dart API, all exact-symbol active-source residue, `LEGACY_JOIN_UNSUPPORTED` helper assertions, and only its legacy test fragments are absent. | `test/core/services/dtr03_dead_core_surface_contract_test.dart::DTR03-03 deprecated topic-only group-join API and legacy tests are absent` | Host source/API contract / fail-closed real-repository enumeration | Scaffolded assertion RED: HEAD has the declaration, four calls, group label/comment, and legacy error assertions -> GREEN: whole-token owned-source census is empty, helper/test files still exist, current C4 claims are gone, and full-config declaration/test remain. | Restore the declaration or add `final legacyJoin = <retired symbol>;` in another owned Dart file -> TC-DTR03-08 red; unreadable/missing roots or files fail rather than count as absence. | Exact `flutter test --no-pub ... --plain-name ...`; AUTO core and classified as core services; the literal selector must report exactly one selected test. |
| TC-DTR03-09 | Full-config helper required fields and Dart MethodChannel method selection remain exact. | `test/core/bridge/bridge_group_helpers_test.dart::sends group:join with groupId, groupConfig, groupKey, keyEpoch`; `test/core/bridge/go_bridge_client_test.dart::BB-007 callGroupJoinWithConfig forwards exact full config payload to groupJoinTopic` | Core host / fake bridge and fake MethodChannel | GREEN sentinels on HEAD -> same command, four required fields, absence of `topicName`, and `groupJoinTopic` method after wrapper deletion. | Drop/change `groupKey` or `keyEpoch`, restore `topicName`, change command/method -> at least one named test red. | Two exact `flutter test --no-pub ... --plain-name ...` commands; AUTO core in `core-host-all`; not covered by the curated `groups` gate, so run directly. |
| TC-DTR03-10 | Live pending/incoming invite materialization and `rejoinGroupTopics` retain the full-config join, and cold startup still runs rejoin before inbox drain. | `test/features/groups/application/accept_pending_group_invite_use_case_test.dart::accepts pending invite, persists group, and drains inbox`; `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart::calls group:join bridge command with groupId, groupConfig, groupKey, keyEpoch`; `test/features/groups/application/rejoin_group_topics_use_case_test.dart::{calls callGroupJoinWithConfig for each active group, builds correct groupConfig from stored members}`; `test/features/identity/presentation/screens/startup_router_recovery_test.dart::PB264-18 cold startup recovers exits after rejoin and inbox drain without resume` | Application host / repository, stream, bridge, and startup fakes | GREEN sentinels on HEAD -> real invite paths send/join, stored members/key/epoch form the rejoin payload, every active group rejoins, and cold startup ordering remains green. | Remove a live invite/rejoin call, drop a required payload field, or remove cold-start rejoin -> the corresponding exact test red. | Exact commands below; accept/incoming/rejoin are in `GROUP_TESTS`; cold-start recovery is an exact per-plan command because it is in baseline rather than `GROUP_TESTS`. |
| TC-DTR03-11 | Dart mapping, Android/iOS/macOS handlers, generated gomobile exports, and Go join behavior remain unchanged; Go still rejects topic-only/invalid key/member/device material and preserves valid round-trip, idempotence, and newer-state refresh. | protected-path `git diff HEAD --quiet`; `scripts/verify_gomobile_bindings.sh all`; `go-mknoon/bridge/bridge_test.go::{TestGroupJoinTopic_BB006RejectsLegacyTopicNameOnlyPayload, TestGroupJoinTopic_RejectsInvalidKeyState, TestSV009GroupJoinAndUpdateConfigRejectMalformedMemberKeys, TestGroupJoinTopic_RejectsIncompleteActiveMemberKeyMaterial, TestGroupJoinTopic_RejectsMalformedActiveDeviceTransportPeerId, TestGroupJoinTopic_BB007RoundTripsFullConfigAndAcceptsPublish, TestGroupJoinTopic_AlreadyJoinedIsIdempotent, TestGroupJoinTopic_BB008AlreadyJoinedRefreshesNewerKeyAndConfig}` | Source-integrity plus generated native binding and real Go unit boundary | GREEN on HEAD -> protected files are clean, wrappers resolve generated exports, and eight exact Go behaviors pass; GREEN after deletion requires the same byte-for-byte protected sources and results. | Edit a protected label/function, remove a generated export, accept topic-only/invalid material, break valid join/idempotence/refresh -> no-diff, verifier, or named Go proof red. | Literal protected-path, binding-verifier, digest, and exact Go commands below; manual exact registration. No claim is made that Go rejects an otherwise empty `groupConfig`. |
| TC-DTR03-12 | DTR-10-owned test-only `joinGroup` and `hydrateGroupsFromPeers` islands remain present and unchanged. | `test/features/groups/application/join_group_use_case_test.dart::BB-006 joins with full config payload and no topicName`; `test/features/groups/application/hydrate_groups_from_peers_use_case_test.dart::{is a no-op (no side effects) when multiDeviceSync is off, when on, rejoins topics and drains only non-dissolved groups, PB264-11 hydrate processes an exit phase without rejoining or draining it}` | Application host / repository and bridge fakes | GREEN sentinels on HEAD -> both separately decision-blocked islands remain after the refusal-helper deletion. | Delete or retarget either DTR-10 island -> protected no-diff or an exact test red. | Exact Flutter commands below; `join_group_use_case_test.dart` is in `GROUP_TESTS`; hydrate remains a manual exact registration. |

### Test Notes

- TC-DTR03-01/04/08: construct exact dead identifiers in the source-contract
  test from split string fragments so the contract itself does not become a
  false caller. Require the helper and bridge-test files plus every owned root
  to exist/read successfully. Enumerate `.dart` files under `lib`, `test`,
  `integration_test`, `test_driver`, `tool`, and `packages`, plus root-level
  Dart entrypoints, without following derived-cache symlinks. Fail on any
  enumeration/read error. TC-DTR03-08 scans the whole exact identifier token,
  not only `name(`; requires `LEGACY_JOIN_UNSUPPORTED` absent from the active
  helper/test; requires the full-config declaration and named payload test
  present; and checks the named current C4 files, not historical Test-Flight
  documents.
- TC-DTR03-07/08 mutation proof has two legs: restore the declaration and add a
  non-call reference such as a tear-off in a different owned Dart file. Each
  must re-red independently, then be reverted.
- TC-DTR03-06: DTR-01 intentionally flags an unstaged tracked deletion as
  `tracked-path-deleted`. Run the final real-tree gate with an isolated
  temporary Git index containing only the exact DTR-03 final-tree paths. Do not
  stage or rewrite the user's real index.
- TC-DTR03-07: approval of the deprecated wrapper is not approval to remove
  `joinGroup`, `hydrateGroupsFromPeers`, `group:join`, native handlers,
  generated bindings, Go `GroupJoinTopic`, or any persisted/wire behavior.
- TC-DTR03-11: the MethodChannel test stops at a mock. Native/generated
  preservation therefore rests on byte-for-byte protected tracked sources,
  Android/iOS binding-input stamps, `verify_gomobile_bindings.sh all`, and real
  Go tests. The selected Go tests preserve exact current validation behavior
  but do not claim that an empty `groupConfig` is rejected.
- Production-critical end-to-end leg: N/A — the retired wrapper cannot reach
  the bridge, and this plan hard-forbids changes to the live command, native,
  wire, crypto, or transport boundary. Host Dart/MethodChannel plus real Go
  sentinels prove the adjacent unchanged boundary; a device leg would not be
  causal for source-leaf absence.

## Implementation Steps

1. Snapshot `git rev-parse HEAD`, `git status --short`, the current index state,
   and path-scoped diffs. Require every TC-DTR03-10/11/12 protected path to be
   clean against `HEAD` before work; otherwise stop and rebase the preservation
   baseline rather than absorbing an unrelated change.
2. Run the fail-closed pre-edit exact-token census and the current BB-006 local-
   refusal selector. Record the outputs as `DTR03-CALLER-01`, including the
   execution commit/worktree, one declaration, four SUT-only call expressions,
   six total test-file tokens, zero other owned-source token, `publish_to:
   none`, and no export facade. Any extra token, missing root, unreadable file,
   or `rg` status other than the expected `0`/`1` is a hard stop.
3. Verify the recorded `DTR03-AUTH-01` and `DTR03-AUTH-02` receipts and the
   matching roadmap decision/caller-floor records. They were approved on
   2026-07-25 by the current authenticated project owner acting in both named
   roles. Stop if either approval is withdrawn, becomes ambiguous, or is
   interpreted to authorize a broader protocol change. The authorization
   addendum below resolves the prior review's only open blocker and marks this
   exact scope ready for execution; it does not claim implementation or GREEN.
4. Snapshot the current focused baselines before introducing RED.
   The planning tree already contains user-owned/uncommitted DTR-01/DTR-02 work;
   do not overwrite, stage, or reformat unrelated changes.
5. Add
   `test/core/services/dtr03_dead_core_surface_contract_test.dart` with
   TC-DTR03-01, TC-DTR03-04, and TC-DTR03-08. Change the DTR-01 real-tree
   expectation to the final five-candidate set and replace the fixed current
   test/integration-reachable aggregate assertion with exact retired-path
   absence plus the existing exact candidate/restricted-root assertions.
   Implement the fail-closed owned-root enumeration, whole-token/legacy-error
   absence, required helper/test file existence, full-config declaration/test
   presence, and current-C4 checks from Test Notes.
   Run each named causal test before production edits and record assertion-level
   RED for the expected current artifact only.
6. Delete `lib/core/services/chat_message.dart`; remove only its exact DTR-01
   declaration; remove its stale current-architecture entries; keep the active
   feature model untouched. Run TC-DTR03-01 through TC-DTR03-03. Stop if any
   importer, runtime root, factory consumer, or non-doc string registration
   appears.
7. Delete `lib/core/services/contact_request_listener.dart` and
   `test/core/services/contact_request_listener_test.dart` atomically; remove
   only the exact DTR-01 declaration and stale current-architecture entries.
   Keep `test/core/services/fake_p2p_service.dart`. Run TC-DTR03-04/05. Stop if
   a non-SUT-only caller appears or `main.dart` does not retain the feature
   listener lifecycle.
8. Remove only `bridge_group_helpers.dart:104-134` by symbol, not by stale line
   range. In `bridge_group_helpers_test.dart`, remove the legacy half of the
   mixed BB-002 test, the two-test legacy group, and the legacy
   `BridgeCommandException` case. The mixed test already has the correct config-
   join name; do not rename it. Retain its full-config half, the full-config
   error case, `_SlowBridge`, and `_bridgeCommandError`, which have other
   consumers. Remove only exact legacy API claims from current C4 docs. Do not
   edit the live command mapping, native/Go sources, generated artifacts,
   integration harness, feature join/hydrate sources, or full-config tests.
   Require the helper diff to be exactly zero additions and 31 deletions, then
   run TC-DTR03-08 through TC-DTR03-12.
9. Run the DTR-01 real-tree gate through the isolated final-tree index from
   Acceptance Gates. Confirm the two retired paths disappear, the remaining
   candidates stay exact, all restricted roots validate, and the command exits
   `0`. Never repin the incidental aggregate from `60` to `59`.
10. Run focused GREEN, live invite/rejoin/startup sentinels, the protected-path
    guard, Android/iOS binding-input digest checks,
    `verify_gomobile_bindings.sh all`, eight exact Go tests, `runtime-roots`,
    `1to1`, `groups`, and the justified `core-host-all`. Run strict analysis,
    completeness, and diff hygiene. Zero test failures, changed protected paths,
    stale/missing generated exports, analyzer issues, unclassified paths, and
    whitespace errors are required.
11. Refresh the app architecture graph once with
   `./graphify-arch/refresh_arch_graph.sh --incremental`. Verify the deleted
   source nodes are gone and record the new fingerprint; do not run a full
   topology/export rebuild.
12. Update plan execution evidence, the DTR-03 registry link/state, decision
    receipts, and candidate reconciliation totals. Mark DTR-03 `Plan-green`
    only after all three deletions and every per-plan gate pass. Wave 1 and
    final full-gate evidence remain roadmap-owned.

## Risks And Blind Spots

- A public top-level Dart API can have an external/raw consumer absent from the
  repository census -> `DTR03-AUTH-02` must resolve the supported-caller floor;
  TC-DTR03-08 is proof after authorization, not authorization itself.
- A naive `! rg '\bcallGroupJoin\('` can miss tear-offs/whitespace and treat
  operational status `2` as success -> all absence checks use a fail-closed
  helper, the exact identifier token, and the complete owned source set.
- The planned source-contract file does not yet exist and could be implemented
  narrowly -> Test Notes require file/root existence, fail-closed enumeration,
  whole-token and legacy-error absence, current-doc checks, and independent
  declaration/tear-off mutations.
- Same-named live/retired models and listeners can make class-name searches
  misleading -> TC-DTR03-01/04 use exact package paths and pin active paths.
- Removing the obsolete contact test could be misreported as lost product
  coverage -> TC-DTR03-05 proves the real feature listener; the obsolete suite
  must be deleted only with its SUT.
- An adjacent edit could retire live `group:join` behavior -> TC-DTR03-09/10/11,
  the exact 31-line deletion invariant, protected no-diff paths, live
  invite/rejoin/startup tests, `groups`, generated binding verification, Go
  proof, and core sweep constrain the edit to the local refusal wrapper.
- The MethodChannel fake cannot exercise Kotlin/Swift/generated dispatch ->
  TC-DTR03-11 requires byte-for-byte protected tracked sources, binding-input
  stamps, and `verify_gomobile_bindings.sh all`; any desired mapping edit is a
  hard stop requiring a separate native plan and proof.
- The first plan revision overclaimed generic Go “full-config admission” ->
  TC-DTR03-11 now names the exact key/epoch/member/device validation and join
  behaviors tested and explicitly does not claim empty-config rejection.
- DTR-01 may false-report ordinary unstaged tracked deletions as drift -> use
  the isolated final-tree index in TC-DTR03-06; do not mutate the user's index.
- Pre-existing DTR-01/DTR-02 worktree changes can be accidentally absorbed ->
  snapshot and compare path-scoped diffs; stop on overlap outside the exact
  files listed in scope.
- Lifecycle / derived-state durability: retired files have no production
  lifecycle; active contact start/dispose and group rejoin remain covered by
  TC-DTR03-05/10, including a cold-start ordering sentinel. Resume/list/Orbit/
  pending-retrier source roots are protected byte-for-byte and exercised by the
  `groups` lane where registered.
- Sibling-surface consistency: live direct messaging, contact requests, group
  invite/rejoin, and native group dispatch are guarded by
  TC-DTR03-02/03/05/09/10/11/12.
- Destructive-action side effects: source/test deletion is Git-recoverable.
  Roll back by restoring each exact file/symbol/test fragment, its DTR-01
  declaration/expectation, and current-doc entries together. No data, schema,
  credential, or external state is mutated.
- Invariant re-verification under new transitions: N/A — there is no new
  runtime transition; inventory exactness and replacement behavior are rerun
  after each deletion slice.

## Gate Cadence

- Per-plan closure: three causal source/API tests; DTR-01 real-tree
  reconciliation; fail-closed caller proof; exact live
  P2P/contact/invite/rejoin/startup/native-binding/Go sentinels; protected-path
  no-diff; the affected `runtime-roots`, `1to1`, and `groups` curated lanes;
  strict analysis; completeness; the justified `core-host-all`; diff hygiene;
  one incremental Graphify refresh.
- `core-host-all` is justified because this plan deletes two `lib/core`
  production files, edits a live core bridge file, deletes/edits core tests,
  and adds a core source/API contract.
- Do not run full `host-all` for this individual plan. Run
  `./scripts/run_host_test_gates.sh host-all` once after
  Wave 1 — Proven dependency leaves (`DTR-03`, `DTR-04`, and `DTR-05`) is
  complete or each slice has a terminal retained/deferred disposition, and
  once again at final rollout/release closure.
- Shared tests outside core globs:
  `test/unit/runtime_root_inventory_test.dart`,
  `test/features/p2p/domain/models/chat_message_test.dart`,
  the feature contact/invite/join/rejoin/hydrate and cold-start tests, the
  binding verifier, and the Go join/validation tests run by the exact commands
  below. Their later aggregate registration does not make full `host-all` a
  per-plan obligation.
- `feature-host-all`, performance, simulator, device, relay, native-build, and
  SQLCipher sweeps are not per-plan gates because no live feature production,
  performance, OS, network, native mapping, crypto, or persistence behavior
  changes.

## Acceptance Gates

Run from the repository root. Every Flutter command must exit `0` with zero
failed tests unless the comment explicitly names the expected RED.

```bash
# Run this block with Bash. Fail closed on both test and search errors.
set -euo pipefail

dtr03_expect_no_match() {
  if rg "$@"; then
    printf 'DTR-03 expected no match but found one\n' >&2
    return 1
  else
    DTR03_RG_STATUS=$?
    if [ "$DTR03_RG_STATUS" -eq 1 ]; then
      return 0
    fi
    printf 'DTR-03 rg failed operationally with status %s\n' \
      "$DTR03_RG_STATUS" >&2
    return "$DTR03_RG_STATUS"
  fi
}

# These live full-config, lifecycle, native/generated-verifier, Go, and
# preservation-test paths are not implementation scope. They are clean on the
# reviewed tree and must remain byte-for-byte unchanged against HEAD.
DTR03_PROTECTED_GROUP_PATHS=(
  lib/core/bridge/go_bridge_client.dart
  lib/main.dart
  lib/core/lifecycle/handle_app_resumed.dart
  lib/features/identity/presentation/startup_router.dart
  lib/features/groups/application/accept_pending_group_invite_use_case.dart
  lib/features/groups/application/handle_incoming_group_invite_use_case.dart
  lib/features/groups/application/rejoin_group_topics_use_case.dart
  lib/features/groups/application/join_group_use_case.dart
  lib/features/groups/application/hydrate_groups_from_peers_use_case.dart
  lib/features/groups/presentation/screens/group_list_wired.dart
  lib/features/orbit/presentation/screens/orbit_wired.dart
  android/app/src/main/kotlin/com/mknoon/app/GoBridge.kt
  ios/Runner/GoBridge.swift
  macos/Runner/MainFlutterWindow.swift
  go-mknoon/bridge/bridge.go
  go-mknoon/node/pubsub.go
  integration_test/group_multi_party_device_real_harness.dart
  scripts/gomobile_binding_inputs.sh
  scripts/verify_gomobile_bindings.sh
  test/core/bridge/go_bridge_client_test.dart
  test/core/lifecycle/handle_app_resumed_group_recovery_test.dart
  test/features/identity/presentation/screens/startup_router_recovery_test.dart
  test/features/groups/application/accept_pending_group_invite_use_case_test.dart
  test/features/groups/application/handle_incoming_group_invite_use_case_test.dart
  test/features/groups/application/rejoin_group_topics_use_case_test.dart
  test/features/groups/application/join_group_use_case_test.dart
  test/features/groups/application/hydrate_groups_from_peers_use_case_test.dart
  go-mknoon/bridge/bridge_test.go
)

# Preflight: record existing user-owned changes and do not alter the real index.
git rev-parse HEAD
git status --short
git diff --cached --name-status
git diff HEAD --quiet -- "${DTR03_PROTECTED_GROUP_PATHS[@]}"

# DTR03-CALLER-01 — pre-edit, fail-closed exact-symbol caller floor.
# Expected current shape: one declaration; four SUT-only call expressions; the
# same test has six whole-token occurrences (four calls, one group label, one
# comment); every other owned/current source has zero whole-token references.
DTR03_HELPER_DECL_COUNT="$(
  rg -o '\bcallGroupJoin\b' \
    lib/core/bridge/bridge_group_helpers.dart |
    wc -l |
    tr -d ' '
)"
DTR03_LEGACY_TEST_CALL_COUNT="$(
  rg -o '\bcallGroupJoin\(' \
    test/core/bridge/bridge_group_helpers_test.dart |
    wc -l |
    tr -d ' '
)"
DTR03_LEGACY_TEST_TOKEN_COUNT="$(
  rg -o '\bcallGroupJoin\b' \
    test/core/bridge/bridge_group_helpers_test.dart |
    wc -l |
    tr -d ' '
)"
test "$DTR03_HELPER_DECL_COUNT" -eq 1
test "$DTR03_LEGACY_TEST_CALL_COUNT" -eq 4
test "$DTR03_LEGACY_TEST_TOKEN_COUNT" -eq 6
printf 'DTR03-CALLER-01 declaration_tokens=%s test_calls=%s test_tokens=%s\n' \
  "$DTR03_HELPER_DECL_COUNT" \
  "$DTR03_LEGACY_TEST_CALL_COUNT" \
  "$DTR03_LEGACY_TEST_TOKEN_COUNT"
dtr03_expect_no_match -n \
  --glob '*.dart' \
  --glob '!lib/core/bridge/bridge_group_helpers.dart' \
  --glob '!test/core/bridge/bridge_group_helpers_test.dart' \
  --glob '!test/core/services/dtr03_dead_core_surface_contract_test.dart' \
  '\bcallGroupJoin\b' .
dtr03_expect_no_match -n '\bcallGroupJoin\b' \
  android ios macos windows linux web go-mknoon go-relay-server
dtr03_expect_no_match -n \
  --glob '*.dart' \
  'export[[:space:]]+.*bridge_group_helpers\.dart' \
  .
rg -n "^publish_to:[[:space:]]*['\"]?none['\"]?" pubspec.yaml

# DTR08-COMP-004 pre-removal behavioral floor: current legacy SUT refuses
# locally and never reaches Bridge.send. This test is deleted with that SUT only
# after DTR03-CALLER-01 and DTR03-AUTH-02 are accepted.
flutter test --no-pub \
  test/core/bridge/bridge_group_helpers_test.dart \
  --plain-name 'BB-006 rejects topic-name-only helper before bridge send'

# Governance receipts are recorded above and in the roadmap.
# DTR03-AUTH-01 approves the two exact files/test/metadata/current-doc scope.
# DTR03-AUTH-02 accepts DTR03-CALLER-01 as the supported external/path/git/raw
# caller floor for only callGroupJoin; full-config/native/Go behavior and both
# DTR-10 islands remain explicitly retained. Reverify the receipt text before
# deletion; withdrawn, ambiguous, or broadened authority is a hard stop.

# First causal RED after scaffolding, before deletion:
# non-zero because the duplicate file/declaration/current-doc claims exist.
flutter test --no-pub \
  test/core/services/dtr03_dead_core_surface_contract_test.dart \
  --plain-name \
  'DTR03-01 duplicate core ChatMessage model and declaration are absent'

# Remaining causal RED selectors before their corresponding edits:
flutter test --no-pub \
  test/core/services/dtr03_dead_core_surface_contract_test.dart \
  --plain-name \
  'DTR03-02 hollow core contact listener and SUT-only suite are absent'
flutter test --no-pub \
  test/core/services/dtr03_dead_core_surface_contract_test.dart \
  --plain-name \
  'DTR03-03 deprecated topic-only group-join API and legacy tests are absent'

# Focused GREEN: all three causal tests pass after exact deletion.
flutter test --no-pub \
  test/core/services/dtr03_dead_core_surface_contract_test.dart

# Exact negative source/API/current-doc census. Every no-match must be rg status
# 1; an operational error (2+) fails through dtr03_expect_no_match.
test ! -e lib/core/services/chat_message.dart
test ! -e lib/core/services/contact_request_listener.dart
test ! -e test/core/services/contact_request_listener_test.dart
dtr03_expect_no_match -n \
  --glob '*.dart' \
  --glob '!test/core/services/dtr03_dead_core_surface_contract_test.dart' \
  '\bcallGroupJoin\b' .
dtr03_expect_no_match -n '\bcallGroupJoin\b' \
  android ios macos windows linux web go-mknoon go-relay-server
dtr03_expect_no_match -n 'LEGACY_JOIN_UNSUPPORTED' \
  lib/core/bridge/bridge_group_helpers.dart \
  test/core/bridge/bridge_group_helpers_test.dart
dtr03_expect_no_match -n \
  'lib/core/services/(chat_message|contact_request_listener)\.dart' \
  tool/runtime_roots/runtime_roots.json \
  test/unit/runtime_root_inventory_test.dart
dtr03_expect_no_match -n \
  'core/services/(chat_message|contact_request_listener)\.dart|\bcallGroupJoin\b' \
  file-structure.md C4_MODEL.md C4/file-structure.md C4/code.md C4/components.md

# Only the 31-line deprecated helper block may change in this production file.
DTR03_HELPER_NUMSTAT="$(
  git diff HEAD --numstat -- lib/core/bridge/bridge_group_helpers.dart
)"
test "$DTR03_HELPER_NUMSTAT" = "$(
  printf '0\t31\tlib/core/bridge/bridge_group_helpers.dart'
)"

# DTR-01 real final-tree gate without touching the user's real Git index.
DTR03_INDEX_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dtr03-index.XXXXXX")"
trap 'rm -rf -- "${DTR03_INDEX_DIR:?}"' EXIT
GIT_INDEX_FILE="$DTR03_INDEX_DIR/index" git read-tree HEAD
GIT_INDEX_FILE="$DTR03_INDEX_DIR/index" git add -A -- \
  lib/core/services/chat_message.dart \
  lib/core/services/contact_request_listener.dart \
  lib/core/bridge/bridge_group_helpers.dart \
  test/core/services/contact_request_listener_test.dart \
  test/core/bridge/bridge_group_helpers_test.dart \
  test/core/services/dtr03_dead_core_surface_contract_test.dart \
  test/unit/runtime_root_inventory_test.dart \
  tool/runtime_roots/runtime_roots.json
GIT_INDEX_FILE="$DTR03_INDEX_DIR/index" \
  ./scripts/run_test_gates.sh runtime-roots

# Active model and LAN preservation.
flutter test --no-pub \
  test/features/p2p/domain/models/chat_message_test.dart
flutter test --no-pub \
  test/core/services/p2p_service_inbound_transport_test.dart \
  --plain-name 'T5: local WiFi messages surface as wifi and are censused'

# Active contact-request replacement preservation.
flutter test --no-pub \
  test/features/contact_request/application/contact_request_listener_test.dart \
  --plain-name 'emits ContactRequestModel for valid v2'

# Full-config helper and MethodChannel preservation.
flutter test --no-pub \
  test/core/bridge/bridge_group_helpers_test.dart \
  --plain-name \
  'sends group:join with groupId, groupConfig, groupKey, keyEpoch'
flutter test --no-pub \
  test/core/bridge/go_bridge_client_test.dart \
  --plain-name \
  'BB-007 callGroupJoinWithConfig forwards exact full config payload to groupJoinTopic'

# Live accepted/incoming invite and rejoin preservation.
flutter test --no-pub \
  test/features/groups/application/accept_pending_group_invite_use_case_test.dart \
  --plain-name 'accepts pending invite, persists group, and drains inbox'
flutter test --no-pub \
  test/features/groups/application/handle_incoming_group_invite_use_case_test.dart \
  --plain-name \
  'calls group:join bridge command with groupId, groupConfig, groupKey, keyEpoch'
flutter test --no-pub \
  test/features/groups/application/rejoin_group_topics_use_case_test.dart \
  --plain-name 'calls callGroupJoinWithConfig for each active group'
flutter test --no-pub \
  test/features/groups/application/rejoin_group_topics_use_case_test.dart \
  --plain-name 'builds correct groupConfig from stored members'
flutter test --no-pub \
  test/features/identity/presentation/screens/startup_router_recovery_test.dart \
  --plain-name \
  'PB264-18 cold startup recovers exits after rejoin and inbox drain without resume'

# Separately test-only DTR-10 join/hydrate islands remain untouched.
flutter test --no-pub \
  test/features/groups/application/join_group_use_case_test.dart \
  --plain-name 'BB-006 joins with full config payload and no topicName'
flutter test --no-pub \
  test/features/groups/application/hydrate_groups_from_peers_use_case_test.dart

# Native/generated preservation. The verifier checks that every wrapper call
# resolves in the generated artifacts. Android/iOS digest equality proves the
# reviewed inputs/artifacts remain aligned without invoking a mutating rebuild.
git diff HEAD --quiet -- "${DTR03_PROTECTED_GROUP_PATHS[@]}"
./scripts/verify_gomobile_bindings.sh all
source scripts/gomobile_binding_inputs.sh
for DTR03_BINDING_PLATFORM in android ios; do
  DTR03_BINDING_DIGEST="$(
    gomobile_binding_input_digest "$PWD" "$DTR03_BINDING_PLATFORM"
  )"
  if [ "$DTR03_BINDING_PLATFORM" = android ]; then
    DTR03_BINDING_STAMP='android/app/libs/GoMknoon.inputs.sha256'
  else
    DTR03_BINDING_STAMP='ios/Runner/GoMknoon.inputs.sha256'
  fi
  DTR03_STORED_BINDING_DIGEST="$(
    tr -d '[:space:]' < "$DTR03_BINDING_STAMP"
  )"
  test "$DTR03_BINDING_DIGEST" = "$DTR03_STORED_BINDING_DIGEST"
done

# Real Go behavior preservation required by DTR08-COMP-004 plus adjacent
# key/epoch/member/device admission guards. No empty-groupConfig claim.
(
  cd go-mknoon
  GOTOOLCHAIN=go1.25.0 go test ./bridge \
    -run '^(TestGroupJoinTopic_BB006RejectsLegacyTopicNameOnlyPayload|TestGroupJoinTopic_RejectsInvalidKeyState|TestSV009GroupJoinAndUpdateConfigRejectMalformedMemberKeys|TestGroupJoinTopic_RejectsIncompleteActiveMemberKeyMaterial|TestGroupJoinTopic_RejectsMalformedActiveDeviceTransportPeerId|TestGroupJoinTopic_BB007RoundTripsFullConfigAndAcceptsPublish|TestGroupJoinTopic_AlreadyJoinedIsIdempotent|TestGroupJoinTopic_BB008AlreadyJoinedRefreshesNewerKeyAndConfig)$' \
    -count=1
)

# Affected curated lanes and justified family sweep.
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh groups
./scripts/run_host_test_gates.sh core-host-all --list |
  rg -nF 'test/core/services/dtr03_dead_core_surface_contract_test.dart'
./scripts/run_host_test_gates.sh core-host-all \
  --continue-on-failure \
  --batch-flutter \
  --concurrency 1 \
  --reporter failures-only

# DTR-02 policy, discovery, graph, and diff hygiene.
./scripts/check_flutter_analyze_strict.sh
./scripts/run_test_gates.sh completeness-check
./graphify-arch/refresh_arch_graph.sh --incremental
git diff --check
```

Semantic outcomes:

- each planned RED exits non-zero only because its exact retired artifact still
  exists;
- `DTR03-CALLER-01` records one declaration, four SUT-only calls, six total
  legacy test tokens, zero other owned-source token, and no search error; any
  additional caller/reference/export or `rg` status `2+` stops execution;
- focused GREEN and preservation selectors exit `0` with zero failed tests;
- `runtime-roots` reports a trustworthy, no-drift final tree, preserves every
  non-DTR-03 candidate/restricted root, and exits `0`;
- the `core-host-all --list` discovery pipeline prints the new source-contract
  path before the family sweep;
- negative censuses print no matches and return through exact `rg` status `1`;
- the helper diff is exactly zero additions and 31 deletions;
- live invite, rejoin payload, and cold-start ordering selectors pass;
- every protected mapping/lifecycle/test path remains clean against `HEAD`;
  the gomobile verifier and Android/iOS input stamps pass;
- eight named Go tests pass without asserting empty-config rejection;
- `1to1`, `groups`, and `core-host-all` report PASS with zero failed items;
- strict analysis reports no issues; completeness reports no unmatched test;
- incremental Graphify refresh succeeds and removes the deleted nodes;
- `git diff --check` emits no errors.

## Execution Interpretation And Done Criteria

- Expected RED: the first source-contract selector fails because
  `lib/core/services/chat_message.dart`, its DTR-01 row, and current-doc claims
  still exist. The other two selectors fail only on their corresponding
  retired artifacts.
- Green sentinels: active feature P2P model/LAN conversion, feature contact
  processing, full-config Dart/MethodChannel join, live accepted/incoming
  invite materialization, `rejoinGroupTopics` payload/lifecycle wiring,
  DTR-10-owned join/hydrate islands, native/generated mappings, and the exact
  Go validation/join behaviors remain unchanged.
- Pre-existing dirty tree / known failure: planning observed an extensive
  user-owned Wave 0 DTR-01/DTR-02 worktree delta, including untracked
  runtime-root tooling and a modified roadmap. All current focused baselines
  named in Planning Progress passed. Execution must snapshot and preserve that
  delta and use the isolated index for DTR-01 final-tree proof.
- Environment blocker: none for the test tier. Closure is host-only; unavailable
  mobile hardware is N/A because no OS/device boundary changes.
- Evidence blocker: none. `DTR03-CALLER-01` is durable and green,
  `DTR03-AUTH-01` plus `DTR03-AUTH-02` bind it to the exact authorized scope,
  and the causal RED/GREEN, preservation, family, policy, graph, and hygiene
  evidence is complete.
- Scope drift: any live feature model/listener edit, group command/native/Go/
  wire/persistence change, DTR-10 leaf deletion, unapproved external API
  assumption, schema/dependency change, or unrelated dirty-tree absorption
  blocks closure and requires re-planning.

- [x] `DTR03-CALLER-01` passes fail-closed against the recorded execution
      HEAD/worktree.
- [x] Both named-owner approval/floor records are durable before deletion.
- [x] Every behavior has a named test or justified proof.
- [x] Causal RED, focused GREEN, and representative mutation re-red are
      recorded.
- [x] Replacement sentinels, protected no-diff paths, binding verifier/input
      stamps, runtime roots, curated lanes, eight-test Go proof, and
      `core-host-all` pass with semantic outcomes.
- [x] AUTO and existing manual registrations are verified; no new array entry
      is needed.
- [x] Strict analysis, completeness, incremental Graphify refresh, and diff
      hygiene pass.
- [x] Scope Contract And Guard and exact rollback boundaries are respected.

## Handoff

- First causal RED command:
  `flutter test --no-pub test/core/services/dtr03_dead_core_surface_contract_test.dart --plain-name 'DTR03-01 duplicate core ChatMessage model and declaration are absent'`.
- Preservation command:
  `flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart
  --plain-name 'sends group:join with groupId, groupConfig, groupKey,
  keyEpoch'` for the reviewed high-risk seam; the P2P/contact/live-invite/
  rejoin/native/Go sentinels and curated/family commands above are also
  mandatory.
- Test Contract: 12 canonical rows.
- Tiers / fixtures: host source/API, unit, application, core integration, tool
  real-tree, source-integrity/generated-binding verification, and real Go unit
  boundary; fakes only where existing decision seams use them.
- Manual registration:
  `DTR03-CALLER-01`, `DTR03-AUTH-01`, `DTR03-AUTH-02`, the existing
  `runtime-roots` gate, exact hydrate/cold-start tests, binding verifier/input
  stamps, protected-path guard, and exact eight-test Go selector. New core
  contract is AUTO; no gate-array edit is planned.
- Migration: none.
- Boundary closure: host-only source deletion plus read-only generated-binding
  verification; no simulator/device/relay/SQLCipher/native build is warranted
  because every native/Go mapping source is protected from change.
- Full-gate owner: Wave 1 runs one full `host-all` after DTR-03/DTR-04/DTR-05
  are complete or terminal; final rollout/release runs it again.
- Confirmed: all three surfaces are isolated exactly as described; the old
  helper has zero supported/runtime repository caller and four SUT-only calls;
  active replacements, live invite/rejoin roots, native/generated mappings,
  and registrations exist; current focused baselines pass.
- Refuted: neither live P2P/contact behavior nor the live full-config group
  protocol is dead.
- Authorization evidence: both named-role records are approved, including
  explicit acceptance of the recorded supported external/path/git/raw caller
  floor. The bounded implementation and all per-plan causal/closure evidence
  are complete; Wave 1 still owns its later aggregate `host-all`.

## Reviewer Findings

Review date: 2026-07-25; authorization addendum: 2026-07-25

Original counterexample verdict: **not-ready pending only
`DTR03-AUTH-01/02`**.

Historical authorization-addendum verdict: **ready for scoped execution**.

Review-stage classification: `authorized`; core bet: **confirmed**.

Historical disposition: proceed with the exact causal RED and bounded
implementation. This addendum records resolution of the prior manual decision
gate; the final execution result is recorded below.

Closure addendum: **Plan-green / implementation-complete** on 2026-07-25.
The bounded deletion, causal proof, preservation proof, per-plan gates, graph
refresh, and hygiene checks all passed. This does not close Wave 1 or replace
its later aggregate `host-all`.

Authorization resolution and applied fixes:

1. **Resolved — `DTR08-COMP-004` caller floor for the DTR-03 wrapper.**
   `DTR03-AUTH-02` accepts the exact execution source set as the complete
   supported external/path/git/raw caller floor and retains the full-config,
   native, generated-binding, Go, and DTR-10 boundaries. `DTR03-AUTH-01`
   separately approves the exact Core Services deletion/retention/rollback
   boundary. DTR-10 disposition remains open.
2. **Applied fix — caller absence is now fail-closed.**
   The first revision's `! rg '\bcallGroupJoin\('` could miss tear-offs,
   whitespace/multiline references, root/test-driver Dart, and could convert
   `rg` operational status `2` into success. TC-DTR03-07/08 and Acceptance
   Gates now use the whole token, all owned roots, exact expected counts, and
   an exit-status-aware helper.
3. **Applied fix — the causal source contract is now specified.**
   It must preserve/read the helper and test files, fail on enumeration errors,
   remove all active legacy token/error residue, retain full-config declaration
   and test, check current C4 files, and re-red on declaration and tear-off
   mutations.
4. **Applied fix — live and platform preservation is no longer inferred.**
   TC-DTR03-10 uses real pending/incoming invite, rejoin payload, and cold-start
   roots. TC-DTR03-11 protects Dart/native/Go/lifecycle/test sources against
   any diff, verifies generated exports/stamps, and runs eight exact Go tests.
   TC-DTR03-12 labels join/hydrate honestly as DTR-10-owned test-only islands.
5. **Applied fix — Go claims match behavior.**
   The plan preserves key/epoch/member/device validation, topic-only rejection,
   valid round-trip, idempotence, and newer-state refresh. It no longer claims
   that Go rejects an otherwise empty `groupConfig`.

Five lenses:

- L1 evidence/classification: **clear after `DTR03-AUTH-01/02`**; the exact
  owner decisions and supported-caller floor are recorded, and the dead-leaf
  core bet is confirmed.
- L2 Test Contract causality: **clear after applied fixes**.
- L3 bypass/scope safety: **clear after applied fixes**.
- L4 execution/gate integrity: **clear after applied fixes**.
- L5 boundary/reversibility: **clear** for Git-recoverable source deletion;
  native/platform behavior is unchanged and mechanically protected.

Blind-spot sweep:

- Hits fixed: B-2 bypass callers, B-4 false-green search/gates, B-8 native
  boundary overclaim, B-9 preservation sentinels, and B-10 platform parity in
  prose.
- B-5 is bounded by exact deletions and Git rollback. B-1/B-6/B-7 are N/A
  because no schema/data/marker/fallback transition is introduced.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-07-25 | pre-authorization preflight complete; implementation stopped | Plan 274 only; all production/test/runtime-root/current-architecture paths read-only | fail-closed `DTR03-CALLER-01` passed; protected-path diff passed; `BB-006 rejects topic-name-only helper before bridge send` passed `+1` | caller floor is durable against HEAD `a68aacee7482f910f966d33d16d3c7598489f059`; cached diff empty; scoped implementation delta independently audited | At this historical checkpoint, `DTR03-AUTH-01` and `DTR03-AUTH-02` had not yet been supplied. | obtain both named approvals before causal RED |
| 2026-07-25 | authorization complete; execution-ready | Plan 274 plus DTR roadmap/index decision records | current authenticated project owner approved both DTR-03 removals while acting as Core Services and Groups owner and confirmed no supported external user of the old group-join function | `DTR03-AUTH-01/02` now record exact scope, retention, rollback, and acceptance of `DTR03-CALLER-01`; `DTR08-COMP-004` is resolved only for the DTR-03 wrapper | No authorization blocker; implementation and all causal/closure gates remain pending. | begin the three causal RED selectors, then exact scoped deletion and verification |
| 2026-07-25 | Plan-green; implementation and per-plan closure complete | three retired source/test files; deprecated wrapper and legacy test fragments; DTR-01 manifest/test; causal contract; five current architecture docs; Plan/roadmap/index | all three causal selectors failed before deletion for their exact artifact, then passed `3/3`; restoring a declaration and adding a tear-off each re-red TC-DTR03-03; 42 focused Dart preservation tests and eight exact Go tests passed; bindings verified with matching Android/iOS input digests | exact removal is 339 dead code/test lines across three deleted files plus wrapper/test fragments; helper diff is exactly `0/31`; 28 protected paths remain clean; isolated `runtime-roots` passed `13/13`, trustworthy/no-drift, 1,054 files; `1to1` passed 2,440; `groups` passed 3,305; `core-host-all` passed 2,765 across 350 paths plus Android renderer contract; strict analysis found no issues; completeness is 1,358/1,358; Graphify refresh is current at `06cfd529b61c6e10`; negative census and diff hygiene pass | No per-plan blocker. Live feature P2P/contact behavior, full-config Dart/native/Go join behavior, and both DTR-10 islands are retained. | await DTR-04/DTR-05 terminal states, then run the single Wave 1 aggregate `host-all` |
