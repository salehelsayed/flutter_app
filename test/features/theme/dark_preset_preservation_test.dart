import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/core/theme/feed_tokens.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/compose_area.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/empty_conversation_state.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/voice_record_button.dart';
import 'package:flutter_app/features/feed/domain/models/feed_letter.dart';
import 'package:flutter_app/features/feed/presentation/widgets/letter_card_system.dart';
import 'package:flutter_app/features/feed/presentation/widgets/nav_bar_button.dart';
import 'package:flutter_app/features/feed/presentation/widgets/nav_bar_theme.dart';
import 'package:flutter_app/features/groups/presentation/widgets/expandable_fab.dart';
import 'package:flutter_app/features/groups/presentation/widgets/glow_fab.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_item.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbital_ring_painter.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbital_visualization.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

OrbitFriend _friend(int index) {
  return OrbitFriend(
    contact: ContactModel(
      peerId: 'peer-$index',
      publicKey: 'pk-$index',
      rendezvous: '/ip4/127.0.0.1/tcp/40$index',
      username: 'Friend $index',
      signature: 'sig-$index',
      scannedAt: '2026-07-07T00:00:00Z',
    ),
    messageCount: index,
    unreadCount: index == 0 ? 2 : 0,
  );
}

void _suppressAssetErrors(WidgetTester tester) {
  final oldHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    final message = details.exceptionAsString();
    if (message.contains('Unable to load asset') ||
        message.contains('SvgPicture')) {
      return;
    }
    oldHandler?.call(details);
  };
  addTearDown(() => FlutterError.onError = oldHandler);
}

void main() {
  test('dark tone tokens preserve every touched transcribed literal', () {
    const colors = BackgroundReadableColors.dark;

    expect(colors.accent, const Color(0xFF1DB954));
    expect(colors.accentIcon, const Color(0xFFFFFFFF));
    expect(colors.ring1, const Color(0x4081E6D9));
    expect(colors.ring2, const Color(0x33A78BFA));
    expect(colors.ringGlow, const Color(0x1481E6D9));
    expect(colors.ctaBg, const Color(0xFF1A1A2E));
    expect(colors.ctaIcon, const Color(0xFF64B5F6));
    expect(colors.ctaMenuFill, const Color(0x1AFFFFFF));
    expect(colors.ctaMenuBorder, const Color(0x26FFFFFF));
    expect(colors.ctaMenuText, const Color(0xFFFFFFFF));
    expect(colors.navActive, const Color(0xFFFFFFFF));
    expect(colors.navInactive, const Color(0x8CFFFFFF));
    expect(colors.navActiveFill, const Color(0x40FFFFFF));
    expect(colors.nodeSelfGlow, Colors.transparent);
    expect(colors.nodeContactGlow, Colors.transparent);
    expect(colors.composerBarColor, const Color.fromRGBO(10, 10, 15, 0.95));
    expect(colors.composerInputFill, const Color(0x0FFFFFFF));
    expect(colors.composerHint, const Color(0x4DFFFFFF));
    expect(colors.sendBg, const Color(0x261DB954));
    expect(colors.sendIcon, const Color(0xFF1DB954));
    expect(colors.connectedHeading, const Color(0xFF1DB954));
    expect(colors.emptyHint, const Color(0x80FFFFFF));
    expect(colors.emptyDate, const Color(0x59FFFFFF));
    expect(colors.emptyDivider, const Color(0x1FFFFFFF));
    expect(colors.emptyAvatarGlow, const Color(0x4D4ECDC4));
    expect(colors.micBg, const Color(0x261DB954));
    expect(colors.micBorder, const Color(0x4D1DB954));
    expect(colors.micShadow, const Color(0x3D1DB954));
    expect(colors.micIcon, const Color(0xFF1DB954));
    expect(colors.avatarFrameBorder, const Color(0x59FFFFFF));
    expect(colors.avatarFrameFill, const Color(0xB316181E));

    expect(FeedTokens.dark.teal400, const Color(0xFF2DD4BF));
    expect(FeedTokens.dark.tealFill08, const Color(0x142DD4BF));
    expect(FeedTokens.dark.green500, const Color(0xFF22C55E));
    expect(FeedTokens.dark.greenFill15, const Color(0x2622C55E));
    expect(FeedTokens.dark.surfaceSubtle, const Color(0xBF101218));
    expect(FeedTokens.dark.surfaceRaised, const Color(0xDB181A20));
    expect(FeedTokens.dark.borderSoft, const Color(0x1FFFFFFF));
    expect(FeedTokens.dark.canvas, const Color(0xE60A0A0F));
  });

  testWidgets('all three dark presets resolve to dark readable/feed tokens', (
    tester,
  ) async {
    for (final preference in [
      BackgroundPreference.defaultBackground,
      BackgroundPreference.cosmic,
      BackgroundPreference.cosmicMirrored,
    ]) {
      late BackgroundReadableColors readableColors;
      late FeedTokens feedTokens;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            extensions: const [BackgroundReadableColors.dark, FeedTokens.dark],
          ),
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: AmbientBackground(
              preference: preference,
              child: Builder(
                builder: (context) {
                  readableColors = context.backgroundReadableColors;
                  feedTokens = context.feedTokens;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(readableColors.isLightSurface, isFalse);
      expect(readableColors.ring1, const Color(0x4081E6D9));
      expect(feedTokens.greenFill15, const Color(0x2622C55E));
    }
  });

  testWidgets('dark touched widgets render the transcribed literals', (
    tester,
  ) async {
    _suppressAssetErrors(tester);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(
          extensions: const [BackgroundReadableColors.dark, FeedTokens.dark],
        ),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  SizedBox(
                    width: 200,
                    height: 120,
                    child: Stack(
                      children: [
                        ExpandableFab(
                          items: [
                            ExpandableFabItem(
                              label: 'New Group',
                              icon: Icons.group_outlined,
                              onTap: () {},
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(
                    width: 360,
                    height: 360,
                    child: OrbitalVisualization(userPeerId: 'self', items: []),
                  ),
                  SizedBox(
                    width: 360,
                    height: 360,
                    child: OrbitalVisualization(
                      userPeerId: 'self',
                      items: [OrbitFriendItem(_friend(0))],
                    ),
                  ),
                  ComposeArea(initialText: 'hi', onSend: (_) {}),
                  const SizedBox(
                    height: 320,
                    child: EmptyConversationState(
                      contactPeerId: 'peer-empty',
                      connectionDate: 'July 7, 2026',
                    ),
                  ),
                  VoiceRecordButton(
                    onTapDown: () {},
                    onTapUp: () {},
                    onTapCancel: () {},
                  ),
                  const UserAvatar(size: 40),
                  NavBarButton(
                    label: 'Feed',
                    svgAsset: 'assets/icons/nav_feed.svg',
                    isActive: true,
                    onTap: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final orbitPainter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<OrbitalRingPainter>()
        .first;
    expect(orbitPainter.ring1Color, const Color(0x4081E6D9));
    expect(orbitPainter.ring2Color, const Color(0x33A78BFA));
    expect(orbitPainter.glowColor, const Color(0x1481E6D9));
    expect(find.byKey(const ValueKey('orbit-node-halo-self')), findsNothing);
    expect(find.byKey(const ValueKey('orbit-node-halo-0')), findsNothing);

    final composerDecoration = tester
        .widgetList<Container>(find.byType(Container))
        .map((container) => container.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((box) => box.gradient is LinearGradient);
    final composerGradient = composerDecoration.gradient! as LinearGradient;
    expect(composerGradient.colors, const [
      Colors.transparent,
      Color.fromRGBO(10, 10, 15, 0.95),
    ]);
    expect(composerGradient.stops, [0.0, 0.2]);

    final date = tester.widget<Text>(find.text('July 7, 2026'));
    expect(date.style!.color, const Color(0x59FFFFFF));
    expect(
      tester
          .widgetList<Container>(find.byType(Container))
          .any((container) => container.color == const Color(0x1FFFFFFF)),
      isTrue,
    );

    final micDecoration =
        tester
                .widget<AnimatedContainer>(
                  find.descendant(
                    of: find.byType(VoiceRecordButton),
                    matching: find.byType(AnimatedContainer),
                  ),
                )
                .decoration
            as BoxDecoration;
    expect(micDecoration.color, const Color(0x261DB954));
    expect((micDecoration.border as Border).top.color, const Color(0x4D1DB954));
    expect(
      tester.widget<Icon>(find.byIcon(Icons.mic_rounded)).color,
      const Color(0xFF1DB954),
    );

    final avatarDecoration = tester
        .widgetList<Container>(find.byType(Container))
        .map((container) => container.decoration)
        .whereType<BoxDecoration>()
        .firstWhere(
          (decoration) => decoration.color == const Color(0xB316181E),
        );
    expect(
      (avatarDecoration.border as Border).top.color,
      const Color(0x59FFFFFF),
    );

    final navText = tester.widget<Text>(find.text('Feed'));
    expect(navText.style!.color, NavBarTheme.activeTextColor);
    final navDecoration =
        tester
                .widget<AnimatedContainer>(
                  find.descendant(
                    of: find.byType(NavBarButton),
                    matching: find.byType(AnimatedContainer),
                  ),
                )
                .decoration
            as BoxDecoration;
    expect(
      (navDecoration.gradient as LinearGradient).colors,
      NavBarTheme.activePillGradient,
    );

    final glowFab = tester.widget<GlowFab>(find.byType(GlowFab));
    expect(glowFab.backgroundColor, const Color(0xFF1A1A2E));
    expect(glowFab.ringColor, const Color(0xFF64B5F6));

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump(const Duration(milliseconds: 250));
    final menuText = tester.widget<Text>(find.text('New Group'));
    expect(menuText.style!.color, const Color(0xFFFFFFFF));
    final menuDecoration = tester
        .widgetList<Container>(find.byType(Container))
        .map((container) => container.decoration)
        .whereType<BoxDecoration>()
        .firstWhere(
          (decoration) => decoration.color == const Color(0x1AFFFFFF),
        );
    expect(
      (menuDecoration.border as Border).top.color,
      const Color(0x26FFFFFF),
    );
  });

  testWidgets('dark Feed system card renders dark token literals', (
    tester,
  ) async {
    const connection = SystemLetter(
      contactPeerId: 'peer-dark',
      displayName: 'Dark Friend',
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(
          extensions: const [BackgroundReadableColors.dark, FeedTokens.dark],
        ),
        home: const Scaffold(
          backgroundColor: Color(0xFF0A0A0F),
          body: Padding(
            padding: EdgeInsets.all(24),
            child: LetterCardSystem(letter: connection),
          ),
        ),
      ),
    );
    await tester.pump();

    final label = tester.widget<Text>(find.text('Connected'));
    expect(label.style!.color, const Color(0xB8C9CED6));

    final bubbleText = tester.widget<Text>(find.text('tap to say hi'));
    final bubbleDecoration =
        tester
                .widget<Container>(
                  find
                      .ancestor(
                        of: find.text('tap to say hi'),
                        matching: find.byWidgetPredicate(
                          (widget) =>
                              widget is Container &&
                              widget.decoration is BoxDecoration &&
                              (widget.decoration as BoxDecoration).color ==
                                  const Color(0x2622C55E),
                        ),
                      )
                      .first,
                )
                .decoration
            as BoxDecoration;

    expect(bubbleDecoration.color, const Color(0x2622C55E));
    expect(bubbleText.style!.color, const Color(0xFFF8FAFC));
  });

  testWidgets('live switch from dark to Signal repaints the ground', (
    tester,
  ) async {
    var preference = BackgroundPreference.defaultBackground;

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          return MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: AmbientBackground(
                preference: preference,
                child: Center(
                  child: TextButton(
                    onPressed: () => setState(
                      () => preference = BackgroundPreference.daylightLagoon,
                    ),
                    child: const Text('switch'),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );

    expect(
      find.byKey(const ValueKey('daylight-lagoon-background-root')),
      findsNothing,
    );

    await tester.tap(find.text('switch'));
    await tester.pump();

    final root = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('daylight-lagoon-background-root')),
    );
    expect((root.decoration as BoxDecoration).color, const Color(0xFFFFFFFF));
  });
}
