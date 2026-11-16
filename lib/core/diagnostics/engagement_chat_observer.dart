import 'engagement_chat_checkpoint_store.dart';
import 'engagement_chat_witness.dart';

typedef EngagementChatObserverOwner = ({
  String accountPeerId,
  String profileBinding,
  int consentEpoch,
});

/// Supplied by the canonical Go calendar; no event timestamps are sent to it.
typedef EngagementChatWeekInterval = ({
  String week,
  int startMilliseconds,
  int endMilliseconds,
});

typedef EngagementChatWeekLookup =
    Future<EngagementChatWeekInterval?> Function(
      EngagementChatObserverCapture owner,
    );
typedef EngagementChatLocalRetention =
    Future<bool> Function(EngagementChatObserverCapture owner, String week);

final class EngagementChatObserverCapture {
  EngagementChatObserverCapture._(this.owner);

  final EngagementChatObserverOwner owner;
}

final class EngagementChatObserverIntent {
  EngagementChatObserverIntent._({
    required this.owner,
    required this.contactAccount,
    required this.messageId,
    required this.generationId,
  });

  final EngagementChatObserverCapture owner;
  final String contactAccount;
  final String messageId;
  final String generationId;
}

/// Compiling RED boundary. Queue, calendar, persistence and retention are absent.
///
/// Producer entry points are synchronous; the eventual bounded worker owns all
/// optional awaits. Existing communication futures never join that worker.
final class EngagementChatObserver {
  EngagementChatObserver({
    required this.store,
    required this.lookupWeek,
    required this.retainChat,
    required this.nowMilliseconds,
  });

  final EngagementChatCheckpointStore store;
  final EngagementChatWeekLookup lookupWeek;
  final EngagementChatLocalRetention retainChat;
  final int Function() nowMilliseconds;
  EngagementChatObserverCapture? _capture;

  EngagementChatPhase get phase => EngagementChatPhase.collecting;

  /// Null temporarily unarms observation without clearing the private checkpoint.
  void replaceOwner(EngagementChatObserverOwner? owner) {
    _capture = owner == null ? null : EngagementChatObserverCapture._(owner);
  }

  /// A diagnostics OFF decision also requests private witness removal.
  void revoke() {
    _capture = null;
  }

  EngagementChatObserverCapture? captureOwner({
    required String expectedAccountPeerId,
  }) {
    final capture = _capture;
    if (capture == null ||
        capture.owner.accountPeerId != expectedAccountPeerId) {
      return null;
    }
    return capture;
  }

  EngagementChatObserverIntent? reserve(
    EngagementChatObserverCapture capture, {
    required String contactAccount,
    required String messageId,
    required String generationId,
  }) => EngagementChatObserverIntent._(
    owner: capture,
    contactAccount: contactAccount,
    messageId: messageId,
    generationId: generationId,
  );

  void admitted(EngagementChatObserverIntent intent) {}

  void cancel(EngagementChatObserverIntent intent) {}

  void delivered(
    EngagementChatObserverCapture capture, {
    required String contactAccount,
    required String messageId,
    required String generationId,
  }) {}

  void incoming(
    EngagementChatObserverCapture capture, {
    required String contactAccount,
  }) {}

  /// Joins accepted work and permits one bounded retry of retained pending work.
  Future<void> flush() => Future<void>.value();

  Future<void> dispose() {
    _capture = null;
    return Future<void>.value();
  }
}
