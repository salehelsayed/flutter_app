import 'package:flutter_app/core/utils/flow_event_emitter.dart';

/// Build provenance, injected at compile time via `--dart-define`.
///
/// Populate from the build command, e.g.:
/// ```
/// flutter run \
///   --dart-define=GIT_SHA=$(git rev-parse --short HEAD) \
///   --dart-define=GIT_DIRTY=$([ -n "$(git status --porcelain)" ] && echo 1 || echo 0) \
///   --dart-define=BUILD_TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
/// ```
/// All three default to empty when the defines are not supplied (e.g. a plain
/// `flutter run`).
const String appBuildGitSha = String.fromEnvironment('GIT_SHA');
const String appBuildGitDirty = String.fromEnvironment('GIT_DIRTY');
const String appBuildTimestamp = String.fromEnvironment('BUILD_TIMESTAMP');

/// Emits a one-time `APP_BUILD_INFO` FLOW milestone at app startup so device
/// and harness logs can be matched against the exact source revision under
/// test. This is the build-provenance gate for the "fixed in the working tree
/// but broken on device" (build-skew) class of bugs: grep the device log for
/// `APP_BUILD_INFO` and confirm `gitSha` equals the commit you built — if it
/// does not, the device ran a stale binary.
void emitAppBuildInfo() {
  emitFlowEvent(
    layer: 'FL',
    event: 'APP_BUILD_INFO',
    details: {
      'gitSha': appBuildGitSha,
      'gitDirty': appBuildGitDirty,
      'buildTimestamp': appBuildTimestamp,
    },
  );
}
