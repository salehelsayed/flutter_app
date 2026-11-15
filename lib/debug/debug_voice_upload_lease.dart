import 'package:flutter_app/core/media/media_upload_in_flight_tracker.dart';
import 'package:flutter_app/features/conversation/application/send_voice_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';

typedef DebugVoiceSend =
    Future<(SendVoiceMessageResult, ConversationMessage?)> Function();

/// BL-32: debug E2E endpoints send a voice note the way production callers
/// do, under the shared upload lease for its attachment, so they never race a
/// production retrier that owns the same attachment.
///
/// [completedByOtherOwner] reports the committed message when another lease
/// owner (for example the network-restored retrier) already finished the send.
Future<(SendVoiceMessageResult, ConversationMessage?)>
sendDebugVoiceUnderUploadLease({
  required String attachmentId,
  required DebugVoiceSend send,
  Future<ConversationMessage?> Function()? completedByOtherOwner,
  MediaUploadInFlightTracker? tracker,
  Duration leaseWait = const Duration(seconds: 30),
  Duration pollInterval = const Duration(milliseconds: 100),
}) async {
  final leases = tracker ?? mediaUploadInFlightTracker;
  final waited = Stopwatch()..start();
  MediaUploadLease? lease;
  while (true) {
    lease = leases.tryClaimAll([
      attachmentId,
    ], source: MediaUploadTriggerSource.resume);
    if (lease != null) break;
    if (waited.elapsed >= leaseWait) {
      return (SendVoiceMessageResult.sendFailed, null);
    }
    await Future<void>.delayed(pollInterval);
  }
  try {
    // Checked under our own lease, so no other owner can be mid-send.
    final committed = await completedByOtherOwner?.call();
    if (committed != null) return (SendVoiceMessageResult.success, committed);
    return await send();
  } finally {
    leases.release(lease);
  }
}
