import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_app/features/contact_request/application/key_exchange_retrier.dart';

/// Shares the existing retry owner's stopped-cycle projection across routes.
class PendingContactRetryScope extends InheritedNotifier {
  PendingContactRetryScope({
    super.key,
    required this.retrier,
    required super.child,
  }) : super(notifier: retrier.stoppedPeerIds);

  final KeyExchangeRetrier retrier;

  static bool isStopped(BuildContext context, String peerId) =>
      context
          .dependOnInheritedWidgetOfExactType<PendingContactRetryScope>()
          ?.retrier
          .stoppedPeerIds
          .value
          .contains(peerId) ??
      false;

  static void noteInterest(BuildContext context, String peerId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      final scope = context
          .getInheritedWidgetOfExactType<PendingContactRetryScope>();
      if (scope != null) unawaited(scope.retrier.retryOnInterest(peerId));
    });
  }
}
