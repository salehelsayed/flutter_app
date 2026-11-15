import 'dart:async';

import 'package:flutter_app/debug/debug_voice_upload_lease.dart';
import 'package:flutter_app/core/media/media_upload_in_flight_tracker.dart';
import 'package:flutter_app/features/conversation/application/send_voice_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_test/flutter_test.dart';

/// BL-32: the device-media sender_resume step called sendVoiceMessage without
/// the upload lease while the production network-restored retrier owned the
/// same attachment, so one of the two sends could fail at random.
const _attachment = 'attachment-bl32';
const _bound = Duration(seconds: 5);

final _message = ConversationMessage(
  id: 'message-bl32',
  contactPeerId: 'peer-b',
  senderPeerId: 'peer-a',
  text: '',
  timestamp: '2026-11-14T00:00:00Z',
  status: 'sent',
  isIncoming: false,
  createdAt: '2026-11-14T00:00:00Z',
);

void main() {
  late MediaUploadInFlightTracker tracker;
  setUp(() => tracker = MediaUploadInFlightTracker());

  test(
    'resume send waits for a foreign lease, then sends under its own',
    () async {
      final foreign = tracker.tryClaimAll([
        _attachment,
      ], source: MediaUploadTriggerSource.networkRestored)!;
      var foreignReleased = false;
      final calls = <bool>[];
      Timer(const Duration(milliseconds: 200), () {
        foreignReleased = tracker.release(foreign);
      });

      final result = await sendDebugVoiceUnderUploadLease(
        attachmentId: _attachment,
        tracker: tracker,
        pollInterval: const Duration(milliseconds: 20),
        send: () async {
          calls.add(foreignReleased && tracker.isInFlight(_attachment));
          return (SendVoiceMessageResult.success, _message);
        },
      ).timeout(_bound);

      expect(
        calls,
        [true],
        reason:
            'one send, only after the foreign lease ended, under our own lease',
      );
      expect(result.$1, SendVoiceMessageResult.success);
      expect(
        tracker.isInFlight(_attachment),
        isFalse,
        reason: 'our lease is released',
      );
    },
  );

  test(
    'a send the foreign owner already completed is success without a second send',
    () async {
      final foreign = tracker.tryClaimAll([
        _attachment,
      ], source: MediaUploadTriggerSource.networkRestored)!;
      var sends = 0;
      Timer(const Duration(milliseconds: 200), () => tracker.release(foreign));

      final result = await sendDebugVoiceUnderUploadLease(
        attachmentId: _attachment,
        tracker: tracker,
        pollInterval: const Duration(milliseconds: 20),
        completedByOtherOwner: () async => _message,
        send: () async {
          sends++;
          return (SendVoiceMessageResult.success, _message);
        },
      ).timeout(_bound);

      expect(sends, 0);
      expect(result.$1, SendVoiceMessageResult.success);
      expect(result.$2?.id, _message.id);
    },
  );

  test(
    'a foreign lease that outlives the bounded wait fails without sending',
    () async {
      tracker.tryClaimAll([
        _attachment,
      ], source: MediaUploadTriggerSource.networkRestored);
      var sends = 0;

      final result = await sendDebugVoiceUnderUploadLease(
        attachmentId: _attachment,
        tracker: tracker,
        leaseWait: const Duration(milliseconds: 300),
        pollInterval: const Duration(milliseconds: 20),
        send: () async {
          sends++;
          return (SendVoiceMessageResult.success, _message);
        },
      ).timeout(_bound);

      expect(sends, 0);
      expect(result.$1, SendVoiceMessageResult.sendFailed);
      expect(result.$2, isNull);
    },
  );

  test('the voice E2E fresh send holds the lease while it sends', () async {
    final heldDuringSend = <bool>[];

    final result = await sendDebugVoiceUnderUploadLease(
      attachmentId: _attachment,
      tracker: tracker,
      send: () async {
        heldDuringSend.add(tracker.isInFlight(_attachment));
        return (SendVoiceMessageResult.success, _message);
      },
    ).timeout(_bound);

    expect(heldDuringSend, [true]);
    expect(result.$1, SendVoiceMessageResult.success);
    expect(tracker.isInFlight(_attachment), isFalse);
  });
}
