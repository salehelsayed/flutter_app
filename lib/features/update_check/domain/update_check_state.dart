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
    this.notifiedSoftLatestBuild,
    this.lastHardNotifyAt,
    this.hardReminderCount = 0,
    this.notifiedHardMinBuild,
  });

  static const UpdateCheckState empty = UpdateCheckState();

  static const int _formatVersion = 1;

  final Uint8List? lastEnvelope;
  final int highestAcceptedRank;

  /// Sequence of [lastEnvelope] within [highestAcceptedRank].
  final int? sequence;
  final DateTime? lastCheckAt;
  final int? dismissedLatestBuild;

  // T4a background notification state. The store merges these by max.

  /// The latestBuild of the last soft notification (once per latestBuild).
  final int? notifiedSoftLatestBuild;

  /// When the last hard notification was posted.
  final DateTime? lastHardNotifyAt;

  /// Hard notifications posted for [notifiedHardMinBuild], the first included.
  final int hardReminderCount;

  /// The minBuild the hard reminders count for. A higher minBuild starts over.
  final int? notifiedHardMinBuild;

  /// Drops the stored envelope only. The rank and sequence stay: they must
  /// never go down (T4a), so a later file still needs a higher sequence or a
  /// higher rank.
  UpdateCheckState withoutVerifiedFile() => UpdateCheckState(
    highestAcceptedRank: highestAcceptedRank,
    sequence: sequence,
    lastCheckAt: lastCheckAt,
    dismissedLatestBuild: dismissedLatestBuild,
    notifiedSoftLatestBuild: notifiedSoftLatestBuild,
    lastHardNotifyAt: lastHardNotifyAt,
    hardReminderCount: hardReminderCount,
    notifiedHardMinBuild: notifiedHardMinBuild,
  );

  UpdateCheckState copyWith({
    Uint8List? lastEnvelope,
    int? highestAcceptedRank,
    int? sequence,
    DateTime? lastCheckAt,
    int? dismissedLatestBuild,
    int? notifiedSoftLatestBuild,
    DateTime? lastHardNotifyAt,
    int? hardReminderCount,
    int? notifiedHardMinBuild,
  }) => UpdateCheckState(
    lastEnvelope: lastEnvelope ?? this.lastEnvelope,
    highestAcceptedRank: highestAcceptedRank ?? this.highestAcceptedRank,
    sequence: sequence ?? this.sequence,
    lastCheckAt: lastCheckAt ?? this.lastCheckAt,
    dismissedLatestBuild: dismissedLatestBuild ?? this.dismissedLatestBuild,
    notifiedSoftLatestBuild:
        notifiedSoftLatestBuild ?? this.notifiedSoftLatestBuild,
    lastHardNotifyAt: lastHardNotifyAt ?? this.lastHardNotifyAt,
    hardReminderCount: hardReminderCount ?? this.hardReminderCount,
    notifiedHardMinBuild: notifiedHardMinBuild ?? this.notifiedHardMinBuild,
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
    if (notifiedSoftLatestBuild != null)
      'notifiedSoftLatestBuild': notifiedSoftLatestBuild,
    if (lastHardNotifyAt != null)
      'lastHardNotifyAtMs': lastHardNotifyAt!.toUtc().millisecondsSinceEpoch,
    if (hardReminderCount != 0) 'hardReminderCount': hardReminderCount,
    if (notifiedHardMinBuild != null)
      'notifiedHardMinBuild': notifiedHardMinBuild,
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
    final notifiedSoft = json['notifiedSoftLatestBuild'];
    final lastHardMs = json['lastHardNotifyAtMs'];
    final hardCount = json['hardReminderCount'] ?? 0;
    final notifiedHard = json['notifiedHardMinBuild'];
    if (envelope != null && envelope is! String) return null;
    if (rank is! int || rank < 0) return null;
    if (sequence != null && (sequence is! int || sequence < 0)) return null;
    if (lastCheckAtMs != null && lastCheckAtMs is! int) return null;
    if (dismissed != null && dismissed is! int) return null;
    if (notifiedSoft != null && notifiedSoft is! int) return null;
    if (lastHardMs != null && lastHardMs is! int) return null;
    if (hardCount is! int || hardCount < 0) return null;
    if (notifiedHard != null && notifiedHard is! int) return null;
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
      notifiedSoftLatestBuild: notifiedSoft as int?,
      lastHardNotifyAt: lastHardMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(lastHardMs as int, isUtc: true),
      hardReminderCount: hardCount,
      notifiedHardMinBuild: notifiedHard as int?,
    );
  }

  /// Merge-on-write (T4a). [disk] is the file as re-read under the lock;
  /// [incoming] is what a writer wants to save, possibly from a stale read.
  ///
  /// - Rank, sequence and envelope move together and never go down: the
  ///   higher (rank, sequence) wins. On a tie the incoming envelope wins, so a
  ///   writer may drop an envelope that no longer verifies, but not its rank.
  /// - lastCheckAt is a schedule, not a security field: the incoming value
  ///   wins, so a clock that went back can still move it back.
  /// - dismissedLatestBuild and notifiedSoftLatestBuild merge by max.
  /// - The hard reminder fields merge as one tuple by max, ordered by
  ///   (notifiedHardMinBuild, hardReminderCount, lastHardNotifyAt), so a
  ///   higher minBuild can restart the count.
  static UpdateCheckState merge(UpdateCheckState disk, UpdateCheckState incoming) {
    final verified = _compareVerified(incoming, disk) >= 0 ? incoming : disk;
    final hard = _compareHard(incoming, disk) >= 0 ? incoming : disk;
    return UpdateCheckState(
      lastEnvelope: verified.lastEnvelope,
      highestAcceptedRank: verified.highestAcceptedRank,
      sequence: verified.sequence,
      lastCheckAt: incoming.lastCheckAt ?? disk.lastCheckAt,
      dismissedLatestBuild: _maxOrNull(
        disk.dismissedLatestBuild,
        incoming.dismissedLatestBuild,
      ),
      notifiedSoftLatestBuild: _maxOrNull(
        disk.notifiedSoftLatestBuild,
        incoming.notifiedSoftLatestBuild,
      ),
      lastHardNotifyAt: hard.lastHardNotifyAt,
      hardReminderCount: hard.hardReminderCount,
      notifiedHardMinBuild: hard.notifiedHardMinBuild,
    );
  }

  static int _compareVerified(UpdateCheckState a, UpdateCheckState b) {
    final byRank = a.highestAcceptedRank.compareTo(b.highestAcceptedRank);
    if (byRank != 0) return byRank;
    return (a.sequence ?? -1).compareTo(b.sequence ?? -1);
  }

  static int _compareHard(UpdateCheckState a, UpdateCheckState b) {
    final byMin = (a.notifiedHardMinBuild ?? -1).compareTo(
      b.notifiedHardMinBuild ?? -1,
    );
    if (byMin != 0) return byMin;
    final byCount = a.hardReminderCount.compareTo(b.hardReminderCount);
    if (byCount != 0) return byCount;
    return (a.lastHardNotifyAt?.millisecondsSinceEpoch ?? -1).compareTo(
      b.lastHardNotifyAt?.millisecondsSinceEpoch ?? -1,
    );
  }

  static int? _maxOrNull(int? a, int? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a > b ? a : b;
  }
}
