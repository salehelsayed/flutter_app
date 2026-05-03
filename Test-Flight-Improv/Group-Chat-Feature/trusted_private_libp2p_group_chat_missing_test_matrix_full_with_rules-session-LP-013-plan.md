# LP-013 Duplicate PubSub Handling Session Plan

Status: execution-ready

## Planning Progress

- 2026-04-30T22:37:01Z | Arbiter completed | Files inspected since last update: Reviewer Pass and full LP-013 plan sections. | Decision/blocker: no structural blockers remain; the reviewer adjustment is incremental and has been captured in-file. Plan is reusable and execution-ready. | Next action: execute only in a later implementation pass; do not execute during this planning turn.
- 2026-04-30T22:36:36Z | Reviewer completed | Files inspected since last update: full LP-013 draft plan, mandatory-section heading scan. | Decision/blocker: plan is sufficient with one incremental artifact-quality adjustment: persist reviewer/arbiter verdict sections so the file is self-contained and reusable. No structural blocker found in scope, evidence order, gate contract, Device/Relay Proof Profile, dirty-worktree handling, or stop rule. | Next action: run Arbiter classification and finalize status if no structural blocker appears.
- 2026-04-30T22:34:15Z | Planner completed | Files inspected since last update: Evidence Collector Notes and prior LP-002/LP-003 plan patterns for gate/fixture handling. | Decision/blocker: draft plan is proof-first, row-owned, and keeps device/relay proof supporting unless raw Go/libp2p proof is unavailable or the executor chooses to claim real-network closure evidence. | Next action: run Reviewer sufficiency pass against required sections, gates, dirty-worktree handling, and Device/Relay Proof Profile.
- 2026-04-30T22:31:59Z | Evidence Collector completed | Files inspected since last update: source matrix LP-013 row, session-breakdown LP-013 row, `test-inventory.md` LP-013 note, `Test-Flight-Improv/test-gate-definitions.md`, `scripts/run_test_gates.sh`, `go-mknoon/node/pubsub.go`, `go-mknoon/node/pubsub_delivery_test.go`, `go-mknoon/node/pubsub_test.go`, `go-mknoon/internal/group_envelope.go`, `go-mknoon/third_party/go-libp2p-pubsub/{midgen.go,pubsub.go,topic.go}`, focused Dart duplicate tests, `integration_test/multi_relay_failover_test.dart`, `integration_test/scripts/run_group_multi_device_real.dart`, device/env checks. | Decision/blocker: LP-013 remains evidence-gated and implementation-committed; raw Go/libp2p proof is available locally, but configured multi-relay and CLI-peer closure proof is blocked because relay/fixture env vars are unset. | Next action: draft a row-owned proof-first implementation plan with an explicit Device/Relay Proof Profile and stop rule.
- 2026-04-30T22:29:20Z | Evidence Collector started | Files inspected since last update: implementation-plan-orchestrator skill, git status, intended plan path existence. | Decision/blocker: LP-013 row and intended path are confirmed; plan file did not previously exist; worktree is dirty with unrelated modified and untracked files. | Next action: inspect source matrix, session breakdown, inventory, gate definitions, owner code/tests, and live device/relay availability before drafting.

## Execution Progress

- 2026-04-30T22:38:43Z | Contract extraction started | Files inspected or touched: `implementation-execution-qa-orchestrator` skill, LP-013 plan, `git status --short`. | Command currently running: none. | Decision/blocker: execution must remain inside LP-013 owner files and respect dirty GL-005/LP-002/LP-003 worktree changes. | Next action: extract exact scope, tests, gates, known failures, non-goals, and isolation requirements before coding.
- 2026-04-30T22:38:43Z | Contract extracted | Files inspected or touched: LP-013 plan sections `real scope`, `closure bar`, `regression/tests to add first`, `exact tests and gates to run`, `Device/Relay Proof Profile`, `known-failure interpretation`, `done criteria`, `scope guard`, and user override forbidding source matrix, test inventory, or session-breakdown updates. | Command currently running: none. | Decision/blocker: add proof-first Go PubSub duplicate/collision tests and focused Flutter duplicate dedupe tests; patch production only if those tests expose a row-owned gap; host-only raw-Go/libp2p proof plus focused Flutter host tests are primary closure evidence; `group-real-network-nightly` is not a substitute while relay env is unset. | Next action: verify spawned Executor/QA isolation availability.
- 2026-04-30T22:39:45Z | Executor spawned/running | Files inspected or touched: LP-013 plan only. | Command currently running: `codex ... exec` with `model=gpt-5.5`, `reasoning_effort=xhigh`, `sandbox=danger-full-access`, `approval=never`. | Decision/blocker: spawned-agent isolation is available through the local Codex CLI after a probe run. | Next action: wait for Executor completion, then inspect landed diff and recorded test evidence before spawning QA.
- 2026-04-30T22:40:52Z | Executor contract extraction confirmed | Files inspected or touched: LP-013 plan and executor/test skill instructions. | Command currently running: none. | Decision/blocker: local Executor pass will stay inside LP-013 owner test/implementation files; source matrix, test inventory, and session-breakdown ledger are explicitly out of scope for this pass. | Next action: inspect git status and dirty owner files before editing.
- 2026-04-30T22:43:49Z | Owner-file inspection completed | Files inspected or touched: `git status --short`, dirty diffs for `go-mknoon/node/{node.go,pubsub.go,pubsub_test.go}` and `test/features/groups/application/group_message_listener_test.dart`, LP-013 duplicate test harnesses, `go-mknoon/internal/group_envelope.go`, vendored PubSub default message-ID code, `group_message_listener.dart`, `handle_incoming_group_message_use_case.dart`, and in-memory group/media repositories. | Command currently running: none. | Decision/blocker: owner files contain unrelated dirty GL-005/LP-003 edits; LP-013 can be added as isolated tests without reverting them. Production changes are not yet justified. | Next action: add LP-013 Go PubSub proof tests and focused Flutter listener duplicate-dedupe test.
- 2026-04-30T22:44:07Z | Test edits started | Files inspected or touched: `go-mknoon/node/pubsub_delivery_test.go`, `test/features/groups/application/group_message_listener_test.dart`, LP-013 plan. | Command currently running: none. | Decision/blocker: adding proof-first LP-013 tests only; no production patch unless these tests expose a real LP-013 gap. | Next action: patch Go and Flutter test files.
- 2026-04-30T22:46:37Z | Test edits completed | Files inspected or touched: `go-mknoon/node/pubsub_delivery_test.go`, `test/features/groups/application/group_message_listener_test.dart`, LP-013 plan. | Command currently running: none. | Decision/blocker: added LP-013 raw PubSub message-ID/hash/sequence proof tests and focused listener dedupe regression; no production code changed in this pass. | Next action: run required focused Go command first.
- 2026-04-30T22:46:56Z | Required command 1 started | Files inspected or touched: `go-mknoon/node/pubsub_delivery_test.go`, LP-013 plan. | Command currently running: `cd go-mknoon && go test ./node -run 'TestLP013|TestPublishGroupMessage_DuplicateProvidedMessageIdRemainsVisibleAfterDecrypt' -v`. | Decision/blocker: validating new raw PubSub proofs before any production patch. | Next action: record exact result.
- 2026-04-30T22:47:31Z | Required command 1 passed | Files inspected or touched: `go-mknoon/node/pubsub_delivery_test.go`, LP-013 plan. | Command currently running: none. | Decision/blocker: `go test ./node -run 'TestLP013|TestPublishGroupMessage_DuplicateProvidedMessageIdRemainsVisibleAfterDecrypt' -v` passed; identical encrypted wire-envelope double publish produced 2 app events in this run, and conflicting duplicate app payloads preserved the same application `messageId` into both events. | Next action: run required Flutter listener LP013 command.
- 2026-04-30T22:47:43Z | Required command 2 started | Files inspected or touched: `test/features/groups/application/group_message_listener_test.dart`, LP-013 plan. | Command currently running: `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'LP013'`. | Decision/blocker: validating focused listener duplicate-dedupe regression. | Next action: record exact result.
- 2026-04-30T22:48:24Z | Required command 2 passed | Files inspected or touched: `test/features/groups/application/group_message_listener_test.dart`, LP-013 plan. | Command currently running: none. | Decision/blocker: `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'LP013'` passed; new listener test produced one row, one UI stream insertion, one local notification, one unread item, and preserved first trusted text/timestamp/status/key/media fields. | Next action: run required handle-incoming duplicate replay command.
- 2026-04-30T22:48:36Z | Required command 3 started | Files inspected or touched: `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, LP-013 plan. | Command currently running: `flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name 'duplicate replay with the same messageId ignores conflicting content'`. | Decision/blocker: validating existing first-writer-wins use-case anchor. | Next action: record exact result.
- 2026-04-30T22:49:01Z | Required command 3 passed | Files inspected or touched: `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, LP-013 plan. | Command currently running: none. | Decision/blocker: `flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name 'duplicate replay with the same messageId ignores conflicting content'` passed; duplicate replay returned null and preserved first text/timestamp. | Next action: run required resume-recovery duplicate command.
- 2026-04-30T22:49:16Z | Required command 4 started | Files inspected or touched: `test/features/groups/integration/group_resume_recovery_test.dart`, LP-013 plan. | Command currently running: `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'same message is not duplicated if both pubsub and group inbox deliver it'`. | Decision/blocker: validating PubSub plus inbox duplicate replay anchor. | Next action: record exact result.
- 2026-04-30T22:49:40Z | Required command 4 passed | Files inspected or touched: `test/features/groups/integration/group_resume_recovery_test.dart`, LP-013 plan. | Command currently running: none. | Decision/blocker: `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'same message is not duplicated if both pubsub and group inbox deliver it'` passed; pubsub delivery plus inbox replay kept one row. | Next action: run required group edge duplicate command.
- 2026-04-30T22:49:56Z | Required command 5 started | Files inspected or touched: `test/features/groups/integration/group_edge_cases_smoke_test.dart`, LP-013 plan. | Command currently running: `flutter test --no-pub test/features/groups/integration/group_edge_cases_smoke_test.dart --plain-name 'duplicate delivery'`. | Decision/blocker: validating fake-network duplicate delivery smoke anchor. | Next action: record exact result.
- 2026-04-30T22:50:19Z | Required command 5 passed | Files inspected or touched: `test/features/groups/integration/group_edge_cases_smoke_test.dart`, LP-013 plan. | Command currently running: none. | Decision/blocker: `flutter test --no-pub test/features/groups/integration/group_edge_cases_smoke_test.dart --plain-name 'duplicate delivery'` passed; fake-network duplicate delivery remained idempotent. | Next action: run required group notification dedupe integration command.
- 2026-04-30T22:50:33Z | Required command 6 started | Files inspected or touched: `test/integration/group_notification_dedupe_integration_test.dart`, LP-013 plan. | Command currently running: `flutter test --no-pub test/integration/group_notification_dedupe_integration_test.dart`. | Decision/blocker: validating notification dedupe integration anchor. | Next action: record exact result.
- 2026-04-30T22:50:59Z | Required command 6 passed | Files inspected or touched: `test/integration/group_notification_dedupe_integration_test.dart`, LP-013 plan. | Command currently running: none. | Decision/blocker: `flutter test --no-pub test/integration/group_notification_dedupe_integration_test.dart` passed; recent remote push suppressed local group notification for the same message. | Next action: run broader Go owner command.
- 2026-04-30T22:51:11Z | Required command 7 started | Files inspected or touched: Go owner packages, LP-013 plan. | Command currently running: `cd go-mknoon && go test ./node ./bridge ./cmd/testpeer -run 'Group|PubSub|Rendezvous|Protocol|Inbox' -v`. | Decision/blocker: broader Go owner-suite validation has started; known unrelated failures will be classified by exact test name if present. | Next action: record exact result.
- 2026-04-30T22:53:21Z | Required command 7 failed with known unrelated owner-suite failures | Files inspected or touched: Go owner packages, `/tmp/lp013-go-owner.json`, LP-013 plan. | Command currently running: none. | Decision/blocker: `cd go-mknoon && go test ./node ./bridge ./cmd/testpeer -run 'Group|PubSub|Rendezvous|Protocol|Inbox' -v` failed only in known peer-mismatch paths: `github.com/mknoon/go-mknoon/node TestPublishGroupMessage_ReturnsPeerCountZero_WhenNoPeers` and `github.com/mknoon/go-mknoon/bridge TestGroupPublish_ResponseIncludesTopicPeers` (`GROUP_ERROR`, `publish to topic: validation failed`, validator reason `peer_mismatch`). Structured rerun showed all LP-013 tests and existing duplicate provided-message-ID test passed inside this broader selection. | Next action: run required `groups` gate.
- 2026-04-30T22:53:40Z | Required command 8 started | Files inspected or touched: `scripts/run_test_gates.sh`, LP-013 plan. | Command currently running: `./scripts/run_test_gates.sh groups`. | Decision/blocker: validating named groups gate; unrelated pre-existing gate failures will be classified by exact test name. | Next action: record exact result.
- 2026-04-30T22:54:24Z | Required command 8 passed | Files inspected or touched: `scripts/run_test_gates.sh`, group integration test suites, LP-013 plan. | Command currently running: none. | Decision/blocker: `./scripts/run_test_gates.sh groups` passed; named gate reported `All tests passed!`. | Next action: run required full group integration directory command.
- 2026-04-30T22:54:40Z | Required command 9 started | Files inspected or touched: `test/features/groups/integration`, LP-013 plan. | Command currently running: `flutter test --no-pub test/features/groups/integration`. | Decision/blocker: running full group integration directory command required by plan. | Next action: record exact result.
- 2026-04-30T22:55:14Z | Required command 9 passed | Files inspected or touched: `test/features/groups/integration`, LP-013 plan. | Command currently running: none. | Decision/blocker: `flutter test --no-pub test/features/groups/integration` passed; directory run reported `All tests passed!`. | Next action: run required `git diff --check`.
- 2026-04-30T22:55:26Z | Required command 10 started | Files inspected or touched: working diff, LP-013 plan. | Command currently running: `git diff --check`. | Decision/blocker: final whitespace/conflict-marker check started. | Next action: record exact result and Executor completion verdict.
- 2026-04-30T22:56:03Z | Required command 10 passed | Files inspected or touched: working diff, LP-013 plan. | Command currently running: none. | Decision/blocker: `git diff --check` passed. | Next action: write final Executor evidence notes.
- 2026-04-30T22:56:03Z | Executor completed | Files inspected or touched: `go-mknoon/node/pubsub_delivery_test.go`, `test/features/groups/application/group_message_listener_test.dart`, LP-013 plan. | Command currently running: none. | Decision/blocker: LP-013 proof-first tests landed without production patches; all focused LP-013 commands passed; required broader Go owner command is blocked only by known unrelated peer-mismatch failures already named in the plan. | Next action: hand off to QA reviewer.
- 2026-04-30T22:57:47Z | QA Reviewer spawned/running | Files inspected or touched: LP-013 plan, `git status --short`, LP-013-owned diff, Executor summary. | Command currently running: `codex ... exec` with `model=gpt-5.5`, `reasoning_effort=xhigh`, `sandbox=danger-full-access`, `approval=never`. | Decision/blocker: separate QA must verify row scope, evidence sufficiency, known-failure classification, and no forbidden source-matrix/test-inventory/session-breakdown edits by this session before any final verdict. | Next action: wait for QA Reviewer completion; run a single fix pass only if QA reports a blocking issue.
- 2026-04-30T22:58:54Z | QA Reviewer local pass started | Files inspected or touched: LP-013 plan, `implementation-execution-qa-orchestrator` skill, `git status --short`, executor evidence notes, Device/Relay Proof Profile, known-failure interpretation, and user override forbidding source matrix/test inventory/session-breakdown updates. | Command currently running: none. | Decision/blocker: QA scope is review-only for LP-013; no source, matrix, inventory, or ledger edits are permitted. | Next action: inspect LP-013 diffs, command evidence, and broad Go failure classification.
- 2026-04-30T23:00:17Z | QA Reviewer completed | Files inspected or touched: `go-mknoon/node/pubsub_delivery_test.go`, `test/features/groups/application/group_message_listener_test.dart`, existing duplicate anchor tests, forbidden doc diffs, `/tmp/lp013-go-owner.json`, and LP-013 plan. | Command currently running: none. | Decision/blocker: accepted; LP-013 changes are test-only, cover the required Go PubSub and Flutter dedupe dimensions, keep production scope unchanged, classify broad Go failures as known unrelated peer-mismatch, and do not require a fix pass. | Next action: controller may close this execution pass under the user override; source matrix, test inventory, and session-breakdown remain intentionally untouched for LP-013.
- 2026-04-30T23:01:00Z | QA post-note validation completed | Files inspected or touched: LP-013 plan and working diff. | Command currently running: none. | Decision/blocker: `git diff --check` passed after QA note edits. | Next action: final QA response with accepted verdict.
- 2026-04-30T23:01:49Z | Final verdict work started | Files inspected or touched: LP-013 plan, Executor summary, QA summary. | Command currently running: none. | Decision/blocker: QA accepted with no fix pass required; final plan verdict must preserve the user override that source matrix, test inventory, and session-breakdown are not updated in this execution pass. | Next action: write final accepted verdict into this plan and run a final `git diff --check`.
- 2026-04-30T23:02:05Z | Final verdict written | Files inspected or touched: LP-013 plan, Executor summary, QA summary. | Command currently running: none. | Decision/blocker: final execution verdict is accepted; no fix pass was required; broad Go owner-suite failure remains classified as known unrelated peer-mismatch; closure-doc updates remain intentionally deferred by user override. | Next action: run final `git diff --check` and report accepted verdict to the user.

## Evidence Collector Notes

- Source row `LP-013` is `Partial` and requires duplicate delivery with same ID, same hash, and conflicting sequence; expected behavior is no double rows, double notifications, or overwritten trusted fields.
- Session breakdown row 4 classifies LP-013 as `repo_external_proof` / `evidence-gated` and says to produce Go, raw-protocol, real-network, simulator, relay, packet-capture, or device-lab proof first, adding repo code/tests only if that proof exposes a gap.
- `test-inventory.md` records existing partial evidence: `go-mknoon/node/pubsub_delivery_test.go` has `TestPublishGroupMessage_DuplicateProvidedMessageIdRemainsVisibleAfterDecrypt`; Dart tests cover DB/media/notification dedupe across direct duplicate delivery and PubSub plus inbox replay paths.
- `go-mknoon/node/pubsub.go` initializes GossipSub with `pubsub.WithFloodPublish(true)` only. It does not set `WithMessageIdFn` or `WithTopicMessageIdFn`.
- The vendored libp2p pubsub default message ID is `DefaultMsgIdFn`, which returns `from + seqno`; topic publish fills `From` and `Seqno` when a peer ID is present.
- `PublishGroupMessage` always encrypts the application payload and stores the application `messageId` in encrypted `extra`; it adds `publishedAtNano`, then publishes the encrypted v3 envelope. Current duplicate same-application-ID proof expects two live `group_message:received` events because different ciphertext/seqno values produce distinct PubSub messages while preserving the same application ID for downstream Dart dedupe.
- `handleIncomingGroupMessage` does message-id dedupe before group/member lookup when event-log tamper gating is not installed, repeats message-id dedupe after event-log append when it is installed, and preserves the first trusted row while optionally enriching quoted/media fields.
- Existing Dart proofs include conflicting duplicate content/timestamp replay, PubSub plus inbox replay dedupe, local notification dedupe, and fake-network duplicate delivery idempotency. They do not prove live GossipSub message hash/sequence collision behavior or a first-class group receipt matrix.
- `group-real-network-nightly` requires `FLUTTER_DEVICE_ID` and passes `MKNOON_REQUIRE_MULTI_RELAY=true` to `integration_test/multi_relay_failover_test.dart`; that test fails deliberately without at least two comma-separated `MKNOON_RELAY_ADDRESSES`.
- Availability checks during planning: `flutter devices --machine` found `emulator-5554`, physical iPhone `00008030-001A6D2801BB802E`, iOS simulators `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, `1B098DFF-6294-407A-A209-BBF360893485`, plus `macos` and `chrome`; `xcrun simctl list devices available` confirmed the booted iOS simulators; `adb devices` failed because `adb` is not installed; `FLUTTER_DEVICE_ID`, `MKNOON_RELAY_ADDRESSES`, `MKNOON_CLI_PEER_COMMAND`, and `MKNOON_CLI_PEER_ARGS` were unset.

## real scope

LP-013 owns duplicate group PubSub handling for the trusted-private group chat path. The session must produce concrete, row-specific evidence for:

- same application `messageId` delivered more than once over live PubSub;
- same encrypted wire envelope bytes, or same wire-data hash, delivered more than once with distinct PubSub sequence values;
- libp2p default message-ID behavior for same `from + seqno` with conflicting payload bytes;
- downstream Dart handling when duplicate live/inbox events carry the same `messageId` but conflicting text, timestamp, quoted-message, media, or notification context.

Product changes are allowed only if these proofs expose a user-visible or persisted-state gap in LP-013 owner files: double DB rows, double local notifications, overwritten trusted fields, missing application `messageId`, or sender/status regression. Otherwise this session should add focused proof tests and update the matrix/inventory with concrete evidence.

This session does not redesign GossipSub, replace the libp2p message-ID algorithm globally, add first-class group read receipts, implement new UI surfaces, or reopen unrelated group reliability rows.

## closure bar

LP-013 is closure-ready only when the executor can show all of the following in committed repo evidence:

- Go/raw-protocol or live libp2p proof demonstrates how default PubSub message IDs, data/hash equality, and sequence differences affect duplicate delivery into the node layer.
- The application `messageId` survives live duplicate delivery into `group_message:received` events, including conflicting duplicate payloads.
- Dart receive/listener tests prove duplicates with the same application `messageId` do not create second rows, second notifications, unread-count inflation, or trusted-field overwrites.
- The source matrix row and `test-inventory.md` are updated from `Partial` to `Covered` or `Closed` only with exact file names, test names, and command evidence. If any proof cannot be produced because a raw-protocol or device fixture is unavailable, the row must stay `Partial` with an exact blocker.

## source of truth

- Current code and focused tests win over stale prose.
- The active row contract is `Test-Flight-Improv/Group-Chat-Feature/trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md` row `LP-013`.
- The active execution breakdown is `Test-Flight-Improv/Group-Chat-Feature/trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md` row 4.
- Existing evidence inventory is `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` row `LP-013`.
- Named-gate truth is `Test-Flight-Improv/test-gate-definitions.md` plus `scripts/run_test_gates.sh`.
- If docs and code disagree, code/tests decide the implementation plan; docs must be corrected only after tests produce concrete evidence.

## session classification

`evidence-gated`

This is not acceptance-only or doc-only. It is implementation-committed gap closure: add focused proof tests first, then patch repo-owned behavior if the proof exposes a gap.

## exact problem statement

LP-013 is still `Partial` because current evidence proves application-level message-id dedupe and one live duplicate-publish shape, but does not prove the broader PubSub collision matrix:

- default GossipSub message IDs are `from + seqno`, not an application `messageId`;
- same encrypted payload bytes can be published with distinct PubSub sequence values and reach the receiver more than once;
- same PubSub message ID with conflicting data is a libp2p-level collision surface that may drop one payload before the app sees it;
- app-level conflicting duplicate delivery must remain first-writer-wins, without overwriting text/timestamp/media/trusted fields or issuing duplicate notifications.

The user-visible behavior to protect is simple: duplicate or malicious group delivery must not create double rows, double notifications, unread inflation, or overwrite a previously accepted trusted message. Existing send, encryption, membership, discovery, relay, and invite semantics must stay unchanged.

## files and repos to inspect next

Production and protocol files:

- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/node.go`
- `go-mknoon/node/rendezvous.go`
- `go-mknoon/node/group_inbox.go`
- `go-mknoon/internal/group_envelope.go`
- `go-mknoon/third_party/go-libp2p-pubsub/midgen.go`
- `go-mknoon/third_party/go-libp2p-pubsub/pubsub.go`
- `go-mknoon/third_party/go-libp2p-pubsub/topic.go`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/domain/repositories/group_message_repository.dart`
- `lib/features/groups/domain/repositories/group_message_repository_impl.dart`

Tests and fixtures:

- `go-mknoon/node/pubsub_delivery_test.go`
- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/node/group_inbox_test.go`
- `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`
- `test/features/groups/integration/group_edge_cases_smoke_test.dart`
- `test/integration/group_notification_dedupe_integration_test.dart`
- `integration_test/transport_e2e_test.dart`
- `integration_test/multi_relay_failover_test.dart`
- `integration_test/scripts/run_group_multi_device_real.dart`
- `scripts/run_test_gates.sh`
- `Test-Flight-Improv/test-gate-definitions.md`

## existing tests covering this area

- `go-mknoon/node/pubsub_delivery_test.go` has `TestPublishGroupMessage_DuplicateProvidedMessageIdRemainsVisibleAfterDecrypt`, proving two live publishes with the same provided application `messageId` decrypt at the receiver with that ID.
- `handle_incoming_group_message_use_case_test.dart` proves event-log tamper rejection, duplicate message-id fast path, PubSub plus group-inbox dedupe, duplicate quoted-message/media enrichment, tampered timestamp ignoring, conflicting-content ignoring, and duplicate media no-resave behavior.
- `group_message_listener_test.dart` proves duplicate local notification suppression and duplicate shipped system event idempotency.
- `group_resume_recovery_test.dart` proves PubSub plus inbox replay with same `messageId` keeps one incoming row and preserves live content over conflicting replay content.
- `group_edge_cases_smoke_test.dart` proves fake-network duplicate delivery idempotency.
- `group_notification_dedupe_integration_test.dart` proves a recent remote push suppresses a later local group notification for the same message.

Missing coverage:

- no test pins default PubSub `from + seqno` message-ID behavior against same data/hash and conflicting data;
- no live/raw Go test republishes the exact same encrypted envelope bytes to show sequence-distinct delivery behavior;
- no focused listener-level test combines conflicting duplicate message content with UI stream count, notification count, unread count, and original trusted row preservation;
- no first-class group read-receipt duplicate path exists in the scoped owner files.

## regression/tests to add first

Add tests before any production change.

1. In `go-mknoon/node/pubsub_delivery_test.go`, add a test-only raw publish helper that reads `n.groupTopics[groupId]` under lock and calls `topic.Publish(ctx, []byte(envelopeJSON))`. Keep it in `_test.go`.
2. Add `TestLP013DuplicateWireEnvelopeWithDistinctPubSubSeqnosPreservesApplicationMessageId`: build one signed/encrypted v3 group envelope with application `messageId=lp013-wire-dup`, publish the identical envelope bytes twice through the raw helper, and assert receiver events either:
   - produce two `group_message:received` events with the same `messageId`, same text, and same key epoch when PubSub treats distinct sequence values as distinct messages; or
   - if libp2p suppresses the second message, produce exactly one event and document that same-wire duplicate suppression happens before the app. Either outcome is acceptable only if the test assertion is explicit and downstream Dart proof covers the delivered shape.
3. Add `TestLP013ConflictingApplicationDuplicatePubSubPayloadsPreserveFirstWriterInputsForDartDedupe`: live-publish two valid group envelopes with the same encrypted application `messageId` but conflicting text/timestamp. The Go assertion should prove both delivered events still carry the same application `messageId`; it should not try to do database dedupe in Go.
4. Add `TestLP013DefaultPubSubMessageIdUsesSourceAndSeqnoNotPayloadHash`, using vendored `pubsub.DefaultMsgIdFn` and `pb.Message`, to prove same `from + seqno` with different `Data` collides at PubSub ID level, while same `Data` with different `Seqno` does not.
5. In `test/features/groups/application/group_message_listener_test.dart`, add or extend a focused LP-013 listener regression that emits two `group_message:received` events with the same `messageId` but conflicting text/timestamp/media/quoted fields while the app is backgrounded. Assert one saved message, one UI stream insertion if that stream is observable, one local notification, stable original text/timestamp/status/key generation, and no unread inflation beyond the first delivery.
6. Reuse existing `handle_incoming_group_message_use_case_test.dart`, `group_resume_recovery_test.dart`, and `group_notification_dedupe_integration_test.dart` as regression anchors. Add new cases there only if the focused listener test cannot observe a required LP-013 dimension.

## step-by-step implementation plan

1. Re-run `git status --short` and inspect any dirty LP-013 owner files before editing. Do not revert unrelated changes. If an owner file is dirty, patch only around current content and preserve existing edits.
2. Add the Go raw-publish helper and LP-013 Go tests in `_test.go` only. Prefer `pubsub_delivery_test.go`; use `pubsub_test.go` only for pure default-message-ID proof if imports or helper placement are cleaner there.
3. Run the focused Go LP-013 tests. If they fail because current code loses application `messageId`, emits malformed events, rejects valid duplicates unexpectedly, or cannot publish a valid raw envelope through existing test seams, patch only `go-mknoon/node/pubsub.go` or the test helper seam needed to preserve app IDs and produce deterministic events.
4. Add the listener-level Flutter LP-013 regression. If it fails because the listener notifies twice, emits duplicate UI rows, or overwrites the first trusted row, patch only `group_message_listener.dart`, `handle_incoming_group_message_use_case.dart`, or the message repository layer that caused the failure.
5. Run the focused Dart duplicate regressions. If the existing use-case tests already prove a dimension, cite them rather than duplicating coverage.
6. Run the broader owner commands and named gates listed below. Treat known unrelated failures according to `known-failure interpretation`.
7. Update only the LP-013 row in the source matrix and `test-inventory.md` after evidence is green. The update must list exact test names and commands. If a required raw/device fixture is unavailable, keep the row `Partial` and record the exact blocker instead of claiming closure.
8. Stop. Do not absorb LP-002, LP-003, LP-006, relay privacy, invite replay, membership, media, push, or UI-redesign work.

## risks and edge cases

- PubSub default ID collision: same `from + seqno` with conflicting data can collapse before app code sees both payloads. The plan must document whether this is proven at the vendored libp2p boundary or requires a deeper raw RPC fixture.
- Same encrypted wire payload with different sequence values can produce repeated app events; Dart dedupe must handle the repeated application `messageId`.
- Same application `messageId` with conflicting text/timestamp/media must not overwrite the first trusted row.
- Listener notification logic must be gated on a newly persisted message, not only event arrival.
- Event-log tamper mode intentionally rejects conflicting duplicates before silent dedupe. Do not weaken that protection.
- Missing first-class group receipts can cause overreach. This session should verify current sender/inbound status behavior, not invent a receipt protocol.
- Dirty owner files can contain prior session changes. Avoid broad formatting or mechanical rewrites.

## exact tests and gates to run

Focused required commands after adding LP-013 tests:

```sh
cd go-mknoon && go test ./node -run 'TestLP013|TestPublishGroupMessage_DuplicateProvidedMessageIdRemainsVisibleAfterDecrypt' -v
```

```sh
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'LP013'
```

```sh
flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name 'duplicate replay with the same messageId ignores conflicting content'
```

```sh
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'same message is not duplicated if both pubsub and group inbox deliver it'
```

```sh
flutter test --no-pub test/features/groups/integration/group_edge_cases_smoke_test.dart --plain-name 'duplicate delivery'
```

```sh
flutter test --no-pub test/integration/group_notification_dedupe_integration_test.dart
```

Broader owner/gate commands:

```sh
cd go-mknoon && go test ./node ./bridge ./cmd/testpeer -run 'Group|PubSub|Rendezvous|Protocol|Inbox' -v
```

```sh
./scripts/run_test_gates.sh groups
```

```sh
flutter test --no-pub test/features/groups/integration
```

```sh
git diff --check
```

Fixture-backed supporting command when relays are available:

```sh
FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD MKNOON_RELAY_ADDRESSES='<relay-multiaddr-1>,<relay-multiaddr-2>' ./scripts/run_test_gates.sh group-real-network-nightly
```

Optional paired-device supporting command only if an LP-013 duplicate scenario is added to the harness:

```sh
MKNOON_RELAY_ADDRESSES='<relay-multiaddr-1>,<relay-multiaddr-2>' dart integration_test/scripts/run_group_multi_device_real.dart -d 347FB118-10D0-40C8-A05B-B0C3BD6B8CCD,5BA69F1C-B112-47BE-B1FF-8C1003728C8F
```

## Device/Relay Proof Profile

Primary LP-013 closure profile: `host-only raw-Go/libp2p proof` plus focused Flutter host tests. This is sufficient for the row only if it covers the PubSub ID/hash/sequence dimensions and downstream DB/UI/notification dedupe listed in the closure bar.

Supporting profile: `single-device multi-relay` through `group-real-network-nightly`. It is not a substitute for LP-013 raw collision proof because the current nightly gate runs `integration_test/multi_relay_failover_test.dart`, which imports transport and group recovery scenarios rather than a duplicate-collision harness.

Current availability:

- `flutter devices --machine` available IDs: `emulator-5554`, `00008030-001A6D2801BB802E`, `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, `1B098DFF-6294-407A-A209-BBF360893485`, `macos`, `chrome`.
- Booted iOS simulator candidates confirmed by `xcrun simctl list devices available`: `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, `1B098DFF-6294-407A-A209-BBF360893485`.
- Android paired-device tooling is incomplete locally: `adb devices` returned `command not found`, although Flutter sees Android emulator `emulator-5554`.
- `FLUTTER_DEVICE_ID` is unset.
- `MKNOON_RELAY_ADDRESSES` is unset.
- `MKNOON_CLI_PEER_COMMAND` and `MKNOON_CLI_PEER_ARGS` are unset.

Classification:

- Host-only: required primary closure evidence for LP-013.
- Single-device: supporting only; a single `FLUTTER_DEVICE_ID` selects the Flutter host target for `group-real-network-nightly`.
- Paired-device: supporting only unless an LP-013 duplicate-collision device harness is added; use `run_group_multi_device_real.dart -d <primary>,<sibling>` for two Flutter app processes.
- Three-party/device-lab: not currently available as LP-013 closure evidence without a duplicate-collision scenario and configured CLI/relay fixtures.
- Multi-relay: external-fixture-blocked locally until at least two relay multiaddrs are provided through `MKNOON_RELAY_ADDRESSES`.

If a device/relay run is attempted without relay env, the expected failure is `MKNOON_REQUIRE_MULTI_RELAY=true requires at least two comma-separated MKNOON_RELAY_ADDRESSES entries via --dart-define`; classify that as a fixture blocker, not a product regression.

## known-failure interpretation

- Existing broad Go owner-suite failures tied to LP-006 or bridge peer-mismatch paths, such as `TestPublishGroupMessage_ReturnsPeerCountZero_WhenNoPeers` and `TestGroupPublish_ResponseIncludesTopicPeers`, are not LP-013 regressions unless the LP-013 diff changes their code paths.
- Existing full offline-inbox MD-011 future-media replay failure is not an LP-013 regression unless LP-013 changes media replay semantics.
- Missing `MKNOON_RELAY_ADDRESSES` or missing CLI fixture output from real-network tests is a fixture blocker. Do not count skipped or self-contained-only real-network output as LP-013 closure evidence.
- Any new failure in the added LP-013 tests, duplicate listener tests, or direct duplicate use-case tests is in scope and must be fixed or explicitly classified with evidence.

## done criteria

- The intended LP-013 tests are committed in owner test files and prove PubSub ID/hash/sequence behavior plus downstream dedupe behavior.
- Any production changes are limited to LP-013 owner files and are directly forced by failing LP-013 proof.
- Focused Go and Flutter commands pass, or any failure is classified as unrelated with exact failing test names and evidence.
- `git diff --check` passes.
- `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md` and `test-inventory.md` are updated only after concrete evidence exists; LP-013 is marked `Covered` or `Closed` only if all closure-bar evidence is present.
- If relay/device proof is unavailable, the final execution record names the exact missing fixture and leaves LP-013 `Partial` rather than claiming closure from host proof alone when a required dimension remains unproven.

## scope guard

Do not:

- change global GossipSub message-ID functions unless a failing LP-013 proof shows the current default causes a user-visible LP-013 bug;
- add a new group receipt/read-receipt product feature;
- alter encryption, signing, membership authorization, key-rotation, invite, relay inbox, media, or discovery behavior unless the LP-013 proof fails specifically there;
- broaden into LP-002 authorization, LP-003 unsubscribe, LP-006 fallback, relay privacy, group admission, or media recovery rows;
- run destructive git commands or revert dirty user/session changes;
- use `group-real-network-nightly` self-contained output as proof for hash/ID/sequence collisions.

## accepted differences / intentionally out of scope

- The current group architecture has sender-side status and inbound `delivered` status, but no first-class per-recipient group receipt protocol in the scoped owner files. LP-013 may document this as an accepted current-architecture difference after verifying duplicate delivery cannot double-update existing status; it must not implement receipts in this row.
- Vendored libp2p default ID behavior is a transport-level fact. The LP-013 app contract is to preserve application `messageId` and dedupe at the app boundary, unless proof shows transport behavior hides or corrupts valid app events.
- Device/relay proof is supporting for this row unless a reviewer later determines host raw-Go tests cannot exercise the required collision surface.

## dependency impact

- Closing LP-013 unblocks later trusted-private closure claims that depend on duplicate delivery safety under live PubSub plus inbox replay.
- LP-013 evidence should be referenced by TP-SMOKE-07 but must not close unrelated TP-SMOKE-07 dimensions such as protocol negotiation, relay/bootstrap fallback, or metadata minimization.
- If this plan changes because raw PubSub collision injection is impossible locally, later rollout sessions must treat LP-013 as external-fixture-blocked until a raw-protocol or device-lab fixture exists.

## dirty-worktree handling

Planning observed a dirty worktree before this plan file was created, including modified group docs, Go node/bridge files, and Flutter group tests, plus untracked prior session plan/test files. Execution must:

- run `git status --short` before editing;
- inspect dirty owner files before patching them;
- preserve unrelated edits and avoid whole-file formatting;
- keep LP-013 changes reviewable by test name and row marker;
- stop and ask for direction if an existing dirty change makes an LP-013 owner edit ambiguous or unsafe.

## regression contract

All LP-013 implementation must be regression-first. A failing or missing proof test must exist before production code changes. If the new tests pass without product changes, do not patch product code. If a product patch is required, rerun the exact failing LP-013 test first, then the focused owner tests and named gates above.

## stop rule

Stop after LP-013 has either:

- concrete repo evidence and doc updates sufficient to mark the source row `Covered` or `Closed`; or
- a precise blocker such as `missing_raw_pubsub_same_seqno_collision_fixture`, `missing_multi_relay_fixture`, or `missing_cli_peer_duplicate_collision_harness`.

Do not loop on broad parity, optional relay breadth, or receipt feature work after the LP-013 closure bar is satisfied or blocked.

## Reviewer Pass

Verdict: sufficient with one incremental adjustment, not insufficient.

Sufficiency answers:

- The plan is sufficient as-is for implementation after the arbiter records the final decision.
- Missing files/tests/gates: none structurally. The plan names the Go raw proof tests, listener/use-case/integration duplicate tests, `groups`, `group-real-network-nightly`, broader Go owner command, Flutter group integration command, and `git diff --check`.
- Stale or incorrect assumptions: none found. It correctly treats current code/tests as source of truth and keeps real-network proof supporting because current fixtures are unset and the nightly gate does not itself exercise LP-013 collision injection.
- Overengineering: no structural overreach. The plan explicitly rejects adding a new receipt protocol or global GossipSub message-ID rewrite unless failing LP-013 proof forces it.
- Decomposition: row-owned and narrow enough; it starts with proof, then patches only observed LP-013 behavior gaps.
- Minimum needed to make sufficient: persist this reviewer verdict and arbiter classification in the plan artifact.

## Arbiter Decision

Structural blockers: none.

Incremental details:

- The reviewer requested self-contained final verdict sections in this artifact. They are now present below.

Accepted differences:

- Device/relay proof remains supporting evidence for LP-013 unless raw host proof cannot exercise a required collision surface.
- First-class group receipt protocol work is intentionally out of scope; the plan verifies current status/dedupe behavior instead of adding a new product feature.

Arbiter stop rule: stop planning. No structural blocker exists, so there is no patch/re-review loop.

## Final Planning Output

Final verdict: `execution-ready`, row-owned, evidence-gated, and implementation-committed.

Final plan: execute the `regression/tests to add first`, `step-by-step implementation plan`, `exact tests and gates to run`, and `Device/Relay Proof Profile` sections above without widening beyond LP-013.

Structural blockers remaining: none.

Incremental details intentionally deferred:

- exact raw helper placement may be `pubsub_delivery_test.go` or `pubsub_test.go`, chosen during implementation based on imports and existing helper locality;
- device/relay proof can be added only when relay multiaddrs and a relevant LP-013 duplicate scenario fixture are available.

Accepted differences intentionally left unchanged:

- current scoped group code has no first-class per-recipient receipt protocol;
- current `group-real-network-nightly` is supporting release confidence and not a duplicate-collision proof by itself.

Exact docs/files used as evidence:

- `Test-Flight-Improv/Group-Chat-Feature/trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/Group-Chat-Feature/trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`
- `go-mknoon/node/pubsub.go`
- `go-mknoon/node/pubsub_delivery_test.go`
- `go-mknoon/node/pubsub_test.go`
- `go-mknoon/internal/group_envelope.go`
- `go-mknoon/third_party/go-libp2p-pubsub/midgen.go`
- `go-mknoon/third_party/go-libp2p-pubsub/pubsub.go`
- `go-mknoon/third_party/go-libp2p-pubsub/topic.go`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/domain/repositories/group_message_repository.dart`
- `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`
- `test/features/groups/integration/group_edge_cases_smoke_test.dart`
- `test/integration/group_notification_dedupe_integration_test.dart`
- `integration_test/multi_relay_failover_test.dart`
- `integration_test/scripts/run_group_multi_device_real.dart`

Why the plan is safe to implement now:

- It starts with focused proof tests and blocks product edits unless those tests expose an LP-013 behavior gap.
- It names exact files, direct tests, named gates, known unrelated failures, fixture blockers, and dirty-worktree rules.
- It keeps closure tied to concrete source-matrix and inventory updates rather than acceptance-only wording.

## Executor Evidence Notes

Executor verdict: ready for QA, with one required broad Go owner command classified as blocked by known unrelated peer-mismatch failures. No LP-013 proof test failed.

Files changed by this Executor pass:

- `go-mknoon/node/pubsub_delivery_test.go`
- `test/features/groups/application/group_message_listener_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-LP-013-plan.md`

Tests added or updated:

- `TestLP013DefaultPubSubMessageIdUsesSourceAndSeqnoNotPayloadHash`
- `TestLP013DuplicateWireEnvelopeWithDistinctPubSubSeqnosPreservesApplicationMessageId`
- `TestLP013ConflictingApplicationDuplicatePubSubPayloadsPreserveFirstWriterInputsForDartDedupe`
- `group notifications LP013 duplicate PubSub delivery preserves first row and notification state`

Production patches: none. The new LP-013 proofs passed without exposing a row-owned production gap.

Required command results:

1. `cd go-mknoon && go test ./node -run 'TestLP013|TestPublishGroupMessage_DuplicateProvidedMessageIdRemainsVisibleAfterDecrypt' -v` passed.
2. `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'LP013'` passed.
3. `flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name 'duplicate replay with the same messageId ignores conflicting content'` passed.
4. `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'same message is not duplicated if both pubsub and group inbox deliver it'` passed.
5. `flutter test --no-pub test/features/groups/integration/group_edge_cases_smoke_test.dart --plain-name 'duplicate delivery'` passed.
6. `flutter test --no-pub test/integration/group_notification_dedupe_integration_test.dart` passed.
7. `cd go-mknoon && go test ./node ./bridge ./cmd/testpeer -run 'Group|PubSub|Rendezvous|Protocol|Inbox' -v` failed with known unrelated failures: `github.com/mknoon/go-mknoon/node TestPublishGroupMessage_ReturnsPeerCountZero_WhenNoPeers` and `github.com/mknoon/go-mknoon/bridge TestGroupPublish_ResponseIncludesTopicPeers`, both `peer_mismatch`/`validation failed` paths called out in the LP-013 known-failure interpretation. Structured rerun confirmed LP-013 tests passed inside this selection.
8. `./scripts/run_test_gates.sh groups` passed.
9. `flutter test --no-pub test/features/groups/integration` passed.
10. `git diff --check` passed.

Required commands not run: none.

Per user override, source matrix, test inventory, and session-breakdown ledger were not updated in this pass. `group-real-network-nightly` was not used as LP-013 evidence because relay fixture env remains outside this required command set and the plan says it is supporting only while relay env is unset.

## QA Reviewer Evidence Notes

QA verdict: `accepted`.

Files reviewed:

- LP-013-owned diffs: `go-mknoon/node/pubsub_delivery_test.go`, `test/features/groups/application/group_message_listener_test.dart`, and this LP-013 plan.
- Existing duplicate anchors: `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`, and `test/integration/group_notification_dedupe_integration_test.dart`.
- Dirty unrelated/pre-existing files: source matrix, `test-inventory.md`, session-breakdown ledger, GL-005/LP-002/LP-003 Go and Flutter files. Their diffs leave LP-013 as `Partial` and do not add LP-013 closure evidence, matching the user override.

Diff review:

- Go proof tests cover default PubSub message IDs as `from + seqno` rather than payload hash, same encrypted wire-envelope duplicate publish behavior, and conflicting duplicate application payloads that preserve the same application `messageId` into received events.
- Flutter listener proof covers one saved row, one UI stream insertion, one local notification, unread count of one, and first trusted text/timestamp/status/key/quoted/media preservation.
- Existing focused use-case and integration tests are sufficient for the plan's reuse clause; no additional use-case test was required.
- Production patches for LP-013: none. Existing production diffs belong to other dirty sessions and were not needed by LP-013.

Tests/gates verified from Executor evidence:

- `cd go-mknoon && go test ./node -run 'TestLP013|TestPublishGroupMessage_DuplicateProvidedMessageIdRemainsVisibleAfterDecrypt' -v` passed.
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'LP013'` passed.
- `flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name 'duplicate replay with the same messageId ignores conflicting content'` passed.
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'same message is not duplicated if both pubsub and group inbox deliver it'` passed.
- `flutter test --no-pub test/features/groups/integration/group_edge_cases_smoke_test.dart --plain-name 'duplicate delivery'` passed.
- `flutter test --no-pub test/integration/group_notification_dedupe_integration_test.dart` passed.
- `cd go-mknoon && go test ./node ./bridge ./cmd/testpeer -run 'Group|PubSub|Rendezvous|Protocol|Inbox' -v` failed only in known unrelated peer-mismatch paths: `TestPublishGroupMessage_ReturnsPeerCountZero_WhenNoPeers` and `TestGroupPublish_ResponseIncludesTopicPeers`. `/tmp/lp013-go-owner.json` also shows all LP-013 tests and the existing duplicate provided-message-ID test passed inside that selection.
- `./scripts/run_test_gates.sh groups` passed.
- `flutter test --no-pub test/features/groups/integration` passed.
- `git diff --check` passed before QA note edits and again after QA note edits.

Blocking issues: none.

Non-blocking residual risks:

- Relay/device duplicate-collision proof was not run; this is acceptable because relay env is unset and the Device/Relay Proof Profile makes host-only raw Go/libp2p plus focused Flutter host tests the primary closure evidence.
- Source matrix, test inventory, and session-breakdown are not updated for LP-013 by user override, so canonical LP-013 row status remains `Partial` until a permitted closure-doc pass records the new evidence.
- First-class group receipts remain out of scope because the current scoped group implementation does not expose a receipt protocol to test or modify in LP-013.

## Final Execution Verdict

Final verdict: `accepted`.

Fix pass required: no.

LP-013 changed only row-owned tests and this plan:

- `go-mknoon/node/pubsub_delivery_test.go`
- `test/features/groups/application/group_message_listener_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-LP-013-plan.md`

Accepted evidence:

- New Go proofs cover default PubSub ID behavior (`from + seqno`, not payload hash), duplicate identical encrypted wire-envelope publish behavior, and conflicting duplicate application payloads preserving the same application `messageId`.
- New Flutter listener proof covers duplicate delivery without second row, second UI stream insertion, second notification, unread inflation, or trusted-field overwrite.
- Existing focused use-case and integration duplicate anchors passed and were accepted by QA as satisfying the plan's reuse clause.
- No LP-013 production patch was needed.
- The broad Go owner command failed only in known unrelated peer-mismatch paths: `TestPublishGroupMessage_ReturnsPeerCountZero_WhenNoPeers` and `TestGroupPublish_ResponseIncludesTopicPeers`; `/tmp/lp013-go-owner.json` shows the LP-013 tests passed inside that selection.

Required commands not run: none.

`group-real-network-nightly` was not substituted for closure evidence because relay env is unset and the Device/Relay Proof Profile makes host-only raw-Go/libp2p proof plus focused Flutter host tests primary. Per user override, source matrix, test inventory, and session-breakdown ledger were not updated in this execution pass.

## Closure Documentation Pass

Closure-doc pass on 2026-05-01 moved LP-013 from `Partial` to `Covered` in `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules.md`, `test-inventory.md`, and `trusted_private_libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md` after the accepted executor/QA evidence and controller reruns. This supersedes the execution-pass-only note above that canonical LP-013 docs still remained `Partial`.

No new production patch was recorded by this closure pass. Residual-only items remain unchanged: relay/device duplicate-collision proof is supporting only while relay env is unset, and first-class group receipts remain outside LP-013 because the scoped group implementation has no first-class receipt protocol to test or modify.
