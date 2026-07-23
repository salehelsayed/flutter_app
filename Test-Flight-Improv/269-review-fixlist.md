# 269 Review — Fix-List (apply against `269-group-media-end-to-end-reliability-tdd-plan.md`)

Source: 11-agent adversarial `/tdd-review` audit (5 source/domain verifiers + 5 dimension
assessors + completeness critic) plus orchestrator self-verification of every material
linchpin in current source, 2026-07-22, HEAD `7749e910a` (branch `new-orbit`).

Verdict: **NOT ready as written — apply §A0, §A, §B and §C before the first RED.** All fixes
are edits to the plan text; none require redesign.
The plan's causal spine is unusually solid (every cited root-cause line verified true, all
five load-bearing technical bets survived adversarial verification). What fails is *proof
integrity*: the counter fix **unmasks a silent full-row overwrite that all 20 rows would stay
green through** (§A0), three named proofs would silently never run, two production route-open
surfaces sit outside the contract, and the headline durability claim can be greened by an
in-process fault.

Dimension scorecard: D1 goal clarity 70 · D2 compartmentalization 50 (weak) · D3 anti-drift 70 ·
D4 define-good 68 · D5 tests-verify-the-goal 68.

## Decisions that need your sign-off (recommendations given; not defaulted silently)

- **D-1 — Posts media ACL lanes.** `attach_post_media_use_case.dart:89-92` (upload `:288`) and
  `pass_post_along_use_case.dart:544-548` (upload `:595-602`) build **relay group-mode ACLs
  from account peer IDs** — the exact identity-defect class Plan 269 exists to fix. Recommend:
  **defer explicitly** (name them in Deferred, narrow TC-269-08's universal wording — item B1),
  not fold in. Folding in widens the plan by a whole product surface.
- **D-2 — iOS closure if iPhone 11 is unavailable.** Recommend: a simulator substitution closes
  only the XCUITest-controller + native registry exact-once contract; the **real-suspension
  claim stays OPEN** and is recorded as a deferred device blocker (item C3). The alternative
  (accept simulator as full closure) silently downgrades the plan's `device` closure tier.
- **D-3 — Execution shape.** Recommend splitting into four named waves with their own
  RED→GREEN→gate→commit checkpoints and an early sender-only device smoke (§D). The
  alternative (execute as one 20-row unit) is what makes D2 score `weak`.

## Verified facts this list relies on (checked in source by the orchestrator, not just by agents)

- `sameExactGroupRetryAttachment` compares both nullable counters raw —
  `retry_incomplete_group_uploads_use_case.dart:931-932`. ✅
- `MediaAttachment.toMap()` omits null counters — `media_attachment.dart:200-201`; migrations
  042 (`:31`) and 089 (`:35`) declare both columns `NOT NULL DEFAULT 0` → save-with-null
  reloads as 0. ✅
- `dbCompleteGroupUploadRetry` writes every authority field verbatim, so an absent key becomes
  an explicit SQL `NULL` → `NOT NULL` failure — `media_attachments_db_helpers.dart:184-205,
  286-297`. Exactly the captured Pixel signature. ✅
- Foreground exits on the strict compare **before** upload — `group_conversation_wired.dart:2403`
  save → `:2407` re-read → `:2418-2424` return null → `:2439` upload. ✅
- Optimistic IDs (`:2783`) ≠ durable IDs (`:2265`); the lease claims only the optimistic set
  (`:2796-2799`). ✅
- `groupMediaAllowedPeersForMembers` emits **account** `member.peerId` —
  `group_media_allowed_peers.dart:4-15`; `GroupMemberDeviceIdentity.transportPeerId`,
  `activeDevices`, `activeDevicesWithLegacyFallback()` already exist —
  `group_member.dart:79-101, 385-386, 404-416`. ✅
- Relay authorizes the authenticated transport peer against the stored ACL —
  `go-relay-server/media.go:522-534`; upload stores `req.AllowedPeers` verbatim (`:492`);
  `MediaStore.store()` replaces meta only on sender re-upload (`:137-151`) → the plan's
  refutation of receiver-only ACL convergence is **correct**. ✅
- Empty ACL is dropped by three `omitempty` layers (Dart `p2p_bridge_client.dart:1111-1112`;
  go-mknoon `node/media.go:26`; relay `media.go:364`) → an empty group ACL becomes a **direct**
  upload addressed to the group ID. Client-side reject-before-side-effects is the only sound
  contract. ✅
- `.heif → image/heic` is not merely acceptable, it is **required**: `GroupMediaMimePolicy`
  allows `image/heic` only and maps `mif1`/`msf1` brands to the heic signature —
  `group_media_mime_policy.dart:15-27, 204-211, 246`. `image/heif` would be rejected. ✅
- Share coordinator builds ACLs from `member.peerId` directly —
  `share_batch_delivery_coordinator.dart:1366-1370`; group-info resurrects an account-ID
  fallback — `group_info_wired.dart:1796-1798`; raw avatar upload has no empty-ACL guard —
  `group_avatar_storage.dart:84-136`. ✅
- `.heif` absent from `_mimeFromPath` — `group_conversation_wired.dart:7294-7311`. ✅
- Native `bgEnd` re-ends a raw ID unconditionally after the expiration handler already ended it
  — `ios/Runner/GoBridge.swift:235-241` vs `:260-273`. ✅

# §A0 — The defect this plan unmasks (highest severity; no plan row would catch it)

- **A0. Completion overwrites `created_at` (and nulls `thumbnail_hash`) from the upload result —
  widen Step 2 from "counters" to "every authority field the upload does not own."**

  Verified chain, all in current source:
  - `dbCompleteGroupUploadRetry` builds its UPDATE from **every** authority field, excluding only
    `id` / `message_id` / `owner_lane` — `media_attachments_db_helpers.dart:286-290`. The field
    list includes `created_at` (`:196`) and `thumbnail_hash` (`:201`).
  - `MediaAttachment.toMap()` emits `'created_at'` and `'thumbnail_hash'` **unconditionally**
    (`media_attachment.dart:198`, `:203`) — only the two counters are `if-null-skip`.
  - `UploadMediaSucceeded` sets `createdAt: now` (`upload_media_use_case.dart:797`) and never
    sets `thumbnailHash`.
  - **No** completion builder restores either field: retry
    `retry_incomplete_group_uploads_use_case.dart:1068-1075`; foreground
    `group_conversation_wired.dart:2671-2684`, `:2693-2706`, `:2717-2734`; voice `:5397-5409`,
    `:5428-5442`. Every one of them `copyWith`s id/messageId/size/mediaType/localPath/status/
    `uploadRetryCount`/contentHash and stops there.

  Today this is invisible because ordinary group completion never succeeds — it throws on the
  `NULL` counter. **The moment §A0's sibling fix (the counter merge) lands, completion succeeds
  and this write goes live**, silently replacing the persisted `created_at` with the upload
  timestamp on every completed group attachment.

  Why it bites: `sameExactGroupRetryAttachment` compares `createdAt`
  (`retry_incomplete_group_uploads_use_case.dart:929`), so a later exact-authority comparison
  against a stale expected attachment now mismatches and silently no-ops; and the plan's own
  TC-269-13 durable query pages by `(created_at, id)`, so cursor ordering shifts under it.
  `thumbnail_hash` is separately populated for group media
  (`send_group_message_use_case.dart:845`), so the completion write nulls a real integrity
  anchor even if a later publish-time save happens to restore it.

  **The edits:**
  1. Step 2: change "merge missing local-only **counter** fields from the exact expected
     attachment before the SQL update" to "merge **every authority field the upload result does
     not own** — `created_at`, `thumbnail_hash`, both counters, and any other locally
     authoritative column — from the exact expected attachment before the SQL update."
  2. TC-269-04 GREEN: replace "raw row is `done`, both raw counters are `0`" with a **full-row
     equality assertion** — the post-completion raw row equals the pre-completion raw row on
     every column in `_groupUploadAttachmentAuthorityFields` except the ones completion
     legitimately owns (`download_status`, `local_path`, `content_hash`, `encryption_*`).
  3. TC-269-04 mutation: add "take `created_at` or `thumbnail_hash` from the upload result
     instead of the expected attachment → this test red."
  4. Repeat the full-row assertion on TC-269-05 (retry-success leg), TC-269-02 (ordinary
     foreground) and TC-269-03 (voice), so all three completion builders are covered.

  *Why this ranks first:* it is the one finding where the plan executes exactly as written, every
  one of its 20 rows goes green, and production data is quietly corrupted.

# §A — Proof integrity: three named proofs would silently never run

- **A1. Fix the false "already registered" claims in TC-269-08.**
  `test/features/groups/integration/group_media_fanout_test.dart` appears **only** in
  `OPTIONAL_MANUAL_TESTS` (`scripts/run_test_gates.sh:657`), which no default gate runs;
  `test/features/groups/presentation/contact_picker_wired_test.dart` appears **nowhere** in
  `run_test_gates.sh` (GROUP_TESTS spans `:348-611`). Change TC-269-08's Gate/registration cell
  from "share/fanout/group-info/contact-picker already registered" to "share (`:516`),
  group-info (`:368`) already registered; **add** `group_media_fanout_test.dart` and
  `contact_picker_wired_test.dart` to `GROUP_TESTS`". *Why:* both files carry new P269 ACL
  sentinels; as written they would run once from the focused command at execution time and
  then never again from `./scripts/run_test_gates.sh groups`.

- **A2. Add an explicit registration-verification gate to Acceptance Gates.**
  `completeness-check` provably **cannot** detect a missing `GROUP_TESTS` registration —
  `classify_path` ends in a feature-local fallback glob, so every gate exits 0 regardless
  (project-memory verified, `group-tests-registration-unenforced`). Add before the curated
  family gates:
  ```bash
  for f in retry_incomplete_group_downloads_use_case_test.dart \
           group_media_reliability_criteria_test.dart \
           group_media_reliability_wiring_test.dart \
           group_message_listener_media_background_task_test.dart \
           handle_app_resumed_group_download_recovery_test.dart \
           pending_message_retrier_group_download_recovery_test.dart \
           group_media_allowed_peers_test.dart group_avatar_storage_test.dart \
           group_media_fanout_test.dart contact_picker_wired_test.dart \
           download_media_use_case_test.dart upload_media_use_case_test.dart; do
    grep -q "GROUP_TESTS\|$f" /dev/null; awk -v f="$f" 'NR>=348 && NR<=700 && index($0,f){hit=1} END{exit !hit}' scripts/run_test_gates.sh \
      || { echo "UNREGISTERED IN GROUP_TESTS: $f"; exit 1; }
  done
  ```
  (Adjust the line range if the array moves; the point is a literal in-array assertion, not
  `completeness-check`.) Also reword the Done-criteria checkbox at plan `:847-849` to cite this
  command instead of `completeness-check`. *Why:* every one of the plan's ~8 promised
  registrations is currently unenforced, and the checkbox gets ticked by inference.

- **A3. Resolve the TC-269-11 ↔ TC-269-04/13 contradiction.**
  `media_attachment_repository_impl_test.dart` is **already** in `GROUP_TESTS`
  (`scripts/run_test_gates.sh:433`), as TC-269-04/13 correctly state. TC-269-11's "add both
  existing conversation files to `GROUP_TESTS`" is wrong for that file and, followed literally,
  adds a duplicate array entry (the suite then runs twice per groups gate). Change TC-269-11 to:
  "add `download_media_use_case_test.dart` (today only in `ONE_TO_ONE_TESTS:63`) to
  `GROUP_TESTS`; `media_attachment_repository_impl_test.dart` is already registered at `:433` —
  do not re-add. Retain both in `ONE_TO_ONE_TESTS`."

# §B — Sibling surfaces the contract does not cover

- **B1. Give the posts media lanes an explicit disposition (see decision D-1).**
  Add under *Deferred / accepted difference*: "Posts media ACLs — `attach_post_media_use_case.dart:89-92`
  (upload `:288`) and `pass_post_along_use_case.dart:544-548` (upload `:595-602`) — build relay
  **group-mode** ACLs (`len(AllowedPeers)>0`, `go-relay-server/media.go:523`) from **account**
  peer IDs and bypass the `uploadMedia` wrapper via raw `callP2PMediaUpload`. They carry the same
  account-vs-transport defect class this plan fixes for group conversations; they are out of
  scope and owned by a named follow-up. Empty-ACL downgrade is unreachable in both lanes (the
  author/passer ID is always present)." Then narrow TC-269-08's behavior cell from "Every
  group-media sender" to "Every **group-conversation** media sender (foreground, voice, retry,
  share/forward, avatar)", and soften the Risks line at `:581` ("pin every caller") the same way.
  *Why:* a universal claim that is false is worse than a scoped one — it invites an executor to
  believe the bypass class is closed.

- **B2. Add the two missing `GroupConversationWired` construction sites to TC-269-15.**
  There are **six** construction sites, not the five slices the plan names (and "main" and
  "notification" are the *same* site): `lib/main.dart:5956`,
  `group_list_wired.dart:334`, `create_group_picker_wired.dart:225`,
  **`orbit_wired.dart:3686`** (auto-open after invite accept), **`feed_wired.dart:1891`**
  (feed group-thread open), plus the constructor itself `group_conversation_wired.dart:362`.
  Add `orbit_wired.dart` and `feed_wired.dart` to TC-269-15's parsed slice set **and** to the
  Affected-files list (`:176-198`). *Why:* as written the wiring test passes while
  orbit-opened and feed-opened conversations have no shared download coordinator — precisely
  the route-open bypass class TC-269-15 exists to close.

- **B3. Add the fifth dedupe exit to TC-269-12 and Step 7.**
  The plan enumerates four exits; there is a fifth: **content-based dedupe** at
  `handle_incoming_group_message_use_case.dart:707-736` (`dedupeBy: 'content'`, fires when the
  wire message carries no `messageId`), which returns `null` with **no** best-effort attachment
  save at all — so the plan's HEAD description "all exits return null after best-effort save"
  is false for it. Either (a) thread the detailed outcome through it too, or (b) state
  explicitly that it is ignored **and why** (no wire `messageId` ⇒ no canonical row to enrich),
  and pin that with an assertion in the TC-269-12 table test. Change Step 7's "all four dedupe
  exits" to "all five dedupe exits (`:190`, `:598`, `:639`, `:693`, `:735`)".

- **B4. Note the shared blast radius of the Swift critical-task registry.**
  `callBgBegin`/`callBgEnd` have production callers beyond `handle_app_paused` and group send:
  `feed_wired.dart:2119`, `:2186`, `share_batch_delivery_coordinator.dart:1313`,
  `conversation_wired.dart:3678`, `:5032`. Add to Step 10 and TC-269-17: the registry changes
  double-end exposure for **all** `bgBegin` callers, so the native suite must include one
  preservation case proving an ordinary begin/end pair from a non-group caller still balances,
  and these files belong in the Affected-files list as preservation-only surfaces.

- **B5. Name the two other production callers of the API Step 7 changes.**
  `handleIncomingGroupMessage` is called not only by the listener
  (`group_message_listener.dart:1171`) but also by `drain_group_offline_inbox_use_case.dart:850`
  and `:1790`, and by `group_pending_key_repair_service.dart:923`. The plan mentions the drain
  only as a lifecycle *ordering* constraint and never mentions key repair at all. Since only the
  listener consumes the new detailed outcome, media enriched during offline drain or key repair
  depends entirely on a later periodic/resume sweep that no named test exercises from those
  entry points. Add one Scope Contract sentence ("drain and key repair keep the nullable wrapper
  and rely on the durable recovery sweep") and seed one TC-269-14 (or TC-269-15 resume) case
  from a drain-persisted enriched row, so the dependency is pinned rather than assumed.

- **B6. Make the wiring test enumerate construction sites instead of asserting a fixed list.**
  Stronger than B2 alone: have `group_media_reliability_wiring_test.dart` grep for every
  `GroupConversationWired(` construction in `lib/**` and fail if any lacks the coordinator
  argument. A fixed slice list goes stale the next time someone adds a route; an enumeration
  cannot.

# §C — Device-proof integrity (host-green is not closure here)

- **C1. Pin TC-269-19's interruption to a real process kill.**
  The row says "interrupted after durable `downloading` claim but before commit" but never says
  *how*. An executor can satisfy it with an in-process thrown exception, which greens the
  plan's headline durability claim (interrupted `downloading` rows recover after **process
  death** without reopening the conversation) without ever proving it. Amend TC-269-19 + its
  Test Note: the named JPEG interruption **must** be a real receiver process kill
  (`adb shell am force-stop <harness package>` triggered when the harness observes the named
  post-claim/pre-commit flow event or barrier file), followed by relaunch **without opening the
  group**; the artifact must show the row read back as `downloading` before recovery and the
  second attempt occurring after relaunch. Name the barrier/flow-event seam and state that it
  must already exist in the `android.e2e.main` profile, so the zero-child-build constraint holds.

- **C2. Make TC-269-20 phase B discriminate the terminal path.**
  "observes native expiry **or** process interruption" lets a run where the process simply dies
  pass the row that exists to prove the expiry-then-late-`bgEnd` double-end path
  (`GoBridge.swift:235-241` vs `:260-273`). Require the artifact to record the **discriminated**
  terminal path (`expired` | `interrupted` | `normal`), require at least one phase-B run to
  observe the **expiry** branch specifically (barrier holds the transfer past the grant window
  after the Home press), and pin the iOS barrier mechanism (launch-environment flag or staged
  relay condition readable by the prepared `ios.device.production` bundle) in the Device/Relay
  Proof Profile.

- **C3. State what a simulator substitution forfeits (see decision D-2).**
  Add to *Deferred / accepted difference* and *Closure role*: "A simulator substitution closes
  only the XCUITest-controller and native registry exact-once contract; the real-suspension /
  expiration claim of TC-269-20 then remains **OPEN** and is recorded as a deferred device
  blocker, not marked closed." *Why:* the plan's closure tier is `device` and the boundary being
  proven is real `UIApplication` background-task behaviour.

- **C4. Pin the TC-269-18 artifact schema so the criteria test cannot be circular.**
  Today both the runner's artifact and the criteria test that validates it are authored by the
  same executor, so "cannot false-green" is defined against whatever the runner chose to emit.
  In the TC-269-18 Test Note, enumerate the minimal literal top-level keys the criteria test must
  assert: `uploads_per_blob`, `publications_per_message`, `download_attempts` (keyed by kind:
  `jpeg=2`, `mp4=1`, `voice=1`), `second_pass_uploads=0`, `second_pass_downloads=0`,
  `cipher_version` (non-empty), `user_version=104`, `role_db_path`, `acl_entries`
  (transport IDs), `account_vs_transport_discriminator`.

- **C5. Add the relay delete-ack as a receiver-transport discriminator.**
  The stored ACL also authorizes **deletion**: `handleMediaDelete` runs the identical
  `containsPeer(meta.AllowedPeers, remotePeer)` check (`go-relay-server/media.go:580-583`), and
  the receiver issues that ack after its durable commit
  (`download_media_use_case.dart:1225`, `MEDIA_ACK_DELETE_FAILED` on refusal). A wrong ACL
  therefore also leaves blobs on the relay until TTL. Add to TC-269-19's criteria: the delete-ack
  is authorized (no `MEDIA_ACK_DELETE_FAILED`; blob absent from the relay afterwards). *Why:* it
  is a second, independent proof that the ACL carries the receiver's real transport identity —
  cheap, and it fails loudly if the identity fix regresses.

- **C6. State that Android's background-task bridge is a hard no-op — iOS is the *only* proof.**
  `android/app/src/main/kotlin/com/mknoon/app/GoBridge.kt:177-178` returns `""` for `bgBegin`
  and `null` for `bgEnd`, and `callBgBegin` (`bridge.dart:781-789`) treats the empty string as
  failure and returns `null`. So on Android the receive-side critical task is **permanently the
  refusal branch**: the required Android row TC-269-19 structurally cannot exercise any granted /
  expiry path. Add to the Scope Contract: "`callBgBegin`/`callBgEnd` are Android no-ops
  (`GoBridge.kt:177-178`), so the receive critical task is iOS-only and Android runs the refusal
  branch by construction; TC-269-19 proves durable recovery, TC-269-20 proves the task boundary."
  *This sharpens decision D-2:* with Android structurally unable to cover it, a simulator
  substitution for TC-269-20 would leave the critical-task change with **no** real-hardware proof
  at all.

- **C7. Say how the device scenarios trigger the "second periodic pass".**
  TC-269-19 requires a zero-work second pass and TC-269-06 requires four passes, but the
  production interval is `PendingMessageRetrier.defaultPeriodicRetryInterval = 5 min`
  (`pending_message_retrier.dart:34`) and the group upload retrier now early-exits without OS
  connectivity (`retry_incomplete_group_uploads_use_case.dart:66`, `:100-107`). Pin the
  mechanism — wait out the real interval, drive an explicit harness-invoked pass, or inject a
  shortened interval — and state which, so "second pass did zero work" is a measured fact rather
  than an assumption about wall-clock timing.

# §D — Execution shape (the weak dimension)

- **D1. Order the causal RED for every row, not only TC-269-01..06.**
  Steps 5-10 contain no test-authoring instruction; the tests for TC-269-07..17 (lease, ACL,
  empty-ACL, HEIF, receiver CAS, duplicate outcome, paging, recovery, coordinator wiring,
  policy, iOS background task) are batched into step 11 **after** those production edits.
  Rewrite each of steps 5-10 to begin: "Author the row's P269 test(s) named in TC-269-XX, run
  the focused command, record the causal RED, **then** edit production and re-run to GREEN."
  Reduce step 11 to registration only (GROUP_TESTS, manifest, discovery, selector).

- **D2. Name four waves with their own checkpoints (see decision D-3).**
  W1 sender persistence (steps 1-4 · TC-01..07, 10) · W2 ACL fail-closed (step 5 · TC-08/09) ·
  W3 receiver recovery (steps 6-9 · TC-11..16) · W4 iOS + harness + device (steps 10-12 ·
  TC-17..20). Each wave ends: commit, record a row in Execution Progress with an explicit
  GO/STOP decision, run the wave gate. *Why:* the riskiest slices (relay-facing ACL identity
  change, process-wide coordinator wiring, native Swift registry) currently share one review
  boundary with a one-line comparator tweak and a `.heif` map entry.

- **D3. Pull the payoff forward with a sender-only device smoke.**
  The only *captured, confirmed* incident is the sender counter/completion failure, yet its
  device payoff is not observable until step 12 / TC-269-19 — gated behind receiver recovery,
  iOS work and the full two-role harness, none of which the sender fix depends on. Insert step
  **4b**: a scripted sender-only run on Pixel `21071FDF600CSC` against the real relay (send
  JPEG + MP4; assert one publication each, rows `done` with both counters 0, and **zero**
  uploads on the next periodic pass — the exact captured-failure discriminator), marked GO/STOP
  before receiver work starts.

- **D4. Add per-wave gate commands.**
  Every gate currently lives in the single terminal Acceptance Gates block. Add inline: after
  step 4 → `./scripts/run_test_gates.sh groups` + the exact Go relay sentinel command; after
  step 5 → the Go sentinels again plus the five ACL focused commands; after step 9 →
  `groups` + `core-host-all`. Label each "GO/STOP: do not proceed on red".

# §E — Under-pinned seams (an executor must improvise these today)

- **E1. Commit the empty-ACL failure type.** Replace "typed terminal validation **such as**
  `EMPTY_GROUP_MEDIA_ACL`" (`:256`) with a committed declaration: the exact identifier, its
  kind (a terminal member of the existing upload-validation classification in
  `upload_media_use_case.dart` — never `MEDIA_ERROR`-wrapped, which already wraps permanent
  rejections, and never a new DB status), its declaring file, and the statement that all three
  guard sites (composer preflight, `uploadMedia` leaf, raw avatar lane) surface the same value.
  Four named tests assert this string; it must be one value.

- **E2. Pin the detailed incoming-outcome API.** TC-269-12/Step 7 specify semantics but no type
  name, method, shape or file. Pin e.g. `IncomingGroupMessageDetailedOutcome` with cases
  `newlyStored(message)` / `duplicateEnriched(message, persistedAttachmentIds)` / `ignored`,
  declared beside the nullable wrapper in `handle_incoming_group_message_use_case.dart`.

- **E3. Pin the Swift registry API.** Step 10 names no class/protocol, no injection seam into
  `GoBridge.swift`, no observable marker. Pin e.g. a `CriticalTaskRegistry` protocol
  (default `UIApplication`-backed, injected via a settable static or init parameter) whose
  `begin` returns the raw ID it registers and whose `end`/`expire` atomically remove-and-end,
  exposing a test-visible ended-ID list — otherwise
  `GoBridgeCriticalTaskTests::test_expirationThenLateDartEndEndsNativeTaskExactlyOnce`
  cannot be written against a stable seam.

- **E4. Constrain the TC-269-02/03 SQL-defaulting wrapper.** Its contract is only "omitted
  counters reload as zero". Add: it must also **reject** an explicit-null counter on update the
  way `NOT NULL` does (otherwise the widget test greens a completion leg the real DB rejects),
  plus one differential fidelity assertion — the same save/reload and the same null-counter
  update through both the wrapper and `MediaRepositoryRealDbFixture` must yield identical
  observable outcomes. *Why:* the wrapper is a fake standing in for migrations 042/089; without
  a differential check its drift is invisible.

- **E5. Say plainly that TC-269-14's "after restart" is simulated.** Add one sentence: host
  "restart" means a fresh use-case/coordinator instance over durable rows and does **not**
  prove process-death durability, which closes only via TC-269-19's kill/relaunch leg (C1) and
  TC-269-20 phase B.

- **E6. Archive the baseline.** The captured Pixel evidence (the literal
  `NOT NULL constraint failed: media_attachments.download_retry_count` line and the two
  `ok:true` relay upload responses) exists only as prose in the Planning Progress table. Pin the
  artifact directory / log path where it is stored, or instruct the executor to archive that
  excerpt under the plan's artifact directory **before** the first production edit.

# §F — Corrections, and favourable facts the plan should record

- **F1. Step 5 names a non-existent "fanout" ACL construction site.** The helper's real callers
  are `retry_incomplete_group_uploads_use_case.dart:1007, :1018`,
  `group_conversation_wired.dart:2357, :2368, :2861`, `group_info_wired.dart:1798`,
  `contact_picker_wired.dart:262`, and `send_group_message_use_case.dart:1123` — the last is a
  *symmetric equality re-check* on both sides of a comparison and needs no change. Drop
  "fanout" from Step 5's call-site list (the fanout **proof** stays; it exercises the composer
  lane).
- **F2. The connectivity gate has landed — fixtures must account for it.**
  `retry_incomplete_group_uploads_use_case.dart:66, :100-107` (`requireOsConnectivity` +
  `RETRY_INCOMPLETE_GROUP_UPLOADS_SKIPPED_NO_CONNECTIVITY`), passed `true` from six `main.dart`
  sites (`:4336, :4378, :4452, :4492, :6584, :6615`). Add a Test Note: TC-269-05/06's
  "periodic pass" fixtures must satisfy the probe (or leave it defaulted off), or the passes
  short-circuit before the bounded sequence they are asserting.
- **F3. Sweeper interplay is already safe — record it so nobody "fixes" it.**
  `dbTransitionGroupSendingToFailed` already excludes parents holding an `upload_pending` group
  attachment in **both** SQL branches (`group_messages_db_helpers.dart:1217-1226`, applied at
  `:1234` and `:1246`), and the upload-retry selection accepts `failed` parents. So the three
  `sending`-status sweepers cannot strand TC-269-06's multi-pass bounded sequence. Add a Test
  Note stating this (with the file:line) and add one swept-parent case to TC-269-06 pinning
  "swept-to-failed parent ⇒ lost authority ⇒ project zero, mutate nothing". *Why:* without the
  note an executor is likely to add a redundant second exclusion.
- **F4. Extend the accepted-difference to devices admitted *after* upload.** The plan covers
  historical blobs with old ACL metadata, but the same immutability
  (`go-relay-server/media.go:137-151` stores the ACL at upload) means a device admitted **after**
  an upload can never download that blob, and `not authorized` is terminal by design. Name the
  user-facing surface for that case so it is a decision, not a surprise.
- **F6. Make the stranded-blob population countable.** The plan defers historical blobs with
  account-ID ACL metadata, and TC-269-11 makes `not authorized` permanently terminal — but adds
  no way to *size* that population. Same for its forward twin (F4). Add to the TC-269-11 work: a
  named flow event carrying a distinguishable reason on legacy-ACL denial, plus one host case
  asserting the denial is terminal and consumes zero budget. Without it, nobody can tell from
  logs how many users are affected or when the population stops growing.
- **F7. Fill the three Must-preserve rows that have no named sentinel.** Most preserve-claims map
  to sentinels that exist verbatim on HEAD, but three do not: incoming group
  private/view-once/disappearing exclusion from automatic recovery, "unrelated direct/group/
  private artifacts are never deleted", and announcement reader/admin authorization. Point each
  at an existing exact test name or add one — an unguarded "stays unchanged" claim is exactly
  where a regression hides.
- **F8. Record the execution scale in the plan (feeds decision D-3).** The edits land in
  `group_conversation_wired_test.dart` (18,097 lines, +7 P269 tests) and
  `group_message_listener_test.dart` (17,028 lines, +3), with production edits in
  `group_conversation_wired.dart` (7,858) and `main.dart` (7,066), plus 8 brand-new test files, a
  greenfield two-role device harness, a Swift registry and an XCUITest controller. Stating this
  in the plan is what makes the four-wave split obviously necessary rather than optional.
- **F9. Nit — `bgBegin` citation.** `group_conversation_wired.dart:627-650` is the *helper
  definition*; the actual wrap sites are begin `:2851` / end `:3163` (ordinary media), begin
  `:3383` / end `:3418` (text), begin `:5158` / end `:5346` (voice). Cite the wrap sites.

# What the plan does well (keep these)

- **The causal chain is real and end-to-end verified.** Every root-cause line cited — null-vs-0
  comparison, the SQL `NULL` completion write, unstable durable IDs, account-ID ACLs, the
  empty-ACL direct-mode downgrade, the missing `.heif` mapping, the blind native `bgEnd` — is
  true in current source. Precise-and-*right* line numbers are rarer than they should be.
- **Its self-refutation is correct and load-bearing.** "A receiver-only retry cannot converge an
  already-stored relay ACL" is exactly right (`media.go:137-151` + `:522-534`), and removing that
  hypothesis is what keeps `not authorized` honestly terminal.
- **All five technical bets survive.** `.heif → image/heic` is not just safe but *required* by
  `GroupMediaMimePolicy`; rejecting empty ACLs client-side is the only sound option given three
  `omitempty` layers; the SQLite mechanism is confirmed by the device incident itself; the Swift
  registry is justified because only native code observes expiration; orphaned `downloading`
  rows really are re-claimable.
- **The infrastructure it promises exists.** Every `run_test_gates.sh` subcommand, every existing
  sentinel name, the sims capability schema fields, the `SIMS_ARTIFACT_*` conventions, and even
  TC-269-19's hard part — a fresh account whose account ID differs from its transport ID
  (`integration_test/group_multi_device_real_harness.dart:427, :854, :3012`) — are real.
- **Honest scope discipline:** no migration, no relay weakening, an explicit Unresolved block
  that forbids promoting hypotheses without a causal RED, and a hard Do-not list that names the
  dirty-tree files to preserve.

## Evergreen blind-spot sweep

| Class | Status | Evidence | Fix |
|---|---|---|---|
| B-1 one-way change / rollback brick | **clear (data) / note (residue)** | No schema, migration, status or wire change (DB stays v104; both counter columns already `NOT NULL DEFAULT 0`). The ACL identity change is client-side only and backward-compatible: legacy single-device members have `transportPeerId == account peerId` (`group_member.dart:388-402`), so an older-build receiver still authorizes. A rollback merely restores the old bug, it strands nothing. The residue worth recording: blobs already published with account-ID ACLs stay permanently denied, and the plan adds no way to count that population. | F4, F6 (record the reasoning in the plan so it is not re-litigated) |
| B-2 undercounted callers / sibling open-sites | **HIT ×3** | Posts lanes build group-mode ACLs from account IDs (`attach_post_media_use_case.dart:89-92`, `pass_post_along_use_case.dart:544-548`); `GroupConversationWired` has 6 construction sites, 2 unnamed (`orbit_wired.dart:3686`, `feed_wired.dart:1891`); a 5th dedupe exit exists (`handle_incoming_group_message_use_case.dart:707-736`). Also 6 unlisted `callBgBegin` callers. | B1, B2, B3, B4 |
| B-3 off-target line numbers | **clear** | Every cited edit target was read and does what the plan says (see Verified facts). One imprecision only: the `bgBegin` citation is the helper definition, not the wrap sites. | F9 |
| B-4 un-verifiable goal gate | **HIT** | Registration is claimed by `completeness-check`, which provably cannot detect a missing `GROUP_TESTS` entry; two files claimed "already registered" are not; the TC-269-18 artifact schema is validated by a test written against the same executor's output. | A1, A2, A3, C4 |
| B-5 atomicity / derived-state preservation | **HIT (the sharpest one)** | No migration exists, but the *derived-state* half is live: completion writes `created_at` and `thumbnail_hash` from the upload result (`media_attachments_db_helpers.dart:286-290` over the list at `:196`, `:201`; `media_attachment.dart:198`, `:203`; `upload_media_use_case.dart:797`), and no completion builder restores them. The plan's counter fix is exactly what makes this write start succeeding. Separately, the receiver-write atomicity concern *is* correctly identified and fixed with a journal-aware CAS modelled on the sound success CAS (`:2530-2597`) — note the ordinary lane has **no** existing failure CAS to reuse (private lanes only, `:1389`, `:1547`). | **A0** |
| B-6 durable-marker survival across restart | **HIT (partial)** | No new flag is introduced, but the durability claim itself ("interrupted `downloading` converges after restart") is proven host-side by a fresh use-case instance, and the device row never mandates a real process kill. | C1, E5 |
| B-7 plan's own #1 risk, domain-verified | **clear — good news** | All five bets survive: `.heif→image/heic` is *required* by `GroupMediaMimePolicy:15-27, 204-211, 246`; empty-ACL client rejection is the only sound option (three `omitempty` layers); SQLite mechanism confirmed by the incident itself; the Swift registry is justified because only native code observes expiration (Apple: the handler must end synchronously or the watchdog fires); orphaned `downloading` rows are re-claimable (`kMediaDownloadClaimableStatuses:2522-2528`). | — |
| B-8 PROD-CRITICAL leg proven only host-green / manually | **HIT** | TC-269-19's interruption mechanism is unspecified (an in-process throw satisfies the text); TC-269-20 phase B accepts expiry **or** interruption without recording which occurred. | C1, C2 |
| B-9 "stays unchanged" = untested assumption | **mostly clear** | The Must-preserve list maps every claim to a named sentinel, and all sentinel names exist verbatim in source. Two unguarded assertions: "share/forward and avatar bypass tests pin every caller" (posts lanes are not pinned) and the shared `bgBegin` callers. | B1, B4 |
| B-10 cross-platform parity asserted, not run | **HIT (mechanism divergence)** | Parity is genuinely *run* — separate Android and iOS pairs with literal commands and a real `RunnerUITests` target. But the per-platform mechanism divergence is never treated as first-class: `GoBridge.kt:177-178` makes `bgBegin`/`bgEnd` Android no-ops, so the required Android row structurally cannot exercise the new critical task at all. | C6, C3 |

## Priority order to apply

1. **§A0** — the only finding where the plan executes perfectly, all 20 rows go green, and
   production data is silently corrupted. Fix before anything else.
2. **§A (A1–A3)** — without these, three named proofs never run and the registration checkbox is
   un-provable. Pure plan-text edits.
3. **§B (B1–B6)** — close or explicitly scope out the remaining bypass surfaces; B2, B3 and B5
   are production paths the current contract would leave green.
4. **§C (C1–C7)** — make the device legs prove what they claim (real process kill, discriminated
   expiry, non-circular artifact schema, delete-ack discriminator, Android no-op stated, second
   pass triggered deliberately).
5. **§D (D1–D4)** — restructure into waves with early payoff before starting execution.
6. **§E, §F** — pin the improvisable seams; record the corrections, the favourable facts, and the
   observability gaps.

## Audit provenance

11 agents: 5 source verifiers (sender/persistence · ACL & sibling sweep · receiver/lifecycle/iOS ·
gates & harness · domain bets incl. WebSearch on Apple background-task semantics), 5 dimension
assessors, 1 completeness critic running the B-1..B-10 sweep. Every material finding above had
its linchpin re-read in source by the orchestrator before being written down; findings that
could not be confirmed that way are not in this list. The plan's own Handoff claim that an
independent `$tdd-review` completed with verdict `ready` and "no further review prerequisite
remains" (plan `:900-902`) is refuted by this audit.
