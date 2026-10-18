/// The disposable variant is an explicit host choice. It never infers a phone
/// from an available target, and never labels an emulator as physical evidence.
bool usesDisposableAndroidPair(Map<String, String> environment) =>
    environment['SIMS_DISPOSABLE_ANDROID_JOURNEYS'] == '1';

String androidCampaignFirstTargetEnvironment(Map<String, String> environment) =>
    usesDisposableAndroidPair(environment)
    ? 'SIMS_ANDROID_EMULATOR_FOURTH_DEVICE_ID'
    : 'SIMS_ANDROID_PHYSICAL_DEVICE_ID';

String androidCampaignFirstTargetKind(Map<String, String> environment) =>
    usesDisposableAndroidPair(environment) ? 'emulator' : 'physical';

bool androidCampaignPairMatchesQemu({
  required String first,
  required String second,
  required bool disposable,
}) =>
    second.trim() == '1' &&
    (disposable ? first.trim() == '1' : const {'', '0'}.contains(first.trim()));
