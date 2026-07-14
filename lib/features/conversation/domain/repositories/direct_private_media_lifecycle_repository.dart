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
