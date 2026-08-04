import '../../domain/models/direct_notification_read_acknowledgement.dart';
import '../../domain/repositories/direct_notification_read_acknowledgement_repository.dart';

class DirectNotificationReadAcknowledgementRepositoryImpl
    implements DirectNotificationReadAcknowledgementRepository {
  final Future<bool> Function({
    required String peerId,
    required String contentKind,
    required String eventIdentity,
    required String messageId,
    required String? actorPeerId,
    required String generation,
    required String acknowledgedAt,
  })
  dbRecord;
  final Future<Map<String, Object?>?> Function({
    required String peerId,
    required String contentKind,
    required String eventIdentity,
    String? generation,
  })
  dbLoadExact;
  final Future<int> Function({
    required String peerId,
    required String contentKind,
    required String eventIdentity,
  })
  dbConsumeExact;
  final Future<int> Function(String peerId) dbDeleteForPeer;

  const DirectNotificationReadAcknowledgementRepositoryImpl({
    required this.dbRecord,
    required this.dbLoadExact,
    required this.dbConsumeExact,
    required this.dbDeleteForPeer,
  });

  @override
  Future<bool> record(DirectNotificationReadAcknowledgement acknowledgement) =>
      dbRecord(
        peerId: acknowledgement.peerId,
        contentKind: acknowledgement.contentKind,
        eventIdentity: acknowledgement.eventIdentity,
        messageId: acknowledgement.messageId,
        actorPeerId: acknowledgement.actorPeerId,
        generation: acknowledgement.generation,
        acknowledgedAt: acknowledgement.acknowledgedAt,
      );

  @override
  Future<DirectNotificationReadAcknowledgement?> loadExact({
    required String peerId,
    required String contentKind,
    required String eventIdentity,
    String? generation,
  }) async {
    final row = await dbLoadExact(
      peerId: peerId,
      contentKind: contentKind,
      eventIdentity: eventIdentity,
      generation: generation,
    );
    return row == null
        ? null
        : DirectNotificationReadAcknowledgement.fromMap(row);
  }

  @override
  Future<int> consumeExact({
    required String peerId,
    required String contentKind,
    required String eventIdentity,
  }) => dbConsumeExact(
    peerId: peerId,
    contentKind: contentKind,
    eventIdentity: eventIdentity,
  );

  @override
  Future<int> deleteForPeer(String peerId) => dbDeleteForPeer(peerId);
}
