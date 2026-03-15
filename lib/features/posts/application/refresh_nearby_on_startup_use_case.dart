import 'package:flutter/foundation.dart';
import 'package:flutter_app/features/posts/application/nearby_location_service.dart';

Future<void> refreshNearbyOnStartup({
  NearbyLocationService? nearbyLocationService,
}) async {
  if (nearbyLocationService == null) {
    return;
  }
  try {
    await nearbyLocationService.refreshSilentlyOnStartup();
  } catch (error) {
    debugPrint('[POSTS] refreshNearbyOnStartup failed: $error');
  }
}
