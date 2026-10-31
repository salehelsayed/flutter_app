import '../../tool/sims/production_group_gm007_criteria.dart';
import '../../tool/sims/production_group_up012_criteria.dart';
import '../support/media_content_oracle.dart';
import 'contact_transfer_native_evidence.dart';

/// Intentional mixed-version old-key sharing remains allowed. This oracle is
/// honest-client admission/removal and live blob authorization, not secrecy
/// against a modified removed client or possession of earlier ciphertext/keys.
Future<List<String>> validateGroupMediaMembershipEntitlementObservations(
  ContactTransferNativeEvidence evidence,
) async {
  final failures = <String>[];
  final observed = evidence.observations;
  final historyProof = await evidence.json(observed['ra016ProofPath']);
  final notificationProof = await evidence.json(
    observed['removedNotificationProofPath'],
  );
  failures.addAll(validateProductionGroupGm007(historyProof));
  failures.addAll(validateProductionGroupUp012(notificationProof));
  if (historyProof['runId'] != evidence.receipt['runId'] ||
      notificationProof['runId'] != evidence.receipt['runId']) {
    failures.add(
      'existing honest-client supporting proofs must bind the actual current run',
    );
  }
  final window = (
    removed: observed['adminRemovedAtMs'] as int,
    readded: observed['adminReaddedAtMs'] as int,
    accepted: observed['readdAcceptedAtMs'] as int,
  );
  if (!(window.removed < window.readded && window.readded <= window.accepted)) {
    failures.add(
      'exact signed admin removal -> admin re-add -> optional later acceptance boundary required',
    );
  }
  final admissions = journeyGapRows(observed['mediaAdmissions']);
  var afterReaddBeforeAccept = false;
  var removedWindowItems = 0;
  for (final row in admissions) {
    final created = row['createdAtMs'] as int;
    if (created >= window.removed && created < window.readded) {
      removedWindowItems++;
      if (row['honestClientRenderedCount'] != 0 ||
          row['honestClientDownloadAttempts'] != 0) {
        failures.add(
          'honest app must filter removal-window media after replay/re-add',
        );
      }
    } else if (created >= window.readded) {
      if (row['honestClientRenderedCount'] != 1 ||
          row['nativeUsable'] != true) {
        failures.add(
          'eligibility begins at admin re-add, not invitation acceptance or a fresh key epoch',
        );
      }
      if (created < window.accepted) afterReaddBeforeAccept = true;
    }
  }
  if (removedWindowItems == 0) {
    failures.add(
      'an actual removal-window media filtering control is required',
    );
  }
  if (!afterReaddBeforeAccept) {
    failures.add(
      'include an eligible media item between admin re-add and later invitation acceptance',
    );
  }
  final denied = await evidence.json(observed['removedLiveFetchResponsePath']);
  final allowed = await evidence.json(
    observed['authorizedLiveFetchResponsePath'],
  );
  final fetch = journeyGapMap(observed['liveBlobFetch']);
  if ((fetch['requestedAtMs'] as int) < window.removed ||
      (fetch['requestedAtMs'] as int) >= window.readded ||
      fetch['removedPeerIsCurrentMember'] != false ||
      fetch['authenticatedRemovedPeerId'] != observed['removedPeerId'] ||
      (fetch['authenticatedRemovedPeerId'] as String).isEmpty ||
      fetch['authorizedPeerIsCurrentMember'] != true ||
      denied['status'] != 'ERROR' ||
      denied['error'] != 'not authorized' ||
      fetch['removedReadableBytes'] != 0 ||
      allowed['status'] != 'OK' ||
      fetch['removedBlobId'] != fetch['authorizedBlobId'] ||
      (fetch['removedBlobId'] as String).isEmpty) {
    failures.add(
      'actual currently removed peer fetch must be authorization-refused for the same live blob that an authorized member can fetch',
    );
  }
  // Only a newly authored removal-window blob is subject to this refusal
  // control. Pre-removal blobs/retained ACLs and earlier keys remain compatible.
  final matchingAdmissions = admissions
      .where(
        (row) =>
            row['logicalMessageId'] == fetch['logicalMessageId'] &&
            row['blobId'] == fetch['removedBlobId'] &&
            row['createdAtMs'] == fetch['mediaCreatedAtMs'] &&
            (row['createdAtMs'] as int) > window.removed &&
            (row['createdAtMs'] as int) < window.readded,
      )
      .toList();
  if (matchingAdmissions.length != 1 ||
      (fetch['logicalMessageId'] as String).isEmpty) {
    failures.add(
      'live refusal/positive must bind exactly one actual media admission authored after removal and before admin re-add',
    );
    return failures;
  }
  final admission = matchingAdmissions.single;
  final signed = await evidence.json(admission['signedMediaDescriptorPath']);
  if (signed['signatureVerified'] != true ||
      signed['logicalMessageId'] != admission['logicalMessageId'] ||
      signed['blobId'] != admission['blobId'] ||
      signed['createdAtMs'] != admission['createdAtMs'] ||
      (fetch['requestedAtMs'] as int) < (admission['createdAtMs'] as int)) {
    failures.add(
      'logical message/blob identity and creation time must match the actual signed media descriptor before the live fetch',
    );
  }
  final admittedSource = await fingerprintMediaFile(
    evidence.file(admission['sourcePlaintextPath']),
  );
  final source = await fingerprintMediaFile(
    evidence.file(fetch['sourcePlaintextPath']),
  );
  final authorized = await fingerprintMediaFile(
    evidence.file(fetch['authorizedPlaintextPath']),
  );
  if (!admittedSource.sameBytes(source) ||
      !source.sameBytes(authorized) ||
      fetch['authorizedNativeUsable'] != true) {
    failures.add(
      'authorized positive must retain the exact usable source bytes of that signed removal-window admission',
    );
  }
  return failures;
}

Future<void> main(List<String> arguments) async {
  final failures = <String>[];
  var evaluated = false;
  if (arguments.contains('--receipt')) {
    try {
      final evidence = await ContactTransferNativeEvidence.load(
        arguments,
        journeyId: 'MEDIA-037',
        requiredKinds: [
          'honest-client-ra016',
          'removed-notification-proof',
          'signed-membership-boundary',
          'live-blob-fetch',
          'authorized-full-media',
        ],
      );
      evaluated = true;
      failures.addAll(
        await validateGroupMediaMembershipEntitlementObservations(evidence),
      );
    } on ContactTransferCaptureUnavailable {
      // Capture absence is NOT RUN; it is not an app failure.
    } on Object {
      failures.add(
        'MEDIA-037 observations are incomplete, malformed or not independently bound',
      );
    }
  }
  writeContactTransferNativeResult(
    journeyId: 'MEDIA-037',
    ids: ['GC-004', 'GC-006', 'MEDIA-037'],
    captureGap:
        'Existing honest-client removal/RA-016 and notification campaigns are supporting proof; no joined currently removed-peer live blob-fetch refusal with same-blob authorized usable positive capture owner exists.',
    prerequisites: [
      'Strict backward secrecy proposal is cancelled: old-key sharing is intentional, modified removed clients are outside this honest-client proof, and eligibility starts at signed admin re-add.',
      'Reuse existing GM007/UP012 criteria and actual live relay media error not authorized; bind the same live blob to signed logical message/blob IDs and timestamp of actual removal-window media, with exact admitted source bytes for the authorized positive.',
      'Future fapp retains the actual signed removal/re-add timeline and real live fetch responses without requiring denied old-epoch repair or absent captured ciphertext.',
    ],
    failures: failures,
    evaluated: evaluated,
  );
}
