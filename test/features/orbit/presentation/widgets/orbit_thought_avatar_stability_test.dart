import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_item.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_thought_note.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/inner_circle_interactive_surface.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_thought_note_bubble.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbital_visualization.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _frame = Duration(microseconds: 16667);
const _settleFrames = 120;
const _observedFrames = 180;

// The intended swim target moves at most 2.2 logical pixels per second.
// Half a pixel per 60 Hz frame leaves ample room for smooth spring motion,
// while rejecting a switch to a different collision/seating solution.
const _maximumFrameStep = 0.5;

void main() {
  const sizes = <Size>[
    Size(320, 568),
    Size(375, 667),
    Size(390, 844),
    Size(412, 915),
    Size(430, 932),
  ];
  for (final size in sizes) {
    for (final scale in <double>[1.0, 1.3, 1.6]) {
      for (final dpr in <double>[2.0, 3.0]) {
        for (var count = 3; count <= 12; count++) {
          final label =
              '${size.width.toInt()}x${size.height.toInt()} '
              'scale=${scale.toStringAsFixed(1)} '
              'dpr=${dpr.toInt()} friends=$count';
          testWidgets('Thought avatars move continuously: $label', (
            tester,
          ) async {
            await _checkMotion(
              tester,
              size: size,
              textScale: scale,
              dpr: dpr,
              friendCount: count,
              label: label,
            );
          });
        }
      }
    }
  }

  const stressCases = <({Size size, double scale, int friendCount})>[
    (size: Size(320, 568), scale: 1.3, friendCount: 11),
    (size: Size(320, 568), scale: 1.6, friendCount: 11),
    (size: Size(430, 932), scale: 1.3, friendCount: 12),
  ];
  for (final scenario in stressCases) {
    for (final hz in <int>[60, 90, 120]) {
      final frameDuration = Duration(
        microseconds: (Duration.microsecondsPerSecond / hz).round(),
      );
      final settleFrames =
          (const Duration(seconds: 2).inMicroseconds /
                  frameDuration.inMicroseconds)
              .ceil();
      final observedFrames =
          (const Duration(seconds: 40).inMicroseconds /
                  frameDuration.inMicroseconds)
              .ceil();
      final label =
          '${scenario.size.width.toInt()}x${scenario.size.height.toInt()} '
          'scale=${scenario.scale.toStringAsFixed(1)} '
          'dpr=3 friends=${scenario.friendCount} ${hz}Hz for 40s';
      testWidgets(
        'Thought avatars remain continuous over clock cycles: $label',
        (tester) async {
          await _checkMotion(
            tester,
            size: scenario.size,
            textScale: scenario.scale,
            dpr: 3.0,
            friendCount: scenario.friendCount,
            label: label,
            frameDuration: frameDuration,
            settleFrames: settleFrames,
            observedFrames: observedFrames,
          );
        },
      );
    }
  }

  // Samsung-like logical presets are hypotheses for the reported phone, not
  // measured Samsung S26 viewport settings. Exercise each without claiming
  // that any one preset matches the affected device.
  const samsungLikeSizes = <Size>[
    Size(360, 780),
    Size(384, 832),
    Size(412, 892),
  ];
  const cadences = <({String label, List<Duration> frames})>[
    (label: '60Hz', frames: [_frame]),
    (label: '90Hz', frames: [Duration(microseconds: 11111)]),
    (label: '120Hz', frames: [Duration(microseconds: 8333)]),
    (
      label: 'alternating8.3ms+16.7ms',
      frames: [Duration(microseconds: 8300), Duration(microseconds: 16700)],
    ),
  ];
  for (final size in samsungLikeSizes) {
    for (final scale in <double>[1.0, 1.15, 1.3]) {
      for (var count = 6; count <= 12; count++) {
        for (final cadence in cadences) {
          final settleFrames = _framesForAtLeast(
            cadence.frames,
            const Duration(seconds: 2),
          );
          final observedFrames = _framesForAtLeast(
            cadence.frames,
            const Duration(seconds: 3),
            startingFrame: settleFrames,
          );
          final label =
              '${size.width.toInt()}x${size.height.toInt()} '
              'scale=$scale dpr=3 friends=$count cadence=${cadence.label}';
          testWidgets(
            'Samsung-like unverified viewport Thought stability: $label',
            (tester) async {
              await _checkMotion(
                tester,
                size: size,
                textScale: scale,
                dpr: 3.0,
                friendCount: count,
                label: 'Samsung-like unverified viewport $label',
                frameCadence: cadence.frames,
                settleFrames: settleFrames,
                observedFrames: observedFrames,
              );
            },
          );
        }
      }
    }
  }

  testWidgets('Reduce Motion keeps dense Thought avatars exactly stationary', (
    tester,
  ) async {
    await _checkMotion(
      tester,
      size: const Size(320, 568),
      textScale: 1.6,
      dpr: 3.0,
      friendCount: 12,
      label: '320x568 scale=1.6 dpr=3 friends=12 Reduce Motion',
      reduceMotion: true,
    );
  });
}

Future<void> _checkMotion(
  WidgetTester tester, {
  required Size size,
  required double textScale,
  required double dpr,
  required int friendCount,
  required String label,
  bool reduceMotion = false,
  Duration frameDuration = _frame,
  List<Duration>? frameCadence,
  int settleFrames = _settleFrames,
  int observedFrames = _observedFrames,
}) async {
  assert(frameCadence == null || frameCadence.isNotEmpty);
  Duration durationForFrame(int frame) => frameCadence == null
      ? frameDuration
      : frameCadence[frame % frameCadence.length];
  tester.view.physicalSize = size * dpr;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
  final now = DateTime.utc(2026, 10, 29, 12);
  final items = List<OrbitItem>.generate(
    friendCount,
    (index) => OrbitFriendItem(_friend(index)),
  );
  final thoughts = <String, OrbitThoughtNote>{
    for (var index = 0; index < friendCount; index++)
      'friend-$index': OrbitThoughtNote(
        postId: 'thought-$index',
        text: _thoughtTexts[index % _thoughtTexts.length],
        isRead: index.isEven,
        expiresAt: now.add(const Duration(hours: 1)),
      ),
  };

  try {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [BackgroundReadableColors.dark]),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: reduceMotion,
              accessibleNavigation: reduceMotion,
            ),
            child: Scaffold(
              body: InnerCircleInteractiveSurface(
                userPeerId: 'self',
                items: items,
                onFriendTap: (_) {},
                onGroupTap: (_) {},
                thoughtsByPeerId: thoughts,
                nowProvider: () => now,
              ),
            ),
          ),
        ),
      ),
    );

    // The last ring entrance finishes after 500 + 11 * 40 milliseconds.
    // Pump actual frames through the live Surface clock, rather than jumping
    // time once or waiting for repeating animation controllers to settle.
    for (var frame = 0; frame < settleFrames; frame++) {
      await tester.pump(durationForFrame(frame));
    }
    expect(find.byType(OrbitThoughtNoteBubble), findsNWidgets(friendCount));
    final visualization = tester.widget<OrbitalVisualization>(
      find.byType(OrbitalVisualization),
    );
    expect(visualization.thoughtSwim, isNotNull);
    expect(visualization.thoughtVisibility, 1.0);
    expect(
      MediaQuery.sizeOf(
        tester.element(find.byType(InnerCircleInteractiveSurface)),
      ),
      size,
    );
    expect(
      visualization.thoughtClock,
      reduceMotion ? 0.0 : greaterThan(1.5),
      reason: 'The motion-enabled fixture must exercise the production clock.',
    );

    final startingClock = visualization.thoughtClock;
    var previous = _sample(tester, friendCount);
    var maximumAbsoluteStep = 0.0;
    var maximumRelativeStep = 0.0;
    var observedMicroseconds = 0;
    // Keep the original 0.5-pixel budget at the default cadence; faster
    // refresh rates receive proportionately smaller steps for the same speed.
    for (var frame = 1; frame <= observedFrames; frame++) {
      final actualFrameDuration = durationForFrame(settleFrames + frame - 1);
      await tester.pump(actualFrameDuration);
      observedMicroseconds += actualFrameDuration.inMicroseconds;
      final limit = reduceMotion
          ? 0.0
          : _maximumFrameStep *
                actualFrameDuration.inMicroseconds /
                _frame.inMicroseconds;
      final current = _sample(tester, friendCount);
      for (var index = 0; index < friendCount; index++) {
        final absoluteStep =
            (current.nodes[index] - previous.nodes[index]).distance;
        final relativeStep =
            (current.relative(index) - previous.relative(index)).distance;
        if (absoluteStep > maximumAbsoluteStep) {
          maximumAbsoluteStep = absoluteStep;
        }
        if (relativeStep > maximumRelativeStep) {
          maximumRelativeStep = relativeStep;
        }
        if (!absoluteStep.isFinite ||
            !relativeStep.isFinite ||
            absoluteStep > limit ||
            relativeStep > limit) {
          final clock = tester
              .widget<OrbitalVisualization>(find.byType(OrbitalVisualization))
              .thoughtClock;
          fail(
            '$label: discontinuous avatar $index at observed frame $frame '
            '(clock=${clock.toStringAsFixed(6)}s, '
            'frame=${actualFrameDuration.inMicroseconds}us). '
            'absolute step=$absoluteStep, relative-to-self step=$relativeStep, '
            'maximum absolute=$maximumAbsoluteStep, '
            'maximum relative=$maximumRelativeStep, limit=$limit. '
            'Node ${previous.nodes[index]} -> ${current.nodes[index]}; '
            'relative ${previous.relative(index)} -> ${current.relative(index)}; '
            'self ${previous.self} -> ${current.self}.',
          );
        }
      }
      previous = current;
    }
    final endingClock = tester
        .widget<OrbitalVisualization>(find.byType(OrbitalVisualization))
        .thoughtClock;
    final minimumClockAdvance =
        frameCadence == null &&
            observedFrames == _observedFrames &&
            frameDuration == _frame
        ? 2.9
        : observedMicroseconds / Duration.microsecondsPerSecond - 0.1;
    expect(
      endingClock,
      reduceMotion
          ? startingClock
          : greaterThan(startingClock + minimumClockAdvance),
    );
  } finally {
    // An assertion may stop a case early. Dispose live clock/expiry timers
    // before draining any delayed entrance callbacks, even in failing cases.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }
}

int _framesForAtLeast(
  List<Duration> cadence,
  Duration duration, {
  int startingFrame = 0,
}) {
  assert(cadence.isNotEmpty);
  assert(cadence.every((frame) => frame > Duration.zero));
  var elapsedMicroseconds = 0;
  var frames = 0;
  while (elapsedMicroseconds < duration.inMicroseconds) {
    elapsedMicroseconds +=
        cadence[(startingFrame + frames) % cadence.length].inMicroseconds;
    frames++;
  }
  return frames;
}

_AvatarFrame _sample(WidgetTester tester, int friendCount) => _AvatarFrame(
  self: tester.getCenter(find.byKey(const ValueKey('orbit-self-node'))),
  nodes: [
    for (var index = 0; index < friendCount; index++)
      tester.getCenter(find.byKey(ValueKey('orbit-node-$index'))),
  ],
);

class _AvatarFrame {
  final Offset self;
  final List<Offset> nodes;

  const _AvatarFrame({required this.self, required this.nodes});

  Offset relative(int index) => nodes[index] - self;
}

OrbitFriend _friend(int index) => OrbitFriend(
  contact: ContactModel(
    peerId: 'friend-$index',
    username: 'Friend $index',
    publicKey: 'pk-$index',
    rendezvous: '',
    signature: '',
    scannedAt: '2026-10-29T00:00:00Z',
  ),
  messageCount: 0,
  unreadCount: 0,
);

const _thoughtTexts = <String>[
  'Planning a quiet walk after work today.',
  'Coffee with old friends sounds good.',
  'One small thing made this a lovely day.',
  'Keeping a little time to catch up soon.',
];
