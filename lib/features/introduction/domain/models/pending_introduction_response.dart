import 'introduction_payload.dart';

/// Durable local staging for intro responses that arrive before the intro row.
class PendingIntroductionResponse {
  final String responseKey;
  final String introductionId;
  final String action;
  final String responderId;
  final String? responderUsername;
  final String createdAt;

  const PendingIntroductionResponse({
    required this.responseKey,
    required this.introductionId,
    required this.action,
    required this.responderId,
    this.responderUsername,
    required this.createdAt,
  });

  factory PendingIntroductionResponse.fromMap(Map<String, dynamic> map) {
    return PendingIntroductionResponse(
      responseKey: map['response_key'] as String,
      introductionId: map['introduction_id'] as String,
      action: map['action'] as String,
      responderId: map['responder_id'] as String,
      responderUsername: map['responder_username'] as String?,
      createdAt: map['created_at'] as String,
    );
  }

  factory PendingIntroductionResponse.fromPayload(IntroductionPayload payload) {
    final responderId = payload.responderId ?? '';
    return PendingIntroductionResponse(
      responseKey: buildResponseKey(
        introductionId: payload.introductionId,
        responderId: responderId,
        action: payload.action,
      ),
      introductionId: payload.introductionId,
      action: payload.action,
      responderId: responderId,
      responderUsername: payload.responderUsername,
      createdAt: payload.timestamp,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'response_key': responseKey,
      'introduction_id': introductionId,
      'action': action,
      'responder_id': responderId,
      'responder_username': responderUsername,
      'created_at': createdAt,
    };
  }

  IntroductionPayload toPayload() {
    return IntroductionPayload(
      action: action,
      introductionId: introductionId,
      responderId: responderId,
      responderUsername: responderUsername,
      timestamp: createdAt,
    );
  }

  static String buildResponseKey({
    required String introductionId,
    required String responderId,
    required String action,
  }) {
    return '$introductionId::$responderId::$action';
  }
}
