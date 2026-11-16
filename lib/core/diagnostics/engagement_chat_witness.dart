import 'dart:convert';
import 'dart:typed_data';

typedef EngagementChatScope = ({
  String profileBinding,
  int consentEpoch,
  String week,
});

enum EngagementChatPhase { collecting, qualifiedPending, qualifiedRetained }

/// Its identity is one runtime generation, captured before producer awaits.
final class EngagementChatCapture {
  EngagementChatCapture._(this.scope);

  final EngagementChatScope scope;
}

/// A known outgoing tuple captured before its durable staging starts.
final class EngagementChatIntent {
  EngagementChatIntent._({
    required this.owner,
    required this.contactAccount,
    required this.messageId,
    required this.generationId,
  });

  final EngagementChatCapture owner;
  final String contactAccount;
  final String messageId;
  final String generationId;
}

/// Compiling RED surface. Witness reduction and codec acceptance are absent.
///
/// Capture/reset bookkeeping lets the behavioral contract execute without
/// introducing qualification, persistence, calendar or production observation.
final class EngagementChatWitness {
  EngagementChatWitness({required EngagementChatScope scope})
    : _scope = scope,
      _capture = EngagementChatCapture._(scope);

  EngagementChatScope _scope;
  EngagementChatCapture? _capture;

  EngagementChatPhase get phase => EngagementChatPhase.collecting;

  EngagementChatCapture? captureOwner() => _capture;

  void reset(EngagementChatScope scope) {
    _scope = scope;
    _capture = EngagementChatCapture._(scope);
  }

  void revoke() {
    _capture = null;
  }

  EngagementChatIntent? reserve(
    EngagementChatCapture capture, {
    required String contactAccount,
    required String messageId,
    required String generationId,
  }) => EngagementChatIntent._(
    owner: capture,
    contactAccount: contactAccount,
    messageId: messageId,
    generationId: generationId,
  );

  void admitted(EngagementChatIntent intent) {}

  void cancel(EngagementChatIntent intent) {}

  void delivered(
    EngagementChatCapture capture, {
    required String contactAccount,
    required String messageId,
    required String generationId,
  }) {}

  void incoming(
    EngagementChatCapture capture, {
    required String contactAccount,
  }) {}

  void confirmRetained(EngagementChatCapture capture) {}

  Uint8List encodeSnapshot() => Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'version': 1,
        'scope': {
          'profileBinding': _scope.profileBinding,
          'consentEpoch': _scope.consentEpoch,
          'week': _scope.week,
        },
        'phase': 'collecting',
        'contacts': <Object?>[],
      }),
    ),
  );

  bool restoreSnapshot(EngagementChatCapture capture, List<int> bytes) => false;
}
