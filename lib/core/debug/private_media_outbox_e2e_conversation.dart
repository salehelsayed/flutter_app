import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/debug/private_media_outbox_e2e.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

typedef PrivateMediaOutboxE2ERequestAction =
    Future<void> Function(PrivateMediaOutboxE2ERequest request);
typedef PrivateMediaOutboxE2ERequestPredicate =
    Future<bool> Function(PrivateMediaOutboxE2ERequest request);

/// Testable orchestration for the one production ConversationWired endpoint.
/// The adapter callbacks below are deliberately state-oriented: the endpoint
/// can report a receipt only after the ordinary send path and repositories
/// prove the requested transition.
final class PrivateMediaOutboxE2EConversationEndpoint {
  const PrivateMediaOutboxE2EConversationEndpoint({
    required this.contactPeerId,
    required this.sendPrivateMedia,
    required this.isSenderQueued,
    required this.isSenderDelivered,
    required this.isReceiverDelivered,
    required this.waitForSenderHostRelease,
    required this.waitForSenderOfflineObservation,
    required this.waitForOfflinePauseResume,
    this.pollInterval = const Duration(milliseconds: 250),
    this.deliveryQuietPeriod = const Duration(seconds: 1),
    this.nowMilliseconds = _systemNowMilliseconds,
  });

  final String contactPeerId;
  final PrivateMediaOutboxE2ERequestAction sendPrivateMedia;
  final PrivateMediaOutboxE2ERequestPredicate isSenderQueued;
  final PrivateMediaOutboxE2ERequestPredicate isSenderDelivered;
  final PrivateMediaOutboxE2ERequestPredicate isReceiverDelivered;
  final Future<void> Function() waitForSenderHostRelease;
  final Future<void> Function() waitForSenderOfflineObservation;
  final Future<void> Function() waitForOfflinePauseResume;
  final Duration pollInterval;
  final Duration deliveryQuietPeriod;
  final int Function() nowMilliseconds;

  Future<Map<String, Object?>> run(
    PrivateMediaOutboxE2ERequest request,
    PrivateMediaOutboxE2EProgressWriter writeProgress,
  ) async {
    if (request.contactPeerId != contactPeerId) {
      throw StateError('private-media outbox contact binding rejected');
    }
    if (!request.isSender) {
      await writeProgress(privateMediaOutboxE2EArmedReceipt(request));
      await waitForPrivateMediaOutboxE2ECondition(
        label: 'exact incoming private media',
        timeout: request.timeout,
        pollInterval: pollInterval,
        check: () => isReceiverDelivered(request),
      );
      return privateMediaOutboxE2ECompletedReceipt(
        request,
        messageIdHash: request.messageIdHash,
        attachmentIdHash: request.attachmentIdHash,
        events: <Map<String, Object?>>[
          privateMediaOutboxE2EEventEvidence(
            request,
            event: privateMediaOutboxReceivedEvent,
            timestampMs: nowMilliseconds(),
          ),
        ],
      );
    }

    final capture = PrivateMediaOutboxE2EFlowCapture(request)..start();
    try {
      // The sender's capture must own the production event sink before ARMED
      // becomes visible to the host. The host then mutates network state and
      // publishes an exact run-bound release before the real send can begin.
      await writeProgress(privateMediaOutboxE2EArmedReceipt(request));
      await waitForSenderHostRelease();
      // The host holds a stable outage beyond Android's delayed network-loss
      // callback window. Confirm the app's current OS snapshot is offline
      // before issuing the attempt, so restore cannot collapse into an
      // online-to-online observation. After QUEUED, the host only polls.
      await waitForSenderOfflineObservation();
      await sendPrivateMedia(request);
      await waitForPrivateMediaOutboxE2ECondition(
        label: 'durable queued private media',
        timeout: request.timeout,
        pollInterval: pollInterval,
        check: () => isSenderQueued(request),
      );
      if (capture.initialEncryptionPreparedCount != 1 ||
          capture.initialUploadRequestCount != 1) {
        throw StateError(
          'private-media outbox initial issuance count rejected',
        );
      }
      capture.markQueued();
      await writeProgress(privateMediaOutboxE2EQueuedReceipt(request));

      if (request.phase == 2) {
        await waitForOfflinePauseResume();
        await waitForPrivateMediaOutboxE2ECondition(
          label: 'queued state after offline resume',
          timeout: request.timeout,
          pollInterval: pollInterval,
          check: () => isSenderQueued(request),
        );
        if (capture.offlineResumeAttemptCount != 0) {
          throw StateError(
            'private-media outbox issued an offline resume attempt',
          );
        }
        await writeProgress(privateMediaOutboxE2EResumedQueuedReceipt(request));
      }

      await capture.waitForRestoredDeliverySignal();
      await waitForPrivateMediaOutboxE2ECondition(
        label: 'settled outgoing private media',
        timeout: request.timeout,
        pollInterval: pollInterval,
        check: () => isSenderDelivered(request),
      );
      final events = await capture.sealAfterQuietPeriod(deliveryQuietPeriod);
      return privateMediaOutboxE2ECompletedReceipt(
        request,
        messageIdHash: request.messageIdHash,
        attachmentIdHash: request.attachmentIdHash,
        events: events,
      );
    } finally {
      capture.dispose();
    }
  }
}

/// Captures the production flow milestones that delimit one armed sender
/// campaign. The resulting evidence contains only run-bound hashes and time;
/// raw message, attachment, contact, path, and media values never leave the
/// device.
final class PrivateMediaOutboxE2EFlowCapture {
  PrivateMediaOutboxE2EFlowCapture(this.request);

  final PrivateMediaOutboxE2ERequest request;
  final List<Map<String, Object?>> _postQueueEvents = <Map<String, Object?>>[];
  final Completer<void> _deliveryObserved = Completer<void>();

  bool _started = false;
  bool _queued = false;
  bool _sealed = false;
  bool _disposed = false;
  E2EFlowEventSinkLease? _sinkLease;
  int _initialEncryptionPreparedCount = 0;
  int _initialUploadRequestCount = 0;
  Object? _capturedError;
  StackTrace? _capturedStackTrace;

  int get initialEncryptionPreparedCount => _initialEncryptionPreparedCount;
  int get initialUploadRequestCount => _initialUploadRequestCount;

  int get offlineResumeAttemptCount {
    final triggerIndex = _postQueueEvents.indexWhere(
      (event) => event['event'] == privateMediaOutboxNetworkRestoredEvent,
    );
    final beforeTrigger = triggerIndex < 0
        ? _postQueueEvents
        : _postQueueEvents.take(triggerIndex);
    return beforeTrigger
        .where(
          (event) =>
              event['event'] == privateMediaOutboxEncryptionPreparedEvent ||
              event['event'] == privateMediaOutboxUploadStartEvent,
        )
        .length;
  }

  void start() {
    if (_started || _disposed) {
      throw StateError('private-media outbox capture cannot be restarted');
    }
    _started = true;
    _sinkLease = installScopedE2EFlowEventSink(_onFlowEvent);
  }

  /// Starts the proof window after the one expected foreground/offline
  /// issuance has settled into the durable queued lane.
  void markQueued() {
    if (!_started || _disposed || _queued) {
      throw StateError('private-media outbox queue boundary is invalid');
    }
    _queued = true;
    _postQueueEvents.clear();
  }

  Future<void> waitForRestoredDeliverySignal() async {
    if (!_queued || _disposed) {
      throw StateError('private-media outbox capture is not queued');
    }
    await _deliveryObserved.future.timeout(request.timeout);
  }

  /// Keeps the scoped sink alive after the first send milestone and after the
  /// durable sender row settles. The bounded quiet window catches a competing
  /// restored/full/manual leg that publishes a second correlated envelope.
  Future<List<Map<String, Object?>>> sealAfterQuietPeriod(
    Duration quietPeriod,
  ) async {
    if (!_queued || _disposed || _sealed || !_deliveryObserved.isCompleted) {
      throw StateError('private-media outbox capture cannot be sealed');
    }
    if (quietPeriod.isNegative || quietPeriod > request.timeout) {
      throw StateError('private-media outbox quiet period rejected');
    }
    if (quietPeriod > Duration.zero) {
      await Future<void>.delayed(quietPeriod);
    }
    _sealed = true;
    final capturedError = _capturedError;
    if (capturedError != null) {
      Error.throwWithStackTrace(
        capturedError,
        _capturedStackTrace ?? StackTrace.current,
      );
    }
    final eventNames = _postQueueEvents
        .map((event) => event['event'])
        .toList(growable: false);
    if (!_exactSenderEventOrder(eventNames)) {
      throw StateError(
        'private-media outbox correlated sender events are not exactly once',
      );
    }
    return List<Map<String, Object?>>.unmodifiable(
      _postQueueEvents.map(Map<String, Object?>.unmodifiable),
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _sinkLease?.release();
    _sinkLease = null;
  }

  void _onFlowEvent(Map<String, dynamic> payload) {
    if (_disposed || _sealed) return;
    try {
      final event = payload['event'];
      if (event is! String) return;
      if (!_queued) {
        if (event == privateMediaOutboxEncryptionPreparedEvent ||
            event == privateMediaOutboxUploadStartEvent) {
          final details = payload['details'];
          if (details is! Map ||
              details['attachmentSha256'] != request.attachmentIdHash) {
            return;
          }
          if (event == privateMediaOutboxEncryptionPreparedEvent) {
            _initialEncryptionPreparedCount++;
          } else {
            _initialUploadRequestCount++;
          }
        }
        return;
      }

      if (!_senderEventNames.contains(event)) return;
      final details = payload['details'];
      if (details is! Map) {
        throw const FormatException('private-media flow details rejected');
      }
      if (event == privateMediaOutboxLeaseClaimedEvent) {
        if (details['attachmentSha256'] != request.attachmentIdHash) return;
        if (details['source'] != privateMediaOutboxNetworkRestoredSource) {
          throw const FormatException(
            'private-media restored lease binding rejected',
          );
        }
      }
      if ((event == privateMediaOutboxEncryptionPreparedEvent ||
              event == privateMediaOutboxUploadStartEvent) &&
          details['attachmentSha256'] != request.attachmentIdHash) {
        return;
      }
      if (event == privateMediaOutboxSendSuccessEvent) {
        if (details['id'] != request.messageId) return;
      }

      final rawTimestamp = payload['ts'];
      final timestamp = rawTimestamp is String
          ? DateTime.tryParse(rawTimestamp)?.millisecondsSinceEpoch
          : null;
      if (timestamp == null) {
        throw const FormatException('private-media flow timestamp rejected');
      }
      _postQueueEvents.add(
        privateMediaOutboxE2EEventEvidence(
          request,
          event: event,
          timestampMs: timestamp,
          source: event == privateMediaOutboxLeaseClaimedEvent
              ? privateMediaOutboxNetworkRestoredSource
              : null,
        ),
      );
      if (event == privateMediaOutboxSendSuccessEvent) {
        if (!_deliveryObserved.isCompleted) {
          _deliveryObserved.complete();
        }
      }
    } on Object catch (error, stackTrace) {
      _capturedError ??= error;
      _capturedStackTrace ??= stackTrace;
      if (!_deliveryObserved.isCompleted) {
        _deliveryObserved.completeError(error, stackTrace);
      }
    }
  }
}

/// Creates a tiny valid JPEG below an app-owned media root. ConversationWired
/// then feeds this file through its ordinary durable staging, encryption,
/// upload, projection, and envelope-send path.
Future<File> createPrivateMediaOutboxE2ESource({
  required MediaFileManager mediaFileManager,
  required PrivateMediaOutboxE2ERequest request,
}) async {
  final trustedRoot = await mediaFileManager.trustedMediaRootPath();
  final directory = Directory('$trustedRoot/private_media_outbox_e2e_sources');
  await directory.create(recursive: true);
  final file = File('${directory.path}/${request.runCorrelationSha256}.jpg');
  await file.writeAsBytes(base64Decode(_onePixelWhiteJpegBase64), flush: true);
  return file;
}

Future<void> waitForPrivateMediaOutboxE2ECondition({
  required String label,
  required Duration timeout,
  required Future<bool> Function() check,
  Duration pollInterval = const Duration(milliseconds: 100),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await check()) return;
    await Future<void>.delayed(pollInterval);
  }
  throw TimeoutException('private-media outbox timed out waiting for $label');
}

const Set<String> _senderEventNames = <String>{
  privateMediaOutboxNetworkRestoredEvent,
  privateMediaOutboxLeaseClaimedEvent,
  privateMediaOutboxEncryptionPreparedEvent,
  privateMediaOutboxUploadStartEvent,
  privateMediaOutboxSendSuccessEvent,
};

bool _exactSenderEventOrder(List<Object?> events) {
  const expected = <String>[
    privateMediaOutboxNetworkRestoredEvent,
    privateMediaOutboxLeaseClaimedEvent,
    privateMediaOutboxEncryptionPreparedEvent,
    privateMediaOutboxUploadStartEvent,
    privateMediaOutboxSendSuccessEvent,
  ];
  if (events.length != expected.length) return false;
  for (var index = 0; index < expected.length; index++) {
    if (events[index] != expected[index]) return false;
  }
  return true;
}

const String _onePixelWhiteJpegBase64 =
    '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAP//////////////////////////////////////'
    '////////////////////////////////////////////2wBDAf//////////////////////'
    '////////////////////////////////////////////////////////////wAARCAABAAED'
    'ASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAf/xAAUEAEAAAAAAAAAAAAAAAAA'
    'AAAA/9oADAMBAAIQAxAAAAF//8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABBQJ/'
    '/8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAgBAwEBPwF//8QAFBEBAAAAAAAAAAAAAAAA'
    'AAAAAP/aAAgBAgEBPwF//8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQAGPwJ//8QA'
    'FBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPyF//9oADAMBAAIAAwAAABD/xAAUEQEA'
    'AAAAAAAAAAAAAAAAAAAA/9oACAEDAQE/EH//xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oA'
    'CAECAQE/EH//xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAE/EH//2Q==';

int _systemNowMilliseconds() => DateTime.now().millisecondsSinceEpoch;
