import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/utils/ring_avatar_generator.dart';
import 'package:flutter_app/features/home/presentation/widgets/ring_avatar_painter.dart';

void main() {
  // TC-13 (156 QW-7, PROD-CRITICAL): RingAvatarPainter.shouldRepaint compares
  // `oldDelegate.data != data`. With value-equality on RingAvatarData (and/or
  // the generate() memo returning the cached instance), two generate() results
  // for the same peerId+size must NOT trigger a repaint. This is the
  // end-behavior lock — it survives whichever mechanism (== or memo) the impl
  // keeps.
  test(
    'shouldRepaint is FALSE for two generate() results of the same peerId+size',
    () {
      final a = RingAvatarGenerator.generate('peerRepaint', 80.0);
      final b = RingAvatarGenerator.generate('peerRepaint', 80.0);

      final p1 = RingAvatarPainter(data: a);
      final p2 = RingAvatarPainter(data: b);

      expect(p2.shouldRepaint(p1), isFalse);
    },
  );

  test('shouldRepaint is TRUE for different peerId data (control)', () {
    final a = RingAvatarGenerator.generate('peerRepaintA', 80.0);
    final b = RingAvatarGenerator.generate('peerRepaintB', 80.0);

    final p1 = RingAvatarPainter(data: a);
    final p2 = RingAvatarPainter(data: b);

    expect(p2.shouldRepaint(p1), isTrue);
  });
}
