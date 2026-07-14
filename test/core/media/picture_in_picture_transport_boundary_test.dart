import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_app/core/media/picture_in_picture_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'PiP source and channel schema contain no messaging or secret fields',
    () async {
      const request = PictureInPictureRequest(
        session: 'opaque-session',
        attachment: 'attachment-1',
        path: '/app/Documents/media/video.mp4',
        positionMs: 3456,
        durationMs: 9000,
      );
      expect(request.toMap().keys.toSet(), <String>{
        'session',
        'attachment',
        'path',
        'positionMs',
        'durationMs',
      });

      final encoded = jsonEncode(request.toMap());
      for (final forbidden in <String>[
        'messageId',
        'peerId',
        'groupId',
        'sender',
        'caption',
        'ownerLane',
        'transport',
        'relay',
        'nonce',
        'encryptionKey',
        'mediaBytes',
        'uriGrant',
      ]) {
        expect(encoded, isNot(contains(forbidden)));
      }

      final nativeEvents = StreamController<Object?>();
      final calls = <({String method, Map<String, Object?>? arguments})>[];
      final gateway = PictureInPictureChannelGateway(
        platform: PictureInPictureHostPlatform.android,
        invokeMethod: (method, arguments) async {
          calls.add((method: method, arguments: arguments));
          return method == 'capability'
              ? <String, Object?>{'supported': true}
              : <String, Object?>{'accepted': true};
        },
        nativeEvents: nativeEvents.stream,
      );
      addTearDown(() async {
        await gateway.dispose();
        await nativeEvents.close();
      });

      expect(
        await gateway.start(request),
        PictureInPictureStartOutcome.started,
      );
      nativeEvents.add(<String, Object?>{
        'session': request.session,
        'attachment': request.attachment,
        'state': 'nativeReady',
        'positionMs': request.positionMs,
        'durationMs': request.durationMs,
        'reason': null,
      });
      await Future<void>.delayed(Duration.zero);
      expect(
        (await gateway.activate(request.session, request.attachment)).accepted,
        isTrue,
      );
      expect(
        (await gateway.stop(request.session, request.attachment)).accepted,
        isTrue,
      );

      expect(calls[0].method, 'capability');
      expect(calls[0].arguments, isNull);
      expect(calls[1].method, 'start');
      expect(calls[1].arguments, request.toMap());
      expect(calls[2].method, 'activate');
      expect(calls[2].arguments, <String, Object?>{
        'session': request.session,
        'attachment': request.attachment,
      });
      expect(calls[3].method, 'stop');
      expect(calls[3].arguments, <String, Object?>{
        'session': request.session,
        'attachment': request.attachment,
      });

      final source = File(
        'lib/core/media/picture_in_picture_gateway.dart',
      ).readAsStringSync();
      for (final forbiddenImport in <String>[
        'p2p_service',
        'bridge.dart',
        'message_repository',
        'group_message_repository',
        'dart:convert',
      ]) {
        expect(source, isNot(contains(forbiddenImport)));
      }
    },
  );

  test('extra or mistyped native response fields fail closed', () async {
    for (final response in <Object?>[
      <String, Object?>{'supported': true, 'extra': true},
      <String, Object?>{'supported': 'true'},
      <String, Object?>{},
      null,
    ]) {
      final gateway = PictureInPictureChannelGateway(
        platform: PictureInPictureHostPlatform.android,
        invokeMethod: (method, arguments) async => response,
        nativeEvents: const Stream<Object?>.empty(),
      );
      final capability = await gateway.capability();
      expect(capability.isVisible, isFalse);
      expect(capability.isSupported, isFalse);
      expect(
        capability.reason,
        PictureInPictureCapabilityReason.channelFailure,
      );
      await gateway.dispose();
    }
  });

  test(
    'Kotlin PlatformException codes retain exact typed Dart reasons',
    () async {
      const expected = <String, PictureInPictureFailureReason>{
        'pip_unavailable': PictureInPictureFailureReason.pipUnavailable,
        'unsupported': PictureInPictureFailureReason.unsupported,
        'invalid_path': PictureInPictureFailureReason.invalidPath,
        'busy': PictureInPictureFailureReason.busy,
        'activity_unavailable':
            PictureInPictureFailureReason.activityUnavailable,
        'stale_session': PictureInPictureFailureReason.staleSession,
        'bad_args': PictureInPictureFailureReason.badArguments,
      };

      for (final entry in expected.entries) {
        final startGateway = PictureInPictureChannelGateway(
          platform: PictureInPictureHostPlatform.android,
          invokeMethod: (method, _) async {
            if (method == 'capability') {
              return <String, Object?>{'supported': true};
            }
            throw PlatformException(code: entry.key);
          },
          nativeEvents: const Stream<Object?>.empty(),
        );
        final startOutcome = await startGateway.start(_request(entry.key));
        expect(
          startOutcome,
          _startOutcome(entry.value),
          reason: 'start must retain ${entry.key}',
        );
        await startGateway.dispose();

        final nativeEvents = StreamController<Object?>();
        final activateGateway = PictureInPictureChannelGateway(
          platform: PictureInPictureHostPlatform.android,
          invokeMethod: (method, _) async {
            if (method == 'capability') {
              return <String, Object?>{'supported': true};
            }
            if (method == 'start' || method == 'stop') {
              return <String, Object?>{'accepted': true};
            }
            throw PlatformException(code: entry.key);
          },
          nativeEvents: nativeEvents.stream,
        );
        final request = _request('activate-${entry.key}');
        expect(
          await activateGateway.start(request),
          PictureInPictureStartOutcome.started,
        );
        nativeEvents.add(<String, Object?>{
          'session': request.session,
          'attachment': request.attachment,
          'state': 'nativeReady',
          'positionMs': 0,
          'durationMs': null,
          'reason': null,
        });
        await Future<void>.delayed(Duration.zero);
        final command = await activateGateway.activate(
          request.session,
          request.attachment,
        );
        expect(command.accepted, isFalse);
        expect(
          command.failureReason,
          entry.value,
          reason: 'activate must retain ${entry.key}',
        );
        await activateGateway.dispose();
        await nativeEvents.close();

        final stopGateway = PictureInPictureChannelGateway(
          platform: PictureInPictureHostPlatform.android,
          invokeMethod: (method, _) async {
            if (method == 'capability') {
              return <String, Object?>{'supported': true};
            }
            if (method == 'start') {
              return <String, Object?>{'accepted': true};
            }
            throw PlatformException(code: entry.key);
          },
          nativeEvents: const Stream<Object?>.empty(),
        );
        final stopRequest = _request('stop-${entry.key}');
        expect(
          await stopGateway.start(stopRequest),
          PictureInPictureStartOutcome.started,
        );
        final stopCommand = await stopGateway.stop(
          stopRequest.session,
          stopRequest.attachment,
        );
        expect(stopCommand.accepted, isFalse);
        expect(
          stopCommand.failureReason,
          entry.value,
          reason: 'stop must retain ${entry.key}',
        );
        await stopGateway.dispose();
      }
    },
  );
}

PictureInPictureRequest _request(String discriminator) =>
    PictureInPictureRequest(
      session: 'session-$discriminator',
      attachment: 'attachment-$discriminator',
      path: '/app/Documents/media/video.mp4',
      positionMs: 0,
    );

PictureInPictureStartOutcome _startOutcome(
  PictureInPictureFailureReason reason,
) => switch (reason) {
  PictureInPictureFailureReason.pipUnavailable =>
    PictureInPictureStartOutcome.pipUnavailable,
  PictureInPictureFailureReason.unsupported =>
    PictureInPictureStartOutcome.unsupported,
  PictureInPictureFailureReason.invalidPath =>
    PictureInPictureStartOutcome.invalidPath,
  PictureInPictureFailureReason.busy => PictureInPictureStartOutcome.busy,
  PictureInPictureFailureReason.activityUnavailable =>
    PictureInPictureStartOutcome.activityUnavailable,
  PictureInPictureFailureReason.staleSession =>
    PictureInPictureStartOutcome.staleSession,
  PictureInPictureFailureReason.badArguments =>
    PictureInPictureStartOutcome.badArguments,
  PictureInPictureFailureReason.unsupportedPlatform ||
  PictureInPictureFailureReason.channelFailure ||
  PictureInPictureFailureReason.platformFailure =>
    PictureInPictureStartOutcome.platformFailure,
};
