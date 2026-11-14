import 'package:flutter_app/features/contact_request/domain/repositories/contact_repair_repository.dart';

/// Task 12b sends the signed marker so a receiver that still holds us as a
/// contact replies once with its key (BL-21: a one-sided QR re-add otherwise
/// deadlocks). On by default: every build at or above minBuild 126 already
/// receives the marker. `--dart-define=CONTACT_REPAIR_ROLLOUT=false` is the
/// off switch. Receiving is always on.
const bool contactRepairRolloutEnabled = bool.fromEnvironment(
  'CONTACT_REPAIR_ROLLOUT',
  defaultValue: true,
);

/// Eligibility from the rollout flag alone.
Future<bool> contactRepairRolloutEligible(String peerId) async =>
    contactRepairRolloutEnabled;

/// Eligibility for one peer: the coordinated rollout flag, or a peer that has
/// itself sent us a valid signed marker. An ordinary ACK, an unsigned header,
/// a peer-ID prefix or a timeout is never evidence.
Future<bool> Function(String peerId) contactRepairEligibility({
  required ContactRepairRepository? repository,
  bool rolloutEnabled = contactRepairRolloutEnabled,
}) => (peerId) async {
  if (rolloutEnabled) return true;
  return await repository?.peerSupportsMarked(peerId) ?? false;
};
