// ignore_for_file: depend_on_referenced_packages
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_item.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_depth_surface.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/thought_reply_status.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

import '../../../../shared/fakes/fake_just_audio.dart';
import '../../support/depth_fixtures.dart';

typedef _Phone = ({Size size, double top, double bottom});
typedef _Place = ({
  double barTop,
  double barBottom,
  double areaTop,
  double areaBottom,
  double ringY,
  double nameTop,
});

const _short = "Who's up for pizza tonight?";
const _medium =
    'Took the long way home today and found a tiny bookshop I never knew '
    "existed. Bought two books I definitely didn't need.";
const _long =
    'Okay, long one. I finally finished the bookshelf for the living room. It '
    'took three weekends, two trips back to the hardware store because I '
    'measured wrong, and one very patient neighbour who lent me his clamps '
    "and then stayed for coffee. The left side still leans a tiny bit if you "
    "look closely, but I've decided that's character. Next project is the "
    "balcony, and this time I'm measuring twice. Maybe three times. Thank you "
    'all for the advice last month, it really helped.';
const _caption =
    'Golden hour from the roof. We stayed up there until the street lights '
    'came on and nobody wanted to go back down.';
const _voiceText = 'You have to hear what the twins said at dinner';

const _phones = <_Phone>[
  (size: Size(360, 640), top: 24, bottom: 0),
  (size: Size(390, 844), top: 47, bottom: 34),
  (size: Size(412, 915), top: 24, bottom: 24),
];

/// Screen points, measured from the owner's "3d" canvas on 390 x 844 and
/// scaled by the surface's k = min(width / 390, stage height / 640).
final _places = <(Size, bool), _Place>{
  (Size(360, 640), false): (
    barTop: 462.76,
    barBottom: 506.76,
    areaTop: 36.54,
    areaBottom: 450.96,
    ringY: 577.31,
    nameTop: 612.71,
  ),
  (Size(390, 844), false): (
    barTop: 587,
    barBottom: 639,
    areaTop: 64,
    areaBottom: 571,
    ringY: 725,
    nameTop: 773,
  ),
  (Size(412, 915), false): (
    barTop: 655.42,
    barBottom: 710.35,
    areaTop: 41.96,
    areaBottom: 638.52,
    ringY: 801.21,
    nameTop: 851.91,
  ),
  (Size(360, 640), true): (
    barTop: 552,
    barBottom: 596,
    areaTop: 247.12,
    areaBottom: 540.20,
    ringY: 158.10,
    nameTop: 193.50,
  ),
  (Size(390, 844), true): (
    barTop: 708,
    barBottom: 760,
    areaTop: 329.61,
    areaBottom: 692,
    ringY: 208.89,
    nameTop: 256.89,
  ),
  (Size(412, 915), true): (
    barTop: 783.25,
    barBottom: 838.18,
    areaTop: 319.39,
    areaBottom: 766.34,
    ringY: 191.87,
    nameTop: 242.57,
  ),
};

void main() {
  late Directory temp;
  late JustAudioPlatform audio;
  late Map<String, PostModel> thoughts;
  late Map<String, List<PostMediaAttachmentModel>> media;
  late ValueNotifier<int> reset;
  setUp(() {
    temp = Directory.systemTemp.createTempSync('orbit-depth-space-');
    MediaFileManager.cacheDocumentsDir(temp.path);
    audio = JustAudioPlatform.instance;
    JustAudioPlatform.instance = FakeJustAudioPlatform();
    thoughts = {for (var i = 0; i < 4; i++) 'peer-$i': depthThought(i)};
    media = {};
    reset = ValueNotifier(0);
  });
  tearDown(() {
    JustAudioPlatform.instance = audio;
    MediaFileManager.debugResetDocumentsDirCache();
    temp.deleteSync(recursive: true);
  });

  PostMediaAttachmentModel attachment(String kind) {
    final file = File('${temp.path}/$kind.mp4')..writeAsBytesSync([0, 1, 2]);
    return PostMediaAttachmentModel(
      mediaId: 'media-$kind',
      postId: 'post-0',
      blobId: 'blob-$kind',
      kind: kind,
      mime: kind == 'voice' ? 'audio/mp4' : 'video/mp4',
      sizeBytes: 40,
      localPath: file.path,
      downloadStatus: 'done',
      createdAt: DateTime.utc(2026).toIso8601String(),
      durationMs: 4000,
      width: kind == 'video' ? 1080 : null,
      height: kind == 'video' ? 1920 : null,
      waveform: kind == 'voice' ? [.1, .4, .2] : null,
    );
  }

  final kinds = <String, void Function()>{
    'short': () => thoughts['peer-0'] = depthThought(0, text: _short),
    'medium': () => thoughts['peer-0'] = depthThought(0, text: _medium),
    'long': () => thoughts['peer-0'] = depthThought(0, text: _long),
    'photo': () {
      thoughts['peer-0'] = depthThought(0, text: _caption, mediaKind: 'image');
      media['post-0'] = [attachment('video')];
    },
    'voice': () {
      thoughts['peer-0'] = depthThought(
        0,
        text: _voiceText,
        mediaKind: 'voice',
      );
      media['post-0'] = [attachment('voice')];
    },
    'photo+voice': () {
      thoughts['peer-0'] = depthThought(0, text: _caption, mediaKind: 'image');
      media['post-0'] = [attachment('voice'), attachment('video')];
    },
  };

  Future<void> mount(
    WidgetTester tester,
    _Phone phone, {
    bool rtl = false,
  }) async {
    tester.view.physicalSize = phone.size;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = FakeViewPadding(top: phone.top, bottom: phone.bottom);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        locale: rtl ? const Locale('ar') : const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Scaffold(
          resizeToAvoidBottomInset: false,
          body: SafeArea(
            child: OrbitDepthSurface(
              items: [
                for (var i = 0; i < 4; i++) OrbitFriendItem(depthFriend(i)),
              ],
              thoughts: thoughts,
              // As the Orbit screen passes them: the header row, and the
              // persistent nav band above the home indicator.
              topClearance: 56,
              bottomClearance:
                  math.max(16, phone.bottom - 14) + 64 + 8 - phone.bottom,
              nowProvider: () => depthNow,
              resetSignal: reset,
              onFriendTap: (_) {},
              onThoughtTap: (_) {},
              onReply: (_, _, _) async => ThoughtReplyStatus.sent,
              loadMedia: (postId) async => media[postId] ?? const [],
              downloadMedia: (item) async => item,
              child: const SizedBox.expand(child: Text('Flat circle')),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> rest(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> enter(WidgetTester tester, {required bool up}) async {
    await tester.timedDrag(
      find.byType(OrbitDepthSurface),
      Offset(0, up ? -220 : 220),
      const Duration(seconds: 1),
    );
    await rest(tester);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    tester.view.reset();
    reset.dispose();
  }

  final bar = find.byKey(const ValueKey('orbit-depth-answers-post-0'));
  final love = find.byKey(const ValueKey('orbit-depth-react-love'));
  final laugh = find.byKey(const ValueKey('orbit-depth-react-laugh'));
  final applause = find.byKey(const ValueKey('orbit-depth-react-applause'));
  final reply = find.byKey(const ValueKey('orbit-depth-reply'));
  final slot = find.byKey(const ValueKey('orbit-depth-card-slot'));
  final ring = find.byKey(const ValueKey('orbit-depth-center-slot'));
  final name = find.byKey(const ValueKey('orbit-depth-name'));
  final text = find.byKey(const ValueKey('orbit-depth-text-post-0'));
  final age = find.text('7 min ago');
  final photo = find.byKey(const ValueKey('orbit-depth-photo-frame'));
  final voice = find.byKey(const ValueKey('orbit-depth-voice-media-voice'));

  Matcher at(double value) => closeTo(value, .01);

  void expectInside(WidgetTester tester, Finder part, _Place place) {
    final rect = tester.getRect(part);
    expect(
      rect.top,
      greaterThanOrEqualTo(place.areaTop - .01),
      reason: '$part',
    );
    expect(
      rect.bottom,
      lessThanOrEqualTo(place.areaBottom + .01),
      reason: '$part',
    );
    expect(rect.overlaps(tester.getRect(bar)), isFalse, reason: '$part');
    expect(rect.overlaps(tester.getRect(ring)), isFalse, reason: '$part');
    expect(rect.overlaps(tester.getRect(name)), isFalse, reason: '$part');
  }

  for (final phone in _phones) {
    for (final up in [false, true]) {
      final size = phone.size;
      final place = _places[(size, up)]!;
      testWidgets('on a ${size.width.toInt()}x${size.height.toInt()} phone, '
          'swiped ${up ? 'up' : 'down'}, the bar, the ring and the thought '
          'area keep one place for every kind of thought', (tester) async {
        final bars = <Rect>{}, rings = <Rect>{}, names = <Rect>{};
        for (final MapEntry(key: kind, value: seed) in kinds.entries) {
          media = {};
          seed();
          await mount(tester, phone);
          await enter(tester, up: up);
          expect(tester.getTopLeft(love).dy, at(place.barTop), reason: kind);
          expect(
            tester.getBottomLeft(love).dy,
            at(place.barBottom),
            reason: kind,
          );
          expect(tester.getTopLeft(slot).dy, at(place.areaTop), reason: kind);
          expect(
            tester.getBottomLeft(slot).dy,
            at(place.areaBottom),
            reason: kind,
          );
          expect(tester.getCenter(ring).dy, at(place.ringY), reason: kind);
          expect(tester.getTopLeft(name).dy, at(place.nameTop), reason: kind);
          bars.add(tester.getRect(bar));
          rings.add(tester.getRect(ring));
          names.add(tester.getRect(name));
          expectInside(tester, text, place);
          expectInside(tester, age, place);
          if (kind.startsWith('photo')) {
            expectInside(tester, photo, place);
            expect(
              tester.getBottomLeft(photo).dy,
              at(place.areaBottom),
              reason: '$kind fills down to the bar',
            );
          }
          if (kind.contains('voice')) expectInside(tester, voice, place);
          await finish(tester);
          reset = ValueNotifier(0);
        }
        expect(bars, hasLength(1));
        expect(rings, hasLength(1));
        expect(names, hasLength(1));
      });
    }
  }

  group('on a 390x844 phone swiped down', () {
    final phone = _phones[1];
    final place = _places[(phone.size, false)]!;

    for (final (kind, sample, size, weight) in [
      ('short', _short, 34.0, FontWeight.w600),
      ('medium', _medium, 26.0, FontWeight.w500),
      ('long', _long, 22.0, FontWeight.w500),
    ]) {
      testWidgets('a $kind text thought is $size pt, white', (tester) async {
        thoughts['peer-0'] = depthThought(0, text: sample);
        await mount(tester, phone);
        await enter(tester, up: false);
        final style = tester.widget<Text>(text).style!;
        expect((style.fontSize, style.fontWeight), (size, weight));
        expect(
          style.color,
          Theme.of(tester.element(text)).colorScheme.onSurface,
        );
        await finish(tester);
      });
    }

    for (final (kind, sample) in [('short', _short), ('medium', _medium)]) {
      testWidgets('a $kind thought sits in the middle of the area, the age '
          'line under it', (tester) async {
        thoughts['peer-0'] = depthThought(0, text: sample);
        await mount(tester, phone);
        await enter(tester, up: false);
        final words = tester.getRect(text);
        final when = tester.getRect(age);
        expect(when.top, greaterThan(words.bottom));
        expect(
          words.top - place.areaTop,
          closeTo(place.areaBottom - when.bottom, 1),
        );
        final paragraph = tester.renderObject<RenderParagraph>(text);
        final last = paragraph
            .getBoxesForSelection(
              TextSelection(baseOffset: 0, extentOffset: sample.length),
            )
            .last
            .toRect()
            .shift(paragraph.localToGlobal(Offset.zero));
        expect(last.left - 14, closeTo(phone.size.width - 14 - last.right, 1));
        await finish(tester);
      });
    }

    testWidgets('a long thought starts at the top with its age line and is '
        'cut at the bottom of the area', (tester) async {
      thoughts['peer-0'] = depthThought(0, text: _long);
      await mount(tester, phone);
      await enter(tester, up: false);
      expect(tester.getTopLeft(age).dy, at(place.areaTop));
      expect(
        tester.getTopLeft(text).dy,
        greaterThan(tester.getBottomLeft(age).dy),
      );
      expect(tester.getTopLeft(text).dx, at(14));
      expect(
        tester.getBottomLeft(text).dy,
        lessThanOrEqualTo(place.areaBottom),
      );
      expect(
        tester.renderObject<RenderParagraph>(text).didExceedMaxLines,
        isTrue,
      );
      await finish(tester);
    });

    testWidgets('in Arabic the bar is mirrored and keeps its place', (
      tester,
    ) async {
      thoughts['peer-0'] = depthThought(0, text: _short);
      await mount(tester, phone, rtl: true);
      await enter(tester, up: false);
      expect(
        tester.getCenter(love).dx,
        greaterThan(tester.getCenter(laugh).dx),
      );
      expect(
        tester.getTopRight(reply).dx,
        lessThan(tester.getTopLeft(applause).dx),
      );
      expect(tester.getTopLeft(love).dy, at(place.barTop));
      expect(tester.getTopLeft(slot).dy, at(place.areaTop));
      expect(tester.getBottomLeft(slot).dy, at(place.areaBottom));
      expect(tester.getCenter(ring).dy, at(place.ringY));
      await finish(tester);
    });
  });

  for (final kind in kinds.keys) {
    testWidgets('on a 360x640 phone swiped up, a $kind thought keeps a valid '
        'layout while Reply opens the keyboard', (tester) async {
      kinds[kind]!();
      await mount(tester, _phones[0]);
      await enter(tester, up: true);
      await tester.tap(reply);
      await tester.pump();
      final composer = find.byKey(const ValueKey('orbit-depth-composer'));
      expect(composer, findsOneWidget);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(tester.getRect(composer).bottom, lessThanOrEqualTo(360));
      tester.view.viewInsets = const FakeViewPadding();
      await tester.pump();
      await finish(tester);
    });
  }
}
