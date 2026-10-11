/// Persisted state of the SE-41 update check.
library;

import 'dart:convert';
import 'dart:typed_data';

/// Everything the update check remembers between launches.
///
/// The envelope is trusted only after it is re-verified at launch against the
/// built-in keys and the rank rule; the signature gives integrity, so the file
/// needs no secrecy.
class UpdateCheckState {
  const UpdateCheckState({
    this.lastEnvelope,
    this.highestAcceptedRank = 0,
    this.sequence,
    this.lastCheckAt,
    this.dismissedLatestBuild,
  });

  static const UpdateCheckState empty = UpdateCheckState();

  static const int _formatVersion = 1;

  final Uint8List? lastEnvelope;
  final int highestAcceptedRank;

  /// Sequence of [lastEnvelope] within [highestAcceptedRank].
  final int? sequence;
  final DateTime? lastCheckAt;
  final int? dismissedLatestBuild;

  /// Drops the envelope, rank and sequence; keeps the schedule and dismissal.
  UpdateCheckState withoutVerifiedFile() => UpdateCheckState(
    lastCheckAt: lastCheckAt,
    dismissedLatestBuild: dismissedLatestBuild,
  );

  UpdateCheckState copyWith({
    Uint8List? lastEnvelope,
    int? highestAcceptedRank,
    int? sequence,
    DateTime? lastCheckAt,
    int? dismissedLatestBuild,
  }) => UpdateCheckState(
    lastEnvelope: lastEnvelope ?? this.lastEnvelope,
    highestAcceptedRank: highestAcceptedRank ?? this.highestAcceptedRank,
    sequence: sequence ?? this.sequence,
    lastCheckAt: lastCheckAt ?? this.lastCheckAt,
    dismissedLatestBuild: dismissedLatestBuild ?? this.dismissedLatestBuild,
  );

  Map<String, Object?> toJson() => {
    'format': _formatVersion,
    if (lastEnvelope != null) 'lastEnvelope': base64.encode(lastEnvelope!),
    'highestAcceptedRank': highestAcceptedRank,
    if (sequence != null) 'sequence': sequence,
    if (lastCheckAt != null)
      'lastCheckAtMs': lastCheckAt!.toUtc().millisecondsSinceEpoch,
    if (dismissedLatestBuild != null)
      'dismissedLatestBuild': dismissedLatestBuild,
  };

  /// Returns null for anything corrupt; the caller then starts empty.
  static UpdateCheckState? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    if (json['format'] != _formatVersion) return null;
    final envelope = json['lastEnvelope'];
    final rank = json['highestAcceptedRank'];
    final sequence = json['sequence'];
    final lastCheckAtMs = json['lastCheckAtMs'];
    final dismissed = json['dismissedLatestBuild'];
    if (envelope != null && envelope is! String) return null;
    if (rank is! int || rank < 0) return null;
    if (sequence != null && (sequence is! int || sequence < 0)) return null;
    if (lastCheckAtMs != null && lastCheckAtMs is! int) return null;
    if (dismissed != null && dismissed is! int) return null;
    Uint8List? envelopeBytes;
    if (envelope is String) {
      try {
        envelopeBytes = base64.decode(envelope);
      } on FormatException {
        return null;
      }
    }
    return UpdateCheckState(
      lastEnvelope: envelopeBytes,
      highestAcceptedRank: rank,
      sequence: sequence as int?,
      lastCheckAt: lastCheckAtMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              lastCheckAtMs as int,
              isUtc: true,
            ),
      dismissedLatestBuild: dismissed as int?,
    );
  }
}
