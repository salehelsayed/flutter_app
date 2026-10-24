# Safe Transfer rows: Pixel and iOS simulator

Status: **NOT RUN by Astra**. Execution belongs to `flutter_app`, using its
existing Appium MCP and TRANSFER-011 setup. No new fixture or automation harness
is required. Scope: TRANSFER-001/002/003/007/015. Physical iPhones are untouched.

## Setup and order

- Use the available, explicitly pinned **Pixel 6 + iOS simulator**. Record the
  actual source/receiver roles, source revision, package/bundle, compile flags,
  artifact hashes and installed candidate. Reuse today's owned T011 debug APK
  and simulator app/setup; preserve unrelated real-app packages and pairings.
  An unavailable target/version is N/A by project policy, not a hardware wait.
- Default direction is Pixel source to simulator receiver. The source's **debug
  Paste migration QR** field replaces camera input. Keep decoded QR text,
  pairing digits, identities and private logs local; mail only paths, counts,
  hashes and redacted facts. Screenshot decoding/paste is **fixture entry, not
  camera coverage**. Resolve the current Appium accessibility tree for actions;
  source widget keys below are navigation hints, not assumed Appium locators.
- Preserve today's retired Pixel state for TRANSFER-015. Run 015 **first** if
  that owned test state still exists. Otherwise run it once after the final
  successful test move. Use the existing T011 fresh-account/setup procedure for
  subsequent disposable source/receiver attempts, retaining source markers and
  existing media when a transfer-progress window is needed. Never revive a
  moved account by restoring its old database/key backup. No new test fixture,
  third target or real identity reset is authorized by this runbook.
- Run negative/cancel cases before the final successful move. Before each
  attempt, record source account/profile/history markers and receiver staging
  baseline through existing observations, without dumping secrets. Check the
  Mac lease/status and existing setup checks; preserve exclusive device
  ownership and the existing campaign deadlines. A setup pass is not a case
  pass. Preserve the first failure and review owned cleanup before a fresh try.

## TRANSFER-015 — erase only the retired test source

1. Require the owned Pixel test package to show **Account moved to another
   phone**. Record that the simulator's transferred copy still opens. If the
   Pixel is active, do not erase it under this case.
2. Open **Erase local data**. Cancel the confirmation first; relaunch
   and require the same retired state and unchanged owned data.
3. Open it again, verify this is the retired disposable source, and explicitly
   confirm **Erase this device?**. Require truthful completion and fresh setup
   after relaunch, with old account data inaccessible. The simulator copy and
   unrelated package/OS state must remain unchanged.
4. Retain existing native/filesystem/registry cleanup receipts, with no key
   values. Fresh onboarding alone proves only the UI leg. If there is no
   existing receipt for actual local data/key cleanup, mark that subleg NOT RUN.
   Do not add fault injection to manufacture an erase failure; failure-path
   preservation remains host support unless an approved existing control exists.

**Verdict:** scoped PASS needs explicit confirmation, owned local cleanup and
preservation evidence; erasure on Cancel, wrong-account erasure or false success
is FAIL. Missing retired fixture/cleanup witness is NOT RUN for that leg.

## TRANSFER-001 — reach the correct roles and pairing entry

1. On the fresh simulator receiver, open **Move from old phone** and retain its
   current QR/session witness. On the Pixel source, open Settings → **Move account to new phone**.
2. Decode that exact receiver QR using the existing T011 route and paste its
   unmodified text through the debug migration field. Verify that the composer/
   keyboard did not alter it; a rejected altered paste remains a first attempt.
3. Require both role-appropriate screens and the same six pairing digits on
   the two actual displays. Do not start the transfer yet.

**Verdict:** scoped PASS for reachable roles, exact debug-paste entry and matching
displays. Camera scan is NOT RUN. Wrong-role/unrelated QR admission is FAIL.

## TRANSFER-003 — matching code and refusal before cutover

1. With a fresh session and genuinely matching displays, leave the source's
   confirmation screen through its supported Back/Cancel route **before Start
   transfer**. Require no completed move, no source retired block and no active
   imported account on the receiver.
2. Reopen both owned apps. Source markers and active-account usability must
   remain; existing authority observations must show no cutover. Observe the
   original attempt's settlement window for a late completion that overrides
   cancellation. UI text alone is not durable authority proof.
3. If codes actually differ, refuse via the same supported route. Do not modify
   a displayed code or transcript and call it authenticated mismatch coverage.
   With no existing mismatch route, report that subcase NOT RUN separately.
4. **After all negative/cancel cases**, use a fresh receiver session, compare
   both displays, then Start transfer once. Require completion, receiver
   activation and source retirement within the existing T011 deadline. Retain
   these as the positive matching-code leg and the recovery retry for 007.

**Verdict:** report matching/Cancel/mismatch legs separately. Any cutover after
refusal or cancellation is FAIL; an unobserved authority/mismatch leg is NOT RUN.

## TRANSFER-002 — reject bad codes and preserve a valid retry

Use the debug paste route for each input; never send QR payloads in mail.

1. **Malformed:** paste invalid/truncated input. **Wrong kind:** paste an existing
   disposable contact QR rather than a migration QR. Require explicit rejection,
   no export/transfer authority and unchanged source data.
2. **Expired:** save a genuine receiver QR and let its original `expiresAt`
   pass, then paste that original input. The current default TTL is five minutes;
   preserve the actual generated deadline and schedule this wait explicitly.
   Do not change system clocks or edit a timestamp and call it natural expiry.
3. **Reused:** retain the QR from a pre-transfer authorization/Cancel attempt
   in 003. Before its expiry, paste it again on the same source. Require the
   existing **already used** authorization result. A fresh rejection caused by
   expiry, a disconnected receiver or a different session is not reuse proof.
4. After every rejection, a fresh legitimate receiver session must still reach
   matching-code confirmation. Do not press Start until the final positive run.

**Verdict:** list all four subcases. Admitting any rejected input is FAIL. If the
existing workflow cannot distinguish a still-valid consumed-session rejection,
mark reused NOT RUN; do not introduce a fixture. Future-time/crossed-key and
untrusted-channel combinations remain outside this requested device subset.

## TRANSFER-007 — cancellation/interruption before commit

1. Use existing source data and a fresh receiver session. Start a move, then
   witness **transfer in progress before durable cutover** with the existing
   stage/authority receipt. A tap, spinner or arbitrary sleep does not establish
   this boundary. If already finalizing/completed, record a missed cut; do not
   undo a completed account or call it a cancellation failure.
2. In one attempt choose **Cancel transfer**. In a separate fresh attempt use
   Appium to terminate only the owned source package at the same witnessed
   pre-cutover boundary, retaining its process-death observation. Do not change
   global network settings or stop another owner's process.
3. Relaunch the same packages/data. Source account/profile/history markers and
   existing native active-state observations must be intact. The receiver must
   have no activated imported account; existing cleanup receipts must show only
   that session's staging removed and unrelated files preserved. Do not manually
   delete staging or repair database/key state to obtain this result.
4. Reject late success for the cancelled attempt. Complete the fresh legitimate
   retry in 003 only after these observations, preserving the first attempts.

**Verdict:** scoped PASS needs both the verified pre-cutover cut and source/
receiver cleanup witnesses. Lost source authority, activated partial receiver or
late cutover is FAIL. Missed cut or unavailable existing native/staging witness
is NOT RUN for that leg; other rows can continue.

## Evidence, scope and cleanup

Today's [T011 summary](/Volumes/CrucialX9/flutter_app/.codex-test-logs/transfer011-20261023T0941Z/SUMMARY.md:10)
records a simulator-receiver PASS: lines 12–13 support 001's pairing entry and
003's positive matching/start leg; lines 14–16 support the representative files
and receiver reopen relevant to 006; lines 16–17 support receiver usability and
source blocking relevant to 010. This does **not** prove their full contracts,
negative cases, complete schema/group/pending-work transfer, receiver DB-key or
push/runtime reconciliation. No rating is upgraded from that evidence alone.
Camera scanning, physical-iPhone receiver and new failure-injection fixtures are
out of scope. Silent voice playback is not intelligible-audio proof.

Return per-row and per-subcase PASS/FAIL/BLOCKED/N/A/NOT RUN, actual candidate/
configuration, original deadlines, first-attempt and cleanup paths, and each
missing witness. Keep raw QR/identity/data contents private. Close only owned
Appium/viewer sessions and restore only state changed by this run; keep unrelated
packages, physical iPhones and retained first-failure evidence untouched.

Source anchors: [QR TTL/parser](../../lib/features/account_migration/application/migration_qr_payload_use_case.dart),
lines 35 and 137–151; [session consumption](../../lib/features/account_migration/application/migration_export_authorization.dart),
lines 66–76; [confirmation/progress UI](../../lib/features/account_migration/presentation/screens/account_migration_journey_screen.dart),
lines 371–425 and 530; [erase confirmation](../../lib/features/account_migration/presentation/screens/account_migration_blocked_screen.dart),
lines 25–60. Shared execution rules follow the existing [Group D runbook](astra-group-d-device-runbook.md).
