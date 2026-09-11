# Historical direct-notification fix — 10 September 2026

Implemented the historical-delivery notification policy and deployed its relay
support at **10:30:02 Berlin time**. The sending phone needs the updated app to
use this policy. No TestFlight/App Store release was published in this task.

## Behavior

The app now consults existing durable sender delivery state immediately before
protected initial-message relay storage. A matching original that is already
delivered/read requests `suppressNotification: true`. This works for existing
custody rows and does not require a database migration or a notification record
from before the relay update.

The proof matches the stored immutable envelope, message/sender/recipient and
creation identity against the canonical delivered successor. It deliberately
does not infer delivery from age, a missing parent, edits, or another device's
delivery status. An absent or failed proof preserves normal notifications.

Both foreground and headless production composition supply the scoped database
check. The Dart bridge and native Go node forward the optional flag outside the
encrypted envelope. Existing callers omit it and retain their previous wire
shape and custody contracts.

The relay accepts the immutable message into custody and suppresses new rich,
opaque and delayed-wake scheduling for valid hinted initial direct messages.
Accepted stores/duplicates also seed the exact existing notification admission
key, preventing an older delayed iOS wake that has not already acquired
provider admission. History-write failures remain observable; they do not
turn the explicit no-notification request into a notification.

The flag is transient and is not persisted in custody. Stored bytes, expiry,
authenticated sender attribution and ACK behavior are preserved. Edits and
unhinted messages keep their existing notification behavior.

## Deployment

- New binary SHA-256: `54edf470da3e37c79aeaad3156c9124d82cd2bb9c14ba099c77a60f4839bf864`.
- Previous binary SHA-256: `47005789a3014a840859863546c689f096394017687077ddaf03430c9ce274ec`.
- Backup: `/var/backups/mknoon-relay/history-fix-20260910T082957Z/relay-server`.
- Process: `1094873`, started `2026-09-10 08:29:57 UTC`.
- Verified active service, exact binary hash, new implementation marker,
  metrics availability, durable Redis backend and enabled push service.
- Configuration, stored messages and Redis records were not bulk rewritten.

The deployment script verified both the uploaded artifact and the unchanged
previous live hash, saved a backup, installed atomically, restarted the service
and checked health. Its first invocation refused an incomplete upload before
changing the live binary; after upload completion the deployment succeeded.

## Validation

- Sender DB/custody suites: 65 passing tests, including 21 new history and
  preservation cases. Includes an existing delivered/read row after reopening
  the real database and proves custody still completes with unchanged bytes.
- Dart bridge/coordinator suites: 12 passing tests, including seven new cases.
- Constructor/production ownership contract: four passing tests after explicitly
  adding the optional callback to the frozen API and checking both DB owners.
- Targeted Dart analysis: no issues.
- Native mobile bridge regression first failed because the new flag was lost.
  It now passes through an actual local framed relay for legacy, protected and
  media-expiry requests; ordinary requests still omit the new field.
- Full Go bridge package: pass, 146.431 seconds.
- Full Go node package: pass, 384.746 seconds.
- New relay historical, wire and wake tests plus existing replay/ACK/wake
  preservation tests: pass.
- Full relay suite: pass, 201.924 seconds, pinned Go 1.25.0.
- iOS Go and NSE frameworks rebuilt and binding verification passed.
- Android Go AAR rebuilt and full ZIP validation passed for all four ABIs.
  SHA-256: `f6c16f714b2b49cf7ee4c70bbb71df542ffdfe98e2fc7b336588f6b1e07f78fa`.
- Core-host Flutter batch: 3,955 passing tests and two initial frozen-source
  fingerprint failures. Removing only the new bootstrap callback exactly
  reproduces the old fingerprint; the updated DTR18 suite passes all four
  tests and preserves that old-baseline assertion. No production correction
  was required after the batch. Exact DTR18 outputs are in
  `dtr18-historical-contract.log` and `dtr18-historical-analyze.log`; both
  pinned Flutter and Dart analysis reported no issues.
- The 1:1 curated Flutter batch passed: 3,747 tests, four skipped, 222 test
  paths. The initial run's sole failing constructor assertion was fixed. A
  subsequent runner diagnostic was reproduced as a concurrent script-edit
  issue; no tests or cleanup were skipped. See `host-runner-audit.md`.
- Both remaining core-host Android manifest contracts passed when run
  sequentially: renderer (Gradle 18 seconds) and dropped-push recovery (Gradle
  six seconds). Initial parallel invocations collided on the generated AAR and
  stamp; a single rebuild repaired those generated outputs before the final
  checks. Archive integrity and its hash remained unchanged after both passes.
  See `core-android-renderer-contract-final.log`,
  `core-dropped-push-contract-final.log` and `host-runner-audit.md`.

The core lane was completed by its original batch plus the exact corrected
DTR18 rerun and both non-Flutter tails; it was not rerun as one full command.

Logs, the source hash manifest and the rollback-capable deployment script are
stored beside this report. This validation uses deterministic host/native
boundaries; it does not claim an updated sender-phone reproduction.

## Operational limit

An older sender app still sends the old request and therefore cannot convey its
historical delivery knowledge. The original no-hint predeployment reproducer
remains a demonstration of that old-client limitation. Deploying relay support
alone cannot reconstruct already-deleted ACK history. A push already accepted
by the provider cannot be retracted by this change.

Opted-in linked-device fanout remains outside the scalar delivery proof. Its
current database stores aggregate delivery rather than durable delivery for
each physical recipient, so treating a sibling's receipt as proof would risk
silencing an undelivered device. The default primary-send path uses scalar
custody and is covered. This task does not claim fanout historical backfill.
