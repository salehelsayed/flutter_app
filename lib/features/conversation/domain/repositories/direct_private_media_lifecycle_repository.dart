import 'package:flutter_app/core/media/private_media_policy.dart';

import '../models/conversation_message.dart';

/// Direct-parent CAS/query authority consumed by the lane adapter.
///
/// Every mutation is an affected-row result. Zero is a normal lost race; no
/// caller may fall back to [MessageRepository.saveMessage].
abstract class DirectPrivateMediaLifecycleRepository {
  Future<ConversationMessage?> loadPrivateMediaLifecycleMessage(
    String messageId,
  );

  Future<bool> claimPrivateMediaOpening(String messageId, {required int nowMs});

  Future<bool> markPrivateMediaViewing(String messageId, {required int nowMs});

  Future<bool> rollbackPrivateMediaOpening(String messageId);

  Future<bool> consumePrivateMedia(String messageId, {required int nowMs});

  Future<bool> advancePrivateMediaClock(String messageId, {required int nowMs});

  Future<bool> failClosedCorruptPrivateMediaState(
    String messageId, {
    required int nowMs,
  });

  Future<bool> hidePrivateMediaForMe(
    String messageId, {
    required String hiddenAt,
    required int nowMs,
  });

  Future<List<ConversationMessage>> loadActiveDisappearingPrivateMedia({
    int limit = 100,
  });

  Future<List<ConversationMessage>> loadPrivateMediaRecoveryCandidates({
    int limit = 100,
  });

  Future<bool> rotatePrivateMediaRecoveryCandidate(
    String messageId, {
    required int nowMs,
  });

  Future<int?> loadNextPrivateMediaExpiryAtMs();
}

/// Durable CAS authority for transitions owned by one exact in-memory lease.
///
/// The parent direction/mode and attachment identity/path are part of the
/// write predicate, rather than only a pre-write read, so a concurrent row
/// replacement cannot inherit another operation's reveal authority.
abstract class DirectPrivateMediaExactOpeningLeaseRepository {
  Future<bool> claimExactPrivateMediaOpening(
    String messageId, {
    required bool isIncoming,
    required PrivateMediaMode mode,
    required String attachmentId,
    required String storedLocalPath,
    required int nowMs,
  });

  Future<bool> markExactPrivateMediaViewing(
    String messageId, {
    required bool isIncoming,
    required PrivateMediaMode mode,
    required String attachmentId,
    required String storedLocalPath,
    required int nowMs,
  });

  Future<bool> rollbackExactPrivateMediaOpening(
    String messageId, {
    required bool isIncoming,
    required PrivateMediaMode mode,
    required String attachmentId,
    required String storedLocalPath,
  });

  Future<bool> consumeExactPrivateMedia(
    String messageId, {
    required bool isIncoming,
    required PrivateMediaMode mode,
    required String attachmentId,
    required String storedLocalPath,
    required int nowMs,
  });
}

/// Optional exact-CAS authority required only for operation-aware settlement
/// recovery after an indeterminate terminalization write.
abstract class DirectPrivateMediaIndeterminateQuarantineRepository {
  Future<bool> quarantineIndeterminatePrivateMediaAvailable(
    String messageId, {
    required bool isIncoming,
    required PrivateMediaMode mode,
    required String attachmentId,
    required String storedLocalPath,
    required int nowMs,
  });
}
