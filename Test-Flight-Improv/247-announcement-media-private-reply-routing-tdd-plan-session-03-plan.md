# Plan 247 Session 03 — Wire Message Sender Through Bubble, Viewer, And App Owners

Status: accepted

Source: `Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan-session-breakdown.md` Session 03

## Planning Progress

- 2026-07-11 — Refreshed after Plan 234 Session 05 closed. Read `AGENTS.md`, the Graphify skill, Plan 247's accepted decision/source/breakdown and accepted Session-02 closure, the accepted Plan-234 Session-05 Execution Result/QA/Closure Audit, current group/viewer/entry-owner source, tests, gate arrays, and the live dirty-tree status. Plan 234 has released the shared-viewer serialization guard; Sessions 01-02 remain accepted and are not reopened.
- 2026-07-11 — Anchored Graphify TDD query (`confidence=anchored`) identified `GroupConversationScreen`, `GroupConversationWired`, `MediaViewerItem`, `FullScreenTypedMediaViewer`, Feed/Orbit/group entry owners, and direct proof candidates. Targeted source verification found exactly five `GroupConversationWired(` production construction sites and confirmed that `MediaViewerAction.messageSender`, the context action, typed opener, and all three Session-03 tests are absent.
- 2026-07-11 — Planner froze the callback-only action, exact localized copy, double-tap and dismissal order, fresh Session-02 resolver use, blank/no-send direct route, the five-site complete/null opener census, Plan-234 privacy preservation, RED/GREEN/mutation proof, literal gates, and dirty-scope attribution below.
- 2026-07-11 — Independent Plan Reviewer rejected the first draft on five concrete blockers. The contract now (1) owns narrow fail-closed enum handling in all three pre-existing exhaustive consumers, (2) tests exact current attachment/page within the existing same-parent viewer rather than inventing cross-parent navigation, (3) preserves the selection-time two-field request so sender drift denies, (4) scopes no-delivery source checks to Plan-247-added hunks while preserving accepted Plan-236/group seams, and (5) seeds the required eligible group source while keeping direct history empty. No test or production edit occurred before these corrections.
- 2026-07-11 — Independent re-review accepted the corrected contract. The reviewer independently recomputed the normalized 32-path scoped manifest as `d5959aafe10aae9c55ad527c6e5f535e2bd7bac488e55a36ef2f03404f43dacd` and found B1-B5/R1-R2 fully resolved with no remaining blocker. Session 03 is execution-ready.

## Dependency State And Owned Outcome

- Plan 247 Sessions 01-02 are accepted. Preserve Session 02's exact two-field `AnnouncementPrivateReplyRequest`, private success mint, fail-closed `AnnouncementPrivateReplyResolver`, canonical IDs, truthful tombstone authority, and accepted focused result **6/6**.
- Plan 234 Session 05 is accepted and closed. Its dedicated private route, `privacyMinimized` typed-viewer behavior, native protection, current-parent decisions, first-frame lifecycle, action denial, and tests are immutable preservation boundaries here. Session 03 adds one ordinary group callback action; it does not modify private-media protection or route private/terminal content into an ordinary viewer.
- The owned result is one deliberate, local **Message sender** navigation from a currently eligible incoming announcement image/video row to the sender's existing fully wired direct conversation. The direct composer is blank with respect to this source. Merely opening or cancelling sends, uploads, forwards, copies, serializes, downloads, or mutates nothing.
- Session 04 remains acceptance-only and prerequisite-blocked until this session has an accepted Execution Result, independent QA, exactly one post-QA incremental Graphify refresh, and a persisted closure audit.

## Binding Behavior Contract

### One central decision at render and dispatch

`GroupConversationWired` is the sole group owner of `AnnouncementPrivateReplyResolver`. It may retain an eligibility snapshot only to decide whether a callback capability is visible. It must call that same Session-02 resolver again with a newly constructed two-field request immediately before every navigation attempt. Screen, overlay, viewer, and app-owner code must not reproduce, weaken, cache as authority, or bypass the resolver matrix.

The request is built from the exact selected current row/item and that same
selection-time two-field identity is retained only for the lifetime of the
transient capability/action. Dispatch re-resolves that request; it must not
replace the selected sender with a newly loaded sender, because sender drift is
a denial rather than permission to route to a different person:

- bubble: current `GroupMessage.id` plus its current `senderPeerId`;
- viewer: the exact current `MediaViewerItem.messageId` and the selected parent row's sender. The current production viewer contains only attachments from that one parent; swiping changes the exact attachment/page but not the parent/sender. Never dispatch the initially opened attachment after the user swipes.

Render eligibility and dispatch both require a complete opener. Any missing, stale, contradictory, throwing, or denied read hides the action before render or denies at invocation. Same-id direct/unresolved attachments, text/audio/file rows, outgoing/self/system rows, non-announcement groups, missing membership, unknown/deleted tombstone authority, blocked/archived/unknown contacts, and missing openers remain ineligible.

### Typed callback and app-owner route

Add one optional callback-only app-owner contract to `GroupConversationWired`, semantically:

```dart
typedef OpenAnnouncementSenderConversation =
    Future<void> Function(ContactModel contact);
```

The callback receives only the freshly resolved current `ContactModel`. Plan 247 must not make `GroupConversationWired` import or construct `ConversationWired`, add or repurpose `MessageRepository`/`ChatMessageListener` or other direct-delivery dependencies, or invoke a send use case. The file's accepted pre-existing Plan-236 Forward fallback and ordinary group send/upload/Bridge/P2P seams remain untouched and are not part of this callback.

Every non-null production opener must await the existing complete direct route through route return and construct it with no Plan-247 source seed: no `initialText`, quote, attachment, pending media, group/source identity, caption, sender display metadata, Forward marker, key/nonce, or payload field. Do not clear or overwrite unrelated direct history. The causal fixture begins with an empty composer and must remain empty until an explicit user edit; opening/cancelling invokes no submit.

### Exact five-site census

The Executor must preserve a source/constructor census of exactly these five current `GroupConversationWired(` construction sites:

| Construction site | Binding opener result |
|---|---|
| `lib/main.dart` notification/app-owner route | complete; adapt the existing `_openConversationForContact` route owner and await route return |
| `lib/features/feed/presentation/screens/feed_wired.dart` | complete; reuse its existing full `ConversationWired` builder and make/keep its opener Future-returning |
| `lib/features/orbit/presentation/screens/orbit_wired.dart` | complete; reuse its guarded full direct builder and await route return |
| `lib/features/groups/presentation/screens/group_list_wired.dart` | explicit null; this owner lacks direct message/listener dependencies and has no current production construction owner, so the action stays absent |
| `lib/features/groups/presentation/screens/create_group_picker_wired.dart` | optional pass-through; Orbit supplies its complete opener, while direct construction/default null keeps the action absent |

Orbit must pass the same complete opener into `CreateGroupPickerWired`; that widget only forwards it to its `GroupConversationWired`. No site may build a partial direct screen or silently omit the named field. If current source gains or loses a construction site before execution, stop and revise this census before production.

### Bubble, viewer, dismissal, coalescing, and feedback

- Add a distinct `MessageContextOverlay.messageSenderActionKey`, boolean, and callback. It is not `Reply`, `onQuoteReply`, or a quote action. Use `Icons.chat_bubble_outline_rounded`. In menu order it follows Reply and precedes Edit/Copy/media actions. Existing order is otherwise unchanged.
- Add only `MediaViewerAction.messageSender`; place it immediately after `reply` in the typed viewer action order, use the same message icon, and use the exact localized action label as tooltip/semantics. It remains callback-only and is rendered only when explicitly present in that ordinary group item's capabilities.
- A bubble overlay dismisses synchronously before starting async dispatch. A viewer action revalidates the exact current item, then dismisses the viewer before opener invocation or feedback. A stale/denied invocation opens no route and shows only the unavailable copy. An eligible opener throw/failure shows only the separate open-failure copy.
- One wired in-flight latch coalesces bubble/viewer/repeated dispatch while resolution or the awaited opener is pending. Overlay `_handleOnce` and typed-viewer `_dispatching` remain local defense, not substitutes for the wired latch. Reset the latch in completion-safe `finally`; never open twice.
- Successful navigation is terminal. It does not trigger Reply, quote state, a group callback, send, upload, Forward, download, or a second route.

### Exact localized copy

Add ARB keys and regenerate the normal localization outputs with these exact values:

| Meaning | English | German | Arabic |
|---|---|---|---|
| Action / tooltip | `Message sender` | `Absender anschreiben` | `مراسلة المرسل` |
| State became unavailable | `Message sender is unavailable.` | `Der Absender kann nicht angeschrieben werden.` | `مراسلة المرسل غير متاحة.` |
| Eligible route failed to open | `Couldn’t open the conversation.` | `Die Unterhaltung konnte nicht geöffnet werden.` | `تعذّر فتح المحادثة.` |

All three values must be visible/semantic, overflow-free at 320x568, and correct under RTL Arabic. Feedback must not reveal whether message, group, membership, tombstone, contact, block state, media, or opener changed.

### Preservation boundaries

- `privacyMinimized == true` continues to publish no ordinary typed-viewer actions, metadata, resume state, or Message sender action. A private/terminal item never enters the legacy or typed ordinary viewer because of this enum addition.
- Do not change `MediaViewerProtection`, `MediaViewerItem.isActionEligible`, current-parent private-media decisions, Plan-234 Save/Files/Share/Forward/bookmark/library/PiP denial, native protection, first-frame callbacks, or dedicated private-route behavior.
- Ordinary direct viewer capabilities remain unchanged. Discussion-group Reply/quote behavior and announcement reader read-only composer plus reactions remain unchanged. Message sender is absent on discussion/QA/outgoing/ineligible rows and is never an alias for Reply.

## Exact Production And Test Scope

Expected production owners:

- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/conversation/presentation/widgets/message_context_overlay.dart`
- `lib/shared/widgets/media/media_viewer_item.dart`
- `lib/shared/widgets/media/full_screen_typed_media_viewer.dart`
- `lib/main.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/features/orbit/presentation/screens/orbit_wired.dart`
- `lib/features/groups/presentation/screens/group_list_wired.dart`
- `lib/features/groups/presentation/screens/create_group_picker_wired.dart`
- `lib/features/conversation/presentation/screens/conversation_screen.dart` — narrow ordinary-direct denial case for the new enum only
- `lib/features/conversation/presentation/screens/direct_shared_media_library_screen.dart` — narrow direct-library denial case only
- `lib/features/groups/presentation/screens/group_shared_media_library_screen.dart` — narrow group-library denial case only
- `lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`, `lib/l10n/app_ar.arb`
- generated `lib/l10n/app_localizations.dart`, `app_localizations_en.dart`, `app_localizations_de.dart`, and `app_localizations_ar.dart`

Test/gate owners:

- new `test/features/groups/presentation/announcement_private_reply_routing_test.dart`
- new `test/features/groups/presentation/announcement_private_reply_entry_surface_test.dart`
- new `test/features/groups/integration/announcement_private_reply_no_auto_send_test.dart`
- existing preservation tests named in the gates below only when a causal compile/exhaustive-enum assertion requires a narrow update
- `scripts/run_test_gates.sh`, `scripts/run_host_test_gates.sh`, and `Test-Flight-Improv/test-gate-definitions.md` only for exact registrations/classification
- this plan during execution; Plan-247 source/breakdown only after accepted QA to mark Session 03 accepted and Session 04 execution-ready

Any other production file is a scope expansion. Stop, record the missing causal seam, and obtain plan review before editing it.

## Pre-Execution Dirty-Tree Baseline

Captured 2026-07-11 after accepted Plan-234 Session-05 closure and while preserving the shared dirty worktree. The ordered manifest is `STATUS<TAB>SHA256-or-ABSENT<TAB>PATH`; its aggregate SHA-256 is:

`d5959aafe10aae9c55ad527c6e5f535e2bd7bac488e55a36ef2f03404f43dacd`

This superseding aggregate is over the exact ordered 32-path manifest printed
below, with status tokens normalized to `CLEAN`, Git porcelain ` M`/`??`, or
`ABSENT`, followed by the listed SHA/`ABSENT` and repository-relative path.

| Baseline state | Paths |
|---|---|
| clean | group screen/wired, context overlay, Feed, Orbit, group list, create picker, `group_shared_media_library_screen.dart`; group screen/context overlay/media boundary/l10n tests |
| already modified, preserve existing hunks | `media_viewer_item.dart`, `full_screen_typed_media_viewer.dart`, `conversation_screen.dart`, `direct_shared_media_library_screen.dart`, `main.dart`, all three ARBs, all four generated l10n files, `group_conversation_wired_test.dart`, `full_screen_typed_media_viewer_test.dart`, both gate scripts/definitions as reported by the manifest |
| absent | all three new Session-03 tests |

Exact per-file digests are frozen here for collision/attribution checks:

```text
group_conversation_screen.dart 1c6a5600610bef3e9e9cdc31ab0621d551836bdc939d8c9f76231b9067bfb5b7
group_conversation_wired.dart f7b230d8639699dfcb79b805e25442ac3a5f2dfe5df3eebe698b5286efbb607b
message_context_overlay.dart 887bab04a931a740ec2b6bc16ad306845fb7d24958c9c26f6a7c9219fafe992a
media_viewer_item.dart 94211520066d42b942b7c14fd4436e88c5aa96cc0c50bb358b3e90e8e5cd36c0
full_screen_typed_media_viewer.dart c6bbb419c191836a7cda68692f254d75cf21b42b12a2e731d1ecb09b1672da32
conversation_screen.dart 32374a2f3deae6d3316c19e2cbe18704026b9fb1c5e525c4f651adfe33908b6b
direct_shared_media_library_screen.dart 929fdde698f9eba27529a9ddf7f45e25291c4bd6ded8c8e30499a35987b0c563
group_shared_media_library_screen.dart 9c552952cbc3d3bda2ba7015ae2e6f45cbeea4bc395974096319d936d762a0ae
main.dart 35af07f6c2b5f9df72b0489ed93b9ff5aea2b0af6b27cb6a327100941b8ed617
feed_wired.dart cf9afa9c29bd684ecd82cd3c25a567c6a498561b4009ce201f8fa39bee5c2520
orbit_wired.dart d23b0f48092045ae143aaf8ba3b8c76223d424e6bf99987c51a798174c2aaf99
group_list_wired.dart 99cd64409273a11216c1f5237272c1f8a906e6bef9a1d624858292db7b23af11
create_group_picker_wired.dart 207934eb64313455fe528343e63b052a4d3297a591f150d31191218b3471f84c
app_en.arb 8c56c90a3f1f82dd05630dd7474deff874df1ab104e73b4e874174e9f93845af
app_de.arb f955316244fad5ab0d0eecd0b177ab0af71e3ce025c699c499123492dd0c4b74
app_ar.arb 9b5414d8c8050287697a99c362a36ab5de5006637c9bba65b0b331f545d409c1
app_localizations.dart 375ea1851862dbac4219e1cdf986967c6827a34eaef53ebab367ed389cc29225
app_localizations_en.dart a159840ddd31f9b31ef39317327c13030208db09d3803616dd35422562fcd6f6
app_localizations_de.dart acb3ad300bfcea76751d6289b74ff674bf57cbec883b1b8e72bcceda14f04c5d
app_localizations_ar.dart 03dd564d8b34446e421d4f2163b5ea961b81db4dba36a89e3ee5d9aae88d48f2
announcement_private_reply_routing_test.dart ABSENT
announcement_private_reply_entry_surface_test.dart ABSENT
announcement_private_reply_no_auto_send_test.dart ABSENT
group_conversation_wired_test.dart 22be829a2d833e68ee471a7623b6a3760aa50c7739b604ebb81d5fe60a14db7f
group_conversation_screen_test.dart 6a49620116280f3a4dabe5c43832827d86e423690139bb25712abbb99e31071a
message_context_overlay_test.dart 8980323ef5f031f75418dfd96339a93ed6211277f516d9eba3f301c24e4aea81
full_screen_typed_media_viewer_test.dart f15b00a4a764dffa7e5961501cb359eb2b0225180097b590266dc802f86ffda9
media_viewer_boundary_test.dart a98cd9e8629518121fd2d43a4d0952d990b71f4976d589b8bfd203a9bd59738f
l10n_integrity_test.dart bfbdc701fff603ed16963170d7232f0217702c3e46fa0dc40c3ff2579bfef07b
run_test_gates.sh 8ae9fea0299100939f4a678e63bdc1cdac73763d66ff92682ca9e204845b0bd7
run_host_test_gates.sh 72afed765525213679d9c0114a0680f867c64d3012c67b1829676db5f859f4d2
test-gate-definitions.md 4723372dca30a5481d66940e5c621a0eb0eff4b4fddca822f7249c1844f703a8
```

The forbidden non-goal manifest (status, binary diff, and current file hashes for `android`, `ios`, `go-mknoon`, `go-relay-server`, `lib/core/database`, group domain, and `send_group_message_use_case.dart`) has 1,190 lines and SHA-256:

`7140031a08ae6ab5abe6293a744475fc637fd3590fc08b7f8a1586d56b94eded`

At execution start, recapture both manifests before RED. If another authorized owner moved a shared file after this planning snapshot, persist a superseding pre-RED hash and exact reason in `## Execution Progress`; do not overwrite, reset, stash, or attribute that work. Final scope proof compares against that execution-start snapshot.

## RED Tests To Add Before Production

Create all three files before editing any production, l10n, or gate file. Then run their combined command and retain the non-zero missing-API/action/opener output. File-not-found intake is not RED.

### `announcement_private_reply_routing_test.dart`

Required named tests:

- `message and viewer open the current eligible sender exactly once`
- `viewer swipe dispatches the exact current attachment and never the initial page`
- `stale menu state dismisses and shows only unavailable feedback`
- `route failure dismisses and shows only open-failure feedback`
- `double taps coalesce while resolution or opener is pending`
- `private reply copy is localized accessible and RTL safe`
- `discussion Reply reactions and private viewer protection stay unchanged`

Use mutable repositories and a pending opener. Prove capability-building calls the Session-02 resolver/current reads, invocation calls it again with the same selection-time `(sourceMessageId, senderPeerId)`, sender drift/block/tombstone/member/message changes after menu open route zero times, overlay/viewer is already gone when feedback/opener runs, swiping from attachment A to B dispatches attachment B under the same parent, and one pending action produces one opener. Assert the exact three-language copy, keys, icon semantics, order, 320x568 layout, and RTL.

### `announcement_private_reply_entry_surface_test.dart`

Required named tests:

- `five group entry sites wire one complete or explicit null opener contract`
- `group wired never constructs a partial direct conversation`

Combine source-constructor census with route spies. Require exactly five production `GroupConversationWired(` calls; pin the table above; require Orbit-to-create-picker pass-through; require every complete opener to await the existing full builder without initial source fields; and require null-owner action absence. Inspect only the new Plan-247 typedef/field/resolver/dispatch hunks for new `ConversationWired`, direct-delivery dependencies, send/upload/Forward/payload, Bridge/P2P command, or service-locator construction. Explicitly preserve and exempt the file's accepted pre-existing Plan-236 `MessageRepository`/`ChatMessageListener` Forward fallback plus ordinary group Bridge/P2P/send/upload seams.

### `announcement_private_reply_no_auto_send_test.dart`

Required named test:

- `opening private composer has zero delivery and source mutations`

Use the real direct `ConversationWired` route fixture behind the injected complete opener, an empty direct history, and a seeded eligible incoming announcement parent plus current group-owned visual attachment. Snapshot that group history/source row/attachment/file before opening. Use throwing/recording direct send, group send, upload, Forward, Bridge/P2P, and source-file seams. Open, assert a blank composer with no quote/media/context, cancel without submit, and prove all delivery/mutation counters are zero, direct history remains empty, and the seeded group history/source rows/files are byte-for-byte unchanged. Only a separate explicit composer-submit control may use existing 1:1 delivery; it is not triggered by Message sender.

Initial RED must be causal: the context callback/key, `MediaViewerAction.messageSender`, typed opener/census, and production routing are absent. Record exact command, exit, and missing symbols/assertions in this file's future `## Execution Progress`.

## Mutation Re-RED Contract

After GREEN, apply and immediately revert each mutation independently:

1. reuse Reply/onQuoteReply or call a group reply callback;
2. dispatch attachment/page A after swiping to attachment/page B of the same parent;
3. skip the second resolver call, replace the selected sender with a drifted freshly loaded sender, or accept a stale/blocked/tombstoned result;
4. invoke opener before dismissing overlay/viewer;
5. remove the wired in-flight latch and allow two pending taps;
6. seed initial text/quote/media/source/group data or invoke send/upload/Forward;
7. omit/change one of the five opener census rows or construct `ConversationWired` inside group wired;
8. allow `messageSender` in `privacyMinimized`/protected/ordinary-direct content;
9. change one exact EN/DE/AR string, action order, key, or semantics.

Each mutation must make its named causal test RED. Revert with `apply_patch`; no mutation residue may remain.

## Gate Registration

- Add all three new files to `GROUP_TESTS`.
- Because `announcement_private_reply_no_auto_send_test.dart` executes the real direct route fixture, also add that exact file to `ONE_TO_ONE_TESTS` and `ONE_TO_ONE_HOST_TESTS`.
- The three group-feature paths are already discovered by `feature-host-all`; do not create duplicate manual host entries for the other two.
- Add exact classifications/reasons to `Test-Flight-Improv/test-gate-definitions.md` and prove completeness. Do not widen baseline, feed, runtime, nightly, or device gates.

## Literal Acceptance Gates

Run in this order after final production GREEN; every failure starts as `pending_triage` and remains blocking until causally classified:

```bash
# Session-03 causal GREEN
flutter test \
  test/features/groups/presentation/announcement_private_reply_routing_test.dart \
  test/features/groups/presentation/announcement_private_reply_entry_surface_test.dart \
  test/features/groups/integration/announcement_private_reply_no_auto_send_test.dart

# Accepted Session-02 application boundary (expected accepted baseline: 6/6)
flutter test \
  test/features/groups/application/announcement_private_reply_request_test.dart \
  test/features/groups/application/announcement_private_reply_policy_test.dart \
  test/features/groups/application/announcement_private_reply_transport_boundary_test.dart

# Existing group/context/viewer preservation
flutter test \
  test/features/groups/presentation/group_conversation_screen_test.dart \
  test/features/groups/presentation/group_conversation_wired_test.dart
flutter test test/features/conversation/presentation/widgets/message_context_overlay_test.dart
flutter test \
  test/shared/widgets/media/full_screen_typed_media_viewer_test.dart \
  test/shared/widgets/media/media_viewer_boundary_test.dart
flutter test \
  test/features/conversation/presentation/screens/conversation_screen_test.dart \
  test/features/conversation/presentation/screens/conversation_shared_media_viewer_test.dart \
  test/features/groups/presentation/announcement_media_library_viewer_test.dart
flutter test test/features/groups/application/group_received_media_action_policy_test.dart \
  --plain-name 'GMA-13 announcement member and admin get core media capabilities without reply while qa stays empty'
flutter test test/features/groups/presentation/group_conversation_wired_test.dart \
  --plain-name 'announcement readers stay read-only for compose but still keep reaction entry'

# Plan-234 viewer/native-protection host preservation
flutter test test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart
flutter test test/core/media/private_media_protection_coordinator_test.dart

# Localization generation/parity
flutter gen-l10n
flutter test test/l10n/l10n_integrity_test.dart

# Exact registration and affected curated/family gates
rg -n 'announcement_private_reply_(routing|entry_surface|no_auto_send)_test.dart' \
  scripts/run_test_gates.sh scripts/run_host_test_gates.sh \
  Test-Flight-Improv/test-gate-definitions.md
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh 1to1
./scripts/run_host_test_gates.sh feature-host-all
./scripts/run_test_gates.sh completeness-check

# Scoped hygiene
dart format --output=none --set-exit-if-changed \
  lib/features/groups/presentation/screens/group_conversation_screen.dart \
  lib/features/groups/presentation/screens/group_conversation_wired.dart \
  lib/features/conversation/presentation/widgets/message_context_overlay.dart \
  lib/shared/widgets/media/media_viewer_item.dart \
  lib/shared/widgets/media/full_screen_typed_media_viewer.dart \
  lib/features/conversation/presentation/screens/conversation_screen.dart \
  lib/features/conversation/presentation/screens/direct_shared_media_library_screen.dart \
  lib/features/groups/presentation/screens/group_shared_media_library_screen.dart \
  lib/main.dart \
  lib/features/feed/presentation/screens/feed_wired.dart \
  lib/features/orbit/presentation/screens/orbit_wired.dart \
  lib/features/groups/presentation/screens/group_list_wired.dart \
  lib/features/groups/presentation/screens/create_group_picker_wired.dart \
  lib/l10n/app_localizations.dart lib/l10n/app_localizations_en.dart \
  lib/l10n/app_localizations_de.dart lib/l10n/app_localizations_ar.dart \
  test/features/groups/presentation/announcement_private_reply_routing_test.dart \
  test/features/groups/presentation/announcement_private_reply_entry_surface_test.dart \
  test/features/groups/integration/announcement_private_reply_no_auto_send_test.dart
flutter analyze \
  lib/features/groups/presentation/screens/group_conversation_screen.dart \
  lib/features/groups/presentation/screens/group_conversation_wired.dart \
  lib/features/conversation/presentation/widgets/message_context_overlay.dart \
  lib/shared/widgets/media/media_viewer_item.dart \
  lib/shared/widgets/media/full_screen_typed_media_viewer.dart \
  lib/features/conversation/presentation/screens/conversation_screen.dart \
  lib/features/conversation/presentation/screens/direct_shared_media_library_screen.dart \
  lib/features/groups/presentation/screens/group_shared_media_library_screen.dart \
  lib/main.dart \
  lib/features/feed/presentation/screens/feed_wired.dart \
  lib/features/orbit/presentation/screens/orbit_wired.dart \
  lib/features/groups/presentation/screens/group_list_wired.dart \
  lib/features/groups/presentation/screens/create_group_picker_wired.dart \
  test/features/groups/presentation/announcement_private_reply_routing_test.dart \
  test/features/groups/presentation/announcement_private_reply_entry_surface_test.dart \
  test/features/groups/integration/announcement_private_reply_no_auto_send_test.dart
bash -n scripts/run_test_gates.sh scripts/run_host_test_gates.sh
git diff --check
```

`feature-host-all` is justified once here by five app-feature entry owners plus shared group/viewer UI. Full `host-all`, `core-host-all`, reliability-sim, device/simulator, native, Go, relay, migration, and performance gates are not Session-03 gates.

## Scope Guard And Non-Goals

At final code state:

- compare the exact owned-file status/content/diff against the execution-start manifest and classify every new hunk;
- regenerate the 1,190-line forbidden manifest with the identical command and require its SHA-256 to equal the execution-start forbidden hash;
- run `git diff --stat` and `git diff -w --stat` over the allowlist so formatting cannot hide scope;
- source-scan the bounded Plan-247-added group-wired typedef/field/resolver/dispatch hunks and all three new tests for newly introduced `sendChatMessage`, `sendGroupMessage`, upload, Forward dispatch, payload/serializer, Bridge/P2P command, direct message/listener ownership, path/media/key/nonce seeding, and partial `ConversationWired` construction; preserve and explicitly exempt the accepted pre-existing Plan-236/group seams elsewhere in the file; and
- confirm exactly five production `GroupConversationWired(` calls and no unregistered new test.

Strict non-goals:

- no migration, schema, DB version/v101, SQL/helper, Plan-238, or persisted route/draft field;
- no native/device/platform, Go, relay, Bridge/P2P, notification, or wire behavior;
- no group/announcement send permission or reaction behavior change;
- no actual PiP, media download, egress, Forward, reporting, contact introduction/add/unblock/unarchive, or automatic send;
- no private-media lifecycle/protection weakening and no Plan-234 Session-06 work; and
- no full `host-all` in this session.

## Graphify, Independent QA, And Closure Cadence

After all literal gates and the final attributable production delta, run Graphify impact over the actual changed production files. The expected maximal command is:

```bash
python3 graphify-arch/tdd_context.py affected \
  lib/features/groups/presentation/screens/group_conversation_screen.dart \
  lib/features/groups/presentation/screens/group_conversation_wired.dart \
  lib/features/conversation/presentation/widgets/message_context_overlay.dart \
  lib/shared/widgets/media/media_viewer_item.dart \
  lib/shared/widgets/media/full_screen_typed_media_viewer.dart \
  lib/features/conversation/presentation/screens/conversation_screen.dart \
  lib/features/conversation/presentation/screens/direct_shared_media_library_screen.dart \
  lib/features/groups/presentation/screens/group_shared_media_library_screen.dart \
  lib/main.dart \
  lib/features/feed/presentation/screens/feed_wired.dart \
  lib/features/orbit/presentation/screens/orbit_wired.dart \
  lib/features/groups/presentation/screens/group_list_wired.dart \
  lib/features/groups/presentation/screens/create_group_picker_wired.dart \
  lib/l10n/app_en.arb lib/l10n/app_de.arb lib/l10n/app_ar.arb \
  lib/l10n/app_localizations.dart lib/l10n/app_localizations_en.dart \
  lib/l10n/app_localizations_de.dart lib/l10n/app_localizations_ar.dart \
  --budget 600
```

Then obtain fresh independent read-only QA. QA must audit exact action/copy, current-item and current-parent revalidation, dismissal order, cross-surface coalescing, five-site complete/null census, real blank-route/no-send proof, Session-02 6/6 preservation, Plan-234 private viewer denial, registrations, every literal gate, and dirty-scope attribution.

Permit at most **two** bounded behavior fix passes. Each behavior correction requires a new causal RED/counterexample before production, reruns all affected focused/named/static gates, reruns Graphify `affected`, and obtains a fresh QA verdict. If blockers remain after two passes, stop as not accepted; do not refresh or close.

Only after QA says `accepted` with zero blockers, run exactly once:

```bash
./graphify-arch/refresh_arch_graph.sh --incremental
```

Do not refresh during planning, RED/GREEN implementation, rejected QA, or closure-doc edits. Persist `## Execution Progress`, `## Execution Result`, final QA/fix-pass count, refresh evidence, and `## Closure Audit` in this file. A separate read-only Closure Reviewer then reconciles evidence and scope. On acceptance, update only Plan-247 source/breakdown to mark Session 03 accepted and Session 04 execution-ready; overall Plan 247 remains implementation-in-progress until Session 04 acceptance/closure. Do not update final index/closure-reference artifacts here.

## Done Criteria

- [x] Independent Plan Reviewer accepted this execution contract before RED.
- [x] All three new tests existed before production and recorded causal missing-contract RED.
- [x] Bubble and exact current viewer page expose only the distinct localized Message sender capability after fresh Session-02 qualification.
- [x] Invocation re-resolves current authority, dismisses first, coalesces, opens exactly once, and reports stale versus route failure with exact privacy-minimized copy.
- [x] All five `GroupConversationWired` sites match the complete/null census; group wired constructs no partial direct route.
- [x] The real direct route opens blank and cancel produces zero direct/group send, upload, Forward, transport, history, or source mutation.
- [x] Session-02 focused proof remains 6/6; discussion Reply/reactions and announcement read-only behavior are unchanged.
- [x] Plan-234 private/terminal viewer protection, privacy-minimized action suppression, native coordinator, and direct private route remain green.
- [x] EN/DE/AR generation, small viewport, RTL, semantics, and l10n parity pass.
- [x] All registrations, `groups`, `1to1`, justified `feature-host-all`, completeness, scoped formatter/analyzer, script syntax, diff, and scope guards pass.
- [x] Final Graphify `affected` is reconciled, independent QA accepts within at most two fix passes, and exactly one post-QA incremental refresh runs.
- [x] Execution Result, Closure Audit, and separate closure-review verdict are persisted; Session 04 alone becomes execution-ready.

## Execution Progress

- 2026-07-11 — Planning completed with an accepted independent review before RED. No Session-03 test, production, l10n, gate, QA, or Graphify refresh occurred during planning. The authoritative execution-start scoped baseline remains the independently matched normalized 32-path aggregate `d5959aafe10aae9c55ad527c6e5f535e2bd7bac488e55a36ef2f03404f43dacd`; all three causal test files are absent.
- 2026-07-11 — Executor recaptured the non-goal boundary before RED with one reproducible manifest: porcelain status, `git diff --numstat`, then sorted per-file SHA-256 for `android`, `ios`, `go-mknoon`, `go-relay-server`, `lib/core/database`, `lib/features/groups/domain`, and `send_group_message_use_case.dart`. Execution-start result: 1,502 lines, SHA-256 `72f86b17ea67d488cc968c7dd929ed1e0d2a71785c17db6d18cc590c9754e86f`. This supersedes the planning-time forbidden digest for final execution comparison because the exact command is now persisted here.
- 2026-07-11 — RED authored before production: all three planned causal files were added, then the combined `flutter test` command exited non-zero. After removing two test-fixture-only typing mistakes and rerunning, failure remained exclusively on the intended missing Session-03 contract: absent `MessageContextOverlay.messageSenderActionKey` / `showMessageSenderAction`, absent `MediaViewerAction.messageSender`, absent three l10n getters, absent `OpenAnnouncementSenderConversation`, absent five owner bindings, and absent the bounded group-wired dispatcher. No production, l10n, gate, or Graphify file had been edited when this RED was captured.
- 2026-07-12 — Production GREEN completed without adding a send path. `MediaViewerAction.messageSender`, the overlay action/key/callback, one render-time and one dispatch-time policy resolution, a wired in-flight latch, exact-current typed-viewer ownership, five complete/null production owner bindings, and EN/DE/AR copy were added. The three causal suites passed together `10/10`; accepted Session-02 request/policy/transport suites remained `6/6`.
- 2026-07-12 — Pre-QA counterexample audit found one real fail-closed gap: a parent-wide eligible result could publish `messageSender` for a corrupt/mismatched typed-viewer current item. A causal exact test, `Plan 247 mismatched viewer attachments never receive Message sender or open`, was RED for direct-owner, unresolved-owner, and wrong-parent pages. The minimal production correction requires the exact parent, group owner, and image/video kind before publishing or dispatching the action; the exact test then passed `1/1`, and all five Plan-247 group-wired behavioral tests passed `5/5`. This was an execution correction before independent QA, not a QA fix pass.
- 2026-07-12 — Test evidence was hardened without widening production: the no-auto-send test now opens the real blank `ConversationWired` route and proves zero direct send/upload/P2P/Bridge commands plus unchanged persisted group message, attachment, and source-file bytes; routing tests cover semantics/order/RTL/small viewports and privacy-minimized denial; the entry-surface test binds the exact five constructor/openers; group-wired tests cover stale render state, sender drift, dismissal-before-feedback, throwing opener, coalescing across resolver/opener, and corrupt viewer owners. An accidental formatter-only rewrite of `group_conversation_wired_test.dart` was reduced to its substantive changes; stable SHA-256 became `4b9f17e51e2fc8653a2cf12bd0b1703cd42e61cf16f846a88a0644dc18dcb9c3`, `git diff --check` clean.
- 2026-07-12 — The nine mutation contracts were exercised independently and restored with `apply_patch`. Named causal RED covered group-reply callback substitution, stale page-A dispatch, sender-drift acceptance, awaiting the opener before dismissal, removal of the shared wired latch, seeded direct composer text, omission of the explicit-null owner row, protected-viewer action publication, and changed English action copy. Latch removal deterministically stopped the named test at its second awaited tap while the first resolver remained gated; the run was terminated as non-settling RED. All captured production SHA-256 values returned exactly after restoration, including group screen `f1c45e49...`, group wired `d1eef09e...`, policy `f939052c...`, typed viewer `c740a637...`, main `93d6e8e...`, group list `aa084197...`, and generated EN l10n `ea6dc2bc...`; no mutation residue remained.
- 2026-07-12 — Literal focused acceptance was rerun from final production state: causal Session-03 `10/10`; Session-02 `6/6`; full group screen+wired `266/266`; overlay `15/15`; typed viewer/boundary `8/8`; conversation/shared-media/announcement-library viewer `81/81`; exact GMA-13 `1/1`; exact announcement-reader preservation `1/1`; Plan-234 private viewer `16/16`; native-protection coordinator `9/9`; generated l10n plus integrity `2/2`. A prior full group screen/wired attempt had one existing timing-sensitive voice cleanup timeout whose exact-name rerun passed; the later fresh `266/266` run supersedes it.
- 2026-07-12 — Curated/family gates passed from final behavior state: `./scripts/run_test_gates.sh groups` `1,951/1,951` plus both Go bridge/node sentinels; `./scripts/run_test_gates.sh 1to1` `1,963/1,963`; `./scripts/run_host_test_gates.sh feature-host-all` passed every one of its `751/751` exact commands on a fresh complete restart; completeness passed `1,179/1,179`. The first family attempt exposed a stale Plan-234 current-parent migration fixture, and a later attempt exposed four stale pre-Plan-234 `SendChatMessageFn` callback shapes. Test-only compatibility repairs seeded the ordinary imported parent and added the optional `PrivateMediaPolicy?` argument respectively; their exact suites passed (`3/3`, `6/6`, and related callback fixtures `16/16`), scoped analysis found no issues, a repository-wide callback scan found no remaining stale shape, and the complete 751-command restart accepted them. Production remained fail closed.
- 2026-07-12 — Static/hygiene evidence: exact registration scan found all three files in the required arrays/docs; the literal 20-file formatter gate passed with `0 changed`; script syntax and `git diff --check` passed. The literal scoped analyzer reported no warning/error and only eight pre-existing info-level findings (`withOpacity`, earlier async-context sites, and an earlier null-aware style site), none in the Plan-247 additions. A separate analyzer over the five compatibility fixtures reported `No issues found`.
- 2026-07-12 — Final scope proof passed. The exact execution-start forbidden-manifest command was recovered and rerun at `1,502` lines with SHA-256 `72f86b17ea67d488cc968c7dd929ed1e0d2a71785c17db6d18cc590c9754e86f`, exactly matching execution start. Production census is exactly five `GroupConversationWired(` call sites plus the constructor declaration: three complete callbacks, one explicit null, and one pass-through. Attributable production hunks contain no send/upload/Forward/Bridge/P2P/direct-repository/source-seed/key/nonce/path seam; matching tokens in causal tests are fixtures or negative assertions. Normal and whitespace-insensitive allowlist stats were captured and `git diff --check` remained clean.
- 2026-07-12 — Final pre-QA Graphify `affected` ran over all 20 attributable production/l10n files with budget 600 and exited zero, surfacing the expected conversation, group, owner-entry, shared-viewer, and localization dependents. No Graphify refresh has run during execution; the single incremental refresh remains gated on an accepted independent QA verdict.
- 2026-07-12 — Independent QA pass 1 rejected closure for one proof-only blocker and found no confirmed production defect: `announcement_private_reply_no_auto_send_test.dart` invoked the injected opener from a test button instead of traversing the real seeded `GroupConversationWired` Message sender action, and it lacked explicit group-send and Forward counters. QA accepted the production policy/routing implementation, all recorded literal gates, scope proof, and compatibility repairs. The rejection establishes QA `fix_passes=1`; behavior-fix count remains zero.
- 2026-07-12 — QA fix pass 1 changed only `announcement_private_reply_no_auto_send_test.dart`. The fixture now mounts a seeded read-only announcement `GroupConversationWired`, long-presses the real media cell, selects `MessageContextOverlay.messageSenderActionKey`, traverses the production dispatcher into the awaited blank `ConversationWired`, cancels, and returns. It records direct/group send proxies, direct/group upload and Forward launchers, P2P/Bridge commands, direct/group histories, source message/attachment/file bytes, and announcement read-only/reaction state. Before, during, and after the route, all delivery counters remain zero and every source/read-only/reaction snapshot remains unchanged. No production, l10n, gate, Graphify, or entry-surface file changed; the entry-surface SHA-256 remained `dc1f32f712d494adf307190f58eb423dad5e30f398827d7a853319208a19baf7`.
- 2026-07-12 — Post-fix affected evidence passed: the exact repaired fixture `1/1`; the complete three-file Session-03 causal command `10/10`; all five `Plan 247` group-wired counterexamples `5/5`; the announcement-reader preservation sentinel `1/1`; formatter `0 changed`; fixture-only analyzer `No issues found`; script syntax and `git diff --check` clean. Because the correction is test-only, leaves registration and production hashes unchanged, and the repaired test itself already belongs to the previously green `groups`, `1to1`, and `feature-host-all` families, those unchanged family sweeps remain valid while the directly affected proof was rerun fresh.
- 2026-07-12 — Fresh independent post-fix QA returned `ACCEPTED` with zero blockers. QA independently reran the repaired real-route fixture `1/1`, reconciled current source and stable production hashes, and accepted the complete policy/current-item/dismissal/coalescing/opener-census/privacy/localization/gate/scope evidence. Honest QA count is `fix_passes=1`; behavior-fix count is `0` because the sole QA correction was proof-only.
- 2026-07-12 01:51 CEST — After and only after accepted QA, exactly one `./graphify-arch/refresh_arch_graph.sh --incremental` completed with exit `0`: `48,196` nodes, `74,807` edges, and a `1,272`-file / `12,416`-named-test / `959`-production-target TDD overlay. No earlier Session-03 incremental refresh ran. Closure-document edits do not trigger another refresh.
- 2026-07-12 — Separate read-only Closure Reviewer returned `ACCEPTED` with zero blockers. It reconciled the real-route proof, QA/fix-pass accounting, focused/family counts, exact forbidden manifest, five-site census, graph cadence, and dependency boundary. Session 03 is closed; Session 04 alone is execution-ready. No final index, announcement audit, or closure-reference artifact was changed by Session 03 closure.
- 2026-07-12 — Session-04's literal no-write formatter exposed four retained Session-03 compatibility fixtures that required only canonical Dart line wrapping/indentation: `account_migration_post_import_behavior_test.dart`, `conversation_wired_bg_task_test.dart`, `conversation_wired_offline_send_ux_test.dart`, and `conversation_wired_sending_to_failed_test.dart`. A temp-copy preview proved no token, assertion, fixture, registration, or behavior change; the repository formatter then changed only those four files. Their combined exact batch passed `34/34`, and the complete Session-04 32-file formatter rerun passed with `0 changed`.
- 2026-07-12 — Fresh independent read-only QA accepted the formatting-only post-closure repair with zero blockers. Historical Session-03 `fix_passes=1` and behavior-fix count `0` remain unchanged; the separate accounting is `post_closure_fix_passes=1` with post-closure behavior-fix count `0`. No Graphify `affected` or refresh is required because symbols, test names, registrations, and behavior are unchanged; the final Wave-1 refresh remains the next graph update.

## Execution Result

Verdict: `accepted` / `closed`.

- The callback-only Message sender route is complete across the bubble, exact current typed-viewer item, and all five production group-entry owners. It reuses the accepted Session-02 fresh resolver at render and invocation, fails closed on drift/corrupt ownership/protection, dismisses transient UI before feedback/navigation, coalesces concurrent taps, and opens only the existing fully wired blank direct conversation.
- The real-route integration proof traverses seeded read-only `GroupConversationWired` through the production action into awaited `ConversationWired`, then cancels and returns. Direct/group send, upload, Forward, P2P, Bridge, history, source-message, attachment, source-file, read-only, and reaction evidence all remain unchanged.
- Final focused evidence is Session-03 `10/10`, Session-02 `6/6`, group screen/wired `266/266`, overlay `15/15`, typed viewer/boundary `8/8`, conversation/shared/announcement viewer `81/81`, GMA-13 `1/1`, announcement reader `1/1`, Plan-234 private viewer `16/16`, protection coordinator `9/9`, and l10n `2/2`.
- Proportional family evidence is groups `1,951/1,951`, 1to1 `1,963/1,963`, feature-host-all `751/751`, and completeness `1,179/1,179`. The post-QA proof-only repair reran its exact test, the combined causal suite, five wired counterexamples, the reader sentinel, and affected static checks; unchanged production and family registrations preserve the complete fresh family results.
- All nine required mutations turned their named causal proof RED and restored exact production hashes. The final forbidden manifest exactly matches execution start at `1,502` lines / `72f86b17ea67d488cc968c7dd929ed1e0d2a71785c17db6d18cc590c9754e86f`. Formatter, script syntax, diff hygiene, scoped analyzer, compatibility-fixture analyzer, registrations, constructor census, and no-send/no-scope source checks pass.
- Fresh independent QA accepted with zero blockers at `fix_passes=1`, behavior-fix count `0`. Exactly one post-QA incremental Graphify refresh completed successfully. No full `host-all`, migration/schema/v101, device/native, Go/relay production, actual PiP, automatic send, or Session-04 implementation ran.
- The later formatting-only compatibility repair is separately accepted at `post_closure_fix_passes=1` / post-closure behavior-fix count `0`, with exact affected proof `34/34` and formatter `0 changed`. It does not alter the historical QA count, behavior, registration, production, or Graphify cadence.

## Closure Audit

- Current classification: `closed`.
- Blocking findings: none in execution or final QA.
- Accepted residuals: eight pre-existing info-level analyzer findings outside attributable additions; one earlier timing-sensitive voice cleanup failure whose exact rerun and later complete `266/266` suite passed; no unresolved test failure or pending triage remains.
- Post-closure formatting audit: `ACCEPTED` with zero blockers; the four compatibility fixtures are canonical, their exact `34/34` batch is green, and no graph refresh is attributable.
- Sessions 01-02 remain accepted and were not reopened. Plan-234 private lifecycle/viewer/native protection stays fail closed. Plan 247 overall remains implementation-in-progress until Session 04 aggregate acceptance and documentation synchronization.
- Graphify cadence is exact: one final `affected` query before QA and exactly one incremental refresh after accepted QA. No closure-doc refresh is permitted.
- Separate read-only Closure Reviewer verdict: `ACCEPTED` with zero blockers. Session 03 is closed and only Session 04 becomes execution-ready; source/breakdown ledgers are synchronized without touching final index/closure-reference artifacts in Session 03.
