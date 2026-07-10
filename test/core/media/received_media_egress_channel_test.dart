import 'package:flutter/services.dart';
import 'package:flutter_app/core/media/received_media_egress.dart';
import 'package:flutter_app/core/media/received_media_egress_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(receivedMediaEgressChannelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'perform channel schema correlation and outcome precedence are exact',
    () async {
      MethodCall? captured;
      messenger.setMockMethodCallHandler(channel, (call) async {
        captured = call;
        return {
          'requestId': 'r_1',
          'outcome': 'partial',
          'items': [
            {'attachmentId': 'a', 'outcome': 'saved'},
            {'attachmentId': 'b', 'outcome': 'permissionDenied'},
          ],
        };
      });
      final gateway = ReceivedMediaEgressChannel(channel: channel);
      final request = MediaEgressRequest(
        requestId: 'r_1',
        destination: MediaEgressDestination.files,
        items: const [
          MediaEgressItem(
            attachmentId: 'a',
            sourcePath: '/private/a.jpg',
            mime: 'image/jpeg',
            displayName: 'a.jpg',
          ),
          MediaEgressItem(
            attachmentId: 'b',
            sourcePath: '/private/b.mp4',
            mime: 'video/mp4',
            displayName: 'b.mp4',
          ),
        ],
      );
      final result = await gateway.perform(request);
      expect(captured!.method, 'perform');
      expect(captured!.arguments, {
        'requestId': 'r_1',
        'destination': 'files',
        'items': [
          {
            'attachmentId': 'a',
            'sourcePath': '/private/a.jpg',
            'mime': 'image/jpeg',
            'displayName': 'a.jpg',
          },
          {
            'attachmentId': 'b',
            'sourcePath': '/private/b.mp4',
            'mime': 'video/mp4',
            'displayName': 'b.mp4',
          },
        ],
      });
      expect(result.outcome, MediaEgressOutcome.partial);

      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {'requestId': 'wrong', 'outcome': 'saved', 'items': []},
      );
      final malformed = await gateway.perform(request);
      expect(malformed.outcome, MediaEgressOutcome.platformFailure);
      expect(
        malformed.items.map((e) => e.outcome),
        everyElement(MediaEgressItemOutcome.platformFailure),
      );

      for (final contradictory in <Map<String, Object>>[
        {
          'requestId': 'r_1',
          'outcome': 'busy',
          'items': [
            {'attachmentId': 'a', 'outcome': 'saved'},
            {'attachmentId': 'b', 'outcome': 'busy'},
          ],
        },
        {
          'requestId': 'r_1',
          'outcome': 'cancelled',
          'items': [
            {'attachmentId': 'a', 'outcome': 'cancelled'},
            {'attachmentId': 'b', 'outcome': 'permissionDenied'},
          ],
        },
      ]) {
        messenger.setMockMethodCallHandler(channel, (_) async => contradictory);
        final rejectedEnvelope = await gateway.perform(request);
        expect(rejectedEnvelope.outcome, MediaEgressOutcome.platformFailure);
      }

      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {
          'requestId': 'r_1',
          'outcome': 'busy',
          'items': [
            {'attachmentId': 'a', 'outcome': 'busy'},
            {'attachmentId': 'b', 'outcome': 'busy'},
          ],
        },
      );
      final busy = await gateway.perform(request);
      expect(busy.outcome, MediaEgressOutcome.busy);
      expect(busy.items.map((item) => item.attachmentId), ['a', 'b']);

      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {
          'requestId': 'r_1',
          'outcome': 'cancelled',
          'items': [
            {'attachmentId': 'a', 'outcome': 'cancelled'},
            {'attachmentId': 'b', 'outcome': 'cancelled'},
          ],
        },
      );
      final filesCancelled = await gateway.perform(request);
      expect(filesCancelled.outcome, MediaEgressOutcome.cancelled);

      final photosRequest = MediaEgressRequest(
        requestId: 'r_1',
        destination: MediaEgressDestination.photos,
        items: request.items,
      );
      final impossiblePhotosCancellation = await gateway.perform(photosRequest);
      expect(
        impossiblePhotosCancellation.outcome,
        MediaEgressOutcome.platformFailure,
      );
      expect(
        impossiblePhotosCancellation.items.map((item) => item.outcome),
        everyElement(MediaEgressItemOutcome.platformFailure),
      );

      for (final cancelledPhotosEnvelope in <Map<String, Object>>[
        {
          'requestId': 'r_1',
          'outcome': 'rejected',
          'items': [
            {'attachmentId': 'a', 'outcome': 'cancelled'},
            {'attachmentId': 'b', 'outcome': 'missingFile'},
          ],
        },
        {
          'requestId': 'r_1',
          'outcome': 'permissionDenied',
          'items': [
            {'attachmentId': 'a', 'outcome': 'cancelled'},
            {'attachmentId': 'b', 'outcome': 'permissionDenied'},
          ],
        },
      ]) {
        messenger.setMockMethodCallHandler(
          channel,
          (_) async => cancelledPhotosEnvelope,
        );
        final impossibleItemCancellation = await gateway.perform(photosRequest);
        expect(
          impossibleItemCancellation.outcome,
          MediaEgressOutcome.platformFailure,
        );
        expect(
          impossibleItemCancellation.items.map((item) => item.outcome),
          everyElement(MediaEgressItemOutcome.platformFailure),
        );
      }

      expect(
        () => MediaEgressRequest(
          requestId: '../bad',
          destination: MediaEgressDestination.share,
          items: const [],
        ),
        throwsArgumentError,
      );
    },
  );
}
