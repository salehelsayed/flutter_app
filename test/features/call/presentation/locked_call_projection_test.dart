import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_app/features/call/application/call_audio_controller.dart';
import 'package:flutter_app/features/call/application/foreground_call_capability.dart';
import 'package:flutter_app/features/call/application/locked_call_presentation.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/call/presentation/locked_call_projection.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'headless directory uses the same generated avatar without a widget frame',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'headless-avatar-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final headless = await LockedCallProjection.renderAvatar(
        'authenticated-peer',
        true,
        documentsDirectory: directory.path,
      );
      final foreground = await LockedCallProjection.renderAvatar(
        'authenticated-peer',
        true,
      );
      expect(headless, foreground);
      expect(headless, isNotEmpty);
      final codec = await ui.instantiateImageCodec(headless!);
      final image = (await codec.getNextFrame()).image;
      expect((image.width, image.height), (336, 336));
      image.dispose();
      codec.dispose();
    },
  );

  test(
    'malformed and oversized local photos preserve generated caller identity',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'headless-avatar-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File(
        '${directory.path}/media/avatars/authenticated-peer.jpg',
      );
      await file.parent.create(recursive: true);
      final generated = await LockedCallProjection.renderAvatar(
        'authenticated-peer',
        false,
        documentsDirectory: directory.path,
      );
      await file.writeAsString('not an image');
      expect(
        await LockedCallProjection.renderAvatar(
          'authenticated-peer',
          false,
          documentsDirectory: directory.path,
        ),
        generated,
      );
      final handle = await file.open(mode: FileMode.write);
      await handle.truncate(8 * 1024 * 1024 + 1);
      await handle.close();
      expect(
        await LockedCallProjection.renderAvatar(
          'authenticated-peer',
          false,
          documentsDirectory: directory.path,
        ),
        generated,
      );
    },
  );

  test(
    'headless contact photo is loaded from supplied directory and respects light frame',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'headless-avatar-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(const Color(0xFFFF0000), BlendMode.src);
      final picture = recorder.endRecording();
      final photo = await picture.toImage(20, 20);
      final bytes = (await photo.toByteData(
        format: ui.ImageByteFormat.png,
      ))!.buffer.asUint8List();
      photo.dispose();
      picture.dispose();
      final file = File(
        '${directory.path}/media/avatars/authenticated-peer.jpg',
      );
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
      final light = await LockedCallProjection.renderAvatar(
        'authenticated-peer',
        true,
        documentsDirectory: directory.path,
      );
      final dark = await LockedCallProjection.renderAvatar(
        'authenticated-peer',
        false,
        documentsDirectory: directory.path,
      );
      expect(light, isNot(dark));
      for (final png in [light, dark]) {
        final codec = await ui.instantiateImageCodec(png!);
        final image = (await codec.getNextFrame()).image;
        final pixels = (await image.toByteData())!.buffer.asUint8List();
        final middle = (168 * 336 + 168) * 4;
        expect(pixels.sublist(middle, middle + 4), [255, 0, 0, 255]);
        image.dispose();
        codec.dispose();
      }
    },
  );

  for (final dimensions in <(int, int, int, int)>[
    (168, 672, 84, 336),
    (672, 168, 336, 84),
    (20, 80, 20, 80),
    (80, 20, 80, 20),
  ]) {
    final (width, height, decodedWidth, decodedHeight) = dimensions;
    test(
      'photo ${width}x$height keeps aspect and bounds decoded resources without upscaling',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'headless-avatar-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final recorder = ui.PictureRecorder();
        Canvas(recorder)
          ..drawColor(const Color(0xFF0000FF), BlendMode.src)
          ..drawCircle(
            Offset(width / 2, height / 2),
            (width < height ? width : height) / 4,
            Paint()..color = const Color(0xFFFF0000),
          );
        final picture = recorder.endRecording();
        late final ui.Image source;
        try {
          source = await picture.toImage(width, height);
        } finally {
          picture.dispose();
        }
        late final List<int> bytes;
        try {
          bytes = (await source.toByteData(
            format: ui.ImageByteFormat.png,
          ))!.buffer.asUint8List();
        } finally {
          source.dispose();
        }
        final file = File(
          '${directory.path}/media/avatars/authenticated-peer.jpg',
        );
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes);

        final createdImages = <ui.Image>[];
        final decodedSizes = <(int, int)>[];
        final disposedImages = <ui.Image>[];
        final createdPictures = <ui.Picture>[];
        final disposedPictures = <ui.Picture>[];
        final oldImageCreate = ui.Image.onCreate;
        final oldImageDispose = ui.Image.onDispose;
        final oldPictureCreate = ui.Picture.onCreate;
        final oldPictureDispose = ui.Picture.onDispose;
        ui.Image.onCreate = (image) {
          createdImages.add(image);
          decodedSizes.add((image.width, image.height));
        };
        ui.Image.onDispose = disposedImages.add;
        ui.Picture.onCreate = createdPictures.add;
        ui.Picture.onDispose = disposedPictures.add;
        late final Uint8List? png;
        try {
          png = await LockedCallProjection.renderAvatar(
            'authenticated-peer',
            false,
            documentsDirectory: directory.path,
          );
        } finally {
          ui.Image.onCreate = oldImageCreate;
          ui.Image.onDispose = oldImageDispose;
          ui.Picture.onCreate = oldPictureCreate;
          ui.Picture.onDispose = oldPictureDispose;
        }
        expect(decodedSizes, [(decodedWidth, decodedHeight), (336, 336)]);
        expect(disposedImages, unorderedEquals(createdImages));
        expect(disposedPictures, unorderedEquals(createdPictures));
        expect(png, isNotNull);
        final codec = await ui.instantiateImageCodec(png!);
        final image = (await codec.getNextFrame()).image;
        try {
          final pixels = (await image.toByteData())!.buffer.asUint8List();
          List<int> pixelAt(int x, int y) {
            final index = (y * 336 + x) * 4;
            return pixels.sublist(index, index + 4);
          }

          // Cover-cropping preserves a round central feature in both source
          // orientations; forcing the source into a square would distort it.
          for (final point in [
            (108, 168),
            (228, 168),
            (168, 108),
            (168, 228),
          ]) {
            final pixel = pixelAt(point.$1, point.$2);
            expect(pixel[0], greaterThan(240));
            expect(pixel[1], 0);
            expect(pixel[2], lessThan(15));
            expect(pixel[3], 255);
          }
          for (final point in [(68, 168), (268, 168), (168, 68), (168, 268)]) {
            final pixel = pixelAt(point.$1, point.$2);
            expect(pixel[0], lessThan(15));
            expect(pixel[1], 0);
            expect(pixel[2], greaterThan(240));
            expect(pixel[3], 255);
          }
        } finally {
          image.dispose();
          codec.dispose();
        }
      },
    );
  }

  test(
    'ringing caller name reaches native before avatar rendering finishes',
    () async {
      final avatar = Completer<Uint8List?>();
      final projection = LockedCallProjection(
        avatarRenderer: (_, _) => avatar.future,
      );
      final capability = _Capability();
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final callId = CallId.parse('11111111-1111-4111-8111-111111111111');
      final update = projection.update(
        capability: capability,
        projection: ForegroundCallProjection(
          session: CallSessionSnapshot.active(
            callId: callId,
            contactPeerId: 'authenticated-peer',
            direction: CallDirection.incoming,
            state: CallState.incomingValidating,
            callerAccountPeerId: 'authenticated-peer',
            callerDeviceId: 'remote-device',
            startedAt: DateTime.utc(2026),
            incomingValidated: true,
          ),
          audio: CallAudioControlState.idle,
        ),
        displayName: 'Beta iPhone',
        light: true,
        l10n: l10n,
      );
      await Future<void>.delayed(Duration.zero);
      expect(capability.values, hasLength(1));
      expect(capability.values.single.$2.displayName, 'Beta iPhone');
      expect(capability.values.single.$2.state, 'preparing');
      expect(capability.values.single.$2.avatarPng, isNull);
      avatar.complete(Uint8List.fromList([1, 2, 3]));
      await update;
      expect(capability.values, hasLength(2));
      expect(capability.values.last.$2.avatarPng, [1, 2, 3]);
      projection.dispose();
    },
  );

  test(
    'avatar generation publishes only the latest authenticated call without a rendered frame',
    () async {
      final projection = LockedCallProjection();
      final capability = _Capability();
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final first = CallId.parse('11111111-1111-4111-8111-111111111111');
      final second = CallId.parse('22222222-2222-4222-8222-222222222222');
      Future<void> update(CallId id, String name) => projection.update(
        capability: capability,
        projection: ForegroundCallProjection(
          session: CallSessionSnapshot.active(
            callId: id,
            contactPeerId: name,
            direction: CallDirection.incoming,
            state: CallState.ringing,
            callerAccountPeerId: name,
            callerDeviceId: 'remote-device',
            startedAt: DateTime.utc(2026),
            incomingValidated: true,
          ),
          audio: CallAudioControlState.idle,
        ),
        displayName: name,
        light: true,
        l10n: l10n,
      );
      await Future.wait([
        update(first, 'Previous caller'),
        update(second, 'Current caller'),
      ]);
      expect(capability.values.last.$1, second);
      final data = capability.values.last.$2;
      expect(data.displayName, 'Current caller');
      expect(data.avatarPng, isNotEmpty);
      expect(data.avatarPng!.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      expect(data.muteAvailable, isFalse);
      expect(data.connectedAtMs, isNull);
      projection.dispose();
    },
  );
}

class _Capability
    implements ForegroundCallCapability, LockedCallPresentationPort {
  final values = <(CallId, LockedCallPresentation)>[];
  @override
  Future<void> updateLockedPresentation(
    CallId callId,
    LockedCallPresentation presentation,
  ) async {
    values.add((callId, presentation));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
