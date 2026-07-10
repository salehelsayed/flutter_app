import 'dart:convert';

/// 229: product conversation kinds distinguished by the media auto-download
/// policy.
///
/// Announcements and discussions are distinct PRODUCT kinds even though both
/// persist attachments under the group storage owner lane — the preference
/// matrix and the policy keep them separate, while storage stays two-lane
/// (see `MediaOwnerLane`).
enum MediaConversationKind { oneToOne, discussion, announcement }

/// Network classes the download policy distinguishes.
///
/// Roaming is an accepted difference: current dependencies cannot detect it,
/// so roaming applies the [cellular] choice until a native network-context
/// owner exists. Do not advertise a distinct roaming toggle.
enum MediaDownloadNetwork { wifi, cellular }

/// Logical media types carried in the preference matrix. Matches
/// `MediaAttachment.mediaTypeFromMime` ('image' | 'video' | 'audio' | 'file').
const List<String> kMediaDownloadPreferenceTypes = <String>[
  'image',
  'video',
  'audio',
  'file',
];

/// Versioned, user-controlled automatic-download matrix.
///
/// Every (lane, media type, network) cell is ENABLED by default so upgrades
/// preserve HEAD behavior; only cells the user explicitly switched off are
/// persisted as disabled. A missing, corrupt or unknown-version stored value
/// decodes to the enabled defaults (never to a silently-restrictive or
/// silently-permissive partial matrix).
class MediaDownloadPreferences {
  static const String storageKey = 'media_download_preferences';
  static const int codecVersion = 1;

  /// Entry keys (`kind/type/network`) the user switched OFF. Absent = enabled.
  final Set<String> _disabled;

  const MediaDownloadPreferences.defaults() : _disabled = const <String>{};

  const MediaDownloadPreferences._(this._disabled);

  static String _entryKey(
    MediaConversationKind kind,
    String mediaType,
    MediaDownloadNetwork network,
  ) =>
      '${kind.name}/$mediaType/${network.name}';

  /// Whether automatic download is enabled for this cell. Unknown media types
  /// stay enabled (HEAD auto-downloads every supported attachment).
  bool isAutoDownloadEnabled({
    required MediaConversationKind kind,
    required String mediaType,
    required MediaDownloadNetwork network,
  }) =>
      !_disabled.contains(_entryKey(kind, mediaType, network));

  MediaDownloadPreferences copyWithChoice({
    required MediaConversationKind kind,
    required String mediaType,
    required MediaDownloadNetwork network,
    required bool enabled,
  }) {
    final next = Set<String>.of(_disabled);
    final key = _entryKey(kind, mediaType, network);
    if (enabled) {
      next.remove(key);
    } else {
      next.add(key);
    }
    return MediaDownloadPreferences._(Set.unmodifiable(next));
  }

  /// Encodes the full explicit matrix so a stored payload is self-describing.
  String toStorageString() {
    final lanes = <String, Map<String, Map<String, bool>>>{};
    for (final kind in MediaConversationKind.values) {
      final types = <String, Map<String, bool>>{};
      for (final type in kMediaDownloadPreferenceTypes) {
        final networks = <String, bool>{};
        for (final network in MediaDownloadNetwork.values) {
          networks[network.name] = isAutoDownloadEnabled(
            kind: kind,
            mediaType: type,
            network: network,
          );
        }
        types[type] = networks;
      }
      lanes[kind.name] = types;
    }
    return jsonEncode(<String, Object>{
      'version': codecVersion,
      'lanes': lanes,
    });
  }

  /// Decodes a stored value; null, corrupt, structurally-invalid and
  /// unknown-version payloads all fail safely to the enabled defaults.
  /// Missing lanes/types/networks inside a valid payload stay enabled.
  static MediaDownloadPreferences fromStorageString(String? value) {
    if (value == null || value.isEmpty) {
      return const MediaDownloadPreferences.defaults();
    }
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map<String, dynamic>) {
        return const MediaDownloadPreferences.defaults();
      }
      if (decoded['version'] != codecVersion) {
        return const MediaDownloadPreferences.defaults();
      }
      final lanes = decoded['lanes'];
      if (lanes is! Map<String, dynamic>) {
        return const MediaDownloadPreferences.defaults();
      }
      final disabled = <String>{};
      for (final kind in MediaConversationKind.values) {
        final lane = lanes[kind.name];
        if (lane is! Map<String, dynamic>) continue;
        for (final type in kMediaDownloadPreferenceTypes) {
          final networks = lane[type];
          if (networks is! Map<String, dynamic>) continue;
          for (final network in MediaDownloadNetwork.values) {
            if (networks[network.name] == false) {
              disabled.add(_entryKey(kind, type, network));
            }
          }
        }
      }
      return MediaDownloadPreferences._(Set.unmodifiable(disabled));
    } on FormatException {
      return const MediaDownloadPreferences.defaults();
    }
  }

  @override
  bool operator ==(Object other) =>
      other is MediaDownloadPreferences &&
      other._disabled.length == _disabled.length &&
      other._disabled.containsAll(_disabled);

  @override
  int get hashCode => Object.hashAllUnordered(_disabled);
}
