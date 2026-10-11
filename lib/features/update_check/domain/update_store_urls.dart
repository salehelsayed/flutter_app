/// Store pages the update prompts open (SE-41). They are built in on purpose:
/// the version file never supplies a URL.
library;

import 'update_check_models.dart';

/// App Store page for Apple ID 6760883540 (SE-41 O5).
const String updateStoreUrlIos = 'https://apps.apple.com/app/id6760883540';

/// Google Play page for the production application id.
const String updateStoreUrlAndroid =
    'https://play.google.com/store/apps/details?id=com.mknoon.app';

Uri updateStoreUrlFor(UpdatePlatform platform) => Uri.parse(switch (platform) {
  UpdatePlatform.ios => updateStoreUrlIos,
  UpdatePlatform.android => updateStoreUrlAndroid,
});
