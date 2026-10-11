/// Pure decision and schedule rules for the SE-41 update check.
library;

import 'update_check_models.dart';

/// How often a running app checks again.
const Duration updateCheckInterval = Duration(hours: 6);

/// installed < minBuild -> hard. Else installed < latestBuild and the user has
/// not dismissed this latestBuild -> soft. Else none. A build number that is
/// not an integer -> none.
UpdateDecision decideUpdate({
  required String installedBuildNumber,
  required UpdatePlatformPolicy? policy,
  required int? dismissedLatestBuild,
}) {
  final installed = int.tryParse(installedBuildNumber.trim());
  if (installed == null || policy == null) return const UpdateDecisionNone();
  if (installed < policy.minBuild) {
    return UpdateDecisionHard(
      minBuild: policy.minBuild,
      reasonCode: policy.reasonCode,
    );
  }
  if (installed < policy.latestBuild &&
      dismissedLatestBuild != policy.latestBuild) {
    return UpdateDecisionSoft(
      latestBuild: policy.latestBuild,
      reasonCode: policy.reasonCode,
    );
  }
  return const UpdateDecisionNone();
}

/// Due at launch (no check yet in this process), when the last check is more
/// than [updateCheckInterval] old, or when the clock went back.
bool isUpdateCheckDue({
  required DateTime now,
  required DateTime? lastCheckAt,
  required bool checkedThisLaunch,
}) {
  if (!checkedThisLaunch || lastCheckAt == null) return true;
  if (now.isBefore(lastCheckAt)) return true;
  return now.difference(lastCheckAt) > updateCheckInterval;
}
