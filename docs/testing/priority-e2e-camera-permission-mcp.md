# Shared camera and permission MCP script

Execution owner: `flutter_app`. Astra prepares this script on the host only.
Use these operations from RG-002, CR-009, MEDIA-002/003, CONTACT-001,
MEDIA-010 and MEDIA-035; keep each caller's acceptance assertions separate.
These are instructions for the executor's **actual Appium MCP tools**, not a
standalone WebDriver client or a claim that a device case has passed.

## Invocation and returned evidence

Call an operation below by name with:

- `role`: an available target already discovered, pinned and owned by the executor;
- `entry`: `conversation_photo` or the current supported `contact_scan` route;
- `decision`: `allow`, `deny`, or `keep` the existing camera permission;
- `capture`: `confirm`, `cancel`, or `scan`;
- `run_directory`: ignored private evidence directory, plus a unique case marker;
- optional `caption`: exact synthetic UTF-8 text, kept out of shared mail.

Return the observed outcome (`captured`, `cancelled`, `permission_denied`,
`scanned`, or `incomplete`) and private evidence references: candidate identity,
permission before/after, entry route, timestamped MCP actions, before/after
trees and screenshots, draft/attachment state, and any first failure. Missing
evidence is `incomplete`; a successful tap is not a successful capture.

Resolve locators from a fresh native accessibility tree before each OS/app
boundary. Flutter `ValueKey`s explain the source but do not prove a native
locator exists. Do not use fixed coordinates, invented tool names, a second UI
harness, imported contacts, injected camera output or a replacement app screen.

## `camera_entry`

1. Record candidate/build, existing permission and the caller-owned draft and
   attachment count. Preserve the owner identity, contacts and photo library.
2. Navigate through the existing UI. For `conversation_photo`, open the ordinary
   attachment sheet and **Take Photo**. Source anchors are `chat_attach` in
   `compose_area.dart` and the photo action in `conversation_wired.dart`.
   For `contact_scan`, the caller supplies the current supported contact-entry
   route; do not substitute a conversation camera or seed a contact repository.
3. On an actual OS permission prompt, apply `decision` through Appium MCP and
   retain its before/after tree. If no prompt appears, record the actual grant
   state; do not claim that a first-request prompt was tested.
4. For `deny`, observe the returned app state, any explanation or settings
   action, and draft/attachment state. Return `permission_denied` only when the
   refusal was observed. Product feedback assertions belong to the caller.
5. If the required grant state needs changing, use MCP system settings on this
   owned target, then return through the ordinary app entry. Do not revoke
   unrelated permissions, clear storage, reset an identity, or modify another
   automation owner's target. An unavailable reset/prompt is an incomplete
   subcase; it is not evidence of permission behavior.

## `camera_capture`

Run `camera_entry` first. With access granted, resolve the real native shutter
and confirmation from the current tree. Photograph a synthetic card with the
case marker, an orientation arrow and detail readable only in the full image.
Use `confirm` to accept the real capture, or `cancel` to leave the camera through
its supported UI. Record the composer/draft and attachment state on return.
For `scan`, present the peer's real UI-generated contact code to the scanner;
record manual code entry or payload import as a separate route that does not
prove camera scanning. Stop before accepting a contact unless the caller owns
that step. Never copy private codes or identities into coordinator mail.

## `camera_send_and_open`

For a confirmed photo, read back the exact caption in the real composer before
one send. Reuse the full-image oracle in
[the Group C runbook](astra-group-c-device-runbook.md#shared-appium-actions-and-evidence).
Within 120 seconds, require the intended receiver to open the full image,
decode/zoom its marker and orientation, show the exact caption, and have one
matching message/attachment. A thumbnail, metadata label or delivery tick alone
does not pass. Reopen the owned apps without clearing data and repeat the
uniqueness/content check. Keep Original and Compressed results separate.

If full-file export is required by a caller, use only an owned synthetic item
and the existing export path; do not write into the owner's photo library as an
assumed prerequisite. Missing file/hash proof remains explicitly incomplete.
Do not add relay-only requirements to an ordinary parity case; a caller that
requires relay custody must retain the existing per-message transport oracle.

## `camera_restore`

Close only this run's camera/viewer and restore the recorded permission,
quality and network state. End only this run's MCP session. Preserve first
failures and deadlines. Delete only exact owned exports when cleanup is
authorized; never remove contacts, history, camera-roll items or another run's
artifacts. Report any remaining state to the coordinator by redacted facts.

Existing camera execution is recorded at
`journey-coverage-matrix.yaml:3987` and `:4056`, backed by the retained
`build/wt-astra-c/.codex-test-logs/astra-c-20261022/RESUME.md:14,18,41`.
Those older instrumented candidates do not certify a new signed store build.
