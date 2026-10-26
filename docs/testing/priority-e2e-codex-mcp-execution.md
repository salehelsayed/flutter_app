# Six journey gaps: execution handoff

Prepared on `ad970f81d3eba2be6f178bfc73eb4003bb4a6f8d`. Device execution is
**NOT RUN**. `flutter_app` executes the steps below after the current campaign
releases its devices. Codex prepares tests and runners only. This packet changes
no application, native plugin, dependency, or deployed relay code.

Use the [shared camera/permission MCP operations](priority-e2e-camera-permission-mcp.md)
from Astra's `d348c936a`; do not start another WebDriver/UI harness. Preserve
owner identities, pairing, history and photo libraries. Never reset an owner
package to make a fixture fresh. Record the first failure and original deadline.

## Setup and recorded verdict

1. Discover the live matrix with `flutter devices --machine`, `adb devices`
   and, for an iOS-specific leg, `xcrun simctl list devices available`. Pin every
   action to a discovered ID and coordinate existing leases. Default shared
   behavior uses USB Pixel plus an available Android emulator. Add available
   emulators for membership roles. iPhone 11/13 may supply an actual iOS
   permission/camera or requested parity leg; neither model is mandatory.
   Unavailable targets are `N/A (target unavailable by project policy)`.
2. Bind roles to the actual installed candidate source and artifact SHA-256.
   For VC-023 also record that `VOICE_CALL_FORCE_RELAY_ENABLED` is false. A
   forced-relay test APK cannot prove the user's preference caused the route.
3. Create a private attempt directory and generate a receipt:

   ```sh
   dart run integration_test/scripts/evaluate_production_journey_gap_receipt.dart --template CONTACT-001 > PRIVATE_ATTEMPT/case.json
   ```

   Set `runId`, `candidateSource`, and `targets` (role to `deviceId`, `platform`,
   `artifactSha256`). Keep actual identities, captions, codes and paths private.
   `evidence` lists relative files with `path`, `sha256`, `kind`; include an
   actual `mcp-transcript`. Retain native trees/screenshots, raw observations
   and cleanup. The complete synthetic host fixtures in
   `test/tool/sims/production_journey_gap_criteria_test.dart` illustrate the
   JSON field shape; they are never device evidence.
4. Execute the named operations and fill `observations` only from saved actual
   results. Set `executionStatus` to `complete` only when those steps ran;
   otherwise retain `not_run`, or use `blocked` with the precise `reason`.
   Evaluate on the host:

   ```sh
   dart run integration_test/scripts/evaluate_production_journey_gap_receipt.dart --source FULL_INSTALLED_CANDIDATE_REVISION --receipt PRIVATE_ATTEMPT/case.json --output PRIVATE_ATTEMPT/verdict.json
   ```

   `PASS_RECORDED` means the supplied observations/files passed this checker.
   It does not operate a device, independently interpret MCP screenshots, or
   certify a signed build. It checks the expected candidate, hashes raw
   evidence, decodes full exported images/video and applies the existing
   whole-file media oracle. `nativeExecutedByThisCommand` remains false.
   `NOT RUN` exits 3, `BLOCKED` 78, and a failed/incomplete receipt 1.
   For an unavailable target, set `executionStatus=target_unavailable`,
   `reason=target_unavailable_by_project_policy` and attach hashed live
   `device-discovery` evidence; the result is `N/A_TARGET_UNAVAILABLE`, never PASS.

## GC-005: already covered; no new runner

Reuse both registered companions, without claiming either has been run here:

| Boundary | Existing runner / wrapper check | Targets / estimate |
|---|---|---|
| Accepted durable text, sender death, same-ID exact-once recovery | `integration_test/scripts/run_production_group_ordered_recovery.dart` / `production-catalog-group-ordered` | Existing campaign requires three available disposable Android emulators; 20–40 min, registered limit 7,200 s |
| Add/remove/re-add process cuts and removed-window exclusion | `integration_test/scripts/run_production_group_process_death.dart` / `production-group-process-death` | Pixel plus two available emulators; 15–30 min, registered limit 2,400 s |

Use the existing wrapper's setup/preview and centrally prepared
`android.e2e.production` artifact. In its prepared SIMS environment the exact
runner commands are:

```sh
dart run integration_test/scripts/run_production_group_ordered_recovery.dart
dart run integration_test/scripts/run_production_group_process_death.dart
```

The first keeps both recipients absent until committed inbox custody and the
verified sender kill, then checks all 103 canonical messages after restart.
The second owns membership cuts and excludes the removed-window marker after
re-add. Preserve both `observations.json`, `oracle.json`, SIMS and restoration
receipts. Insufficient currently available topology is N/A, not a demand to
create devices. See `production_group_ordered_recovery_criteria.dart` and
`production_group_process_death_criteria.dart` for their existing oracles.

## CONTACT-001: scanner refusal and one real request

Estimate 10–15 min per supported platform. Use an isolated test relationship
on the Android pair; an available iPhone supplies a separate native iOS leg.

1. Record `before.contactCount`, `requestCount`, `requestSendAttempts` for this
   exact test relationship from the existing repository/protocol observations.
   Start the complete request-egress observation before opening the scanner;
   absence of a UI bubble alone cannot prove zero network send. Missing egress
   observability is BLOCKED, not an assumed zero.
2. `camera_entry(scanner, contact_scan, keep)` then
   `camera_capture(cancel)` before any code result. In `cancelled` record the
   outcome and all three counters unchanged.
3. `camera_entry(scanner, contact_scan, deny)`; observe actual denial and return
   to the original surface. In `denied` all counters still equal the baseline.
4. Grant through MCP OS settings, reopen the ordinary scanner, then use
   `camera_capture(scan)` on the peer's real UI-generated code. Paste/import
   does not supply this optical leg. Record `granted.entry=contact_scan`,
   `input=optical_camera`, `permission=granted`, authenticated request and the
   measured counters. Exactly one contact/request is added. Transport retries
   are not additional logical requests.
5. Reopen without clearing data; observe ten seconds, retaining one logical
   contact/request and no additional request dispatch. Fill `reopened` and
   `duplicateObservationMs`. `camera_restore` and set `cleanupRestored=true`
   only after checking the recorded permissions/state.

## MEDIA-010: permission recovery preserves the draft

Estimate 10–20 min. Default Pixel/emulator; repeat on an available iPhone for
the actual iOS permission boundary, using its existing preserved pairing.

1. Enter a unique multiline Unicode draft. Record draft, sent-message counter
   and zero staged attachments. Call `camera_entry(sender,
   conversation_photo, deny)`. Record the real denial and visible error, the
   unchanged draft/counter, zero attachments and no false success.
2. Grant in OS settings through MCP. Re-enter with `camera_entry(..., allow)`;
   `camera_capture(confirm)` must stage one real photo. Read back the original
   draft, send once, then use `camera_send_and_open(caption)` on the peer.
   Require one message/attachment and exact caption after reopen.
3. Repeat through the actual **Media Library** action for photo access. If the
   platform uses a permission-free system picker, record that actual boundary
   as `status=N/A`, `reason=system_picker_has_no_photo_permission_boundary`;
   cancel it and prove draft/counter unchanged. Do not report cancellation as
   denial or require an unavailable older OS.
4. `observations.cases` contains `camera` and `photos`: `draftBefore`,
   `draftAfterDeny`, `sendsBefore`, `sendsAfterDeny`, `attachmentsAfterDeny`,
   `permissionBefore/After`, `visibleDenial`, `falseSuccessAfterDeny`,
   `stagedAfterRetry`, `sendTaps`, `receiverMessages`, `receiverAttachments`,
   `receiverMessagesAfterReopen`, `receivedCaption`. For system-picker N/A use
   `draftAfterCancel`/`sendsAfterCancel`. Restore with `camera_restore`.

## MEDIA-035: group camera, every current recipient, removed member

Estimate 20–30 min. Use Pixel sender, available Android receiver(s) and one
separate removed member. An available iPhone may supply an explicitly recorded
iOS receiver leg; do not require a particular phone model.

1. Use existing production group create/accept/remove UI actions. Record the
   exact group, `senderRole`, current `memberRoles` and separate `removedRole`.
   Confirm removal settled before capture; do not seed received message rows.
2. For **Original**, use shared `camera_entry` and `camera_capture(confirm)`
   on a unique high-detail orientation card. Enter a unique exact caption and
   send once. Repeat as a distinct capture/message for **Compressed**.
3. On **each** entitled receiver independently, use shared
   `camera_send_and_open`'s full-image oracle: full viewer, readable marker/fine
   detail, correct orientation/caption, one message/attachment, reopen and ten
   seconds of duplicate observation. Export only this owned full file through
   the existing supported path. A thumbnail/tick/row is insufficient.
4. On the removed member require zero rows, attachments and download attempts
   for each marker, including after its reopen and a ten-second observation.
   Keep any recipient failure in the attempt; do not report aggregate PASS
   from only the successful receivers.
5. In `observations.group` record membership. In `observations.media` record
   the two distinct message/attachment identities, `owner=group`, `groupId`,
   `quality`, `capture=native_camera`, `caption`, `marker`, and every recipient.
   Each recipient records exact IDs/counts before/after reopen, full-file path,
   native backend/frame dimensions, marker/orientation and duplicate window.
   `removed` records its role and zero counts/attempts/window. Restore via
   `camera_restore`.

The evaluator fully decodes every exported file. When the existing native
encryption-input observer supplied a pinned processed-send receipt, include
`senderReceiptFile`/`senderReceiptSha256`: the existing `SentMediaBinding` oracle
also checks exact plaintext equality. Without that capture, this stronger byte
comparison stays **NOT RUN**, even if recorded full-viewer/content assertions
pass. Never manufacture an encryption-input receipt from raw camera bytes.

## VC-023: saved relay setting, emulator-only outage, restore

Estimate 15–25 min. Subject is an available rooted Android emulator; peer is
Pixel. **Start each call only after 08:30 CET**; record the actual timezone-aware
first call start as `observations.startedAt`. Preserve prior preference/rules.

1. With force-relay build restriction false, enable **Always relay calls**
   through MCP, reopen settings and read its durable value. Initiate a real
   call, answer on Pixel, and record selected **local relay candidate**, native
   `iceTransportPolicy=relay`, exact call, and both peers' sent/received RTP
   counters advancing over the same observation window. End and verify cleanup.
2. Obtain only the configured Hetzner TURN IPs/ports/transports from existing
   configuration/diagnostics, excluding credentials. Confirm root on the
   emulator. `flutter_app` confirms exact runtime iptables syntax. Create one
   run-owned chain and an OUTPUT jump scoped to this package UID; DROP only
   those TURN destinations. Record original rules and packet counters. Include
   all actually usable IPv4/IPv6 TURN routes; leave signaling reachable.
   Never change Hetzner, global firewall policy or either owner's iPhone.
   A representative IPv4 rule shape is:

   ```sh
   adb -s "$EMU" shell iptables -N "$OWNED_CHAIN"
   adb -s "$EMU" shell iptables -A "$OWNED_CHAIN" -d "$TURN_IP" -p udp --dport "$TURN_PORT" -j DROP
   adb -s "$EMU" shell iptables -I OUTPUT 1 -m owner --uid-owner "$APP_UID" -j "$OWNED_CHAIN"
   ```

3. With the saved preference still on, make a distinct call. Require effective
   TURN rule hits while signaling remains reachable, no direct selected pair
   or connected interval, failure within the existing setup deadline and native
   cleanup. A wholly offline device does not prove no direct fallback.
4. Delete exactly the run-owned jump, flush/delete only its own chain, restore
   prior rules and verify them. Make a third distinct call and repeat selected
   relay plus both-direction RTP progress/cleanup. Restore the preference.
5. Record `savedAlwaysRelay`, `turnFault`, `beforeOutage`, `outage`,
   `afterRestore`. Successful phases include two `peers` with role and native
   start/end `packetsSent`/`packetsReceived`; outage records policy, zero direct
   pairs, no connected interval, unchanged-deadline terminal and release.
   Missing root, a safe per-emulator rule, selected-pair/RTP observation or
   signaling-preserving fault is BLOCKED with that reason. Do not invent a
   network harness, mutate Hetzner, or use the forced-relay local-call campaign.

## MEDIA-018: held partial transfer through abrupt process death

Estimate 20–35 min for image sender/receiver cuts; repeat the same two cuts
with a short marked video for video coverage. Keep format results separate.
Use the Android pair and the **existing run-owned disposable media relay
fixture**, centrally prepared production-journey artifact and ordinary UI.
Its test-only `/transfer-checkpoint` addition does not modify a deployed relay.

Appium cannot hold a libp2p body atomically across a process kill. This is the
specific gap covered by the small checkpoint/cut adapter; all UI remains MCP.

1. Start/reuse the existing fixture lease/launcher and its private readiness
   probe/multiaddr. Verify the candidate actually uses this fixture. Close any
   other owned transfer before arming. Choose a real media file larger than
   64 KiB and bind the target peer, original message/attachment, native pending
   row from existing observations. The gate learns the actual ciphertext size
   from the production request/response, rather than guessing raw camera size.
   If durable row or
   per-transfer identity cannot be observed, stop as BLOCKED, not an app verdict.
2. POST this body to `PROBE/transfer-checkpoint`, using the sender's peer for
   upload (receiver's peer for download):

   ```json
   {"op":"arm","gateId":"UNIQUE_RUN_CUT","direction":"upload","peerId":"OWNED_PEER","attachmentId":"OWNED_ATTACHMENT","afterBytes":65536}
   ```

   When arming before UI assigns the attachment ID, omit `attachmentId`: the
   first matching transfer binds it once. Still obtain and verify the exact
   actual attachment before invoking the cut helper; the private probe returns
   its ID and digest. Other peers pass through. An optional known `totalBytes`
   must match the real production header.
3. Trigger the ordinary UI upload/download with MCP. A GET of the same endpoint
   must show a bound, held partial **ciphertext body**, not metadata/header
   bytes. For download also retain the actual nonempty incomplete receiver
   file and its pending row; no `done` or false completed viewer state.
4. While held, run the limited Android cut helper with exact discovered IDs:

   ```sh
   dart run integration_test/scripts/cut_production_media_transfer.dart --probe "$PROBE" --gate-id "$CUT" --attachment-id "$ATTACHMENT" --device "$OWNED_ANDROID_ID" --package "$OWNED_PACKAGE" --output PRIVATE_ATTEMPT/cut.json
   ```

   It verifies the same attachment's held partial body, force-stops only that
   package, verifies process absence, saves the still-held post-kill witness,
   and releases only its gate. Hold is bounded at 45 seconds. Missing/late cuts
   retain failure and do not diagnose an app defect. The helper permits only
   the existing private fixture host, not a public relay URL.
5. Reopen normally with MCP without clearing data. Within the existing
   120-second recovery window, require original IDs, exactly one full usable
   received file and exact caption. Apply the native full-image oracle; for
   video play through its marker and end, and retain native playback positions.
   Export only the owned full file. Reopen once more and observe ten seconds
   with one message/attachment. A preview never supplies full recovery.
6. Repeat on a fresh item for receiver download. In `observations.cuts` record
   both directions, original IDs/owner/caption/marker, durable row and pending
   status, before/after gate witnesses, process absence, distinct runtime nonces,
   receiver partial-file bytes, full file and recipient native/open/count proof
   as in MEDIA-035. For video set `mediaType=video` and include native duration,
   start/end positions and `markerAndEndObserved`. Host video checking requires
   existing `ffmpeg` and decodes the full stream. Missing prerequisites remain
   incomplete/blocked; no new app hook or app fix belongs in this packet.

## Closure

Restore only this run's permission, quality, preference, firewall and lifecycle
changes; end its MCP sessions and local fixture lease. Preserve owner accounts,
contacts/history and unrelated evidence. Never hide a first failure with a retry.
Send Kayan one per-item outcome and redacted evidence paths. These scripts and
host tests are preparation; actual device execution and app defects are reported
by the execution owner. Unavailable hardware cannot be a closure requirement.
