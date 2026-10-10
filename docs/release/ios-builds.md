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

(Rows oldest first. The only known fact is that the newest build is 123. Fill nothing else in.)
