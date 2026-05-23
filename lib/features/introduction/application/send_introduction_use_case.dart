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
  final effectiveRecipientMlKemPublicKey =
      _normalizeOptionalKey(recipientMlKemPublicKey) ??
      _normalizeOptionalKey(recipientContact?.mlKemPublicKey);

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
          recipientMlKemPublicKey: effectiveRecipientMlKemPublicKey,
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
  required ContactModel friend,
  required String now,
}) async {
  final existingPairIntroductions = await _loadExistingIntroductionsForPair(
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
    recipientMlKemPublicKey: recipientMlKemPublicKey,
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
    recipientMlKemPublicKey: recipientMlKemPublicKey,
    timestamp: now,
  );

  // The intro row and both outbound target rows are committed together before
  // any network attempt so either target can be retried after a sender crash.
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
    recipientMlKemPublicKey: recipientMlKemPublicKey,
    createdAt: now,
  );

  final deliveryForRecipient = await createIntroductionOutboxDelivery(
    bridge: bridge,
    senderPeerId: introducerPeerId,
    targetPeerId: recipientPeerId,
    targetMlKemPublicKey: recipientMlKemPublicKey,
    payload: payloadForRecipient,
  );
  final deliveryForIntroduced = await createIntroductionOutboxDelivery(
    bridge: bridge,
    senderPeerId: introducerPeerId,
    targetPeerId: friend.peerId,
    targetMlKemPublicKey: friend.mlKemPublicKey,
    payload: payloadForIntroduced,
  );

  final deliveryRows = [deliveryForRecipient, deliveryForIntroduced];
  if (existingPairIntroductions.isEmpty) {
    await introRepo.saveIntroductionWithOutboxDeliveries(model, deliveryRows);
  } else {
    await introRepo.replaceIntroductionWithPendingResponseMigration(
      intro: model,
      deliveries: deliveryRows,
      replacedIntroductionIds: existingPairIntroductions
          .map((intro) => intro.id)
          .toList(growable: false),
    );
  }

  // Send to recipient (User-B)
  await deliverStagedIntroductionDelivery(
    introRepo: introRepo,
    p2pService: p2pService,
    delivery: deliveryForRecipient,
  );

  // Send to introduced friend (User-C)
  await deliverStagedIntroductionDelivery(
    introRepo: introRepo,
    p2pService: p2pService,
    delivery: deliveryForIntroduced,
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

String? _normalizeOptionalKey(String? key) {
  final trimmed = key?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}

Future<List<IntroductionModel>> _loadExistingIntroductionsForPair({
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

  return duplicates;
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
