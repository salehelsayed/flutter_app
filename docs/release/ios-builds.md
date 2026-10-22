# iOS build log

Convention (owner-approved 2026-10-10, SE-32):
- Marketing version and build number live only in pubspec.yaml (`version: <marketing>+<build>`).
- Build number: +1 for every archive uploaded to App Store Connect. Never reset (not even when the marketing version changes) and never reuse a number, even after a failed or abandoned upload. Android shares the same counter.
- Before each Xcode Archive:
  - Regenerate the iOS Flutter settings from pubspec without --build-name or --build-number overrides (e.g. `flutter build ios --release --config-only`).
  - Confirm Xcode Runner > General shows the expected Version (Build).
  - Archive from a clean commit.
- Tag the released commit `ios-<version>-<build>` (e.g. ios-1.0.1-124).
- Add one line per release candidate at archive time. Replace PENDING with the App Store Connect build ID once processing finishes.

Format:
date | marketing version | build | platform | commit SHA | tag | ASC build ID or PENDING | note

## Builds

(Backfilled 2026-10-10. Commits for builds made before this log are UNKNOWN. Fill every <FAJR:...> placeholder from the read-only App Store Connect inventory.)

<FAJR:date> | <FAJR:version> | <FAJR:build> | iOS | UNKNOWN | none | <FAJR:asc-build-id> | backfill, VALID
<FAJR:date> | <FAJR:version> | <FAJR:build> | iOS | UNKNOWN | none | <FAJR:asc-build-id> | backfill, VALID
<FAJR:date> | <FAJR:version> | <FAJR:build> | iOS | UNKNOWN | none | <FAJR:asc-build-id> | backfill, VALID
<FAJR:date> | <FAJR:version> | <FAJR:build> | iOS | UNKNOWN | none | <FAJR:asc-build-id> | backfill, VALID
<FAJR:date> | <FAJR:version> | 123 | iOS | UNKNOWN | none | <FAJR:asc-build-id> | backfill, VALID, newest
2026-10-22 | 1.0.1 | 126 | iOS | 9ec2091a3 | none | PENDING | store build from origin/main f14f7d369, not uploaded yet

(Rows oldest first. The only known fact is that the newest build is 123. Fill nothing else in.)

## Update check after each release (SE-41)

Every shipped build reads the signed version file at
`https://updates.mknoon.xyz/mknoon/version.json`. After a release, update it
as follows. The full steps are in the
[update check runbook](se41-update-check-runbook.md).

1. When the new build is live in both stores, publish a new version file with
   `latestBuild` set to the new build number. Keep `minBuild` as it is. Older
   builds then show the soft update notice. They keep working.
2. Raise `minBuild` only when every condition in runbook
   [§6](se41-update-check-runbook.md#6-when-to-raise-minbuild-o8) is true:
   100% phased release, live in every store country, and installable on the
   oldest supported iOS and Android versions. Builds below `minBuild` show the
   forced update screen.
3. Every new file needs a higher `sequence` than the last one published. Never
   reuse or lower a `sequence` (runbook
   [§3](se41-update-check-runbook.md#3-sequence-rules)).
4. The owner signs the file offline with k1. Publishing it to the update host
   needs the owner's approval.
5. To undo a `minBuild` raise, publish a new file with a lower `minBuild` and a
   higher `sequence`. Never delete the file (runbook
   [§5](se41-update-check-runbook.md#5-rollback)).
