import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_item.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_thought_note.dart';
import 'package:flutter_app/features/orbit/domain/orbit_arc_layout.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/inner_circle_interactive_surface.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_thought_note_bubble.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbital_visualization.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _frame = Duration(microseconds: 16667);
const _settleFrames = 120;
const _observedFrames = 180;

const _seatTolerance = 0.01;
const _deadline = Duration(seconds: 3);

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
          testWidgets('Thought avatars stay on their exact seats: $label', (
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
      testWidgets('Thought avatars stay fixed across forty seconds: $label', (
        tester,
      ) async {
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
      });
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

    // Drain the real entrance animations before sampling the static seats.
    for (var frame = 0; frame < settleFrames; frame++) {
      await tester.pump(durationForFrame(frame)).timeout(_deadline);
    }
    final notes = find.byType(OrbitThoughtNoteBubble).evaluate().length;
    final badges = find
        .byWidgetPredicate((widget) {
          final key = widget.key;
          return key is ValueKey<String> &&
              key.value.startsWith('orbit-thought-badge-');
        })
        .evaluate()
        .length;
    expect(notes, lessThanOrEqualTo(4));
    expect(notes + badges, friendCount);
    final visualization = tester.widget<OrbitalVisualization>(
      find.byType(OrbitalVisualization),
    );
    expect(visualization.thoughtVisibility, 1.0);
    expect(
      MediaQuery.sizeOf(
        tester.element(find.byType(InnerCircleInteractiveSurface)),
      ),
      size,
    );
    final layout = computeOrbitLayout(
      memberCount: friendCount,
      geometry: visualization.geometry,
    );
    final starting = _sample(tester, friendCount);
    for (final seat in layout.seats) {
      expect(
        (starting.relative(seat.index) - Offset(seat.dx, seat.dy)).distance,
        lessThan(_seatTolerance),
        reason: '$label: first sample, seat ${seat.index}',
      );
    }
    for (var frame = 0; frame < observedFrames; frame++) {
      await tester
          .pump(durationForFrame(settleFrames + frame))
          .timeout(_deadline);
      final current = _sample(tester, friendCount);
      for (var index = 0; index < friendCount; index++) {
        final absoluteStep =
            (current.nodes[index] - starting.nodes[index]).distance;
        final relativeStep =
            (current.relative(index) - starting.relative(index)).distance;
        if (!(absoluteStep < _seatTolerance && relativeStep < _seatTolerance)) {
          fail(
            '$label: avatar $index moved by $absoluteStep on frame $frame '
            '($relativeStep relative to the centre).',
          );
        }
      }
    }
  } finally {
    await tester.pumpWidget(const SizedBox.shrink()).timeout(_deadline);
    await tester.pump(const Duration(seconds: 2)).timeout(_deadline);
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
