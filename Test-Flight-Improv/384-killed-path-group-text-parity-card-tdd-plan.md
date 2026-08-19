# 384 - Killed-Path Group Notifications: The Parity False-Positive (G19) And The Strict Lane's Missing Push (G26)

Status: executed 2026-08-19 — Wave 1 (G19) host green + DEVICE CLOSED; Wave 2 (G26) host green, NOT deployed
Type: Bug
Spec: free-text intent (no formal spec) — closes **G19** and **G26** from the [UI-23 E2E map](../UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Behavior_and_E2E_Test_Map.md) §4.6; PRD clauses at `Mknoon_Private_Reliable_Notifications_PRD_v1.2.md:172` (§6 "Suspended / terminated … render locally or leave the generic fallback"), `:290` ("Post a generic local fallback if private rendering cannot complete")
Classification: implementation-ready
Closure tier: device (Wave 1, G19) / host (Wave 2, G26 — no device leg exists)

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-18 | Evidence Collector (lead) | push_decrypt_preview parity block + copy path, bmh context builder/dispatch/catch, send use case inboxPayload, replay-envelope builder, relay inbox_test, 3 device flow logs, host row `:1185-1280` | Outer-context check did NOT fire on device; host killed-path rows stub the whole resolver; Dart replay envelope is id-complete — so the observed mismatch was unexplained by the replay-path source | Fan out verify→refute |
| 2026-08-18 | Verify→refute (wf_65f28eed-400, 6 agents: parity-test inventory, producer census, siblings, fix posture, closure surfaces, adversarial refute) | see Graph Grounding Snapshot | **Root cause pinned**: default-lane pushes carry the Go LIVE envelope (no inner sender key) × clause 6's missing null-guard; all 5 refute angles dead; PRD affirmatively sanctions the killed-path card; full 10-surface census for a third out-of-catalog scenario | Emit Test Contract |
| 2026-08-18 | /tdd-review (wf_cf1112fb-b22, 4 workers: factual, counterexample, wire-domain, boundary/campaign; lead self-verified every blocker linchpin in source) | runner `:295-320`, pubsub `:1860-1876`, bridge `:2599-2741`, predicate/test files re-read | **plan-fixes-required → all deltas applied same session** (3 blockers: hoisted-guard escape, guard-the-throw escape, runner validator dispatch; 4 plan-fixes: window-scoped ERROR rule, contains-based SHOWN binding, extra-shape correction, media-List correction + wrapper closure commands); core bet CONFIRMED end-to-end | Execute |

## Problem And Evidence

- Behavior to improve: a group TEXT (or media) push arriving at a **killed** Android app on the default send lane dies at `PUSH_ANDROID_DATA_DECRYPT_FAIL{kind: group, reason: group_parity_mismatch}` → `PUSH_BACKGROUND_NOTIFICATION_ERROR OrdinaryMessageNotificationIntegrityException(group_plaintext_parity_mismatch)` and posts **no OS card**, breaking §1.3's `Suspended/killed → FCM wake → Card` promise. Observed 3/3 deterministically (Plan 379 runs 13/14/15 warm-up pushes; recipient `21071FDF600CSC`, real FCM, relay v1.8.0, APK `0a8c93f6`). The matching host row passes because it stubs the entire resolver.
- Impact: every killed-app group text/media notification on the default (non-strict) lane is silently lost — the highest-volume killed-app typed event. Live since the parity check landed (`491ad6d91`, 2026-07-13; predicate shape since `f1b568bca`, 2026-08-04). Group *reactions* card fine on the same path (different resolver), which is why this went unnoticed until 379's warm-up text.
- **Confirmed root cause (two composing halves, both source-verified; survived a 5-angle adversarial refute):**
  1. **Producer reality:** the default group send does NOT push the Dart replay envelope. `sendGroupMessage` → `callGroupSendReliable` (`send_group_message_use_case.dart:3079`) → Go `SendGroupMessageReliable` stores a **live Go envelope** (version "3", `type: group_message`, no `kind` field — `go-mknoon/node/pubsub.go:424-441,:497-539`; `go-mknoon/internal/group_envelope.go:25-37`) whose encrypted plaintext is `GroupMessagePayload{text, timestamp, username, extra}` with **no `senderId`/`senderPeerId`/`sender_id` and no `groupId` key anywhere**; `extra` = every bridge opt except `timestamp`, plus `messageId` (overwritten) and `publishedAtNano` — on a default text send roughly 10 keys (`senderDeviceId`, `senderTransportPeerId`, `senderDevicePublicKey`, `senderKeyPackageId`, `logicalDeliveryId`, `groupName`, `recipientPeerIds`, `preserveRecipientPeerIds`, …; `pubsub.go:1860-1876,:496`, opts source `bridge.go:2698-2741`) — and **none of them matches the parity reader's sender keys** (review-corrected: the plan's earlier "only 3 keys" description was wrong; the conclusion is unchanged). The relay forwards it verbatim (`inbox.go:854-899,:1221-1256`) — producing exactly the 9 FCM dataKeys observed on the failing push (no `kind`, no outer sender-ACCOUNT key; `sender_transport_peer_id` IS present and is exactly what resolves the context that arms clause 6).
  2. **Predicate asymmetry:** the parity check (`push_decrypt_preview.dart:1002-1021`; extraction `:983-1001`) OR's six clauses into one collapsed reason. Clause 3 (`decodedGroupId != null && …`) null-guards an absent inner group id; **clause 6 (`context.senderPeerId != null && decodedSender != context.senderPeerId`) has no null-guard**, so the live envelope's absent inner sender (`decodedSender == null`) fires it on **every** killed-app delivery with a resolved context. Clauses 1/2/4 pass (`extra.messageId` == outer `message_id`), clause 3 is skipped, clause 5 is false — clause 6 is the only structurally-armed clause for this shape.
  - The group-message resolver is the ONLY one of the four preview resolvers that decodes plaintext as a raw JSON map with hand-rolled per-field extraction; direct message / direct reaction / group reaction all use typed factories that reject absent identity fields wholesale into distinct reasons (`message_payload.dart:196-211`, `reaction_payload.dart:170-187`, `group_reaction_payload.dart:82-125`) — the asymmetry exists only here.
- Fix (surgical, PRD-aligned): add the same null-guard clause 3 already has — `decodedSender != null &&` on clause 6 — so an inner plaintext that *omits* the sender is cross-checked against nothing and the card renders from **trusted context facts** (title = local `groupName`, sender prefix = roster `context.senderUsername` — the copy path already refuses decrypted names when a context exists, `:1080-1093`); an inner sender that is **present but wrong** still throws (genuine-tamper posture unchanged and test-locked). Plus: a `clause` discriminator key on the existing `group_parity_mismatch` flow event, so the next parity red is diagnosable in one log read instead of a multi-agent day (the collapsed catch-all is called out by the map's G19 row itself). No reason-string literals change; zero tests or gates pin them (repo-wide census).
- Existing coverage: `push_decrypt_preview_test.dart:1224-1345` locks genuine-tamper throws (4-row mismatch loop `:1302-1344` — its sender-attacker row `:1314-1318` is already a UNIQUE clause-6 pin) and the outer-context check (`:1276-1300`); `:1769-1866` locks decrypt-error/preview-unavailable fail-closed; bmh G17 rows lock resolver-fallback → SHOWN. Gates: the file is in `GROUP_TESTS`/`ONE_TO_ONE_TESTS` (`run_test_gates.sh:285,:824`; review-corrected — `:273` is a comment) + AUTO feature-host.
- Missing coverage (host-tier inventory, wf_65f28eed-400 agent A): the **null-decodedSender arm of clause 6 has zero rows in either direction** — every CONTEXT-BEARING fixture is id-complete in the Dart replay-envelope shape (two contextless fixtures at `:1439-1477,:1540-1602` already model live-envelope-like payloads, but clause 6 is context-gated and unreachable there — review-sharpened); clause 1's throwing arm untested; clause 2's no-context protection arm has zero mismatch rows; clauses 2/5 have no uniquely-pinning row (deleting either alone survives the suite); no killed-path group-text device proof exists (the muted lane's warm-up is deliberately ungraded).
- Refuted findings (do NOT re-introduce):
  - "Already fixed on the worktree / by a recent commit" — refuted: `push_decrypt_preview.dart` diff-free; the uncommitted G17 hunk (`bmh:1040-1129`) is downstream of the parity throw.
  - "Harness artifact" — refuted: the warm-up is a real-composer send (uiautomator into the production editor, capture `:3782-3806`), commit live-gated on `outcome=success` + exact inbox custody; repush/pending lanes would have failed the capture; sibling reaction pushes in the same killed window validated fine.
  - "Stale/skewed build" — refuted: APK `0a8c93f6` built 08-18 09:50Z after every relevant commit; all three recipient logs emit the `nondurable_fallback` detail that exists only in the current worktree.
  - "E2E build divergence" — refuted: `E2E_TEST_MODE`/`PRODUCTION_FCM` gate debug seams and push registration only, never the plaintext/envelope/context resolution.
  - "Not relay-originated" — refuted: server-form FCM ids, exact relay dataKey set, custody-stored ingestion.
  - "Outer message_id is obfuscated for the relay" (this plan's own early hypothesis) — refuted: `_relayVisibleReplayMessageId` passes ordinary ids through (`group_offline_replay_envelope.dart:2605-2610`).
  - "The context's expectedMessageId comes from a stale local row" — refuted: it is the outer `message_id` (`bmh:3098-3106`).
- Unresolved findings (recorded, none gate the fix): (a) sender/outer/stored **id triangulation** across the three captures is undecidable from disk (sender logs discarded; outer app-level id never logged) — the host causal RED reproduces the exact live-envelope shape instead; (b) the empirical clause tag from a live device was never observed pre-fix — if the post-fix campaign run ever reds at parity again, the new `clause` key answers it in one read.
- **New finding surfaced by the producer census (not this plan's scope, must not be lost):** the STRICT lane (plan-377 fresh/strict-authority groups) produces **no `type=group_message` FCM push at all** — per-recipient custody goes to the DIRECT inbox and `extractChatPushMetadata` has no case for the replay envelope (`inbox.go:1358-1467`), so `ShouldNotify=false`; killed-path notification for strict groups rides the opaque-wake/headless-recovery machinery (GAP-N02/N08 activation) → recorded under Deferred with owner.
- Affected production / test / gate files: `lib/features/push/application/push_decrypt_preview.dart` (the ONLY production edit); `test/features/push/application/push_decrypt_preview_test.dart`; `integration_test/scripts/group_muted_notification_android_criteria.dart` + `group_reaction_notification_device_criteria.dart` + `capture_group_reaction_notification_device.dart` (new scenario) + `run_group_muted_notification_android.dart` (validator dispatch at `:302` — review blocker); `integration_test/group_muted_notification_proof_test.dart`; `test/integration/group_muted_notification_criteria_test.dart`; `scripts/test/group_muted_notification_device_contract_test.sh`; `tool/sims/critical_features.json` (+ its two byte-pins: `scripts/test/reliability_simulation_discovery_contract_test.sh:229-271`, `test/tool/sims/sims_proof_binding_registry_test.dart:414-475`).

## Graph Grounding Snapshot
- Graph fingerprint / freshness: `9915847b12a9dee5`; current (incremental refresh run at planning start after the Stop-hook marker).
- Query / profile: `python3 graphify-arch/tdd_context.py query "push_decrypt_preview group_plaintext_parity_mismatch OrdinaryMessageNotificationIntegrityException background_message_handler group text notification killed path" --profile tdd --budget 700`; refined by workflow `wf_65f28eed-400` (6 agents: A parity-test inventory, B producer census, C adversarial refute, D siblings, E fix posture, F closure surfaces).
- Anchors: parity block `push_decrypt_preview.dart:1002-1021` (condition `:1002-1012`, emit `:1013-1017`, throw `:1018-1020`), outer check `:913-923`, extraction `:983-1001`, copy path `:1080-1119`, trusted fallbacks `:874-890,:1040-1055`; context builder `background_message_handler.dart:3049-3106`, dispatch `:2665-2700`, terminal catch `:1544,:1636-1641`; Go producer `pubsub.go:424-441,:1860-1876`, `group_envelope.go:25-46`; relay `inbox.go:854-899,:1221-1256,:2766-2852`; sender `send_group_message_use_case.dart:2567-2590,:3040-3079`; muted-lane surfaces per agent F (listed in TC-384-07).
- Surfaced proof/gate files: `push_decrypt_preview_test.dart` (in `GROUP_TESTS`/`ONE_TO_ONE_TESTS`, `run_test_gates.sh:285,:824`); `foreground_group_message_notification_resolver_test.dart`; `group_muted_notification_criteria_test.dart`; the three device flow logs under `build/sims/proofs/groups.muted_notification_campaign/capture-{1787053468061245-18726,1787054530723960-25728,1787055431430779-31910}/`.
- Graph gaps that required raw source search: Go relay/bridge literals, device flow logs, plan/PRD markdown (all labeled `GRAPH_OK`).
- Reuse rule: anchors are search starting points; every conclusion above carries current-source evidence and must be re-verified at execution (line numbers drift).

## Scope Contract And Guard

In scope:
- **W1 (the fix):** null-guard clause 6 (`decodedSender != null &&`), mirroring clause 3 — one condition in `push_decrypt_preview.dart:1011`.
- **W2 (discriminator):** a `clause` detail key on the existing `PUSH_ANDROID_DATA_DECRYPT_FAIL{kind: group, reason: group_parity_mismatch}` emit, valued as the FIRST true clause in evaluation order (`inner_message_id_missing` · `inner_id_outer_mismatch` · `inner_group_id_mismatch` · `inner_id_context_mismatch` · `inner_sender_is_local` · `inner_sender_context_mismatch`); the `reason` literal and the exception reason are byte-unchanged.
- **W3 (host contract):** live-envelope-shape causal rows (text + media), per-clause tag rows including the two untested arms (clause 1; clause 2's no-context arm), unique pins for clauses 5 and 6.
- **W4 (device closure):** third out-of-catalog scenario `android_group_text_killed_app_card` in the Plan-330/379 muted-campaign lane + its own validator + registration sweep (TC-384-07).
- Execution-time map/index/memory updates (G19 row → closed-by-384; record the strict-lane no-push finding).

Must preserve:
- Genuine-tamper suppression (present-but-wrong inner fields still throw) → the 4-row mismatch loop `push_decrypt_preview_test.dart:1302-1344` stays green byte-unchanged (TC-384-04).
- Outer-context check, decrypt-error fail-closed, preview-unavailable lane → existing rows `:1276-1300,:1769-1866`; group-reaction parity sentinel `:490-542`; private-media redaction rows `:1480-1667` (citation review-corrected) — all stay green.
- The two shipped muted scenarios (`groups.muted_notification_campaign`) stay green — the fix makes their ungraded warm-up text CARD, which their scoped assertions tolerate by construction (zero-card checks are muted-group/marker-scoped, capture `:2951-2962,:3527-3535`; the control card is asserted via BODY CHANGE `:3519-3524`) → re-proven by the same campaign run (TC-384-06).
- Foreground drain resolver suite (pre-decrypt fail-closed rows and the clause-1-shaped malformed row are untouched by the null-guard) → TC-384-08.
- The muted validator's admission/exact-keys grammar untouched (the new scenario ships its own validator kind).

Hard `Do not`:
- Do not change the Go live-envelope payload or any wire format (adding inner sender/group keys is deferred hardening, owner GAP-N02 payload work) — the recipient-side null-guard is the complete fix for legitimate traffic.
- Do not convert genuine-mismatch (present-but-wrong) throws into cards — that posture is deliberate and test-locked; changing it would re-derive 4 green rows for zero G19 benefit.
- Do not decompose the sibling collapsed reasons (direct message `:798-811`, direct reaction `:675-689`, group reaction `:513-538`) — diagnosability-only, no null-guard defect exists there (typed factories), out of scope.
- Do not grade the warm-up push or touch the ≥-wakes/neither-graded-first rules (G21 discipline).
- Do not name the new scenario with the `_message_unread_lifecycle` suffix or a prefix shared with the two muted ids (dispatch-fallback + anchored `--name` + contract-sh traps, criteria `:34-39`, dispatch `:851-857`, sh `:128-133`).
- Do not edit `lib/core/debug/group_reaction_e2e_probe.dart` (the new scenario needs no probe staging — no reaction, no in-app seeding beyond the existing real-UI fixture).
- Do not touch `mUserLockedFields`/fingerprint machinery or anything Plan-380 owns.

Deferred / accepted difference:
- ~~**Strict-lane killed-path notification** (no `group_message` push exists at all on that lane) → owner GAP-N02/N08 activation wave.~~ **DISCHARGED by Wave 2 below** (G26), at host tier and behind a default-off flag. Its reaction half remains deferred as G27.
- **Sibling collapsed-reason decomposition** (direct/reaction) → unowned, optional diagnosability; the typed factories already fail distinctly on absent fields.
- **Producer self-describing payload** (inner sender/group keys in the live envelope) → GAP-N02 payload shape work.
- **1:1 killed-path device evidence** → G22 / Plan 380 b12 rows (unchanged by this plan).
- **Clause 4 is structurally dead as a FIRST-true clause** (the upstream outer check forces `outerMessageId == expectedMessageId` whenever both exist, so clause 1 — id missing — or clause 2 — id ≠ outer — always fires first; with `outerMessageId` null and `expectedMessageId` set, the outer check throws pre-decrypt; review-verified boolean walk) — kept as defense-in-depth, documented, and deliberately NOT given a unique pin (impossible by construction; the tag can never emit `inner_id_context_mismatch` while the outer check holds; it becomes clause 1's fallback tag under a clause-1 deletion, which is exactly how TC-384-03's deletion walk reds that row).
- Foreground drain-error path improvement (legitimate live-envelope texts now card instead of null-swallow at `foreground_group_message_notification_resolver.dart:171-173`) — accepted consequence of the same seam; guarded by TC-384-01/08, no separate foreground row.

Dependencies:
- **Plan 383's working-tree fix must be present (commit it first).** The device leg's card renders through G17's non-durable fall-through; on a tree without it, a passing parity still exits silently at the durable-effect block. (The map §4.3 already demands the commit; this plan's device run hard-depends on it.)
- Muted-campaign environment: pinned pair (`emulator-5554` sender, `21071FDF600CSC` recipient), relay v1.8.0, FCM, prebuilt `android.production_fcm` APK, run via the repo-resident host wrapper (`docker-ws/run_muted_campaign_383.sh:27` precedent — host bridge drops container env).

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD state → GREEN | Mutation that re-reds | Gate / registration |
|---|---|---|---|---|---|---|
| TC-384-01 | **Live-envelope group TEXT with full context renders the trusted typed card** — decrypted payload `{text,timestamp,username,extra:{…full default-lane opts key set…}}` (byte-shape from `group_envelope.go:42-47` + `pubsub.go:1860-1876,:496` + `bridge.go:2698-2741` — extra carries the ~10 real keys incl. `senderDeviceId`/`senderTransportPeerId`/`senderDevicePublicKey`/`senderKeyPackageId`/`logicalDeliveryId`/`groupName`/`recipientPeerIds`, `extra.messageId` == outer `message_id`), outer data = the 9 relay keys, full `GroupMessageNotificationContext` | `test/features/push/application/push_decrypt_preview_test.dart::'live Go envelope without inner sender key renders the trusted group card'` | unit / hand-built context + decrypt closure (fixture fidelity pinned to the Go source anchors in a comment) | causal RED (HEAD throws `OrdinaryMessageNotificationIntegrityException` — clause 6 fires on null `decodedSender`) → returns card: title == context groupName, body == `_groupUserPreviewBody` sender-prefixed text (roster `senderUsername`, never a decrypted name), `PUSH_ANDROID_DATA_DECRYPT_OK{kind:group}` emitted, **ZERO `PUSH_ANDROID_DATA_DECRYPT_FAIL` events captured by the flow sink** (review blocker: without this, a wrong fix that keeps clause 6 firing but skips only the THROW — emit-FAIL-then-card — passes every row), comparand == the TRUSTED outer comparand (decodedSender null ⇒ fallback binding — composite assertion) | revert the `decodedSender != null &&` guard → row red (throws again) | `flutter test test/features/push/application/push_decrypt_preview_test.dart`; AUTO (feature glob) + already in `GROUP_TESTS`/`ONE_TO_ONE_TESTS` |
| TC-384-02 | **Live-envelope group MEDIA same shape no longer throws** — `extra.media` is a **List of attachment maps** end-to-end (review-corrected: `send_group_message_use_case.dart:2537-2539` → `bridge_group_helpers.dart:455` → `bridge.go:2606` `[]map[string]interface{}` → opts → extra; the earlier "non-List encoding degrades to generic copy" premise was refuted) — card returned with trusted title + non-empty TYPED media body (private-media redaction body when the four `mediaPolicy` wire keys are present; exact copy deliberately not over-pinned), ZERO `PUSH_ANDROID_DATA_DECRYPT_FAIL` | same file::`'live Go envelope media flavor renders a card instead of throwing'` | unit / same fixture + `extra.media` as a List of attachment maps with `mediaType` | causal RED (same clause-6 throw) → no throw, card fields asserted | same guard revert | same command; same registration |
| TC-384-03 | **Parity flow event carries a per-clause discriminator** — `details.clause` = first-true clause; rows: clause 1 (`inner_message_id_missing`: id-free AND **sender-free** payload + context — currently a fully UNTESTED throwing arm), clause 2 no-context arm (`inner_id_outer_mismatch`: context NULL, decoded id ≠ outer id — currently zero mismatch rows), clause 3 (`inner_group_id_mismatch`: **sender-ABSENT live-envelope payload with a wrong inner `groupId`** — review blocker: with a present sender this row cannot distinguish the correct clause-6-only guard from a HOISTED guard (`decodedSender != null &&` wrapped around clauses 3-6 or the whole condition, which silently disables tamper checks for sender-absent payloads); with the sender absent, the correct fix tags `inner_group_id_mismatch` while any hoisted variant CARDS → row red), clause 5 (`inner_sender_is_local`: hand-built context with `senderPeerId == localPeerId` — production builder forbids this at `bmh:3061`, noted in-test), clause 6 (`inner_sender_context_mismatch`: present-but-wrong sender). `reason` stays `group_parity_mismatch` byte-identical | same file — one `test` per clause row, flow-sink captured via `debugSetFlowEventSink` (setter `flow_event_emitter.dart:57`; usage precedent `background_message_handler_test.dart:720`) | unit / flow-event sink | causal RED (`clause` key absent on HEAD) → each row asserts its exact tag AND the unchanged `reason` literal | remove the tag emit → all rows red; delete any single clause → its row red (deletion walk verified: clause 1 deleted → its fixture tags `inner_id_context_mismatch` instead → tag-inequality red; clauses 2/3/5 deleted → their fixtures fire nothing → missing-throw red; clause 6 deleted → its row red AND existing loop row `:1314-1318` red) | same command; same registration |
| TC-384-04 | **Genuine-tamper posture preserved** — the existing 4-row mismatch loop (wrong groupId / wrong messageId / attacker sender / self sender, all fields PRESENT) still throws; outer-check row, decrypt-error rows, preview-unavailable rows untouched | `push_decrypt_preview_test.dart:1224-1345` (loop `:1302-1344`), `:1276-1300`, `:1769-1866` — byte-unchanged | unit / existing | GREEN sentinel → still green | post-fix mutation: delete clause 6 entirely → TC-384-03's `inner_sender_context_mismatch` row red (unique pin); delete clause 3 → its tag row red | same command |
| TC-384-05 | **Killed-path group text posts a card on device** — kill recipient → ungraded warm-up (absorbs first wake, storage-warmth-gated) → graded real-composer group text → `PUSH_BACKGROUND_NOTIFICATION_SHOWN` whose details carry the graded push's FCM messageId (valid on this lane because the killed path takes the NON-durable branch, `bmh:1529-1543` — the durable SHOWN form carries no id; if the durable disposition ever activates here, re-derive the validator), **ZERO `PUSH_BACKGROUND_NOTIFICATION_ERROR` lines in the scenario's accumulated post-kill flow window** (review-corrected: the ERROR event carries no id — `bmh:1636-1641` — so an id-bound rule is unimplementable; the window holds only the warm-up + graded wakes, post-fix neither may error, and storage-deferral emits no ERROR so G21 stays out of scope), OS card whose **body CONTAINS the graded marker** (dumpsys-side, independent of the flow event; the wait's stale/exclusion set includes BOTH the baseline and warm-up markers — the warm-up now cards under the same conversation-keyed notification id, so bare body-change latches early), pre-kill baseline card as the alive-lane control | new scenario `android_group_text_killed_app_card` in the muted-campaign lane (own lifecycle fn cloning capture `:3468-3502` kill/warm-up/warmth steps + one `_sendGroupText`; **default else-branch fixture** — `TC257Group<micros>`, creator = recipient, zero fixture-branch edits, the validator pins that shape) | device proof / pinned pair, prebuilt APK, real FCM, relay v1.8.0 | manual/device-only proof — **deterministically RED today**: the identical push dies at parity (capture's own `:3036-3046` comment + 3 archived flow logs) → GREEN post-fix | revert the clause-6 guard → the campaign run reds at this scenario (card never posts; SHOWN absent, ERROR present in-window) | `/claude-host-bin/host-run bash docker-ws/run_muted_campaign_383.sh` (the existing env wrapper — name is historical, it runs the whole capability; 3 scenarios); registration per TC-384-07 |
| TC-384-06 | **Existing muted scenarios stay green with the now-carding warm-up** — review-audited rule-by-rule: no SHOWN-count or ERROR rule exists in the muted validator, muted/control rules are contains-based (`criteria:1040-1047,:1066-1076,:1108-1183,:1351-1377`), the binding resolver excludes only `received.first`, and the control-card "exactly one" check survives because every lane posts under one conversation-keyed notification id. The fix's SECOND behavior change — the ALIVE-lane foreground drain-error fallback for group texts now returns a card instead of null (`foreground_group_message_notification_resolver.dart:171-173` swallow no longer reached for legitimate live-envelope texts) — is tolerated for the same two reasons: muted display-eligibility gates BEFORE the resolver, and the one shared conversation-keyed id keeps the control card count at 1 | `android_group_muted_message_suppression` + `android_group_muted_reaction_background_suppression` in the SAME campaign run | device proof / same run | GREEN sentinel (device) → still green | n/a — guarded by the same campaign run as TC-384-05 (one run proves both) | same closure command |
| TC-384-07 | **Registration complete for the third scenario** — id const + `groupMutedNotificationScenarioIds` append + criterion string; **runner validator dispatch (review blocker, source-confirmed): the runner loop hard-codes `validateGroupMutedNotificationAndroidArtifact` for EVERY id (`run_group_muted_notification_android.dart:302-308`) and the muted admission (`criteria:523-528`) rejects a third id — so without a runner edit the campaign reds at runner-validation even after the capture child self-validates green; dispatch the per-scenario validator via `groupReactionCaptureDispatchFor(scenarioId)!.validatorKind` (mirror capture dispatch site 4) and mirror it in `--validate-artifact` (`:543-556`)**; source scenario + lifecycle-stage/validator-kind enum cases + dispatch branch placed before the TERMINAL catch-all (`:857-863` — the catch-all, not the suffix branch, is what would swallow an unbranched id); **reuse observation kind `mutedTarget`** — no new `GroupReactionCaptureObservationKind` case (zero consumers; over-engineering avoided); capture lifecycle case + own validator `validateGroupKilledTextCardAndroidArtifact` (muted validator admission untouched); artifact schema: receivedDigests (≥2, graded ≠ `receivedDigests.first`), **SHOWN binding pinned CONTAINS-based: `shownDigests` CONTAINS `sha256(gradedFcmMessageId)` — `single`/`last`/exact-count over SHOWN are FORBIDDEN (the warm-up SHOWNs too post-fix; mirror the muted validator's contains-rules `:1166-1183`)**, marker, card-dump evidence; proof test third `test()` + dart-define `MKNOON_384_GROUP_TEXT_KILLED_CARD_ARTIFACT`; contract-sh census re-pin (`:112-133`); `critical_features.json:895` assertions +1 with its TWO byte-pins re-derived in the same commit (discovery-contract sh `:229-271`, registry test `:414-475`; capability stays the LAST element) | `test/integration/group_muted_notification_criteria_test.dart` new rows: positive fixture accepted; negatives — SHOWN-binding missing → reject, ANY `PUSH_BACKGROUND_NOTIFICATION_ERROR` line in the post-kill window → reject, card/marker evidence missing → reject, graded push == first wake → reject | host / artifact fixtures + sh contract | causal RED by construction (validator + rows don't exist; the sh `cmp` reds on the census edit until re-pinned — same-change resolution) → all green | remove the dispatch branch → criteria test's dispatch-coverage row red; remove the validator's window-ERROR rule → its negative row red; revert the runner dispatch → the campaign reds at runner-validation on the new id | `flutter test test/integration/group_muted_notification_criteria_test.dart` (host-all-only dir → direct gate); `/claude-host-bin/host-run bash scripts/test/group_muted_notification_device_contract_test.sh`; `flutter test test/tool/sims/sims_proof_binding_registry_test.dart`; `/claude-host-bin/host-run bash scripts/test/reliability_simulation_discovery_contract_test.sh` |
| TC-384-08 | Foreground resolver suite unaffected (pre-decrypt fail-closed rows assert `decryptCalls == 0`; the malformed row dies pre-decrypt at the resolver's own nonce input gate — `foreground_group_message_notification_resolver.dart:129-134`, proven by its `decryptCalls == 0` assertion, so parity is never reached (review-corrected from "clause-1-shaped"); the happy row uses the id-complete replay shape) | `test/features/push/application/foreground_group_message_notification_resolver_test.dart` — unchanged | unit / existing | GREEN sentinel → still green | guarded by TC-384-01 (same seam; a foreground-specific regression implies the resolver seam changed, which TC-384-01/03 pin) | `flutter test test/features/push/application/foreground_group_message_notification_resolver_test.dart` |

### Test Notes
- TC-384-01/02 fixture fidelity is the point: the decrypt closure returns the **Go live-envelope plaintext byte-shape** (fields `text`/`timestamp`/`username`/`extra` with the FULL default-lane extra key set), NOT the Dart `inboxPayload` shape every existing context-bearing fixture uses. Pin the shape's source anchors (`group_envelope.go:42-47`, `pubsub.go:1860-1876,:496`, `bridge.go:2698-2741`) in a comment so a future Go payload change tells the reader which side moved.
- TC-384-02 device note: oversized media envelopes are stripped relay-side to the 6-key `preview_unavailable` fallback (`inbox.go:882-897`) and never reach parity on device — which is why the media flavor closes at host tier.
- TC-384-03 tag semantics: first-true clause in evaluation order. Clause-5's fixture requires a hand-built context with `senderPeerId == localPeerId` (the production context builder rejects self-senders at `bmh:3061` — the row documents it pins the predicate, not a production-reachable state). Clause-2's row is the no-context arm (clause 2 CAN also fire with a context — existing loop row `:1309-1313` does — but that shape is already covered; the no-context protection arm is the one with zero rows). The sender-ABSENT constraint on the clause-1 and clause-3 fixtures is load-bearing (kills the hoisted-guard wrong fix) — do not "simplify" them to field-complete payloads.
- TC-384-05 scenario id traps (agent F): not a prefix of / prefixed by the two muted ids; no `_message_unread_lifecycle` suffix; append LAST in `groupMutedNotificationScenarioIds` so declaration order (and the sh census) stays stable for the shipped pair.
- TC-384-05 asserts the graded card via **body change to the graded marker** — post-fix the warm-up cards too (same conversation, one stable notification id), so presence alone is vacuous; the tone window makes the graded card land silent-channel, so no channel/sound assertion (out of scope — G12's discipline lives in the payload campaign).
- The campaign runner isolates scenarios (fresh installs + per-id artifact purge + clean-slate check at window open, runner `:230-235`, capture `:4266-4278`), so the new card-present scenario cannot leak cards into the muted scenarios.

## Implementation Steps
1. Snapshot `git status --short` (expected dirty: Plan-383 fix + 380/381 work — do NOT revert). **Commit or verify-present the 383 bmh fix** (device-leg dependency).
2. Author TC-384-01/02/03 rows; record the causal REDs (each must fail with the clause-6 throw / missing `clause` key respectively).
3. **W1+W2 production edit** (`push_decrypt_preview.dart` only): add `decodedSender != null &&` to clause 6; compute the first-true clause and add `'clause': <tag>` to the `:1013-1017` emit. Stop-if: any OTHER clause turns out to fire for the TC-384-01 fixture → the root cause is mis-pinned; halt and re-open the refute pass (do not widen the guard).
4. Focused GREEN: the full preview test file + foreground resolver file + graph-affected named files.
5. **W4**: criteria consts/census + criterion string; source scenario + enums + dispatch; capture lifecycle fn (clone kill→warm-up→warmth from `:3468-3502`, add pre-kill baseline card, graded `_sendGroupText`, marker-CONTAINS card wait with baseline+warm-up in the stale set, flow-binding extraction); **runner validator dispatch** (`run_group_muted_notification_android.dart:302` + `--validate-artifact:543-556` — per-scenario via `groupReactionCaptureDispatchFor`); own validator + TC-384-07 host rows; proof-test third block + dart-define; contract-sh re-pin; `critical_features.json` assertions + re-derive its two byte-pins; update the capture's `:3036-3046` warm-up parity-death comment to past tense (fixed by 384) so the file stops documenting dead behavior.
6. Registration verification: grep gates below + discovery + completeness.
7. Device closure: one `groups.muted_notification_campaign` run (3 scenarios) via the host wrapper; archive the new artifact; update the E2E map (G19 → closed-by-384; add the strict-lane no-push finding), `00-INDEX.md`, and rebuild project-memory (`python3 project-memory/src/build_graph.py`).

## Risks And Blind Spots
- Fake side-effect fidelity → THE causal theme: TC-384-01/02 pin the real producer's plaintext shape; the device row (TC-384-05) closes the boundary the stubs cannot.
- Sibling-surface consistency → verified: direct message/reaction + group reaction use typed factories that reject absent identity fields distinctly (agent D census); asymmetric fix is deliberate and recorded; sibling reason decomposition deferred.
- Lifecycle / derived-state durability → N/A: the fix removes a throw; no new derived state. The scenario's killed-process reconstruction is the existing lane discipline.
- Destructive-action side effects → N/A: no delete/cleanup change; the runner's per-id purge covers the new artifact automatically (id joins the shared list).
- Invariant re-verification under new transitions → the no-throw path re-verifies card invariants via TC-384-01's composite assertions (trusted comparand binding, DECRYPT_OK, no decrypted-name promotion).
- Construction/call-site census → `resolveBackgroundPushNotification` callers: 5 in `bmh` (`:2613,:2672,:2723,:2768,:2781`) + 2 in the foreground resolver (`:121,:148`) — the edit is INSIDE the callee, all callers inherit; re-grep at execution.
- Composite-node assertions → TC-384-01 (comparand fields from the TRUSTED context on one returned object); TC-384-05 (SHOWN event bound to the graded FCM id; card body bound to the graded marker).
- Build-artifact provenance → inherited: the runner's central-build provenance check (`run_group_muted_notification_android.dart:323-330`) gates the campaign; no new native artifact.
- Permission/ACL verb symmetry → N/A: no permission surface.
- The `critical_features.json` triple byte-pin (file + discovery-contract sh + registry test) must move in ONE commit or `sims-contracts` reds — same-change resolution, named in TC-384-07.

## Gate Cadence
- Per-plan closure: focused causal tests + sentinels + `./scripts/run_test_gates.sh groups` (the affected curated lane; the preview file also rides `1to1`, exercised by the same direct run) + the sh contracts named in TC-384-07 + the device campaign run. No `core-host-all`/`feature-host-all` sweep (one production file changed, direct + lane coverage is proportionate).
- Graph-affected first: `python3 graphify-arch/tdd_context.py affected lib/features/push/application/push_decrypt_preview.dart --budget 600` → run every named test file directly BEFORE the lane.
- Full `host-all` is NOT a per-plan gate — owner: the GAP-N12 wave + final release closure (same owner Plan 380 named).
- Shared tests outside feature/core globs: `flutter test test/integration/group_muted_notification_criteria_test.dart` and `flutter test test/tool/sims/sims_proof_binding_registry_test.dart` (direct commands; host-all-only dirs).

## Acceptance Gates  (literal — copy/paste)
```bash
# Dirty-tree snapshot (383/380/381 worktree edits expected — do not revert; commit 383's fix first)
git status --short

# Causal REDs (before production edits) — must FAIL for the documented reason
flutter test test/features/push/application/push_decrypt_preview_test.dart --plain-name 'live Go envelope without inner sender key renders the trusted group card'   # RED: clause-6 throw on null decodedSender
flutter test test/features/push/application/push_decrypt_preview_test.dart --plain-name 'live Go envelope media flavor renders a card instead of throwing'           # RED: same throw
flutter test test/features/push/application/push_decrypt_preview_test.dart --plain-name 'parity mismatch reports inner_sender_context_mismatch clause'              # RED: no clause key on HEAD

# Focused GREEN (after the fix) — exit 0, zero failures
flutter test test/features/push/application/push_decrypt_preview_test.dart
flutter test test/features/push/application/foreground_group_message_notification_resolver_test.dart
flutter test test/integration/group_muted_notification_criteria_test.dart
flutter test test/tool/sims/sims_proof_binding_registry_test.dart

# Graph-affected dependents BEFORE the lane
python3 graphify-arch/tdd_context.py affected lib/features/push/application/push_decrypt_preview.dart --budget 600
# then: flutter test <each named file>

# Curated lane
./scripts/run_test_gates.sh groups            # exit 0

# Contracts (host bridge; sh gates are grep-pinned, never run-verified for registration)
/claude-host-bin/host-run bash scripts/test/group_muted_notification_device_contract_test.sh      # PASS with the 3-id census
/claude-host-bin/host-run bash scripts/test/reliability_simulation_discovery_contract_test.sh     # PASS (critical_features pin re-derived)
grep -c 'android_group_text_killed_app_card' integration_test/scripts/group_muted_notification_android_criteria.dart   # expect >=2 (const + census list)
grep -c 'MKNOON_384_GROUP_TEXT_KILLED_CARD_ARTIFACT' integration_test/group_muted_notification_proof_test.dart          # expect >=1
./scripts/check_reliability_simulation_discovery.sh   # exit 0 (no new files expected — sentinel)
/claude-host-bin/host-run ./scripts/run_test_gates.sh completeness-check   # PASS, 0 unmatched

# Device closure (pinned pair; MUST run via the repo-resident env wrapper — the host bridge drops
# container env, so a bare run_with_devices.sh from here loses MKNOON_RELAY_ADDRESSES/FCM creds and
# self-blocks; the wrapper passes "$@" before --only, so --list passes through. Review-corrected.)
/claude-host-bin/host-run bash docker-ws/run_muted_campaign_383.sh --list    # groups.muted_notification_campaign listed
/claude-host-bin/host-run bash docker-ws/run_muted_campaign_383.sh          # PASS: 3 validated artifacts (2 muted + android_group_text_killed_app_card)
# host-shell alternative (running ON the Mac with env exported): .claude/skills/sims/scripts/run_with_devices.sh major --only groups.muted_notification_campaign

# Hygiene
flutter analyze            # 0 new issues
git diff --check
```

## Execution Interpretation And Done Criteria
- Expected RED: the three causal-RED commands; the contract-sh `cmp` between the census edit and its re-pin (same-change resolution).
- GREEN sentinel: mismatch-loop/outer/decrypt-error/preview-unavailable rows; foreground resolver suite; the two muted device scenarios.
- Pre-existing dirty tree / known failure: 383/380/381 worktree edits; `sims-contracts` aggregate still carries the three pre-existing reds recorded by Plan 380 (dtr13 hash pin, intro-accept adapter assertion, project-memory-381) — none owned here; the two sh contracts this plan touches must pass individually.
- Environment blocker (NOT product): missing FCM credentials / relay / prebuilt APK / device pair for the campaign run; Pixel keyguard (unlock before uiautomator legs).
- Scope drift (BLOCKING): any behavior change outside `push_decrypt_preview.dart`'s two edits; any weakened genuine-tamper row; any muted-validator grammar edit; any Go/wire change.

- [ ] Every behavior has a named test/proof (TC-384-01…08).
- [ ] Causal RED → GREEN + the guard-revert mutation re-red recorded (TC-384-01 at minimum).
- [ ] Sentinels + `groups` lane + both sh contracts + registry/discovery/completeness green with semantic outcomes.
- [ ] Registration grep-verified (census counts above).
- [ ] Device campaign run passes with all 3 artifacts validated; the new artifact carries the SHOWN binding + marker-bound card evidence.
- [ ] Map G19 row closed-by-384 + strict-lane finding recorded; `00-INDEX.md` row updated; project-memory rebuilt.
- [ ] `flutter analyze` clean; `git diff --check` clean; Scope Contract respected.

## Handoff
- First causal RED command: `flutter test test/features/push/application/push_decrypt_preview_test.dart --plain-name 'live Go envelope without inner sender key renders the trusted group card'` (after authoring the row).
- Preservation command: `flutter test test/features/push/application/push_decrypt_preview_test.dart` (whole file — mismatch loop + outer + fail-closed rows).
- Manual registration: the TC-384-07 sweep (criteria consts/census/criterion string, source scenario + enums + dispatch, capture lifecycle + validator kind, **runner validator dispatch `:302` + `--validate-artifact`**, proof-test block + dart-define, contract-sh census, critical_features assertions + two byte-pins).
- Migration: none.
- Boundary closure: one `groups.muted_notification_campaign` device run (3 scenarios) on the pinned pair.
- Unresolved evidence: pre-fix clause tag never observed live (non-blocking — the host RED reproduces the shape; the tag answers any future parity red in one read); id-triangulation across the archived captures undecidable from disk (recorded, moot once the scenario binds ids by design).

## Device/Relay Proof Profile
- Profile: paired-device (os-notification device lab) — the muted-campaign lane.
- Boundary being proven: OS-level card presence for a killed-process FCM group text — the exact boundary where host stubs lied (G19's lesson: the stubbed host row passed while the device posted nothing).
- Live availability check: `adb devices -l` → `21071FDF600CSC` (Pixel 6, SDK 36) + `emulator-5554` (SDK 36) (verified this session by Plan 379/380 work).
- Pinned targets: sender `emulator-5554`, recipient `21071FDF600CSC` (same roles as the shipped muted scenarios — the physical recipient is the measured G19 device).
- Automation: fully harness-driven (adb + uiautomator real-composer send; no user taps). Pixel keyguard must be unlocked (session landmine).
- Closure role: required closure evidence for G19.
- `FLUTTER_DEVICE_ID`: host selector only; both ids pinned in campaign argv.
- Registration: third id in `groupMutedNotificationScenarioIds` + dispatch + own validator kind + proof-test block; capability `groups.muted_notification_campaign` (assertions +1, entry stays LAST).
- Discovery command: `/claude-host-bin/host-run bash docker-ws/run_muted_campaign_383.sh --list` → capability listed (wrapper exports relay+FCM env; `"$@"` precedes `--only`).
- Closure command: `/claude-host-bin/host-run bash docker-ws/run_muted_campaign_383.sh` → PASS, 3 validated artifacts.
- Deferred device work: strict-lane killed-path (no push exists — GAP-N02/N08); 1:1 killed-path (G22/Plan 380); real-radio/Doze variants (GAP-N12).

## Wave 2 — G26: Strict-Authority Group Content Never Woke The Recipient

Status: executed 2026-08-19 (host green, mutation-verified; **NOT deployed — behaviour is OFF in production**)
Closure tier: host (no device leg exists — see Deferred below)
Landed: `37dd2eb20`

This wave closes the finding Wave 1's producer census surfaced and recorded under Deferred ("the STRICT
lane produces no `type=group_message` FCM push at all"). It was implemented directly on request, so
there is no separate pre-execution planning record and none is invented here.

### Problem And Evidence

- Behavior improved: a strict/fresh-authority group (Plan 377) delivered its messages to relay custody
  and then went completely silent — no push, no wake, no counter. §1.3's
  `Suspended/killed → FCM wake → Card` row was unreachable on that lane **by construction**. Unlike
  Wave 1's G19 this is not a parity failure: there was no push at all.
- Impact: total for that lane, for backgrounded and killed recipients alike. A strict group's messages
  became visible only when the recipient's app next ran and drained the inbox. The messages themselves
  were never lost — only the wake.
- **Root cause (two halves, both re-verified in source at execution rather than inherited from the
  planning-time census):**
  1. **Strict sends never reach the group topic.** `sendGroupMessage` returns before
     `callGroupSendReliable` (`send_group_message_use_case.dart:3040-3072`) and instead signs ONE
     `group_offline_replay` envelope per recipient into the DIRECT inbox under the `group_content_v1`
     ack-custody namespace (`group_offline_replay_envelope.dart:1286-1325`; custody kind at
     `inbox_store_outcome.dart:23`). The relay admits and stores it (`ack_custody.go:331-440`).
  2. **The direct push seam could not see that shape.** `launchStoredDirectPush`
     (`go-relay-server/inbox.go:2090`) recognized exactly two things: a `type: message_reaction` direct
     reaction, and `extractChatPushMetadata`'s switch on `envelope["type"]` (`inbox.go:1358-1468`). A
     replay envelope has **no `type` field at all**, so it fell to that switch's `default:` and produced
     `ShouldNotify: false`. `directWakeOutcomeProducer` reached the same verdict, so the durable
     wake-outcome path declined too. Nothing incremented.
- Why it stayed invisible: none of those declines had a counter. The lane produced no metric and no log
  line — the only observable was a user not getting a notification.
- **Facts that made the fix small, each verified before writing code:**
  - The envelope already carries every field `buildGroupPushMessage` needs (`groupId`, `keyEpoch`,
    top-level `ciphertext`/`nonce`, `messageId`, `senderTransportPeerId`), and
    `addGroupEncryptedPushData` (`inbox.go:1221-1256`) already falls back to top-level ciphertext/nonce.
  - **The recipient needed no change.** It routes on `data['type']` alone and ignores `kind`
    (`background_message_handler.dart:2579,:2683,:3030`).
  - **Plaintext parity agrees.** The strict plaintext is the id-complete `inboxPayload`
    (`send_group_message_use_case.dart:2567-2589`) and
    `contentEventId == resolvedMessageId == plaintext.messageId == outer message_id`. This is exactly
    the shape that never needed Wave 1's null guard — the two waves are the two halves of the same
    seam.
  - **The route resolves.** Strict custody recipients are `device.transportPeerId`
    (`send_group_message_use_case.dart:431-457`); `register_token` keys push tokens by the
    authenticated `remotePeer` (`inbox.go:3699-3708`) — the same namespace.
  - Both the plain `Store` path and the ack-custody path converge on `launchStoredDirectPush`
    (`inbox.go:1930`, `ack_custody.go:1029-1033`), so one branch covers both.
- Refuted during execution (do NOT re-introduce):
  - "The recipient must learn a new push type" — refuted: it routes on `type`, and this push IS
    `type: group_message`.
  - "The group-reaction wake already covers this" — refuted: `fanOutGroupReactionPush` is on the GROUP
    INBOX path (`s.store(groupId, …)`), which strict content never touches.
  - "A `case` in `extractChatPushMetadata` is enough" — refuted: that function switches on `type`, and
    a `kind` case there would entangle the strict lane's audience rules with the chat grammar.

### Scope Contract And Guard (Wave 2)

In scope:
- **W5:** recognize strict group content at the direct push seam and route `payloadType:
  group_message` through the existing `buildGroupPushMessage`.
- **W6:** a wake counter for every decision this lane makes, including the declines.
- **W7:** a default-off kill switch matching every sibling push flag.

Must preserve:
- Custody is never affected by the flag — only the wake (pinned by TC-384-11, which asserts the row is
  still stored).
- The ordinary chat, direct-reaction and group-topic push lanes stay byte-unchanged.
- The oversized/unusable-envelope fallbacks keep applying, so a bad key epoch degrades to a
  routing-only push rather than to silence.

Hard `Do not`:
- Do not route `payloadType: group_reaction` onto the group-message push. Its audience is author-only
  (PRD §6.5) and its copy comes from a separate notification-extension grammar; the group-message
  fanout would alert every member. → deferred as **G27**.
- Do not change the envelope, the custody admission, or any wire format — the producer already emits
  everything needed.
- Do not weaken the wake-token gate. This lane uses the ordinary-message gate (fail-open when the
  recipient registered no set), because this envelope IS the group's ordinary message traffic.

### Test Contract (Wave 2)

| Case | Behavior | Named test/proof | Tier | HEAD state → GREEN | Mutation that re-reds |
|---|---|---|---|---|---|
| TC-384-09 | The generic extractor cannot see strict group content — the root cause itself | `group_content_push_test.go::TestExtractChatPushMetadata_StrictGroupContentIsInvisible` | host (Go) | GREEN sentinel — documents why a dedicated lane is required, not optional | n/a (sentinel) |
| TC-384-10 | A complete strict group message is recognized AND eligible; a reaction is recognized and DECLINED; a non-custody replay envelope is not recognized at all; missing routing fields decline | `…::TestExtractGroupContentPushMetadata` (6 subtests) | host (Go) | causal RED by construction → green | reactions-eligible; drop the custody check; drop the routing-field guard — each reds its own subtest |
| TC-384-11 | The kill switch suppresses the wake and never drops custody | `…::TestInboxStore_StrictGroupContentStaysSilentWhenDisabled` | host (Go) | causal RED by construction → green | ignore the flag → red |
| TC-384-12 | **Causal row:** a stored strict group message wakes the recipient with the 7 data keys it routes on | `…::TestInboxStore_StrictGroupContentWakesTheRecipient` | host (Go) | causal RED (HEAD sends nothing) → green | delete the branch → red |
| TC-384-13 | **Production path:** the same wake through the ACK-CUSTODY store, whose admission validates signature, canonical signed payload and recipient set | `…::TestStoreAckCustody_StrictGroupContentWakesTheRecipient` + its disabled sibling | host (Go) | causal RED → green | delete the branch → red |
| TC-384-14 | Strict group reactions stay silent custody | `…::TestInboxStore_StrictGroupReactionStaysSilentCustody` | host (Go) | GREEN by construction | make reactions eligible → red |
| TC-384-15 | An unusable key epoch degrades to a routing-only push, never to silence | `…::TestInboxStore_StrictGroupContentWithUnusableEpochStillWakes` | host (Go) | causal RED → green | delete the branch → red |
| TC-384-16 | The flag is default-OFF and accepts only `1`/`true` | `…::TestLoadGroupContentPushEnabledFromEnv` | host (Go) | GREEN by construction | flip the default → red |
| TC-384-17 | **Recipient half:** the exact 10 data keys the relay now emits render a trusted card with ZERO `PUSH_ANDROID_DATA_DECRYPT_FAIL`; the routing-only fallback still cards generically | `push_decrypt_preview_test.dart::'strict-lane group content push renders the trusted group card'` + `'strict-lane routing-only fallback still returns a trusted card'` | host (Dart) | GREEN on first run — which IS the finding: **no client change was needed** | n/a — the row exists to prove the no-change claim, not to drive one |

#### Test Notes (Wave 2)
- TC-384-13 is load-bearing and was added after TC-384-12 already passed. Strict content never reaches
  `InboxStore.Store`; proving the wake only there would be the same class of gap that let G19 ship — a
  host row green on a path the real traffic does not take.
- TC-384-17's fixture is the relay's own output shape, not an invented one; the anchors are pinned in a
  comment so a future relay change tells the reader which side moved.
- Two closure gates census the EXACT caller set of `sendSelectedPushThroughGateway`
  (`opaque_wake_closure_test.go`, `push_token_vault_closure_test.go`). Any new push adapter reds both
  until it is declared in their `wantCallers` lists. By design, and easy to mistake for a real break.

### Affected Files (Wave 2)
- `go-relay-server/group_content_push.go` (**new** — extractor, gateway adapter, flag loader)
- `go-relay-server/group_content_push_test.go` (**new**)
- `go-relay-server/inbox.go` (the branch + `groupContentPushEnabled` field and setter)
- `go-relay-server/main.go` (flag wiring + startup log)
- `go-relay-server/metrics.go` (`relay_group_content_wake_total`)
- `go-relay-server/opaque_wake_closure_test.go`, `go-relay-server/push_token_vault_closure_test.go`
- `test/features/push/application/push_decrypt_preview_test.dart` (recipient rows)

### Gate Cadence (Wave 2)
- `cd go-relay-server && gofmt -l . && go vet ./... && go test ./...` — the authoritative gate. The
  `groups` lane runs the same Go suite at its end.
- `flutter test test/features/push/application/push_decrypt_preview_test.dart`.
- `./scripts/run_test_gates.sh groups` carries a KNOWN INTERMITTENT red in
  `group_conversation_wired_test.dart`'s voice block (a different row each run; all pass in isolation).
  Unrelated — this wave touches zero `lib/` files; verify with `git diff --stat HEAD -- lib/` before
  investigating.
- No `host-all` sweep: no production Dart changed.

### Acceptance Gates — Wave 2  (literal — copy/paste)
```bash
cd go-relay-server && gofmt -l . && go vet ./... && go test ./...   # exit 0, gofmt silent
cd .. && flutter test test/features/push/application/push_decrypt_preview_test.dart   # exit 0
flutter analyze            # 0 new issues
git diff --check
```

### Deferred / Accepted Difference (Wave 2)
- **G27 — strict group REACTIONS stay silent custody.** Deliberate: author-only audience (PRD §6.5)
  plus a separate notification-extension grammar. `extractGroupContentPushMetadata` returns them
  recognized-but-ineligible so they can never fall through, and TC-384-14 pins that. The natural fix is
  a strict-custody sibling of `fanOutGroupReactionPush` reusing the group-topic reaction's audience
  resolution. Unowned.
- **Deployment.** `GROUP_CONTENT_PUSH_ENABLED` is default-OFF, so deploying the binary alone changes
  nothing. Enabling needs a relay deploy plus the env var, on a PRODUCTION box with no staging twin.
  Not done here. Sibling landmine on record: the Plan-344 custody admission flag sat default-off and
  silently killed every offline send until it was flipped on 2026-08-16.
- **Device leg.** None exists. No registered scenario creates a strict-authority group, so
  `groups.muted_notification_campaign` cannot reach this path. A device proof needs a new fixture branch
  that forces the strict lane, and it can only run after the deploy above.
- **Durable wake-outcome ledger.** Strict group content does not participate in the Plan-370
  wake-outcome admission (`directWakeOutcomeProducer` still declines it), so there is no durable
  delivery-outcome row for these wakes. Not a regression — today there is no wake at all — but it is
  the next observability step after the deploy.

### Handoff (Wave 2)
- Turning it on: deploy the relay binary, then set `GROUP_CONTENT_PUSH_ENABLED=1`. The startup log
  prints the resolved value — confirm it there rather than assuming.
- Watch `relay_group_content_wake_total` after enabling. `attempted` should track strict-group sends; a
  spike in `invalid_or_disabled` means the flag never took or an envelope shape drifted.
- First device experiment: force a strict-authority group on the pinned pair, kill the recipient, send
  one text, and read the recipient's own flow log for
  `PUSH_BACKGROUND_MESSAGE_RECEIVED → PUSH_ANDROID_DATA_DECRYPT_OK → PUSH_BACKGROUND_NOTIFICATION_SHOWN`.
- Unresolved: no device evidence exists for this lane at any tier, and none can until the deploy lands.

## Reviewer Findings — Wave 1 (wf_cf1112fb-b22, 2026-08-18 — fixes applied same session)
- Verdict was **plan-fixes-required / apply-plan-fixes**; core bet **CONFIRMED** end-to-end by an independent wire-domain re-derivation (payload struct `group_envelope.go:42-47`; single extra producer `pubsub.go:1860-1876` with the messageId overwrite at `:1874`; bridge opts never carry a sender-account key; relay 9-key mapping byte-matches the archived failing push; the null-guard is forward-correct — a future present inner sender re-arms the cross-check). The clause-4-dead derivation, the TC-384-06 muted-campaign tolerance (verified rule-by-rule: contains-based, no SHOWN-count/ERROR pins, one conversation-keyed id), the G17 commit dependency, the one-group else-branch fixture, append-LAST ordering, the scenario-id traps, and the zero reason-literal pins all **survived attack**. Deleting clause 6 is caught twice (the new tag row AND existing loop row `:1314-1318`).
- Blockers fixed: (1) **hoisted-guard escape** — `decodedSender != null &&` wrapped around clauses 3-6 (or the whole condition) passed every row as originally authored while silently disabling tamper checks for sender-absent payloads → the clause-1 and clause-3 tag fixtures are now pinned sender-ABSENT (the clause-3 row cards under any hoist and reds); (2) **guard-the-throw escape** — keeping clause 6 firing but skipping only the throw (emit-FAIL-then-card) passed every row → TC-384-01/02 now assert ZERO `PUSH_ANDROID_DATA_DECRYPT_FAIL`; (3) **runner validator dispatch** — "runner needs ZERO edits" was refuted in source: the loop hard-codes the muted validator (`run_group_muted_notification_android.dart:302-308`) whose admission rejects a third id, so the campaign would red at runner-validation after a green capture → TC-384-07 now carries the dispatch edit (+ `--validate-artifact` mirror) and the runner joined the Affected files.
- Plan-fixes applied: the id-bound ERROR negative was unimplementable (`PUSH_BACKGROUND_NOTIFICATION_ERROR` details = `{'error': …}` only, source + archived log) → window-scoped zero-ERROR rule; SHOWN binding pinned contains-based (warm-up SHOWNs too post-fix; `single`/`last`/exact-count forbidden; the non-durable-branch id-presence rationale + durable-activation re-derive note recorded); extra-shape description corrected (~10 keys, full opts minus timestamp + messageId + publishedAtNano — fixture anchors widened); TC-384-02's media premise corrected (extra.media IS a List of attachment maps; typed media body; oversized-media relay strip note added); device closure commands routed through the env wrapper (`docker-ws/run_muted_campaign_383.sh` — a bare `run_with_devices.sh` from the container self-blocks on missing env); graded card wait hardened to marker-CONTAINS with baseline+warm-up in the stale set (bare body-change latches on the warm-up card); observation-kind enum deliberately NOT extended (zero consumers — over-engineering avoided); citation drifts fixed (`run_test_gates.sh:285,:824`; `bmh:3061`; foreground malformed row is nonce-gated pre-decrypt, not clause-1-shaped; `:490-542`/`:1480-1667` sentinel relabels; clause-4 wording "clause 1 or 2 fires first").
- Over-engineering review (explicitly requested): the contract survived with 8 rows; nothing was found removable without losing a proven obligation — the clause tag is what makes clauses individually mutation-detectable (2/5 were shadow-covered, 2 arms untested), TC-384-02 closes the media flavor at the only tier that can reach parity (relay strips oversized media to `preview_unavailable` on device), and the third scenario reuses the existing lane/fixture/wrapper with zero new files beyond its own validator. Deliberately NOT added: sibling reason decomposition, producer payload changes, a 384-named wrapper copy, a new observation-kind enum case, genuine-tamper card conversion.

## Execution Progress
| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-08-19 | Dependency | working tree | `git commit` -> `90bc7d601` | Plan 383's bmh fix committed with the 379/380/381/382/385 wave | device leg's non-durable fall-through now present at HEAD | author causal REDs |
| 2026-08-19 | TC-384-01/02/03 causal RED | `push_decrypt_preview_test.dart` (+287 lines) | 7 rows RED for the documented reasons | 01/02: `OrdinaryMessageNotificationIntegrityException(group_plaintext_parity_mismatch)` with `PUSH_ANDROID_DATA_DECRYPT_FAIL{reason: group_parity_mismatch}`; 03 x5: `clause` absent (`Expected 'inner_*' / Actual <null>`) — every clause fixture already THREW, confirming each targets an armed clause | root cause confirmed: the sender clause is the only armed one for the live-envelope shape | W1+W2 |
| 2026-08-19 | W1+W2 production edit | `push_decrypt_preview.dart` (only production file) | full preview suite `+42 All tests passed` | `_groupPlaintextParityClause` returns the first true clause; the sender clause gained `decodedSender != null`; `reason` byte-unchanged | Stop-if not triggered: no other clause fires for the TC-384-01 fixture | mutation walk |
| 2026-08-19 | Mutation walk (9) | same | every mutation caught | guard revert -> 01/02 red; tag removal -> all 5 clause rows red; delete clause 1/2/3/5/6 -> own row red (3 and 6 ALSO red the pre-existing 4-row tamper loop); **hoisted guard -> clause-3 row red**; **guard-the-throw -> 01/02 red** | both wrong-fix escapes the reviewer constructed are closed | graph-affected |
| 2026-08-19 | TC-384-04/08 + affected | foreground resolver, bmh, storage-deadline, announcement private-media | `+102 All tests passed` | `tdd_context.py affected` named 4 dependent test files; all green | sentinels hold | W4 |
| 2026-08-19 | W4 registration | criteria/dispatch/capture/runner/proof/contract-sh/critical_features + 2 byte-pins | criteria host suite `+62`; registry `+8`; both sh contracts PASS on host | third scenario `android_group_text_killed_app_card` with its own validator kind, artifact grammar and per-scenario runner dispatch; 7 validator-rule mutations each red exactly their own row | census grep is 1 not >=2 because the id list references the CONST, not a repeated literal — enrollment is pinned by an exact-list host row instead | lane |
| 2026-08-19 | `groups` lane | - | first run `+4378 -1` -> fixed -> re-run green | the one red was REAL and mine: DTR10-PAYLOAD-01 forbids the retired Dart type's identifier anywhere under `lib/`, and the new production comment named it | census gates that match by path string stay invisible to the graph — the lane is still the final word | device closure |
| 2026-08-19 | TC-384-05/06/07 device closure | `docker-ws/plan384_g19_device_evidence.txt` | `host-run bash docker-ws/run_muted_campaign_383.sh` -> `PASS groups.muted_notification_campaign assertions=6` | all 3 artifacts validated (capture-1787125915764845-93175). New scenario: both post-kill wakes `RECEIVED -> DECRYPT_OK -> DURABLE_EFFECT_DEFERRED -> SHOWN`, graded card body `Alice: Plan384Grad9d466ffff3` (roster username). Muted lane's warm-up group TEXT — the 3/3 G19 casualty from Plan 379 runs 13/14/15 — now cards. ZERO DECRYPT_FAIL and ZERO NOTIFICATION_ERROR in every post-kill window | G19 CLOSED at device tier; TC-384-06 confirmed by the same run | docs + memory |
| 2026-08-19 | W2 re-verify (G26) | send use case, replay envelope, `inbox.go`, `ack_custody.go`, `reaction_push.go` | source read end to end | strict lane returns before `callGroupSendReliable`; envelope has no `type`; `extractChatPushMetadata` default -> `ShouldNotify:false`; the direct-reaction extractor also requires `type` | G26 confirmed and BROADER than Wave 1 recorded — reactions are unpushed on this lane too | feasibility |
| 2026-08-19 | W2 feasibility | `addGroupEncryptedPushData`, bmh type routing, `inboxPayload`, `_strictPhysicalGroupRecipientPeerIds`, `register_token` | source read | the group push builder reads this shape unmodified; the client routes on `type` only; inner/outer ids agree; recipient ids share the push-token namespace | recipient needs NO change — the fix is relay-only | implement |
| 2026-08-19 | W5+W6+W7 | `group_content_push.go` (new), `inbox.go`, `main.go`, `metrics.go` | `go build` / `go vet` clean | branch placed BEFORE the chat switch; declines return rather than fall through | reactions deliberately declined (G27) | tests |
| 2026-08-19 | TC-384-09..16 | `group_content_push_test.go` (new) | `go test -run 'GroupContent\|StrictGroup'` green | 9 Go rows incl. two on the ack-custody path | TC-384-13 added after noticing TC-384-12 proved a path the traffic never takes | mutations |
| 2026-08-19 | W2 mutation walk (5) | same | every mutation caught | drop branch -> wake rows red on BOTH paths; reactions-eligible -> 2 red; ignore flag -> 1 red; drop custody check -> 1 red; drop routing-field guard -> 2 red | causality established | recipient half |
| 2026-08-19 | TC-384-17 | `push_decrypt_preview_test.dart` | `+44 All tests passed` | both rows green on FIRST run | confirms the no-client-change claim rather than driving a change | W2 gates |
| 2026-08-19 | W2 gates | two closure census gates | full relay suite green after declaring the new adapter; `flutter analyze` clean; `git diff --check` clean | the `groups` lane red is the pre-existing `group_conversation_wired_test.dart` voice flake — zero `lib/` files changed | landed as `37dd2eb20` | relay deploy + device leg (both OPEN) |
