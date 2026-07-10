import 'package:flutter/services.dart';
import 'package:flutter_app/core/media/received_media_egress.dart';

const String receivedMediaEgressChannelName = 'mknoon/received_media_egress';

abstract interface class ReceivedMediaEgressGateway {
  Future<MediaEgressResult> perform(MediaEgressRequest request);
}

class ReceivedMediaEgressChannel implements ReceivedMediaEgressGateway {
  ReceivedMediaEgressChannel({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(receivedMediaEgressChannelName);

  final MethodChannel _channel;

  @override
  Future<MediaEgressResult> perform(MediaEgressRequest request) async {
    try {
      final raw = await _channel.invokeMethod<Object?>(
        'perform',
        request.toMap(),
      );
      return _decode(raw, request);
    } on MissingPluginException {
      return _failure(request);
    } on PlatformException {
      return _failure(request);
    } catch (_) {
      return _failure(request);
    }
  }

  MediaEgressResult _decode(Object? raw, MediaEgressRequest request) {
    if (raw is! Map ||
        !_exactKeys(raw, const {'requestId', 'outcome', 'items'})) {
      return _failure(request);
    }
    final requestId = raw['requestId'];
    final outcomeName = raw['outcome'];
    final itemMaps = raw['items'];
    if (requestId != request.requestId ||
        outcomeName is! String ||
        itemMaps is! List) {
      return _failure(request);
    }
    final outcome = _aggregateOutcomes[outcomeName];
    if (outcome == null) return _failure(request);
    if (request.destination == MediaEgressDestination.share) {
      if (itemMaps.isNotEmpty ||
          !const {
            MediaEgressOutcome.presented,
            MediaEgressOutcome.busy,
            MediaEgressOutcome.platformFailure,
          }.contains(outcome)) {
        return _failure(request);
      }
      return MediaEgressResult(
        requestId: request.requestId,
        outcome: outcome,
        items: const [],
      );
    }
    // Photos has no user-cancellable picker. A native `cancelled` result on
    // that destination is therefore contradictory rather than truthful.
    if (request.destination == MediaEgressDestination.photos &&
        outcome == MediaEgressOutcome.cancelled) {
      return _failure(request);
    }
    if (itemMaps.length != request.items.length) return _failure(request);
    final decoded = <MediaEgressItemResult>[];
    for (var index = 0; index < itemMaps.length; index++) {
      final itemRaw = itemMaps[index];
      if (itemRaw is! Map ||
          !_exactKeys(itemRaw, const {'attachmentId', 'outcome'})) {
        return _failure(request);
      }
      final id = itemRaw['attachmentId'];
      final itemOutcomeName = itemRaw['outcome'];
      final itemOutcome = itemOutcomeName is String
          ? _itemOutcomes[itemOutcomeName]
          : null;
      if (id != request.items[index].attachmentId || itemOutcome == null) {
        return _failure(request);
      }
      decoded.add(
        MediaEgressItemResult(attachmentId: id as String, outcome: itemOutcome),
      );
    }
    // Photos has no cancellation UI. Reject cancellation anywhere in its
    // envelope, including when a different aggregate could otherwise hide it.
    if (request.destination == MediaEgressDestination.photos &&
        decoded.any(
          (item) => item.outcome == MediaEgressItemOutcome.cancelled,
        )) {
      return _failure(request);
    }
    if (_aggregateForItems(decoded) != outcome) {
      return _failure(request);
    }
    return MediaEgressResult(
      requestId: request.requestId,
      outcome: outcome,
      items: decoded,
    );
  }

  bool _exactKeys(Map<dynamic, dynamic> map, Set<String> keys) =>
      map.keys.every(keys.contains) && map.length == keys.length;

  MediaEgressResult _failure(MediaEgressRequest request) => MediaEgressResult(
    requestId: request.requestId,
    outcome: MediaEgressOutcome.platformFailure,
    items: request.destination == MediaEgressDestination.share
        ? const []
        : request.items
              .map(
                (item) => MediaEgressItemResult(
                  attachmentId: item.attachmentId,
                  outcome: MediaEgressItemOutcome.platformFailure,
                ),
              )
              .toList(growable: false),
  );
}

const _aggregateOutcomes = <String, MediaEgressOutcome>{
  'saved': MediaEgressOutcome.saved,
  'partial': MediaEgressOutcome.partial,
  'cancelled': MediaEgressOutcome.cancelled,
  'busy': MediaEgressOutcome.busy,
  'permissionDenied': MediaEgressOutcome.permissionDenied,
  'rejected': MediaEgressOutcome.rejected,
  'platformFailure': MediaEgressOutcome.platformFailure,
  'presented': MediaEgressOutcome.presented,
};

const _itemOutcomes = <String, MediaEgressItemOutcome>{
  'saved': MediaEgressItemOutcome.saved,
  'cancelled': MediaEgressItemOutcome.cancelled,
  'busy': MediaEgressItemOutcome.busy,
  'permissionDenied': MediaEgressItemOutcome.permissionDenied,
  'missingFile': MediaEgressItemOutcome.missingFile,
  'unsupportedType': MediaEgressItemOutcome.unsupportedType,
  'outsideOwnedRoot': MediaEgressItemOutcome.outsideOwnedRoot,
  'identityConflict': MediaEgressItemOutcome.identityConflict,
  'platformFailure': MediaEgressItemOutcome.platformFailure,
};

MediaEgressOutcome _aggregateForItems(List<MediaEgressItemResult> items) {
  if (items.every((item) => item.outcome == MediaEgressItemOutcome.saved)) {
    return MediaEgressOutcome.saved;
  }
  if (items.any((item) => item.outcome == MediaEgressItemOutcome.saved)) {
    return MediaEgressOutcome.partial;
  }
  if (items.any(
    (item) => item.outcome == MediaEgressItemOutcome.platformFailure,
  )) {
    return MediaEgressOutcome.platformFailure;
  }
  if (items.any(
    (item) => item.outcome == MediaEgressItemOutcome.permissionDenied,
  )) {
    return MediaEgressOutcome.permissionDenied;
  }
  if (items.every((item) => item.outcome == MediaEgressItemOutcome.cancelled)) {
    return MediaEgressOutcome.cancelled;
  }
  if (items.every((item) => item.outcome == MediaEgressItemOutcome.busy)) {
    return MediaEgressOutcome.busy;
  }
  return MediaEgressOutcome.rejected;
}
