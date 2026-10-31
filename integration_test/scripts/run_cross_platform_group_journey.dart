import '../support/media_content_oracle.dart';
import 'contact_transfer_native_evidence.dart';

Future<List<String>> validateCrossPlatformGroupObservations(
  ContactTransferNativeEvidence evidence,
) async {
  final failures = <String>[];
  final targets = journeyGapMap(evidence.receipt['targets']);
  final platforms = targets.values
      .map((value) => journeyGapMap(value)['platform'])
      .toSet();
  final observed = evidence.observations;
  final memberRoles = (observed['memberRoles'] as List).cast<String>();
  final members = memberRoles.toSet();
  if (!platforms.containsAll(['android', 'ios']) ||
      members.length < 3 ||
      memberRoles.length != members.length ||
      members.any((role) => role.isEmpty) ||
      !members.every(targets.containsKey)) {
    failures.add(
      'actual mixed Android/iOS target roles and all group members required; Android A/B is insufficient',
    );
  }
  final actions = journeyGapRows(observed['membershipActions']);
  if (actions.map((row) => row['action']).join(',') !=
          'add,role_change,remove,readd' ||
      actions.any((row) => row['signedAdminAuthorized'] != true) ||
      (actions[2]['atMs'] as int) >= (actions[3]['atMs'] as int)) {
    failures.add(
      'actual authorized add/role-change/remove/admin-readd actions must occur in order',
    );
  }
  final platformKindLegs = <String>{};
  for (final row in journeyGapRows(observed['sends'])) {
    final sender = row['senderRole'] as String;
    final senderPlatform = journeyGapMap(targets[sender])['platform'];
    final kind = row['kind'];
    platformKindLegs.add('$senderPlatform/$kind');
    final entitledRoles = (row['entitledRolesAtSend'] as List).cast<String>();
    final entitled = entitledRoles.toSet();
    final received = journeyGapRows(row['receivers']);
    final receiverRoles = received.map((r) => r['role']).toSet();
    if (!members.contains(sender) ||
        !['android', 'ios'].contains(senderPlatform) ||
        !['text', 'media'].contains(kind) ||
        entitled.isEmpty ||
        entitledRoles.length != entitled.length ||
        entitled.contains(sender) ||
        !entitled.every(members.contains) ||
        received.length != entitled.length ||
        receiverRoles.length != entitled.length ||
        !receiverRoles.containsAll(entitled)) {
      failures.add(
        'every send must independently reach all and only its currently entitled recipients',
      );
    }
    for (final recipient in received) {
      if (recipient['messageId'] != row['messageId'] ||
          recipient['text'] != row['text'] ||
          recipient['persistedCountAfterReopen'] != 1 ||
          recipient['authenticatedKeySha256'] !=
              recipient['currentSenderKeySha256'] ||
          !RegExp(
            r'^[a-f0-9]{64}$',
          ).hasMatch('${recipient['authenticatedKeySha256']}') ||
          !RegExp(
            r'^[a-f0-9]{64}$',
          ).hasMatch('${recipient['currentSenderKeySha256']}')) {
        failures.add(
          'cross-platform content/current key/duplicate count mismatch',
        );
      }
      if (row['kind'] == 'media') {
        final source = await fingerprintMediaFile(
          evidence.file(row['processedSentFilePath']),
        );
        final full = await fingerprintMediaFile(
          evidence.file(recipient['fullReceivedFilePath']),
        );
        if (!source.sameBytes(full) || recipient['nativeUsable'] != true) {
          failures.add(
            'every cross-platform recipient needs exact full usable media',
          );
        }
      }
    }
  }
  if (!platformKindLegs.containsAll([
    'android/text',
    'android/media',
    'ios/text',
    'ios/media',
  ])) {
    failures.add(
      'both text and full-media sends from EACH actual platform are required',
    );
  }
  final removed = journeyGapMap(observed['removedWindow']);
  final readded = journeyGapMap(observed['postAdminReadd']);
  if (removed['renderedMessages'] != 0 ||
      removed['downloadAttempts'] != 0 ||
      readded['eligibleSinceAdminReadd'] != true ||
      readded['persistedCount'] != 1) {
    failures.add(
      'honest-client removal filtering and admin-readd admission must hold across platforms',
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
        journeyId: 'GX-002',
        requiredKinds: [
          'mixed-platform-membership',
          'signed-admin-actions',
          'every-recipient-text',
          'every-recipient-full-media',
          'native-full-open',
        ],
      );
      evaluated = true;
      failures.addAll(await validateCrossPlatformGroupObservations(evidence));
    } on ContactTransferCaptureUnavailable {
      // Capture absence is NOT RUN; it is not an app failure.
    } on Object {
      failures.add(
        'GX-002 observations are incomplete, malformed or not independently bound',
      );
    }
  }
  writeContactTransferNativeResult(
    journeyId: 'GX-002',
    ids: ['GX-002'],
    captureGap:
        'Existing Android/iOS-simulator catalog pieces do not join an actual mixed-platform text/media/add/remove/admin-readd/role-change capture to every entitled receiver.',
    prerequisites: [
      'Future fapp pins actual available Android/iOS target kinds and exact artifacts; simulator observations do not establish physical-iOS parity, unavailable legs are N/A by project policy.',
      'Capture real app membership actions, current authenticated senders, full received bytes and native usability for every entitled receiver.',
      'Re-add admission follows admin re-add; do not require fresh welcome keys, epoch denial or secrecy against a modified removed client.',
    ],
    failures: failures,
    evaluated: evaluated,
  );
}
