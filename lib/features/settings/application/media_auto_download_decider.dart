import 'package:connectivity_plus/connectivity_plus.dart';

import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/settings/application/media_download_policy.dart';
import 'package:flutter_app/features/settings/application/media_download_preference_use_cases.dart';
import 'package:flutter_app/features/settings/domain/models/media_download_preferences.dart';

/// Classifies the current network for the download policy.
///
/// Any active Wi-Fi/ethernet interface counts as [MediaDownloadNetwork.wifi];
/// a mobile-only connection is [MediaDownloadNetwork.cellular] (roaming is an
/// accepted difference — it applies the cellular choice). With no or unknown
/// connectivity the classifier answers wifi so the policy stays permissive
/// exactly like HEAD; the transfer itself still fails honestly offline.
Future<MediaDownloadNetwork> resolveMediaDownloadNetwork({
  Connectivity? connectivity,
}) async {
  try {
    final results = await (connectivity ?? Connectivity()).checkConnectivity();
    final hasWifiClass = results.any(
      (r) =>
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.ethernet ||
          r == ConnectivityResult.vpn,
    );
    if (!hasWifiClass && results.contains(ConnectivityResult.mobile)) {
      return MediaDownloadNetwork.cellular;
    }
    return MediaDownloadNetwork.wifi;
  } catch (_) {
    return MediaDownloadNetwork.wifi;
  }
}

/// Production [MediaAutoDownloadDecider]: resolves the persisted preference
/// matrix and the current network class per decision, then delegates to the
/// pure [MediaDownloadPolicy].
///
/// Preference/network resolution failures fall back to the HEAD-compatible
/// enabled defaults / wifi class; owner violations from the pure policy are
/// NOT swallowed (fail closed on untrusted rows).
class PreferenceBackedMediaAutoDownloadDecider
    implements MediaAutoDownloadDecider {
  PreferenceBackedMediaAutoDownloadDecider({
    required Future<MediaDownloadPreferences> Function() loadPreferences,
    required Future<MediaDownloadNetwork> Function() resolveNetwork,
  })  : _loadPreferences = loadPreferences,
        _resolveNetwork = resolveNetwork;

  factory PreferenceBackedMediaAutoDownloadDecider.fromSecureKeyStore({
    required SecureKeyStore secureKeyStore,
    Connectivity? connectivity,
  }) {
    return PreferenceBackedMediaAutoDownloadDecider(
      loadPreferences: () async {
        try {
          return await loadMediaDownloadPreferences(
            secureKeyStore: secureKeyStore,
          );
        } catch (_) {
          return const MediaDownloadPreferences.defaults();
        }
      },
      resolveNetwork: () =>
          resolveMediaDownloadNetwork(connectivity: connectivity),
    );
  }

  final Future<MediaDownloadPreferences> Function() _loadPreferences;
  final Future<MediaDownloadNetwork> Function() _resolveNetwork;

  @override
  Future<bool> shouldAutoDownload({
    required MediaConversationKind conversationKind,
    required MediaOwnerLane? storageOwner,
    required String mediaType,
    required String downloadStatus,
    bool userInitiated = false,
    bool isProtected = false,
  }) async {
    final preferences = await _loadPreferences();
    final network = await _resolveNetwork();
    return MediaDownloadPolicy.shouldAutoDownload(
      preferences: preferences,
      conversationKind: conversationKind,
      storageOwner: storageOwner,
      mediaType: mediaType,
      network: network,
      downloadStatus: downloadStatus,
      userInitiated: userInitiated,
      isProtected: isProtected,
    );
  }
}
