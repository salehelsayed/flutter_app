import '../models/direct_notification_read_acknowledgement.dart';

abstract interface class DirectNotificationReadAcknowledgementRepository {
  Future<bool> record(DirectNotificationReadAcknowledgement acknowledgement);

  Future<DirectNotificationReadAcknowledgement?> loadExact({
    required String peerId,
    required String contentKind,
    required String eventIdentity,
    String? generation,
  });

  Future<int> consumeExact({
    required String peerId,
    required String contentKind,
    required String eventIdentity,
  });

  Future<int> deleteForPeer(String peerId);
}
