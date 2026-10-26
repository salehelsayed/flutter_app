# Private media and direct notifications: MCP packet

Prepared against `60e97ee0ca08b1936a0a95666cd0b7bf1e884638` for DC-021,
DC-023 and GC-010. Execution belongs to flutter_app. Astra ran no device case.
This packet reuses typed host/native oracles and adds execution instructions;
it adds no app hook, generic driver or manual-boolean verdict. The priority
Python receipt checker does not implement these three journeys.

## Shared setup and evidence

Follow `docs/testing/TESTING.md` setup/recovery guidance and the existing
`tool/testing/selection.json` mappings. The execution owner discovers and pins
available targets, checks leases and provider readiness, and records exact
source, installed artifact/package/configuration and private actor bindings.
Use an available USB Android plus emulator for shared paired behavior. GC-010's
independence leg needs a sender and two distinct entitled receiving profiles on
actually available targets. Separate iOS-specific native protection/APNs legs.
Unavailable hardware makes only that leg N/A by project policy; missing access,
elapsed expiry time or observations on available targets remain incomplete.

Remote test relay traffic must use Hetzner; owned disposable local fixtures are
allowed. Verify the actual app/runner binding before traffic. Do not fall back
to production AWS, bypass local-fixture attestation or change a remote service.
An artifact that cannot use the permitted test binding has an execution setup
gap; source/debug results do not certify an untested signed distribution build.

Use actual Appium MCP tools for UI, consent, picker/viewer, notification taps,
settings and lifecycle. Existing campaigns own their documented native,
custody, process and ephemeral-card observations. Respect the registered
`ui_driver_reason`; end the owner's MCP session before a campaign controls a
target and wait for owned cleanup before returning to MCP. One owner per target,
one test process at a time, and no heavy launch above one-minute host load 80.

Use owned source files and disposable profiles, with fresh logical identities
for each independent send. Record accepted rendition/hash, encrypted transport
and actual receiving attachment/policy/state through existing private observers.
A badge, thumbnail, ciphertext descriptor or local seeded row does not prove
full downloaded/decrypted media. Compare accepted plaintext rendition to the
actual receiving content; ciphertext hashes have a different purpose. Do not
extract keys or add an app observation seam to complete a missing assertion.
Missing full-byte/policy/native observations stay incomplete.

Keep identities, content, native dumps, paths containing secrets and keys in
private run artifacts; mail evidence paths and redacted facts only. Retain first
failures, original deadlines and owned cleanup before a fresh attempt. Do not
edit SQL rows, accelerate clocks, clear data at persistence cuts or stop another
owner's services. An exact duplicate reuses the original authenticated logical
message through an existing replay path; a second UI send creates a new message.

## DC-021: paired private policy, download and local lifecycle

Source boundaries and existing oracles:

- `lib/core/media/private_media_policy.dart:84-92` permits a new private send
  only for one image/video without text/caption, edit or forward. Supported modes
  are protected, view-once and disappearing. Allowed disappearing durations are
  exactly 3,600, 86,400 and 604,800 seconds (`:152`): one hour, one day, one week.
  Do not author a private GIF, audio/file, multi-attachment or five-second expiry.
- `lib/features/conversation/application/private_media_action_eligibility.dart:95-119`
  permits private Reply, safe Info and Delete for me; available rows permit
  in-app opening/explicit download. Save Photos/Files, external share, internal
  forward, bookmark, shared-media exposure and PiP are denied. Safe Info fields
  are enumerated at `:232-236`; keys, nonce, private path and export handles are
  not Info. Ordinary controls must retain their supported actions.
- `lib/core/media/private_media_lifecycle_engine.dart:300-321` records the direct
  one-shot first frame as durable **viewing**. The viewer settles the exact lease
  to terminal consumption/cleanup on exit, with narrowly qualified pre-frame
  rollback (`lib/features/conversation/application/direct_private_media_viewer_controller.dart:779-808`).
  Do not expect a direct consumed column at the same instant as the first frame,
  or treat arbitrary route launch/close as a successful decoded frame.
- `production.private_media_local`, through
  `integration_test/scripts/run_production_private_media_local.dart:31-76`, uses
  prepared local rows/files. Reuse its typed lifecycle/window observations at
  that scope. `device-media` / `android.direct_media_blob_custody` is an actual
  authenticated blob-custody/restart baseline, not this private-mode matrix.
- Supporting boundaries include
  `integration_test/direct_private_media_lifecycle_sqlcipher_proof_test.dart`,
  `integration_test/direct_private_media_platform_protection_proof_test.dart`,
  `test/features/conversation/integration/private_media_restart_replay_test.dart`,
  `private_media_committed_pending_cleanup_recovery_test.dart` in that directory,
  and `test/features/conversation/application/private_media_action_eligibility_test.dart`.
  Their fakes, local fixture provenance and assertions remain explicit.

Execute with two owned peers A/B and reverse sending/receiving roles. Use each
mode with fresh real media; include a fully decoded image and a playable short
video across the matrix. If a full image-by-video-by-mode cross product is
claimed, execute every corresponding row instead of inferring it. Keep an
ordinary image/video control and an unopened private sibling on the receiver.

| Actual selected mode | Required receiving behavior |
| --- | --- |
| Protected | Policy survives encrypted send/download; protected in-app content opens fully, closes and remains reopenable after cold restart. It is not a view-once budget. |
| View-once | Unopened cold reopen remains eligible; actual first frame enters the current direct lease's viewing state. Close/settlement commits consumption and owned cleanup; later open/replay/restart cannot resurrect it. |
| Disappearing | The actual persisted supported deadline governs opening and expiry; no open, retry or duplicate grants a new lifetime. Expiry removes access and performs terminal owned cleanup, including after cold restart. |

1. Establish ordinary full-media exchange, then select the actual private mode
   in the shipped composer and send once through the normal encrypted path.
   Verify each receiver's accepted policy and real downloaded/decrypted content
   under the exact message/attachment identity. Fresh receiver state must not
   have that private row/file preinstalled. A local protected-viewer fixture is
   useful separately but cannot fill this wire assertion.
2. Before first opening a view-once sibling, cold-restart the receiving process
   without clearing its profile. Confirm that row is still available and its
   policy did not become ordinary. Open a different view-once row and bind the
   actual decoded first frame to its exact opening lease. Observe close and
   persisted settlement/cleanup, then repeat the open attempt after process
   restart and exact replay. It must remain terminal with no thumbnail, stale
   private preview or playable bytes exposed by the app. A narrowly qualified
   pre-frame rollback is supporting host coverage, not a rule that every
   pre-frame user close must restore availability.
3. For protected rows, prove native route/window protection using existing typed
   platform evidence while actual content is visible, including an owned
   background/resume transition. Close and reopen after restart; verify content
   remains usable and ordinary siblings are unaffected. Do not weaken the
   protected window to obtain a screenshot or claim universal OS capture
   prevention from one platform's window flag.
4. For disappearing rows, record the actual persisted deadline and before/after
   samples. Use the supported one-hour option for the shortest new-send native
   expiry leg. Wait for real expiry, or use an owned genuinely aged wire send
   with original source/artifact/time provenance and limit that evidence to
   those identities. Do not shorten the duration, seed an expired row or change
   clocks. A quick smoke before expiry leaves this leg incomplete. Prove
   available-before/terminal-after behavior both on an active protected viewer
   and on a separate unopened row recovered after expiry. Observe the existing
   cleanup/recovery owner; do not manually drain first and call it natural
   recovery. Host fake-clock tests cover other exact timer boundaries only.
5. On available, terminal and applicable unsupported-policy host rows, exercise
   the actual action policy above. Verify forbidden export/library/PiP paths
   are unavailable and cannot publish private bytes through an existing tested
   dispatch path. Safe Info has only its allowed metadata. Keep unsupported
   wire/version/shape counterexamples in existing host fixtures; this packet
   adds no native malformed-message injector. Test ordinary positive actions
   through the same UI so a broken menu cannot masquerade as private protection.
6. Verify existing owned cleanup observations for terminal plaintext,
   ciphertext, private preview/thumbnail and attachment ownership. Preserve
   files still legitimately referenced by unrelated owners. Cold reopen and
   exact replay must not reacquire pixels or a fresh deadline. Protected and
   ordinary siblings remain usable; a subsequent fresh private send succeeds.

The claim is local lifecycle enforcement. Remote revocation, account-wide
consumption and all-device one-shot synchronization are not established.

## DC-023: real OS card, exact routing, unread and privacy

Reuse these complementary boundaries without merging their claims:

- `test/features/conversation/presentation/screens/direct_notification_policy_lifecycle_test.dart:49-171`
  joins real SQL unread/read/reopen and exact logical replay to fake native cards
  and registry storage. Its channel-blocked case (`:175-200`) still emits one
  request on `mknoon_messages`; OS denial is outside the fake. Its private-media
  case (`:204`) proves generic Dart preview, not actual OS publication/full bytes.
- `production.notification_open`, through
  `integration_test/scripts/run_production_notification_open.dart` and
  `tool/sims/production_notification_open_criteria.dart:51-61`, requires the exact
  warm-other-chat, cold-start and same-peer rows. Its native card, provider,
  SQL/read and route/lifecycle observations are reusable. That cold-start kills
  the process **after delivery**; killed-before-send is a separate assertion.
- `production.notification_sound`, through
  `integration_test/scripts/run_production_notification_sound.dart` and
  `tool/sims/production_notification_sound_criteria.dart`, retains the exact
  native first-alert/OS-disposition and suppression windows. Capture the first
  audible native card before a later same-ID silent hydration update. A final
  screenshot or Dart publication request alone cannot establish that boundary;
  an OS audible disposition alone is not acoustic speaker proof.
- `device-notifications-android` / `notifications.android_payload_campaign`
  supplies its killed-before-send, duplicate/custody, permission/channel and
  restoration cases. `device-notifications-ios` /
  `notifications.ios_payload_fast_path` supplies its APNs/NSE native boundary.
  Use their actual package/configuration/provider requirements; a local server
  and UI tap cannot substitute for accepted FCM/APNs plus native ingress.
- `integration_test/direct_notification_durability_sqlcipher_proof_test.dart`,
  `test/integration/live_direct_notification_integration_test.dart` and
  `test/integration/chat_notification_dedupe_integration_test.dart` support
  persistence/deduplication at their documented native-substitute boundaries.

Use owned receiver R and distinct trusted senders A/B. Establish actual allowed
notification permission/channel settings and record R's initial unread/card and
navigation state privately. Preserve exact campaign deadlines; use fresh sends
only for independent rows and exact logical replay for duplicates.

1. With R backgrounded from B's mounted chat, send real encrypted A1 and B1.
   Join provider acceptance/native ingress, committed rows, actual first OS
   cards and per-peer unread deltas. Tap A's actual native card through MCP.
   Verify the exact A route, message identity, one read transition and cleared
   A card/unread; B remains unread and its correct card survives. Preserve the
   other mounted route under the existing warm-other-chat oracle.
2. Run cold-after-delivery and same-peer tap with the reviewed open campaign's
   exact assertions. Same-peer must not push/replace another route. If claiming
   killed-before-send, separately execute the existing payload campaign's real
   ingress/recovery case. Record actual process incarnation and plugin initial
   payload provenance; clearing app data is not a cold-open test.
3. Replay an original authenticated unread message, then replay it again after
   read and after cold reopen. Verify one logical row, no extra unread increment
   and no second user alert/card identity or resurrection of the read card.
   A conversation card may legitimately update for another **new** message;
   card generation and exact logical identity, rather than one-card-per-message,
   decide duplicate correctness. Do not count a permitted same-ID silent update
   as a second audible notification.
4. While R visibly reads A in the foreground, deliver fresh A2 and B2. Verify
   the current same-chat suppression/read rule for A and the positive B alert
   and unread delta. Leave A and deliver A3 to prove alerts still work. Use
   `lib/features/push/application/show_notification_use_case.dart:72-78` and the
   current visibility owner, not a manually set legacy active-peer flag.
5. Exercise shipped **OS Messages-channel mute/block**, separately from app-wide
   notification denial, and retain persisted unread/message custody across
   receiver reopen. Confirm no disallowed native alert and no alternate-channel
   bypass, including forced-silent recovery. Restore the owned channel/access
   setting and prove a fresh allowed message alerts again; use the existing
   campaign if claiming replay/drain behavior on regrant. The current direct
   contact model has no per-chat mute field, and the inspected direct UI contains
   no notification-mute control; do not invent one or borrow group mute. If the
   execution candidate adds such a setting, inspect its actual contract and add
   distinct toggle/reopen observations before claiming it. A Dart request while
   the OS blocks the channel is not itself a failure.
6. Send actual eligible private media and observe its **first native** preview,
   later same-card updates, lock-screen presentation under the owned OS preview
   setting, tap and cold reopen. Body/copy follows the shipped generic private
   template; media pixels, private paths, keys, nonce or serialized payload must
   never become preview content. A permitted verified contact display name is
   not automatically a privacy failure. Bind this notification to DC-021's
   actual received policy/content; notification descriptor-only sound fixtures
   cannot prove media download. On iOS, retain real APNs/NSE/extension evidence
   and actual OS preview settings separately from Android channel claims.
7. Close only owned observers/sessions, restore settings/navigation and confirm
   subsequent ordinary alerts and per-peer unread remain correct. Missing first
   card, exact route/read, provider or native privacy evidence leaves the
   corresponding assertion incomplete; host PASS does not supply it.

## GC-010: encrypted fanout and each receiver's private lifecycle

Group policy is not the direct wire schema or action allowlist:

- `lib/features/groups/domain/models/group_private_media_policy.dart:57-66`
  permits one image/video with no caption/text, quote, edit or forward.
  Protected-only is lifecycle `standard` plus protection, view-once is wire
  `viewOnce`, and disappearing uses the same one-hour/day/week durations.
  All four wire fields at `:141-146` must survive: `mediaPolicyVersion`,
  `mediaLifecycle`, `mediaDurationSeconds`, `mediaProtected`. The duration is
  explicitly null for protected-only/view-once. Do not substitute direct
  `privateMedia`/`view_once` encoding or infer policy from a local menu badge.
- `lib/features/groups/application/group_private_media_lifecycle.dart:178-234`
  consumes group view-once at the actual first frame, revalidates the exact
  grant, and cleans terminal content on settlement. This differs from direct's
  durable viewing-then-settlement transition; observations must use the actual
  lane. Consumption/expiry is recipient-local, not one global fanout budget.
- `lib/features/groups/application/group_received_media_action_policy.dart:32-45`
  returns no received-media actions for private/unsupported policies.
  `lib/features/groups/presentation/screens/group_conversation_wired.dart:6582-6625`
  applies it to viewer actions, alongside `group_media_forward_policy.dart`.
  Verify denied Save/Share/Info/Delete/Reply/Forward on that **media-action
  surface**; do not copy direct's safe Info/Reply/Delete allowlist or infer that
  every outer message deletion feature is prohibited. Ordinary received-media
  controls retain the actual group-type/write/integrity restrictions.
- Reuse `device-group-media` / `groups.media_send_reliability` for its ordinary
  encrypted custody/recovery observations. Its typed receiver cut is not the
  whole private matrix. `integration_test/group_private_media_platform_proof_test.dart`
  uses local/in-memory fixtures; its native observations do not prove fanout.
  `integration_test/group_private_media_lifecycle_db_proof_test.dart`,
  `test/features/groups/application/group_private_media_lifecycle_test.dart`,
  `test/features/groups/integration/group_private_media_payload_roundtrip_test.dart`,
  `group_private_media_crash_recovery_test.dart`,
  `group_private_media_cleanup_replay_test.dart` in that directory and
  `test/features/groups/presentation/group_private_media_capabilities_test.dart`
  retain their existing database, recovery, policy and fake-platform scope.

Use a stable owned authorized group with sender S and distinct entitled receivers
B/C. Confirm real membership and each receiver's actual encrypted delivery and
download independently. Keep ordinary image/video and protected siblings as
controls. New-member entitlement/removal is a separate journey; do not mutate
the roster to simulate recipient-local consumption.

1. Send fresh protected-only, view-once and disappearing media through the real
   group composer/fanout path. Include real image and short playable video across
   the matrix, with full cross-product execution only if that coverage is claimed.
   At B and C, bind the accepted sender rendition, group/message/attachment,
   actual decrypted content and exact group policy. Neither receiver may rely
   on a preinstalled private row or sender-local file. Verify current authorized
   opening and native route protection using existing owned observers.
2. Leave C's actual received view-once unopened. Cold-restart C and confirm it
   remains eligible. At B observe the exact first decoded frame, B's durable
   consumption and close/cleanup. Restart B, replay the original authenticated
   group message, and show it cannot reopen or re-download into availability.
   C's independent copy remains unopened/eligible and can then be consumed by
   C's own first frame/settlement. B stays terminal. Retain separate per-recipient
   receipts; one receiver's result or sender status cannot stand in for another.
3. For protected-only, close/restart/reopen at each receiver without consumption.
   Apply actual group media-action and PiP restrictions while keeping ordinary
   controls functional. Use the current native protection semantics per platform;
   do not disable protection for screenshots or claim another OS from this proof.
4. For disappearing, record each receiver's real persisted deadline; do not
   assume simultaneous local expiry or refresh lifetime on fanout retry/replay.
   Use the actual supported one-hour minimum, or a properly provenance-bound aged
   wire send as in DC-021. Observe before/after expiry and natural cold recovery
   independently at B/C, including owned byte/thumbnail cleanup and no reopening.
   Host fake-clock expiry is supporting causal coverage, not elapsed native time.
5. Preserve unrelated rows/files and protected/ordinary siblings, including any
   legitimate shared ownership. Prove a later fresh ordinary/private fanout still
   works. Keep each available receiver/platform result separate; absent full
   content, expiry, action, native protection or cleanup observations remain
   incomplete. No remote revocation or account-wide consumption is claimed.
