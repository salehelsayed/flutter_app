import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/theme/feed_colors.dart';

void main() {
  group('FeedColors', () {
    test('accentPurple is #a78bfa', () {
      expect(FeedColors.accentPurple, const Color(0xFFa78bfa));
    });

    test('accentTeal is #81e6d9', () {
      expect(FeedColors.accentTeal, const Color(0xFF81e6d9));
    });

    test('cardBg is rgba(255,255,255,0.03)', () {
      expect(FeedColors.cardBg, const Color.fromRGBO(255, 255, 255, 0.03));
    });

    test('cardBorder is rgba(255,255,255,0.08)', () {
      expect(FeedColors.cardBorder, const Color.fromRGBO(255, 255, 255, 0.08));
    });

    test('messageReceivedBg matches spec', () {
      expect(
        FeedColors.messageReceivedBg,
        const Color.fromRGBO(255, 255, 255, 0.06),
      );
    });

    test('messageSentBg matches spec', () {
      expect(
        FeedColors.messageSentBg,
        const Color.fromRGBO(255, 255, 255, 0.04),
      );
    });

    test('messageUnreadBg matches spec', () {
      expect(
        FeedColors.messageUnreadBg,
        const Color.fromRGBO(255, 255, 255, 0.06),
      );
    });

    test('moreMessagesHint color is rgba(167,139,250,0.7)', () {
      expect(
        FeedColors.moreMessagesHint,
        const Color.fromRGBO(167, 139, 250, 0.7),
      );
    });

    test('viewEarlierText is rgba(255,255,255,0.35)', () {
      expect(
        FeedColors.viewEarlierText,
        const Color.fromRGBO(255, 255, 255, 0.35),
      );
    });

    test('backgroundTop is #0f0f18', () {
      expect(FeedColors.backgroundTop, const Color(0xFF0f0f18));
    });

    test('backgroundBottom is #0a0a0f', () {
      expect(FeedColors.backgroundBottom, const Color(0xFF0a0a0f));
    });

    test('textMuted is rgba(255,255,255,0.50)', () {
      expect(
        FeedColors.textMuted,
        const Color.fromRGBO(255, 255, 255, 0.50),
      );
    });

    test('chevronColor is rgba(167,139,250,0.5)', () {
      expect(
        FeedColors.chevronColor,
        const Color.fromRGBO(167, 139, 250, 0.5),
      );
    });
  });
}
