/// Exact signed profile used only by the physical-iPhone Plan 397 fixture
/// setup build. Ordinary profile/release builds never receive this define.
const String groupReactionNotificationIosSetupBuildProfile =
    'ios.device.group_reaction_notification_397';

/// Keeps the generic intro fixture actions closed unless the one signed
/// Plan 397 setup product also explicitly enables E2E mode.
bool allowsGroupReactionNotificationIosSetupActions({
  required bool e2eTestMode,
  required String installedProfileId,
}) =>
    e2eTestMode &&
    installedProfileId == groupReactionNotificationIosSetupBuildProfile;
