import 'package:flutter_app/features/contact_request/domain/repositories/contact_repair_repository.dart';

/// Task 12b, owner decision "1. (a)": automatic repair runs only between
/// phones verified as updated in the coordinated rollout. There is no
/// mixed-version fallback: an older receiver rejects the signed marker, so an
/// initiator must never guess.
///
/// The coordinated rollout build sets `--dart-define=CONTACT_REPAIR_ROLLOUT=true`.
/// Absent, every initiating send stays unmarked (today's behaviour). Receiving
/// is always on: a valid stored-authority-signed marker proves its sender is
/// updated, so an updated receiver may answer it.
const bool contactRepairRolloutEnabled = bool.fromEnvironment(
  'CONTACT_REPAIR_ROLLOUT',
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
