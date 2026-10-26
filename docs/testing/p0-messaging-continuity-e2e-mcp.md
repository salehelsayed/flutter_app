# P0 messaging, media and account continuity: MCP packet

Prepared against `7603e691066902c7448676b846e9a227ab22bc48` after the
2026-10-26 catalog audit. Scope: DC-008, DC-014, DC-019, GC-003 and GC-006.
The other named messaging entries already have complete reviewed runners; reuse
them. Execution belongs to flutter_app. Astra ran no device case. This packet
adds no application fault seam, generic UI driver or manual-boolean verdict.
The priority Python receipt checker does not implement these five journeys.

## Shared setup and evidence

Follow `docs/testing/TESTING.md` setup/recovery guidance and the existing
`tool/testing/selection.json` mappings. The execution owner discovers and pins
the available targets, reviews setup and leases, and retains exact source,
artifact/package/configuration and private actor bindings. Shared behavior uses
an available USB Android plus emulator by default; group/transfer cases add only
actually available owned roles. Use iOS separately for an explicit platform
claim. An unavailable exact topology is N/A for that leg; missing access or
observations on an available target remain incomplete.

Remote test relays must be Hetzner; owned local disposable fixtures are allowed.
Verify the actual app/runner binding before traffic. Never let an unset override
fall back to production AWS, bypass a local-fixture attestation, or deploy/change
a remote relay. A signed production artifact which cannot use this test binding
cannot be exercised in this lane. These source/debug proofs do not certify it.

Use actual Appium MCP tools for setup, consent, picker/viewer, ordinary navigation
and lifecycle. Reuse existing native campaigns for exact custody, file, process
and protocol observations. Their registered `ui_driver_reason` explains the
non-UI assertions; end the owner's MCP session before a campaign controls its
targets and wait for cleanup before resuming MCP. One owner per target and one
test process at a time; defer heavy checks above one-minute host load 80.

Use disposable accounts/profiles and owned fixtures, never personal history or
an occupied migration destination. Do not clear data at a persistence cut,
rewrite rows into a desired result, alter clocks or stop foreign services.
Retain first failures, original deadlines and owned cleanup before another run.

Each case records actual submission, accepted logical identity, sender/receiver
roles, transport/custody where required, first UI observation, persisted state,
restart incarnation and raw evidence paths. Keep content, identities, keys and
native dumps private; mail paths and redacted facts only. Compare complete
accepted content/file bytes privately, not a shortened label or thumbnail.
Missing native byte/capture/observability evidence stays incomplete.

## DC-008: real paired media, both directions and reopen

Reuse these existing boundaries:

- `device-media` / `android.direct_media_blob_custody`, through
  `integration_test/scripts/run_direct_media_blob_custody_sims.dart`, proves its
  authenticated voice-blob custody/restart case. It is not every picker/viewer.
- `test/features/conversation/integration/one_to_one_media_encryption_round_trip_test.dart`
  and `media_attachment_flow_test.dart` in that directory supply host transport,
  encryption and attachment controls, with their native substitutes retained.
- `production.private_media_local` and
  `integration_test/scripts/run_production_private_media_local.dart:31-76` use
  locally prepared private rows/files. Reuse their lifecycle oracle, never label
  those fixtures as remotely received bytes.
- The reviewed `priority-e2e-mcp-execution.md` DC-011 steps and
  `priority-e2e-camera-permission-mcp.md` actions cover real media UI. The camera
  helper's send action already sends once; do not send it again.

Execute with fresh media identities for each row and reverse A/B:

| Actual send | Required receiving observation |
| --- | --- |
| Ordinary photo with caption | Full correct image and exact accepted caption, not a thumbnail; bind byte/hash evidence to the actual attachment. |
| Short video | Full decoded moving content and usable actual playback; a generated thumbnail or advancing timer is insufficient. |
| Supported file, for example an owned PDF | Correct complete file bytes/type/name and usable supported opening, not merely a download badge. |
| Representative supported private media, using protected/reopenable mode | The received attachment retains the selected policy and native protected viewer behavior; no ordinary-media downgrade. |

1. Record owned source fixtures and current per-type limits. Choose through the
   real shipped picker/camera/file UI, including an actual supported file. If
   using a camera, capture a new image through the existing camera actions;
   synthetic bytes cannot stand in for that capture. Establish actual two-peer
   delivery and each receiving open above.
2. Bind source bytes, accepted message/attachment identity, destination attachment
   and decoded observation. Compare decrypted/full content through existing
   owned file/custody observers. Do not compare ciphertext bytes to plaintext
   or require a transcoded camera image to match the original camera encoding;
   bind the actual accepted upload rendition instead.
3. Close viewers and restart both owned processes without clearing identities.
   Reopen each received ordinary/protected item: same logical row, full usable
   content and exact caption, no second attachment/send or lost local owner.
   Show a later live send still works. Preserve unrelated history and files.
4. For the private row, verify the source-defined protected-viewer/window policy
   through existing native evidence. Protected media is reopenable; do not
   consume it as view-once. If additional private modes are claimed, observe
   their actual first-frame/close/expiry contract separately. The complete
   protected/view-once/disappearing lifecycle matrix remains DC-021; this row
   does not claim remote revocation or account-wide consumption.

Host widgets, cached images and local private fixtures remain supporting results.
Unavailable exact-file or native-viewer evidence cannot become a native PASS.

## DC-014: exact Unicode content and visible direction on both peers

Reuse the four fixtures and actual `LetterCard` assertions in
`7603e6910:test/features/conversation/integration/bidi_transport_rendering_test.dart:12-99`.
That host file exists on the preparation branch but was absent on audited main
`422c3f4b2`; cite its revision and do not claim it ran on the execution checkout.
The native case below is additional transport/UI proof.

Use Arabic, Arabic-first mixed text, emoji/Latin-first mixed text, and the existing
supported long fixture. Expected directions are RTL, RTL, LTR and RTL. The long
fixture repeats its mixed phrase 80 times; current
`lib/core/utils/text_sanitizer.dart` defines the 10,000-character message bound.
If that source policy changes, select an accepted fixture within the new bound;
do not silently truncate a rejected input to call the original message delivered.

1. Submit each fixture through real compose UI A-to-B, then B-to-A. Retain input
   privately and derive expected accepted text using the actual current
   `sanitizeMessageText` policy. Safe Unicode and emoji joins must survive;
   source-defined removal of forbidden controls is not transport corruption.
2. Compare complete accepted sender and receiver text and logical identity through
   existing exact-row observations. Retain a digest/length plus private original
   text; length alone is insufficient. Require one receiver row for each send.
3. On both real screens, inspect the actual message bubble and all long-text
   lines through scrolling. Observe the expected first-strong direction,
   Arabic/Latin word ordering, emoji joins and absence of clipped/missing content.
   Keep screenshots/tree evidence bound to that message. A host `RichText`
   direction assertion or a matching database string alone cannot establish
   the native visible rendering; pixel-identical fonts are not required.
4. Reopen the conversations without clearing data and compare the same accepted
   rows/content and rendered direction again. Report the exact platform/rendition
   observed; an English-only short send does not fill the long/Arabic cases.

## DC-019: transferred account, retained content and fresh peer exchange

This is conditional on account transfer being exposed/affected. Use owned source
S, empty disposable destination D and an existing peer P; add only actually
available owned group roles. It is a Move Account test, distinct from RG-001's
in-place store upgrade. Preserve actual source/destination identity ownership
according to the current transfer protocol; invent no new key-rotation rule.

Existing component controls include:

- `test/features/account_migration/application/account_migration_end_to_end_test.dart`
  and `account_migration_post_import_behavior_test.dart` in that directory;
- `test/features/migration/account_migration_full_transfer_test.dart`;
- `integration_test/account_migration_group_media_durability_simulator_test.dart`
  and `account_migration_local_transfer_timeout_simulator_test.dart` in that
  directory. Their SQLCipher/file/fake-store assertions are not the complete
  app-to-app-and-peer journey.

Retain the scoped TRANSFER-011 receiver proof separately. Silent migrated audio
and a scoped simulator import cannot establish this whole continuity row.

1. Through ordinary UI, establish S/P direct history and an entitled group.
   Seed representative received/sent text, ordinary image/video/file and a
   usable voice note with known private content/byte witnesses. Record logical
   rows, membership/keys at their existing observer boundary, attachment owners
   and unrelated state. Confirm all source items open before transferring.
2. Start Move Account through the supported source/destination UI and actual
   transfer/verification flow. D must be the intended empty owned destination;
   never replace a personal account. Observe successful import and the actual
   source cutover outcome. A copied database or injected completed receipt is
   not the transfer. Do not expose any transfer secret or QR payload in mail.
3. Cold-reopen D without clearing data. With D's networking temporarily unavailable
   through an existing owned operation, open retained direct/group content.
   Require actual full image/video/file and intelligible voice content, correct
   captions/history and attachment ownership. This prevents a relay refetch
   from concealing a missing imported local file. Restore networking afterward.
4. From D and P, exchange a fresh unique direct message both ways and fresh group
   text/media from the migrated account and an existing member. Observe each
   entitled receiver, current authority, original conversation/group identity
   and no duplicate imported rows. Reopen D once more and keep both imported
   and fresh content. Do not require source S to keep using authority which the
   current transfer contract retires.
5. Inspect owned cleanup and unrelated history; preserve any first import/open/
   peer failure. Missing-original recovery is a separate TRANSFER-011 gap,
   not silently certified here by a successful happy-path import.

## GC-003: natural offline/background group recovery

Reuse relay/SQL controls in
`test/features/groups/integration/group_resume_recovery_test.dart` and the
existing group catalog custody/replay scenarios. Its host case near line 1922
explicitly supplies a drain; IR-001 also drains. Neither is a natural OS-resume
observation. The existing `production.foreground_group_push` campaign supplies
its narrower push/busy-guard protocol checks and is not a replacement UI driver.

1. Establish an owned authorized group and baseline exact rows. In separate
   cases, leave receiver R genuinely offline, background it through the OS,
   and terminate its owned process. Keep another member as a live delivery
   control. Send numbered exact messages and retain real relay-custody identity
   where R is offline. Stay within current inbox capacity/retention and record
   actual dwell; RG-003's multi-day/page breadth is separate.
2. Use only the normal supported trigger: real foreground/relaunch, or actual
   eligible push when configured. Before any manual inbox drain, generic
   protocol probe or force-rejoin command, observe the natural UI catching up.
   Capture the first complete exact transcript and its time. A diagnostic which
   drains first cannot establish causality even if it later reads correct rows.
3. Then use existing row observers to bind all messages, order, group/author/key
   epoch and exactly-once receiver rows to their accepted source. Restart R
   again and show replay adds no duplicate. A fresh live message still arrives
   after recovery and the control member remains usable.
4. Keep foreground recovery and push recovery separate. A local fixture without
   configured native push may establish the foreground leg, not real FCM/APNs.
   Force-stop/force-quit suppresses wake differently from OS termination; name
   the actual cut and do not expect provider delivery in a suppressed state.

## GC-006: each entitled member gets usable media after receiver interruption

Reuse registered `device-group-media` / `groups.media_send_reliability` and its
existing controller/typed criteria. In
`integration_test/scripts/android_group_media_reliability_controller.dart`,
TC-269-19 kills the owned receiver at its existing JPEG post-claim/pre-commit
barrier and relaunches without navigating to the group. Preserve that exact
cut; do not call it arbitrary mid-network-byte interruption. Native MP4 thumbnail
or voice-player readiness does not establish full playback content.

1. On an owned group with at least sender S and two entitled receivers, send
   an actual image/caption, short video and voice note through supported UI.
   Bind accepted rendition bytes and every actual recipient/attachment. Open
   the full correct image, video content and intelligible voice on each receiver;
   no sender-only status or one-member thumbnail can fill another recipient.
2. Reuse the existing attested receiver-interruption campaign for its exact
   checkpoint and same-byte/restart proof. Retain its own candidate, artifact,
   actor/group and typed report bindings. Additional MCP playback observations
   must be linked to the actual messages they open; never join unrelated run
   identities into one fabricated interrupted-transfer result. If same-message
   full-content observation is unavailable, preserve the component result and
   keep that interrupted-content assertion incomplete.
3. Reopen receivers, compare original logical IDs/attachment counts and full
   bytes, then open content again. No duplicate attachment or lost local file.
   Keep active receivers and unrelated conversations intact during the cut.
4. Reuse `production.group_new_member_media` for its supported admission/media
   boundary, then observe actual post-join wire delivery/opening through MCP.
   Honor current pre-admission entitlement; do not promise old-history backfill.
   `integration_test/group_new_member_media_simulator_proof_test.dart` constructs
   local fixtures and widgets and cannot supply that wire proof by itself.

Record one scoped verdict per case/platform/recipient. Existing typed native
reports remain authoritative for their implemented predicates; MCP observations
add the missing visible/content boundary. Missing cut, natural-trigger, byte,
audible or per-recipient evidence remains incomplete, never a release PASS.
