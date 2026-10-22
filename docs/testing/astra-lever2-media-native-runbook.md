# Lever 2: processed-sent media byte oracle and native ledger

This is the handoff for the **32 MEDIA device routes** in the closure analysis,
after the seven MEDIA host joins and excluding MEDIA-019/038 (flutter_app's
separate relay fixture lever). Source baseline for this packet is
`944e742cd7281e55cadeb96e41b82afe5bc3c856`. Astra performs host work only.
**Every native ledger entry below is NOT RUN. No additional matrix rating is
upgraded by adding the helper or this runbook.**

The reusable implementation is
`integration_test/support/media_content_oracle.dart`; its native-client adapter
is `integration_test/support/media_oracle_go_bridge_client.dart`. The observer
intercepts the real `GoBridgeClient.send` call at **`blob:encrypt payload.filePath`**.
That file has already passed the selected processing/preparation path. It reads
the whole plaintext before/after the unchanged native call and the whole returned
ciphertext, then binds the capture to the actual outgoing SQL attachment's
owner/parent/item, plaintext size and ciphertext hash. Receipts contain no
media key, nonce, peer address, caption or raw camera path. The
native request already contains ephemeral crypto parameters; they pass unchanged
to the existing client and are not retained by the observer.

The receiver compares its **complete decrypted original** with that captured
plaintext, after current row/read authority checks and another check after
hashing. `MediaAttachment.contentHash` identifies encrypted blob bytes; it is
only the source-to-row ciphertext binding. It must never be compared directly
with the receiver's plaintext SHA. `group_media_integrity_policy.dart:166`
documents that distinction. Thumbnails, filename/size matches and delivery
receipts are insufficient.

## Integration into the existing executor

The adapter is opt-in test composition; **it is not automatically installed in
the current C/D apps or all 32 campaign drivers**. These exact integration steps
remain for flutter_app before its native run. No shipping app source is changed
by this packet, and no second bridge/event-channel owner should be introduced.

1. In the existing owned test composition, construct
   `MediaOracleGoBridgeClient(mediaInputObserver: observer)` in place of that
   composition's `GoBridgeClient`, and pass the same native client to its real
   send/runtime graph. Retain existing callbacks, initialization and cleanup.
   The ordinary upload uses `sourcePath` after preparation
   (`conversation_wired.dart:4686`); native encryption is called by
   `upload_media_use_case.dart:186`/`bridge.dart:834`. Group preparation delegates
   to that same encrypt helper
   (`prepared_group_media_blob_custody_coordinator.dart:129`). The voice action
   already accepts the real `Bridge` (`android_voice_message_e2e.dart:116`). Extend those
   existing owners, not an isolated fake-native pipeline. If the active app's
   composition cannot accept the adapter, record **SOURCE_CAPTURE_NOT_WIRED**
   with its exact factory path and return that integration gap; do not stamp a
   raw camera hash or a separately encrypted fixture as the source witness.
   When wiring a campaign, add these helper dependencies to that campaign's
   affected mapping and preserve its mandatory release requirements. Their
   current unused test-composition paths retain the manifest's conservative
   host-consumer mapping; this packet does not silently narrow that selection.
2. After the existing driver proves publication/custody, reload the actual
   outgoing attachment and bind it using the shared campaign run ID, wire
   message ID, attachment ID and owner lane. Call `observer.bindSentRow`.
   Capture is encryption-input evidence; it does not itself prove publication,
   membership, policy authentication, caption or transport. Keep those original
   driver assertions. Successful legs require a capture and no unexplained
   observer failure. Native failures/responses/exceptions remain unchanged and
   first failures remain visible.
3. Export `binding.toSenderReceipt()` and pin **the producer's
   `binding.senderReceiptSha256`** in the existing owned fixture-driver result.
   The digest canonicalizes the receipt body; it is distinct from a JSON file's
   raw file SHA. Keep both the raw artifact SHA and canonical pin when copying
   artifacts. On the receiving process, use `SentMediaBinding.fromSenderReceipt`
   with that independently obtained pin and the expected identity. Never derive
   the expected pin from the untrusted imported body. No keys/paths/raw IDs are
   in this transfer receipt. The campaign run ID must remain stable across an
   intended restart, and change for a new attempt even when fixture IDs repeat.
4. Call `verifyReceivedMediaBytes` with actual current repository loads,
   `MediaFileManager` path resolution and current read-authority assertions.
   Ordinary media uses the real current-parent/file authority. Private media
   does this **inside the existing protected viewer grant, before first frame
   can consume the file**. Revalidate that grant; never open a second unprotected
   player, bypass privacy, resurrect a consumed row or export private bytes.
   The result is `byte_gate=PASS, native_gate=NOT_RUN` until native proof occurs.
5. Call `verifyNativeMediaOpen` from that same existing proof. Its mandatory
   `assertCurrentOpenAuthority` rechecks the current owner; the helper rehashes
   immediately before the native delegate. The `assertNativeOpen` delegate must
   execute the reviewed real frame/player/PDF assertions described below and
   return bound observations plus its actual nonempty proof artifact. It is not
   permission to fill in plausible dimensions or a `nativePlayed=true` flag.
   The helper refuses host targets, host-produced source receipts, wrong
   MIME/kind/identity/hash, missing frame dimensions, nonadvancing playback and a PDF
   without a rendered page. It does not reread a view-once file after consumption.
   `proofArtifact` must be readable by the mobile executor. If the actual
   Appium/frame capture lives on the host, write a small device-local probe
   receipt after the real assertion, link its independently recorded host
   artifact digest, and retain both in the owned bundle. A host filesystem path
   is not a readable device file and must not be used as one.

Example of the cross-process join, within the existing current-authority owner:

```dart
final identity = MediaWireIdentity(runId: campaignRunId,
    owner: owner, messageId: wireMessageId, attachmentId: attachmentId);
final sent = observer.bindSentRow(actualOutgoingRow, identity);
// Existing driver durably exports sent.toSenderReceipt() and the producer pin.
final imported = SentMediaBinding.fromSenderReceipt(receipt: senderReceipt,
    expectedReceiptSha256: producerPinnedDigest, expectedIdentity: identity);
final equality = await verifyReceivedMediaBytes(sent: imported,
    loadCurrentReceivedRow: reloadExactReceivedAttachment,
    assertCurrentReadAuthority: assertCurrentParentAndReadGrant,
    resolveStoredPath: files.resolveStoredPath);
final result = await verifyNativeMediaOpen(equality: equality,
    observerCase: existingProofCase,
    assertCurrentOpenAuthority: revalidateCurrentViewerOwner,
    assertNativeOpen: assertActualCurrentNativeFrameOrPlayback);
```

The native result says `PASS_EXISTING_ASSERTION`: it records that a **named,
reviewed existing native assertion** returned with bound facts and an artifact.
This helper is not cryptographic attestation of arbitrary receipts/delegates.
The device executor and reviewer must inspect that producer and its raw native
evidence. A host schema test or an empty delegate cannot certify native behavior.
Dimensions alone do not prove image/video rendering: the reviewed delegate must
perform the actual native frame assertion, including the controlled marker.

## Native witnesses and existing drivers

| Witness | Required actual observation | Reuse / exact gap |
| --- | --- | --- |
| I — image | Full received file opens in the current actual viewer, engine decodes its original dimensions, controlled detail/orientation/marker is correct. Bind the active item, not a cached thumbnail. | Group C/D image legs; group reliability criteria's real JPEG frame. Record first frame plus source/receiver digest receipt. |
| V — video | Full received file initializes in the real video backend, renders a recognizable fixture frame and advances playback at least 250 ms within its real duration; preserve orientation/audio track/caption. | Existing C/D video legs and `media_notification_playback_continuity_test.dart`. Group reliability's MP4 **thumbnail** alone is insufficient: extend the existing observer to actual full-video frame and progress. |
| A — voice/audio file | Existing actual just_audio/native player opens the equal-hash file and advances at least 250 ms within the decoded duration; observe completion/replay where the row requires them. | `android_voice_message_device_campaign.dart`; `android_voice_message_e2e.dart:555`; `android_voice_message_evidence.dart:128`. Its real recording/hash/player witness is useful; a group `player_loaded` flag alone is insufficient. This is file playback, not semantic live-call audio. |
| P — PDF | Actual supported native/external viewer renders at least one page of the complete fixture and the expected visible marker; preserve exact source and dismiss/cancel safely. | `received_media_native_egress_proof_test.dart` and its operator/native boundary. `presented`, a `%PDF-` prefix or an OS intent success is insufficient. Use a renderer/page observation or an honestly reviewed operator/Appium page witness, never blind PASS. |
| E — ordinary export | Actual native destination/receiver ledger contains the exact selected identities/order and full plaintext hashes; partial/cancel/permission outcomes preserve source. | Existing received-media native egress proof and `android_received_media_egress_receiver` helper. Preserve real platform permission state and owned cleanup. |
| Q — private protection | Actual protection owner precedes bytes/first frame; prohibited derivatives have zero dispatch; capture/background/failure settles correctly and only owned bytes are cleaned. | Existing direct/group private platform protection proofs. Debug-injected capture events establish channel policy, not an actual OS screenshot. Actual OS capture claims need a separate positive control and platform-truthful limits. |

For Original quality, the actual candidate must include Codex's full-resolution
fix `886b49d66e966ba5b130b581ed0b8c92f2490ac6` before the quality legs.
`git show 886b49d66 -- lib/core/media/image_processor.dart` shows Original still
uses native quality/metadata handling while disabling normal downscaling.
**Never compare receiver SHA to a raw camera original**, including Original
quality. Independently check Original's expected source-resolution geometry
(allowing orientation normalization) and a controlled high-detail card; equal
processed hashes alone would not detect an erroneous quality/downscale choice.
Record the actual candidate/build/configuration; the helper branch itself stays
on the assigned test base and does not cherry-pick the app fix.

## Per-journey ledger and device steps

For every positive accepted item: capture/bind the real sent source, compare
current receiver bytes, then execute the named native witness. For an expected
refusal/cancel, assert zero unintended send/open/export and use a separate valid
positive control; do not invent a required file/open for rejected work. Every
row's byte/native status remains **NOT RUN** until flutter_app supplies evidence.

| Journey | Existing lane / input and action | Defining assertions beyond the common byte gate | Native witness | Byte / native status |
| --- | --- | --- | --- | --- |
| DC-008 | C/D ordinary pair; send real photo, video and complete PDF in both directions, with captions. | One correct row/item after reopen; exact captions/order. Bind each processed output independently. | I + V + P | NOT RUN / NOT RUN |
| DC-018 | D interrupted-media driver; valid near-limit direct item, then actual owned transfer interruption and retry. | True near-cap final file length; partial object never done; original identity/source retained. Oversize refusal has zero dispatch. | I or V for accepted type | NOT RUN / NOT RUN |
| GX-003 | Existing group reliability driver; near-limit authorized item with one held/failing recipient, then recover it. | Cap/refusal per item; settled authorized recipient not resent; group custody and expected roles remain exact. | I + V as selected | NOT RUN / NOT RUN |
| DC-021 | Existing direct private proof plus actual pair transfer. | Private policy stays inside authenticated payload; ordinary downgrade and policy/state tampering rejected; sender and receiver source binding agree. | Q + I/V for accepted private type | NOT RUN / NOT RUN |
| GC-006 | Group reliability with current available endpoints and receiver-role permutations. | Each authorized recipient gets exact full content; one failed member remains explicit without hiding another's success. No unnecessary simultaneous extra phone. | I + V + A | NOT RUN / NOT RUN |
| GC-010 | Existing group private platform proof; deliver to allowed recipients, then view/consume only one. | Independent recipient lease/expiry/cleanup; other recipient remains eligible; derivatives refused and removed member stays unauthorized. | Q + actual private I/V | NOT RUN / NOT RUN |
| MEDIA-001 | C in-app camera plus controlled high-detail/orientation card and caption. | Real OS camera output, selected processing and exact caption; current full image, not sender preview. | I | NOT RUN / NOT RUN |
| MEDIA-002 | Reuse C iPhone-camera → Android online relay leg, Original then Compressed. | Per-message relay witness; exact caption; Original geometry after886; actual processed source digest for each quality. Historical stock125 is separate. | I | NOT RUN / NOT RUN |
| MEDIA-003 | Reuse C Android-camera → iPhone leg at selected qualities. | Receiver full file SHA from authorized app/test owner; viewer Info/size alone is insufficient. Preserve iPhone identity/photo library. | I | NOT RUN / NOT RUN |
| MEDIA-004 | Existing ordinary gallery flow; known JPEG and PNG with distinct markers/captions. | Correct current attachment after gallery selection, no cross-item/caption substitution; decode each full file. | I | NOT RUN / NOT RUN |
| MEDIA-005 | Same flow with a real supported HEIC/HEIF fixture and a separate unsupported/malformed control. | Accepted normalized result is hashed after conversion and natively opens; rejected input produces honest refusal/no success. Do not assume camera MIME is HEIC. | I for accepted output | NOT RUN / NOT RUN |
| MEDIA-006 | C/D in-app video capture, then transfer to actual peer. | Full file/frame, correct orientation, decoded duration and exact caption; actual playable video, not a thumbnail. | V | NOT RUN / NOT RUN |
| MEDIA-007 | Gallery video with known rotation/duration marker and caption. | Source baseline is post-video-processing output; native received frame orientation/duration and caption match the intended processing contract. | V | NOT RUN / NOT RUN |
| MEDIA-008 | Existing composer batch with distinct image/video markers and one deliberately refused/held sibling. | Accepted order and exact parent/item identity, separate outcomes; refusal cannot silently erase or duplicate valid siblings. | I + V for accepted items | NOT RUN / NOT RUN |
| MEDIA-010 | D actual camera/photos denial, OS grant, return and fresh successful pick. | Honest visible denial, preserved draft, no send on denial, one valid send after grant. ASTRA-D-1 app fix remains Codex-owned; host known gap is not silently waived. | I positive control | NOT RUN / NOT RUN |
| MEDIA-011 | Existing ordinary document route with send flag enabled and complete one-page fixture. | Real outgoing PDF/current received identity; exact source digest; actual rendered page and caption. Separate no-viewer failure remains truthful. | P | NOT RUN / NOT RUN |
| MEDIA-014 | Reuse C iPhone-camera → offline Android relay-inbox catch-up, both qualities. | Actual offline/app-state cut and custody before delivery; one row after cold relaunch; source snapshot exported before the cut. | I | NOT RUN / NOT RUN |
| MEDIA-015 | Existing local-media driver with internet unavailable; reconnect only for the separate deferred leg. | Per-message actual local path; local write is not durable receiver commit. LAN and relay witnesses must remain distinct. | I/V/P for selected accepted control | NOT RUN / NOT RUN |
| MEDIA-016 | Existing owned transport refusal/retained retry; no usable local/relay path, then recover it. | Honest pending/failed state, original retained source/identity and one eventual row; no synthetic success while unavailable. | I or V after recovery | NOT RUN / NOT RUN |
| MEDIA-017 | Existing C/D media transfer handover Wi-Fi/mobile or disconnect at owned checkpoint. | No thumbnail-only done state; retained accepted custody, exact full file and caption after bounded retry. Keep original deadlines/first failure. | I + V selected handover inputs | NOT RUN / NOT RUN |
| MEDIA-018 | Reuse D sender/receiver restart transfer leg; source witness before actual cut, same run ID after restart. | Real process/transfer cut and current SQL recovery; partial original/cache cannot manufacture done; one stable row and caption. | I; V/A if those formats are claimed | NOT RUN / NOT RUN |
| MEDIA-020 | Existing ordinary transfer, delete only owned sender preview/cache after accepted custody. | Receiver full original/hash unaffected; sender preview disappearance is not receiver proof. Never delete shared/foreign/owner photo data. | I or V on receiver | NOT RUN / NOT RUN |
| MEDIA-021 | Existing settings/composer route selects photo/video quality, then sends controlled source. | Native processor received selected preference; Original geometry after886, supported compressed geometry; each processed output hashes/opens, without expecting raw-source equality. | I + V | NOT RUN / NOT RUN |
| MEDIA-023 | Existing video continuity/PiP proof on current received video. | Pause, seek, resume and available rotation/PiP preserve exact current owner/position; old page/controller stops. Unavailable OS PiP is N/A. | V with control/lifecycle assertions | NOT RUN / NOT RUN |
| MEDIA-024 | Existing ordinary native egress proof; allowed mixed selection, permission/partial/cancel branches. | Current-row eligibility, exact native destination full hashes/order, no resend/export of refused work, source/draft preserved on cancel. | I/V/P + E as selected | NOT RUN / NOT RUN |
| MEDIA-027 | Existing native voice campaign plus actual hold/release and lock/review UI in C/D. | Real nonempty recording, no review auto-send, exact encoded file after processing; actual recipient player progress/completion/replay. Recorder bypass alone does not prove UI consent. | A | NOT RUN / NOT RUN |
| MEDIA-028 | Same voice owner: discard/cancel, mic denial and actual call-conflict interruption, then valid control. | Delete only owned recording, no silent send, review intent retained. No native open expected for discarded audio. | A positive control; negative zero-send | NOT RUN / NOT RUN |
| MEDIA-029 | Existing voice playback/ownership proof; seek/speed/pause and competing audio interruption. | Only current owner resumes; exact selected file, native advancing position and truthful stop/cleanup; no duplicate audio. | A | NOT RUN / NOT RUN |
| MEDIA-030 | Existing direct private platform proof combined with a real sent/received protected item. | Protected current grant before bytes/frame; no Save/Share/Forward/unauthorized derivatives; source hash under grant before consume. | Q + I/V | NOT RUN / NOT RUN |
| MEDIA-033 | Same private owner; actual available OS capture/background boundary and injected native-channel failure leg kept separate. | Positive control for actual screenshot/capture claims; fail-closed cover/settlement/no reopen; iOS truthfully reports its capture limits. | Q + permitted native I/V | NOT RUN / NOT RUN |
| MEDIA-036 | Existing group driver/fixture extension with gallery image, full video, complete PDF and real voice file. | Exact eligible-member and per-item outcomes; extend missing full-video/PDF/voice-play observations, without treating JPEG/thumbnail/player-loaded as all-format proof. | I + V + P + A | NOT RUN / NOT RUN |
| MEDIA-037 | Existing new-member media/history group driver; add/remove/re-add only disposable owned membership. | Actual history/key/blob ACL and policy-permitted accepted items; removed/old member fetch denied. Native open only for the authorized current recipient. | I/V/A/P for policy-permitted controls | NOT RUN / NOT RUN |

## Execution and evidence ownership

Host preparation source is `2ee6975cdc6005a46f6cb75bcacf6376afc330b8`.
Final host oracle suite: **23 PASS, zero skips** (`004-oracle-final`); targeted
analysis of all three code files: **no issues** (`005-analyze-final`). Earlier
16/22-case runs are subsets, not extra passes; the first analyzer's two brace
infos remain in `003-analyze` and were fixed before the final run. The final test
and analyzer started with load below 38 and 21 respectively; both had no swapout
increase. No additional heavy job was started during the earlier above-80 load.

Metadata validation passed. Explicit base `944e742cd --local` preview selected
21 checks over five changed rows, with zero unmapped changes. The exact changed
oracle check also ran through `mknoon_checks.py` with one worker: the same
**23 cases PASS**, child exit 0. Overall wrapper exit is **3 / NOT RUN** because
the other 20 selected checks were omitted; no broad affected-lane/host-all or
device/release verdict is implied. Evidence directory:
`.codex-test-logs/astra-lever2/`, notably `006-ledger-audit.json`,
`008-final-host-summary.json`, `change-plan/plan.json` and
`oracle-wrapper/results.json`. The wrapper recorded working-tree source identity
`baca6a770034b41ec80fdcfe890770943b345a4d546997cfe473208d09c8ba38`;
subsequent handoff edits are documentation only.

| Failure / split | First causal check |
| --- | --- |
| `ACTUAL_SENT_SOURCE_NOT_CAPTURED` | Check the actual client's test-composition wiring, observed command and detail-free observer failures. Do not substitute a raw camera hash or encrypt another fixture later. |
| `SENDER_RECEIPT_NOT_PINNED` | Match the actual producer pin, campaign run ID, owner/parent/item and raw receipt artifact. A new attempt gets a new run ID; an intended restart retains the old one. |
| Current row/identity/path/read-authority refusal | Inspect current SQL and the exact owned file/grant. A stale or consumed item must remain refused; never force its row back to done to satisfy the oracle. |
| Cipher binding succeeds but plaintext differs | Preserve full source/receiver hashes, exact row identity and original download/decrypt/commit evidence. Diagnose copy/decrypt/promotion or stale-file work before changing a codec/renderer assertion. |
| Plaintext matches but native open fails | Investigate processing/encoded format, native decoder and actual current renderer/player ownership. Equal wire bytes alone cannot certify a usable media file. |
| Native fields/probe incomplete | Record NOT RUN or the actual failure. Collect the full native frame/progress/page observation; do not fill measurements from metadata or a thumbnail/player-loaded flag. |
| `NATIVE_SOURCE_REQUIRED` / `NATIVE_TARGET_REQUIRED` | Host-generated fixtures/receipts do not certify a native pair. Reuse an available real mobile executor and source; do not override platform detection. |

Only flutter_app discovers/controls available targets. Reuse the
[Group C](astra-group-c-device-runbook.md) and
[Group D](astra-group-d-device-runbook.md) drivers and existing native campaign
preflight/cleanup. Default shared two-peer topology is the available physical
Android plus available emulator; use iOS only for its boundary/explicit parity.
Unavailable targets/accessories/topology are N/A by project policy. Preserve the
existing physical iPhone install, identity and pairing; no erase/uninstall or
owner Photos mutation to satisfy an old proof's reset precondition.

Keep exact source/build/configuration, shared run ID, first native failures,
sender receipt artifact plus producer pin, byte receipt, named native probe,
native artifact and owned cleanup outcome together in ignored run artifacts.
Do not reset original deadlines or erase a first failure after a successful
retry. Mail paths and redacted facts only. Actual published signed-artifact
release certification remains a separate gate.

The no-hook Android-receiver energy proxy is a **live-call** scope decision;
iPhone-receiver/content proof still **needs a test-build audio hook (not approved
now)**. This file-media oracle neither adds nor requires that live-call hook.
