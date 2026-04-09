import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/introduction/application/introduction_outbound_delivery.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_payload.dart';
import 'package:flutter_app/features/introduction/domain/repositories/introduction_repository.dart';
import 'package:uuid/uuid.dart';

typedef IntroductionSendProgressCallback =
    void Function(int completed, int total);

const int _maxConcurrentIntroductionChains = 10;

/// Sends introductions from the introducer to both the recipient and each
/// introduced friend.
///
/// For each friend in [friendsToIntroduce], creates a unique introduction
/// record and sends the payload to both the recipient (User-B) and the
/// introduced friend (User-C). Messages are encrypted with ML-KEM when
/// the target has a public key, otherwise sent as v1 plaintext.
///
/// Returns the list of created [IntroductionModel] records.
Future<List<IntroductionModel>> sendIntroductions({
  required ContactRepository contactRepo,
  required IntroductionRepository introRepo,
  required P2PService p2pService,
  required Bridge bridge,
  required String introducerPeerId,
  required String introducerUsername,
  required String recipientPeerId,
  required String recipientUsername,
  required String? recipientMlKemPublicKey,
  required List<ContactModel> friendsToIntroduce,
  IntroductionSendProgressCallback? onProgress,
}) async {
  emitFlowEvent(
    layer: 'UC',
    event: 'SEND_INTRODUCTIONS_START',
    details: {
      'recipientPeerId': recipientPeerId.length > 10
          ? recipientPeerId.substring(0, 10)
          : recipientPeerId,
      'friendCount': friendsToIntroduce.length,
    },
  );

  final results = <IntroductionModel>[];
  final now = DateTime.now().toUtc().toIso8601String();
  var completed = 0;

  onProgress?.call(completed, friendsToIntroduce.length);

  // Look up recipient contact to get their public keys
  final recipientContact = await contactRepo.getContact(recipientPeerId);
  final recipientPublicKey = recipientContact?.publicKey;
  final recipientMlKemPk = recipientContact?.mlKemPublicKey;

  for (
    var startIndex = 0;
    startIndex < friendsToIntroduce.length;
    startIndex += _maxConcurrentIntroductionChains
  ) {
    final endIndex = startIndex + _maxConcurrentIntroductionChains;
    final batch = friendsToIntroduce.sublist(
      startIndex,
      endIndex > friendsToIntroduce.length
          ? friendsToIntroduce.length
          : endIndex,
    );

    final batchResults = await Future.wait(
      batch.map((friend) async {
        final model = await _sendIntroductionChain(
          introRepo: introRepo,
          p2pService: p2pService,
          bridge: bridge,
          introducerPeerId: introducerPeerId,
          introducerUsername: introducerUsername,
          recipientPeerId: recipientPeerId,
          recipientUsername: recipientUsername,
          recipientPublicKey: recipientPublicKey,
          recipientMlKemPublicKey: recipientMlKemPublicKey,
          recipientPayloadMlKemPublicKey: recipientMlKemPk,
          friend: friend,
          now: now,
        );
        completed++;
        onProgress?.call(completed, friendsToIntroduce.length);
        return model;
      }),
    );
    results.addAll(batchResults);
  }

  // Set introsSentAt on the recipient contact
  await contactRepo.setIntrosSentAt(recipientPeerId, now);

  emitFlowEvent(
    layer: 'UC',
    event: 'SEND_INTRODUCTIONS_DONE',
    details: {'count': results.length},
  );

  return results;
}

Future<IntroductionModel> _sendIntroductionChain({
  required IntroductionRepository introRepo,
  required P2PService p2pService,
  required Bridge bridge,
  required String introducerPeerId,
  required String introducerUsername,
  required String recipientPeerId,
  required String recipientUsername,
  required String? recipientPublicKey,
  required String? recipientMlKemPublicKey,
  required String? recipientPayloadMlKemPublicKey,
  required ContactModel friend,
  required String now,
}) async {
  await _deleteExistingIntroductionsForPair(
    introRepo: introRepo,
    introducerPeerId: introducerPeerId,
    recipientPeerId: recipientPeerId,
    introducedPeerId: friend.peerId,
  );

  final introId = const Uuid().v4();

  // Build "send" payload for recipient (User-B)
  final payloadForRecipient = IntroductionPayload(
    action: 'send',
    introductionId: introId,
    introducerId: introducerPeerId,
    introducerUsername: introducerUsername,
    recipientId: recipientPeerId,
    recipientUsername: recipientUsername,
    introducedId: friend.peerId,
    introducedUsername: friend.username,
    introducedPublicKey: friend.publicKey,
    introducedMlKemPublicKey: friend.mlKemPublicKey,
    recipientPublicKey: recipientPublicKey,
    recipientMlKemPublicKey: recipientPayloadMlKemPublicKey,
    timestamp: now,
  );

  // Build "send" payload for introduced friend (User-C)
  // Same introductionId so both parties can reference the same introduction
  final payloadForIntroduced = IntroductionPayload(
    action: 'send',
    introductionId: introId,
    introducerId: introducerPeerId,
    introducerUsername: introducerUsername,
    recipientId: recipientPeerId,
    recipientUsername: recipientUsername,
    introducedId: friend.peerId,
    introducedUsername: friend.username,
    introducedPublicKey: friend.publicKey,
    introducedMlKemPublicKey: friend.mlKemPublicKey,
    recipientPublicKey: recipientPublicKey,
    recipientMlKemPublicKey: recipientPayloadMlKemPublicKey,
    timestamp: now,
  );

  // Persist before outbound staging so a sender crash cannot leave remote
  // recipients ahead of the sender's own intro truth.
  final model = IntroductionModel(
    id: introId,
    introducerId: introducerPeerId,
    recipientId: recipientPeerId,
    introducedId: friend.peerId,
    introducerUsername: introducerUsername,
    recipientUsername: recipientUsername,
    introducedUsername: friend.username,
    introducedPublicKey: friend.publicKey,
    introducedMlKemPublicKey: friend.mlKemPublicKey,
    recipientPublicKey: recipientPublicKey,
    recipientMlKemPublicKey: recipientPayloadMlKemPublicKey,
    createdAt: now,
  );
  await introRepo.saveIntroduction(model);

  // Send to recipient (User-B)
  await deliverIntroductionPayloadReliably(
    introRepo: introRepo,
    p2pService: p2pService,
    bridge: bridge,
    senderPeerId: introducerPeerId,
    targetPeerId: recipientPeerId,
    targetMlKemPublicKey: recipientMlKemPublicKey,
    payload: payloadForRecipient,
  );

  // Send to introduced friend (User-C)
  await deliverIntroductionPayloadReliably(
    introRepo: introRepo,
    p2pService: p2pService,
    bridge: bridge,
    senderPeerId: introducerPeerId,
    targetPeerId: friend.peerId,
    targetMlKemPublicKey: friend.mlKemPublicKey,
    payload: payloadForIntroduced,
  );

  emitFlowEvent(
    layer: 'UC',
    event: 'SEND_INTRODUCTION_SENT',
    details: {
      'introductionId': introId,
      'introducedPeerId': friend.peerId.length > 10
          ? friend.peerId.substring(0, 10)
          : friend.peerId,
    },
  );

  return model;
}

Future<void> _deleteExistingIntroductionsForPair({
  required IntroductionRepository introRepo,
  required String introducerPeerId,
  required String recipientPeerId,
  required String introducedPeerId,
}) async {
  final existing = await introRepo.getIntroductionsByIntroducer(
    introducerPeerId,
  );
  final duplicates = existing
      .where((intro) {
        if (intro.introducerId != introducerPeerId) return false;
        return _isSameIntroductionPair(
          introRecipientId: intro.recipientId,
          introIntroducedId: intro.introducedId,
          recipientPeerId: recipientPeerId,
          introducedPeerId: introducedPeerId,
        );
      })
      .toList(growable: false);

  for (final intro in duplicates) {
    await introRepo.deleteIntroduction(intro.id);
  }
}

bool _isSameIntroductionPair({
  required String introRecipientId,
  required String introIntroducedId,
  required String recipientPeerId,
  required String introducedPeerId,
}) {
  final sameDirection =
      introRecipientId == recipientPeerId &&
      introIntroducedId == introducedPeerId;
  final reversedDirection =
      introRecipientId == introducedPeerId &&
      introIntroducedId == recipientPeerId;
  return sameDirection || reversedDirection;
}
