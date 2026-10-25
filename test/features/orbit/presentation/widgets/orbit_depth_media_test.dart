// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_depth_media.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/audio_player_widget.dart';
import 'package:flutter_app/shared/widgets/media/media_grid.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import '../../../../shared/fakes/fake_just_audio.dart';

void main() {
  late Directory temp;
  late JustAudioPlatform original;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('orbit-depth-media-');
    MediaFileManager.cacheDocumentsDir(temp.path);
    original = JustAudioPlatform.instance;
    JustAudioPlatform.instance = FakeJustAudioPlatform();
  });
  tearDown(() {
    JustAudioPlatform.instance = original;
    MediaFileManager.debugResetDocumentsDirCache();
    temp.deleteSync(recursive: true);
  });
  PostMediaAttachmentModel attachment(String kind, String? path) =>
      PostMediaAttachmentModel(
        mediaId: 'media-$kind',
        postId: 'post',
        blobId: 'blob-$kind',
        kind: kind,
        mime: kind == 'voice'
            ? 'audio/mp4'
            : kind == 'video'
            ? 'video/mp4'
            : 'image/png',
        sizeBytes: 40,
        localPath: path,
        downloadStatus: path == null ? 'pending' : 'done',
        createdAt: DateTime.utc(2026).toIso8601String(),
        durationMs: kind == 'image' ? null : 4000,
        waveform: kind == 'voice' ? [.1, .4, .2] : null,
      );
  Future<void> mount(
    WidgetTester tester,
    Future<List<PostMediaAttachmentModel>> Function(String) load,
    Future<PostMediaAttachmentModel> Function(PostMediaAttachmentModel)
    download, {
    VoidCallback? open,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: OrbitDepthMedia(
              postId: 'post',
              load: load,
              download: download,
              onOpen: open ?? () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  for (final kind in ['image', 'video', 'voice']) {
    testWidgets(
      'front $kind uses real local attachment and existing renderer without downloading',
      (tester) async {
        final file = File(
          '${temp.path}/local.${kind == 'image'
              ? 'png'
              : kind == 'video'
              ? 'mp4'
              : 'm4a'}',
        );
        file.writeAsBytesSync(
          kind == 'image'
              ? base64Decode(
                  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
                )
              : [0, 1, 2, 3],
        );
        final item = attachment(kind, file.path);
        var downloads = 0;
        var opens = 0;
        await mount(tester, (_) async => [item], (item) async {
          downloads++;
          return item;
        }, open: () => opens++);
        if (kind == 'voice') {
          final audio = tester.widget<AudioPlayerWidget>(
            find.byType(AudioPlayerWidget),
          );
          expect(audio.attachment.localPath, file.path);
          expect(audio.attachment.waveform, [.1, .4, .2]);
          expect(
            find.byKey(const ValueKey('orbit-depth-voice-media-voice')),
            findsOneWidget,
          );
        } else {
          final grid = tester.widget<MediaGrid>(find.byType(MediaGrid));
          expect(grid.media.single.localPath, file.path);
          expect(grid.media.single.mediaType, kind);
          await tester.tap(find.byType(MediaGrid));
          await tester.pump();
          expect(opens, 1);
        }
        expect(downloads, 0);
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      },
    );
  }
  testWidgets(
    'failed download exposes retry and retry renders persisted local content',
    (tester) async {
      var item = attachment('image', null);
      var attempts = 0;
      final file = File('${temp.path}/retry.png')
        ..writeAsBytesSync(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
          ),
        );
      await mount(tester, (_) async => [item], (value) async {
        attempts++;
        if (attempts == 1) throw StateError('offline');
        item = value.copyWith(localPath: file.path, downloadStatus: 'done');
        return item;
      });
      expect(
        find.byKey(const ValueKey('orbit-depth-media-retry')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('orbit-depth-media-retry')));
      await tester.pump();
      await tester.pump();
      expect(attempts, 2);
      expect(
        find.byKey(const ValueKey('orbit-depth-media-retry')),
        findsNothing,
      );
      expect(
        tester.widget<MediaGrid>(find.byType(MediaGrid)).media.single.localPath,
        file.path,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final (width, height, ratio) in const [
    (720, 1280, 16 / 9),
    (1920, 1080, 9 / 16),
    (200, 2000, 16 / 9),
    (null, null, 3 / 4),
  ]) {
    testWidgets(
      'a single ${width}x$height video keeps its own shape (height/width $ratio)',
      (tester) async {
        final file = File('${temp.path}/shape.mp4')
          ..writeAsBytesSync([0, 1, 2, 3]);
        final item = attachment(
          'video',
          file.path,
        ).copyWith(width: width, height: height);
        await mount(tester, (_) async => [item], (item) async => item);
        final rect = tester.getRect(
          find
              .descendant(
                of: find.byType(MediaGrid),
                matching: find.byType(AspectRatio),
              )
              .first,
        );
        expect(rect.height / rect.width, closeTo(ratio, .01));
        expect(rect.height, lessThanOrEqualTo(600 * .45));
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      },
    );
  }

  testWidgets('dispose fences pending load before any download is started', (
    tester,
  ) async {
    final held = Completer<List<PostMediaAttachmentModel>>();
    var downloads = 0;
    await mount(tester, (_) => held.future, (item) async {
      downloads++;
      return item;
    });
    await tester.pumpWidget(const SizedBox());
    held.complete([attachment('image', null)]);
    await tester.pump();
    expect(downloads, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets('relative cached post media is reused offline without a download', (
    tester,
  ) async {
    final relative = 'post_media/post/cached.png';
    final file = File('${temp.path}/$relative')
      ..parent.createSync(recursive: true);
    file.writeAsBytesSync(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
      ),
    );
    var downloads = 0;
    await mount(tester, (_) async => [attachment('image', relative)], (
      item,
    ) async {
      downloads++;
      throw StateError('offline');
    });
    final downloadCount = downloads;
    final cachedStillExists = file.existsSync();
    final gridPath = tester
        .widget<MediaGrid>(find.byType(MediaGrid))
        .media
        .single
        .localPath;
    await tester.pumpWidget(const SizedBox());
    expect(downloadCount, 0);
    expect(cachedStillExists, isTrue);
    expect(MediaFileManager.resolveStoredPathSync(gridPath!), file.path);
  });
  testWidgets(
    'joins an active media download and displays completion on the same card',
    (tester) async {
      var item = attachment(
        'video',
        null,
      ).copyWith(downloadStatus: 'downloading');
      final held = Completer<PostMediaAttachmentModel>();
      var joins = 0;
      await mount(tester, (_) async => [item], (value) {
        joins++;
        return held.future;
      });
      final joinedBeforeCompletion = joins;
      item = item.copyWith(
        localPath: '${temp.path}/completed.mp4',
        downloadStatus: 'done',
      );
      File(item.localPath!).writeAsBytesSync([0, 1, 2, 3]);
      held.complete(item);
      await tester.pump();
      await tester.pump();
      final finalStatus = tester
          .widget<MediaGrid>(find.byType(MediaGrid))
          .media
          .single
          .downloadStatus;
      await tester.pumpWidget(const SizedBox());
      expect(joinedBeforeCompletion, 1);
      expect(finalStatus, 'done');
    },
  );
  testWidgets('retry waiting can be retried through the existing downloader', (
    tester,
  ) async {
    var item = attachment(
      'image',
      null,
    ).copyWith(downloadStatus: 'retry_waiting');
    var attempts = 0;
    await mount(tester, (_) async => [item], (value) async {
      attempts++;
      if (attempts == 1) return item;
      final file = File('${temp.path}/retry-waiting.png')
        ..writeAsBytesSync(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
          ),
        );
      item = value.copyWith(localPath: file.path, downloadStatus: 'done');
      return item;
    });
    final retry = find.byKey(const ValueKey('orbit-depth-media-retry'));
    expect(retry, findsOneWidget);
    await tester.tap(retry);
    await tester.pump();
    await tester.pump();
    expect(attempts, 2);
    expect(
      tester
          .widget<MediaGrid>(find.byType(MediaGrid))
          .media
          .single
          .downloadStatus,
      'done',
    );
    await tester.pumpWidget(const SizedBox());
  });
}
