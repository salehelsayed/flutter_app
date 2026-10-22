# Group C: cross-platform camera, chat, calls and contact addition

Status: **device execution NOT RUN**. These are steps for the `flutter_app`
automation owner to execute through the existing Appium MCP connection. Astra
has not discovered, installed, launched or controlled any target. Host results
are separate evidence; they do not establish native interoperability.

Source baseline: `f14f7d369646b9877bc80c71f517494628f4fe2b`, plus the test/docs
commits in the Group C packet. Record the actual candidate source, artifact
hashes, configuration and installed version before execution. A source-only
or disposable-package pass does not certify the signed production candidate.

## Ownership, setup and preservation

1. `flutter_app` resolves the currently available matrix using its normal
   discovery tools and pins every action to its discovered target. Use the
   available iPhone 13 and Pixel 6 for the explicit cross-platform legs. Do not
   use the iPhone 11. An unavailable target is `N/A (target unavailable by
   project policy)`; never substitute an invented ID or require absent hardware.
2. Reuse the existing iPhone/Pixel pairing for media, text and calls. Record a
   local, private before-state of each identity, linked contact, candidate and
   history. Keep actual IDs and conversation content out of shared mail.
3. Never uninstall, erase, reset storage or replace the iPhone 13 identity.
   Install-over only, with the existing signing/bundle identity if updating the
   real app. Prefer an already prepared disposable test package when that
   package has its own isolated pairing; do not imply that disposable results
   prove the preserved real-app pairing. Pixel installations use install-over
   (`install -r` through the existing installer), not an unsolicited data reset.
4. One automation owner per target. Use the existing device campaign setup and
   recovery guidance in `TESTING.md`; run `scripts/lease_status.py` before any
   build lease acquisition. Coordinate the expected duration of a campaign-wide
   hold with Kayan. No sudo or password prompts. Do not stop another owner.
5. Use Appium MCP for UI, native camera, permission dialogs, settings and
   lifecycle actions. Take a current accessibility tree before resolving an
   action. Existing Flutter `ValueKey`s are widget-test anchors, not assumed
   native Appium locators. Use exposed semantic identifiers and discovered
   native camera controls; no fixed coordinates or new UI framework.
6. Record and later restore the prior image quality, permission and network
   settings. Use only new synthetic test messages/media, and save their exact
   local identities for scoped cleanup. No production credentials or contacts.

## Shared Appium actions and evidence

The app exposes `chat_attach`, `chat_composer`, `chat_send` in
`lib/features/conversation/presentation/widgets/compose_area.dart`, and
`chat_call_button` in `conversation_header.dart`. On an English candidate,
the attachment sheet has **Take Photo**, **Record Video**, **Media Library**
(`conversation_wired.dart`, `app_en.arb`). Resolve the actual native camera
shutter and confirmation from its current tree, rather than assuming an OS
label. Quality choices are **Original** and **Compressed** in the existing
settings quality sheet (`image_quality_toggle.dart`).

For each action, save its timestamp, target role, before/after screenshot,
relevant accessibility nodes and candidate identity under an ignored run
directory. Record failure at its first deadline. A later retry is a distinct
attempt; never replace the first failure or stretch its deadline.

Use a unique run marker and UTF-8 captions with Arabic, accented Latin, emoji
and a newline. Keep the exact strings only in the private fixture/receipt.
Photograph a different synthetic high-detail card for each case: unique marker,
orientation arrow and fine detail that cannot be read in a thumbnail. Capture
the actual source MIME, encoded size, dimensions and orientation through the
existing fixture/diagnostic export where available. Do not assume HEIC or JPEG
from the platform or extension.

**Full-image oracle:** after the received tile becomes available, open it,
wait for the native/full viewer to decode, zoom to read the fine detail and
confirm its marker/orientation against the sender's capture. Assert the exact
caption, one received message and one attachment. Use the existing Save/Share
action on this owned synthetic item, export the full received file, decode it
with the existing host media tooling, and retain its size/dimensions/hash.
Compare against the sender's *prepared upload* file when that export exists;
Original can still strip EXIF, so comparison to raw camera bytes is incorrect.
A metadata row, preview, thumbnail, send tick or successful tap alone is not a
full-image pass. If full-file evidence cannot be obtained, report the visual
subcase and leave full-file proof incomplete.

Viewer anchors in `full_screen_typed_media_viewer.dart` include
`media_meta_caption`, `media_meta_mime`, `media_meta_dimensions` and
`media_action_*` as Flutter keys. Treat them as explanatory widget anchors;
resolve corresponding visible metadata/actions from the native tree.

**Relay-only precondition:** `flutter_app` must use its existing controlled
relay/network fixture and retain per-message native route/custody receipts
showing a relay circuit and no successful direct delivery. A VPN, Wi-Fi label,
radio state, host fake transport or TURN policy for calls does not prove the
messaging route. The debug override seam is debug-only
(`lib/core/bridge/debug_node_feature_flags.dart`); do not pretend it applies to
a release/profile artifact. If the exact candidate cannot satisfy and witness
this precondition, report `BLOCKED (relay-only precondition)` and retain the
setup evidence. Do not weaken the journey to ordinary online delivery.

## MEDIA-002: iPhone camera and caption, relay-only online

Run two independent cases, **Original** then **Compressed**:

1. Both existing paired apps are foreground and online; establish and witness
   the relay-only precondition. Set and reopen the iPhone quality sheet to
   verify the requested selection.
2. On iPhone, open the existing Pixel conversation, activate `chat_attach`,
   choose **Take Photo**, capture the case's card with the actual camera,
   confirm the capture and enter the private exact caption in `chat_composer`.
   Assert one pending image before tapping `chat_send` exactly once.
3. Within 120 seconds, Pixel has exactly one new image message with the caption.
   Apply the full-image oracle. Reopen the conversation and app normally;
   after a 10-second duplicate observation window there is still exactly one
   message and attachment with the same full content/caption.
4. PASS only if both quality cases satisfy the native capture, actual route,
   full image, caption and duplicate checks. Keep the two results separate.

## MEDIA-014: iPhone camera to offline Android, inbox catch-up

Repeat Original and Compressed with fresh cards:

1. Keep iPhone online with witnessed relay-only messaging. On Pixel, turn off
   both Wi-Fi and cellular data using Appium system settings, and verify the
   disconnected precondition. Terminate only the owned Pixel app normally.
2. Capture and send on iPhone as above. Retain actual relay inbox custody for
   the new message. A sender tick alone is insufficient. Before restoring
   Pixel connectivity, verify that no receiver delivery was observed.
3. Restore only the network settings changed by this run, relaunch the same
   Pixel package/data and wait at most 120 seconds for automatic catch-up.
   Do not tap a retry button to pass the automatic catch-up condition.
4. Apply the full-image oracle and exact caption check. Relaunch Pixel once
   more and observe 10 seconds: same message/attachment exactly once, usable
   full content and no permanently loading/thumbnail-only success.
5. For transient transport loss, preserve pending/retry evidence and the first
   deadline. Recovery must retry automatically and the UI must not report a
   completed/openable file while only a partial file exists.

## MEDIA-003: Android camera and caption to iPhone

Use the preserved pairing. Repeat the capture/send/full-image/caption oracle
with Pixel as sender and iPhone as receiver, using fresh cases at both quality
settings. Each case has a 120-second delivery/decode deadline and a 10-second
duplicate observation after reopen. Record the actual observed route; this
journey does not turn an unwitnessed route into relay-only evidence. Preserve
the iPhone identity and unrelated existing history during the reopen/cleanup.

## DC-011: text and representative media in both directions

1. On the preserved pair, send two distinct numbered Unicode/multiline texts
   from iPhone to Pixel, then two from Pixel to iPhone. Enter via
   `chat_composer` and send once per item. Within 60 seconds per send, assert
   exact text, sender/conversation, relative order and exactly one received row.
2. The successful MEDIA-002/003 image cases may supply this run's image legs
   only when their candidate/pair/run identities match. Additionally record a
   short video with a visible unique marker and a voice note with a distinct
   spoken synthetic sequence, **from each platform**.
3. Within 120 seconds per media item, open on the other platform: video plays
   through the marker and end; voice plays the exact spoken sequence through
   the end; image passes the full-image oracle. A duration label or play tap
   without decoded content/audio is not a pass. Use a local human/acoustic
   observer for content when Appium cannot measure it; mark that leg manual.
4. Relaunch both owned apps without clearing data, reopen the same conversation
   and play/open the six received media items again. Assert exact message
   counts and text order. Report each direction/type separately.

## VC-015: each platform initiates and answers

1. On the preserved pair, iPhone taps `chat_call_button`; Pixel's incoming
   screen must identify the expected caller within 30 seconds. Tap
   `call_answer`. Within the unchanged call setup deadline, both have the same
   active call and structural media readiness, not merely a ringing screen.
2. For 20 seconds exchange distinct spoken synthetic sequences in each
   direction. Retain call-bound native RTP progression in **both** directions
   and an actual local human/acoustic audibility/content observation. Appium
   Connected text and host fake RTP flags do not prove intelligible audio.
   The existing Android-only audio campaign/runner cannot certify this pair.
3. The answering Pixel taps `call_end`. Within 10 seconds both calls terminate;
   existing native diagnostics show no owned connection, microphone session or
   ongoing call service, and each history contains one matching terminal row.
4. Reverse roles: Pixel initiates, iPhone taps `call_answer`, repeat audio
   proof, and the answering iPhone ends. Require both complete directions.
   An unavailable audibility observer leaves that manual proof incomplete.
5. Semantic controls are defined in `incoming_call_screen.dart` and
   `call_controls.dart`: `call_answer`, `call_end`, `call_status`, `call_mute`,
   `call_speaker`. Do not infer audio or cleanup from control visibility alone.

## CR-009: preserve physical identity; fresh-add on isolated simulator

**Choice:** retain the existing physical pairing. Its media/text/call passes
are not evidence of a fresh add. Run the fresh-add leg on a currently available
disposable iOS simulator paired with the available Pixel test package. This
leg exercises iOS/Android application parity; it does not certify the physical
iPhone camera scanner. Never delete the physical iPhone/Pixel contact to make
the test appear fresh. Never create a simulator merely to satisfy this plan.

The actual contact-entry/Orbit route is **WAITING for UI-Update to land** under
the coordinator's ownership constraint. Host request/consent/key tests can run
now. `flutter_app` should bind the following steps to the landed route's current
Appium tree; no Orbit/navigation/notification UI patch belongs in this packet.

1. Verify no contacts/requests between the isolated simulator identity and the
   Pixel test identity. Capture the simulator's actual supported contact code
   or manual entry through existing UI. Pixel scans/adds it through the real
   supported UI, never by seeding a contact repository.
2. Before explicit acceptance, the receiver has exactly one pending request
   and no accepted linked relationship. Accept on the simulator. Wait at most
   60 seconds for reciprocal keys/linking, then send exact first text in each
   direction through the real chat composer. No keyless/plaintext fallback.
3. Repeat with fresh disposable package identities and the simulator as
   initiator, using the supported iOS contact entry. A simulator fake camera
   feed/manual entry is recorded as such, not physical camera capture.
4. Reopen both disposable packages, verify the same linked identity and one
   copy of each first message. If no suitable simulator or supported native
   entry is available, record the specific subcase N/A; the preserved physical
   pairing remains intact and does not fill this fresh-add evidence gap.

## Cleanup and reporting

End only this run's active calls/viewers/Appium sessions; restore prior network,
quality and permission settings. Remove only owned exported fixture files and
disposable simulator/test-package state using the existing approved cleanup.
On the real iPhone, do not clear history, contacts or data and never uninstall.
Verify its identity/pairing equals the private before-state. Retain first
failures, resource/setup interruptions and cleanup evidence in the ignored run
directory. Send Kayan paths and redacted per-case outcomes only.

Return per-case `PASS`, `FAIL`, `BLOCKED`, `N/A` or `NOT RUN`, with exact artifact,
route/native evidence and manual observations. Do not promote the journey
matrix from host-only coverage to an executed cross-platform pass until these
actual target/candidate obligations have been reviewed.
