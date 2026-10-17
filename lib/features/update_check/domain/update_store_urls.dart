/// Store pages the update prompts open (SE-41). They are built in on purpose:
/// the version file never supplies a URL.
library;

import 'update_check_models.dart';

/// Public TestFlight invitation while iOS distribution is beta-only.
/// HTTPS also offers installation instructions when TestFlight is absent.
const String updateStoreUrlIos = 'https://testflight.apple.com/join/nUVjrEYS';

/// Google Play page for the production application id.
const String updateStoreUrlAndroid =
    'https://play.google.com/store/apps/details?id=com.mknoon.app';

Uri updateStoreUrlFor(UpdatePlatform platform) => Uri.parse(switch (platform) {
  UpdatePlatform.ios => updateStoreUrlIos,
  UpdatePlatform.android => updateStoreUrlAndroid,
});
