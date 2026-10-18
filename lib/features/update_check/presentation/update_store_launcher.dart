import 'package:url_launcher/url_launcher.dart';

import '../application/update_check_fixture.dart';
import '../domain/update_check_models.dart';
import '../domain/update_store_urls.dart';

/// Opens a built-in store page. Tests replace it.
typedef UpdateStoreLauncher = Future<bool> Function(Uri storeUrl);

Future<bool> launchUpdateStore(Uri storeUrl) async {
  try {
    await recordUpdateCheckFixtureStoreOpen(storeUrl);
    return await launchUrl(storeUrl, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// The store page for [platform]. Off iOS and Android there is no check, so
/// the Play page is only a safe fallback.
Uri updateStoreUrlForPlatform(UpdatePlatform? platform) =>
    updateStoreUrlFor(platform ?? UpdatePlatform.android);
