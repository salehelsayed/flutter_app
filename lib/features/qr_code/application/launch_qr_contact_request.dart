import 'dart:async';

import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/contact_request/application/mlkem_reannounce_marker.dart';
import 'package:flutter_app/features/contact_request/application/send_contact_request_use_case.dart';

typedef QrContactRequestLaunch = ({
  bool retryRetained,
  Future<SendContactRequestResult>? transmission,
});

/// Prepares durable retry custody and hands the caller a detached transmission.
Future<QrContactRequestLaunch> launchQrContactRequest({
  required SecureKeyStore secureKeyStore,
  required String peerId,
  required Future<bool> Function(String) shouldMarkContactRequest,
  required Future<SendContactRequestResult> Function(bool markAsNewRequest)
  send,
  bool Function()? canQueue,
  void Function(Object error)? onPreparationError,
}) async {
  var retryRetained = false;
  try {
    retryRetained = await tryQueueMlKemReannouncePeer(
      secureKeyStore,
      peerId,
      canQueue: canQueue,
    );
    if (!retryRetained || canQueue?.call() == false) {
      return (retryRetained: retryRetained, transmission: null);
    }
    final marked = await shouldMarkContactRequest(peerId);
    if (canQueue?.call() == false) {
      return (retryRetained: retryRetained, transmission: null);
    }

    final transmission = Future<SendContactRequestResult>.sync(
      () => send(marked),
    );
    // Observe failure during the handoff without changing the returned future.
    unawaited(
      transmission.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
    return (retryRetained: retryRetained, transmission: transmission);
  } catch (error) {
    onPreparationError?.call(error);
    return (retryRetained: retryRetained, transmission: null);
  }
}
