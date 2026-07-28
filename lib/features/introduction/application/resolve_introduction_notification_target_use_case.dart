import 'dart:async';

import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_payload.dart';
import 'package:flutter_app/features/introduction/domain/repositories/introduction_repository.dart';

/// Final status-context result for an exact acceptance anchor.
///
/// [fallbackReason] is non-null only when the bounded listener wait could not
/// observe the matching persisted status. Callers still use [statusContext] so
/// notification routing remains fail-open to the already-resolved B
/// conversation.
class IntroductionNotificationStatusConvergenceResult {
  final String statusContext;
  final String? fallbackReason;

  const IntroductionNotificationStatusConvergenceResult({
    required this.statusContext,
    this.fallbackReason,
  });

  bool get converged => fallbackReason == null;
}

/// Owner for one bounded exact-anchor listener subscription.
///
/// The resolver arms this subscription before its repository re-read. The
/// notification-open coordinator starts the timeout only after it has prompted
/// the B-conversation navigation, and cancels the owner on every exit path.
class IntroductionNotificationStatusConvergence {
  final _IntroductionNotificationStatusConvergenceWaiter _waiter;

  IntroductionNotificationStatusConvergence._(this._waiter);

  Future<IntroductionNotificationStatusConvergenceResult> wait() =>
      _waiter.wait();

  Future<void> cancel() => _waiter.cancel();
}

/// Outcome of resolving an anchored Intros notification target after the
/// notification-open inbox drain.
///
/// Either the local user is the introducer of a canonical `accept` and the
/// recipient (User B) still resolves as a contact — in which case [target] is
/// B's conversation and [contact] is non-null — or the resolution fails
/// closed to the original generic Intros route.
class IntroductionNotificationTargetResolution {
  final NotificationRouteTarget target;
  final ContactModel? contact;
  final String reason;

  /// Machine-readable acceptance progress for the resolved introduction:
  /// `b_accept_recorded` while the intro is still pending the second
  /// response, `bc_connected` once mutually accepted. Null on fallback.
  final String? statusContext;

  /// Present only when the exact responder's persisted acceptance was not yet
  /// visible at the repository re-read and a real listener stream was
  /// supplied.
  final IntroductionNotificationStatusConvergence? statusConvergence;

  const IntroductionNotificationTargetResolution._({
    required this.target,
    this.contact,
    required this.reason,
    this.statusContext,
    this.statusConvergence,
  });

  const IntroductionNotificationTargetResolution.intros(String reason)
    : this._(target: const NotificationRouteTarget.intros(), reason: reason);

  IntroductionNotificationTargetResolution.conversation({
    required ContactModel contact,
    required String statusContext,
    IntroductionNotificationStatusConvergence? statusConvergence,
  }) : this._(
         target: NotificationRouteTarget.conversation(contact.peerId),
         contact: contact,
         reason: 'introducer_accept',
         statusContext: statusContext,
         statusConvergence: statusConvergence,
       );

  bool get opensConversation =>
      target.kind == NotificationRouteTargetKind.conversation &&
      contact != null;
}

/// Resolves an Intros notification target to the introducer's originating
/// recipient conversation, or fails closed to the generic Intros route.
///
/// May return B's conversation ONLY when all of these hold after the
/// notification-open drain:
/// - the target carries a canonical `accept` envelope message ID,
/// - the introduction row exists locally,
/// - the local identity is the introduction's introducer, and
/// - the recipient (User B) still resolves as a contact.
///
/// The route is always the introduction `recipientId` (User B) — never the
/// responder — so B-accept and C-accept for the same introduction both land
/// in the thread that carries the introduction status messages.
Future<IntroductionNotificationTargetResolution>
resolveIntroductionNotificationTarget({
  required NotificationRouteTarget routeTarget,
  required IntroductionRepository introRepo,
  required ContactRepository contactRepo,
  required Future<String?> Function() loadOwnPeerId,
  Stream<IntroductionModel>? introStatusChanges,
  Duration statusConvergenceTimeout = const Duration(seconds: 45),
}) async {
  if (routeTarget.kind != NotificationRouteTargetKind.intros) {
    return const IntroductionNotificationTargetResolution.intros(
      'not_intros_route',
    );
  }

  final identity = IntroductionPayload.parseEnvelopeMessageId(
    routeTarget.messageId,
  );
  if (identity == null) {
    return const IntroductionNotificationTargetResolution.intros(
      'unanchored_or_malformed_message_id',
    );
  }
  if (identity.action != 'accept') {
    return const IntroductionNotificationTargetResolution.intros(
      'not_accept_action',
    );
  }

  // This must be armed before the repository re-read. IntroductionListener's
  // output is broadcast, so subscribing afterward can lose the exact
  // persistence edge that races a cold notification tap.
  final convergenceWaiter = introStatusChanges == null
      ? null
      : _IntroductionNotificationStatusConvergenceWaiter(
          stream: introStatusChanges,
          identity: identity,
          timeout: statusConvergenceTimeout,
          fallbackStatusContext: 'b_accept_recorded',
        );
  var handOffConvergence = false;

  try {
    final intro = await introRepo.getIntroduction(identity.introductionId);
    if (intro == null) {
      return const IntroductionNotificationTargetResolution.intros(
        'introduction_missing',
      );
    }

    final ownPeerId = await loadOwnPeerId();
    if (ownPeerId == null || ownPeerId != intro.introducerId) {
      return const IntroductionNotificationTargetResolution.intros(
        'not_introducer',
      );
    }

    final contact = await contactRepo.getContact(intro.recipientId);
    if (contact == null) {
      return const IntroductionNotificationTargetResolution.intros(
        'recipient_contact_missing',
      );
    }

    final responderIsRecipient = identity.senderPeerId == intro.recipientId;
    final responderIsIntroduced = identity.senderPeerId == intro.introducedId;
    final responderStatus = responderIsRecipient
        ? intro.recipientStatus
        : responderIsIntroduced
        ? intro.introducedStatus
        : null;
    final statusContext = _statusContextForIntroduction(intro);

    IntroductionNotificationStatusConvergence? statusConvergence;
    if (convergenceWaiter != null &&
        responderStatus == IntroductionStatus.pending) {
      statusConvergence = IntroductionNotificationStatusConvergence._(
        convergenceWaiter,
      );
      handOffConvergence = true;
    }

    return IntroductionNotificationTargetResolution.conversation(
      contact: contact,
      statusContext: statusContext,
      statusConvergence: statusConvergence,
    );
  } finally {
    if (!handOffConvergence) {
      await convergenceWaiter?.cancel();
    }
  }
}

class _IntroductionNotificationStatusConvergenceWaiter {
  _IntroductionNotificationStatusConvergenceWaiter({
    required Stream<IntroductionModel> stream,
    required this.identity,
    required this.timeout,
    required this.fallbackStatusContext,
  }) {
    _subscription = stream.listen(
      _onStatusChanged,
      onError: (Object _, StackTrace _) {
        _completeFallback('stream_error');
      },
      onDone: () {
        _completeFallback('stream_done');
      },
    );
  }

  final IntroductionEnvelopeIdentity identity;
  final Duration timeout;
  final String fallbackStatusContext;
  final Completer<IntroductionNotificationStatusConvergenceResult> _result =
      Completer<IntroductionNotificationStatusConvergenceResult>();

  late final StreamSubscription<IntroductionModel> _subscription;
  Timer? _timer;
  Future<void>? _cancelFuture;

  Future<IntroductionNotificationStatusConvergenceResult> wait() {
    if (!_result.isCompleted && _timer == null) {
      _timer = Timer(timeout, () {
        _completeFallback('timeout');
      });
    }
    return _result.future;
  }

  Future<void> cancel() async {
    if (!_result.isCompleted) {
      _result.complete(
        IntroductionNotificationStatusConvergenceResult(
          statusContext: fallbackStatusContext,
          fallbackReason: 'cancelled',
        ),
      );
    }
    await _cancelSubscription();
  }

  void _onStatusChanged(IntroductionModel intro) {
    if (intro.id != identity.introductionId) {
      return;
    }

    var responderAcceptancePersisted = false;
    if (identity.senderPeerId == intro.recipientId &&
        intro.recipientStatus == IntroductionStatus.accepted) {
      responderAcceptancePersisted = true;
    } else if (identity.senderPeerId == intro.introducedId &&
        intro.introducedStatus == IntroductionStatus.accepted) {
      responderAcceptancePersisted = true;
    }
    if (!responderAcceptancePersisted || _result.isCompleted) {
      return;
    }

    _result.complete(
      IntroductionNotificationStatusConvergenceResult(
        statusContext: _statusContextForIntroduction(intro),
      ),
    );
    unawaited(_cancelSubscription());
  }

  void _completeFallback(String reason) {
    if (_result.isCompleted) {
      return;
    }
    _result.complete(
      IntroductionNotificationStatusConvergenceResult(
        statusContext: fallbackStatusContext,
        fallbackReason: reason,
      ),
    );
    unawaited(_cancelSubscription());
  }

  Future<void> _cancelSubscription() {
    _timer?.cancel();
    return _cancelFuture ??= _subscription.cancel();
  }
}

String _statusContextForIntroduction(IntroductionModel intro) {
  return intro.status == IntroductionOverallStatus.mutualAccepted
      ? 'bc_connected'
      : 'b_accept_recorded';
}
