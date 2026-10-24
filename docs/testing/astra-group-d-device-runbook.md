# Group D: Android durability, permission recovery and migrated media

Status: **device execution NOT RUN by Astra**. `flutter_app` owns execution
through its existing Appium MCP and production campaign adapters. These steps
do not create a new automation framework. Host SQL reopen, fake permissions or
host image decoding are separate supporting evidence, not actual Android kills,
OS settings, native crypto, relay delivery or video/voice/PDF playback.

## Setup and shared oracles

Use the currently available **Pixel 6 plus headless Android emulator**, pinned
to discovered IDs by `flutter_app`. Do not create a hardware/version requirement
outside the available matrix. An unavailable target is N/A under project policy.
Astra must not discover/control targets. No iPhone or iPhone 11 is used here.

Use existing approved disposable package IDs and synthetic test identities so
the preserved Group C/real-app pairing is untouched. Pixel installs are
install-over (`-r` through the existing installer); do not clear an unrelated
package or erase its data. Record exact source, package/artifact hashes,
configuration, installed candidate and local target-role bindings.

Run the existing campaign setup checks and honor exclusive device ownership.
Check `scripts/lease_status.py` before every build/wrapper acquire; Kayan's
queue/host holds remain binding even during a FREE gap. No sudo. Record expected
duration before holding a lease for a whole campaign. A setup pass is not a
scenario pass. Never kill another owner's app process, host service or session.

Use Appium MCP for UI, system settings, termination and relaunch. Resolve the
current accessibility tree before each action. Direct chat exposes
`chat_composer`, `chat_send`, `chat_attach`; camera/gallery choices are **Take
Photo** / **Media Library** on the English candidate. Flutter `ValueKey`s are
not assumed Appium locators. Do not patch Orbit/navigation/notification UI; if
the current test route needs UI-Update changes, mark that route WAITING and
continue independent cases.

Keep exact synthetic transcripts, internal message/group IDs and native logs
in the private run directory. Mail only paths, counts, hashes and redacted
facts. Every first failure/setup miss/cleanup result remains visible. A retry
uses a fresh attempt with the original assertion and deadline.

For an exact transcript, use the existing campaign's full conversation
observation when available. Otherwise scroll the complete run-specific history
through Appium, retain overlapping ordered viewports and reconstruct every
numbered row, including duplicates. A screenshot of the final page, a count of
send taps, a tail sample or a set that discards duplicates is insufficient.
Keep full row IDs/counts from an existing native observation adapter when it
provides them; do not invent a new DB/UI harness or seed expected result rows.
If the complete order/count cannot be observed, leave that oracle incomplete.

For a kill checkpoint, use only the owned disposable package. Appium terminate
must actually stop the old process; retain the existing campaign's process-death
receipt or owner-pinned process observation and fresh launch identity. Returning
home/backgrounding or rebuilding a Dart widget does not prove a process kill.
Do not infer durable acceptance from a tap, spinner or local optimistic bubble.

## DC-002: 100 numbered texts, both peers restarted

1. Establish authorized disposable Pixel/emulator contacts using the existing
   real fixture/UI. Record empty run-specific history on both. Prepare a local
   expected sequence with unique run marker and numbers 001–100; alternate
   sender roles so both endpoints exercise sending and receiving.
2. Enter/send one numbered text at a time through the composer. Within 60
   seconds of each send, require the corresponding received row with exact
   text/sender and the intended order. Keep all 100 expected rows in a local
   list, not a set.
3. At checkpoints 025, 050, 075 and 100, retain the accepted sender/receiver
   evidence, terminate **both** owned packages, verify the old processes ended,
   and relaunch the same packages/data. Within 120 seconds, reconstruct the
   complete prefix on both endpoints and compare it exactly against the
   expected prefix, with each row occurring once.
4. At checkpoint 050, make the receiver genuinely offline for the next numbered
   item. Require relay custody while it is offline, then restore connectivity
   and relaunch to prove catch-up before continuing the numbered sequence.
5. After 100, relaunch both once more, allow a 10-second replay/settlement window
   and compare the full transcript: numbers exactly 001–100 in order, 100 rows,
   correct sender direction and no loss/duplication. Passing only 5/10 receipts
   or allowing a percentage of deliveries does not pass this case.

## GC-005: accepted group text and membership at process-death cuts

Reuse the existing production group setup/process-death harness
`integration_test/scripts/run_production_group_process_death.dart` for the
membership protocol/native observations. Its existing add/removal/re-add cuts
do not substitute for the following accepted-text sender cut.

1. Create/accept an owned two-peer test group and establish the exact member
   roles/key epoch on both. Use the real existing setup, not direct result-row
   insertion. Stage a unique run-specific text while the recipient is offline.
2. Observe the actual sender's durable accepted inbox/custody receipt for that
   exact message. Record group/message identity and `inboxStored`/equivalent
   native acceptance witness. Before any receiver delivery, terminate the
   sender package and verify process death. Missing checkpoint evidence is a
   setup blocker; an arbitrary sleep does not establish this cut.
3. Relaunch sender, reconnect/relaunch recipient, and within 120 seconds assert
   the exact same message identity/text appears once. Verify the sender's
   accepted text and group/member/key state survive. Relaunch both and observe
   another 10 seconds for replay; still one copy.
4. Run the existing membership add, removal and re-add cuts. After each durable
   mutation, kill/reopen the owning package and verify the actual current
   roster/role/key epoch. Removal must remain effective before re-add; fresh
   re-add must not restore revoked old membership authority or stale-key access.
   An old message legitimately retained in history is not a new membership.
5. Preserve the accepted-text result separately from membership-only results.
   The host current-SQL test models both-graph reopen; it is not native kill,
   live relay acceptance or complete revoked-key isolation evidence.

## MEDIA-018: interruption during upload and download

Required cuts: sender while uploading, receiver while downloading. Use a real
image with a unique visible marker and fine detail; repeat with a representative
video when the existing fixture can witness the same cuts. Keep source media
within the candidate's actual supported size policy. Save exact source/prepared
hashes, dimensions/duration and captions locally.

1. Use the existing controlled media/relay fixture to make a transfer long
   enough to witness the cut. Require native progress with
   `0 < transferredBytes < totalBytes` or an equivalent existing writer/relay
   checkpoint for that exact attachment. A spinner or MEDIA_UPLOAD_START event
   alone is insufficient. If the cut is missed, retain that attempt and use a
   fresh owned fixture; do not pretend completion was a mid-transfer kill.
2. Terminate the selected owned package at the witnessed cut and verify process
   death. Preserve its data and any partial file; do not manually delete the
   partial, mark a row done or inject a successful download.
3. Relaunch the same package/data and restore only connectivity changed by the
   run. Accepted durable work must automatically retry within 120 seconds.
   While incomplete, the UI remains pending/retrying/unavailable truthfully;
   a thumbnail or partial local file must not manufacture completed/openable
   original content. Record any actual recovery tap as a separate manual case,
   not automatic retry success.
4. Receiver opens the full image and reads its fine-detail marker/caption;
   export only the owned received item with existing Save/Share and decode/hash
   its complete file. Compare to the prepared upload, not raw pre-compression
   camera bytes. Video must play its distinct marker and content through the
   end; metadata duration/play-button visibility alone is insufficient.
5. Reopen both packages and wait 10 seconds: one message/attachment, same full
   usable content, exact caption, no permanently loading or thumbnail-only
   success. Preserve checksum/truncation failures and first deadlines.
6. Host scopes differ: the ordinary receiver test uses the default legacy lane,
   real SQLite/files, a retained ciphertext prefix and a recreated listener;
   the existing committed-share sender recovery test explicitly enables a
   strict-custody cohort. Neither certifies all native sender/receiver cuts or
   legacy sender durability. Report each cohort/cut separately.

## MEDIA-010 and CONTACT-001: deny, grant, retry

Use fresh disposable test-package permission state, not a real identity reset.
Record prior permissions and restore them at cleanup. If a target's actual
picker exposes no photo-authorization boundary, record that boundary N/A and
test cancellation separately; a cancelled picker is not an OS denial.

MEDIA-010, separately for camera and photos:

1. Enter a unique unsent draft and record its text/attachments and zero outgoing
   result count. Deny the actual OS authorization, attempt **Take Photo** or
   **Media Library**, and return to the composer.
2. Require visible truthful failure/recovery feedback, the unchanged draft,
   no invented attachment/upload/send, and no duplicate existing attachment.
   Camera feedback is known host finding **ASTRA-D-1**, routed for a post-126
   fix. Record the current candidate's outcome honestly; do not count the host
   KNOWN GAP skip as a device pass or silently substitute a fixed candidate.
3. Grant access through Appium system Settings, return without clearing data,
   retry the intended pick/capture, and assert exactly one staged valid image.
   Tap Send once. Within 120 seconds, recipient opens one full correct image
   with the retained exact draft/caption. Reopen and observe 10 seconds: no
   second upload/send/message and no lost draft content.

CONTACT-001:

1. Record no contact or pending request for the new disposable peer. Open the
   real scanner route and close it before a code is reported. Verify previous
   surface, zero added contacts, zero sent/pending requests and preserved draft.
2. Deny actual camera permission, reopen the scanner, require truthful camera
   failure and zero contact/request effects. Close it; grant permission in
   Settings, then reopen and scan a fresh supported code.
3. Complete the normal explicit consent/request flow exactly once; repeated
   camera detections must not add/send duplicates. Reopen to verify one linked
   relationship and first exact message. If root navigation/Orbit binding needs
   UI-Update, mark that route WAITING and preserve the independent scanner
   cancel/denial evidence. A fake admission callback is only host support.

## TRANSFER-011: migrated content really opens on receiver

1. Use only disposable source/receiver accounts/packages. Before Move Account,
   the source has valid received photo, video, voice and PDF fixtures with known
   local content/captions. Open/play each on source and retain its prepared/full
   file hash and content oracle. Generated `.bin` data or a renamed magic prefix
   is not a media fixture. An existing receive-only PDF fixture can be used
   without claiming a default-off document-authoring feature is enabled.
2. Execute the existing actual Move Account workflow/fixture through Appium,
   including its supported pairing entry, native transfer/import and authority
   cutover. A debug QR paste is recorded as fixture entry, not camera scanning
   or signed-release coverage. Preserve transfer first failures and exact
   candidate/configuration. Never point this destructive account move at the
   preserved Group C/real-app identity.
3. From the receiver's migrated conversation, open each authoritative attachment:
   image fully decodes with correct content/orientation/caption; video and voice
   play the known content through the end; PDF opens in the available actual
   document viewer and renders the known page/text. Retain native screenshots,
   content/audio observations and owned full-file hash/path receipts.
4. Repeat after terminating/relaunching the receiver. Require the same media,
   captions and message identities/counts. No path back to the source app/cache,
   no test-only placeholder renderer and no silent re-download can substitute
   for the migrated full file. A missing viewer/original remains explicitly
   incomplete, with truthful failure/retry behavior.
5. The extended host end-to-end chain now includes a real portrait JPEG and
   host Flutter codec/pixel/caption assertions after actual loopback transfer
   and import. Native mobile video/voice/PDF/viewer/authority/keychain proof
   remains NOT RUN; host photo decode does not pass the complete journey.

## Cleanup and handoff

Close this run's viewers/calls/Appium sessions and restore only the permissions,
network settings and disposable fixtures changed by it. Keep native process and
cleanup receipts. Remove only owned exported files/test-package state through
the existing approved cleanup; preserve other sessions and real packages.

Return per-case PASS/FAIL/BLOCKED/N/A/NOT RUN with artifact/configuration identity,
exact cut/content/count evidence and manual observations. Keep the original
assertions/deadlines across retries. Matrix host ratings remain separate from
device execution and release certification.
