import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/theme/app_colors.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';
import 'package:flutter_app/features/identity/presentation/widgets/cosmic_background.dart';
import 'package:flutter_app/features/identity/presentation/widgets/cosmic_background_mirrored.dart';
import 'package:flutter_app/features/identity/presentation/widgets/daylight_lagoon_background.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrapAmbient({
    BackgroundPreference preference = BackgroundPreference.defaultBackground,
    bool isFeedSurface = false,
    bool chatSurface = false,
    bool disableAnimations = false,
  }) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(390, 844),
          disableAnimations: disableAnimations,
        ),
        child: AmbientBackground(
          preference: preference,
          isFeedSurface: isFeedSurface,
          isChatSurface: chatSurface,
          child: const Text('Content'),
        ),
      ),
    );
  }

  testWidgets('renders child over the default Mirror Cosmic treatment', (
    tester,
  ) async {
    await tester.pumpWidget(wrapAmbient());

    expect(find.text('Content'), findsOneWidget);
    expect(find.byType(CosmicBackground), findsNothing);
    expect(find.byType(CosmicBackgroundMirrored), findsOneWidget);
    expect(
      find.byKey(const ValueKey('cosmic-background-mirrored-root')),
      findsOneWidget,
    );
  });

  testWidgets('aurora preference renders the ambient glow', (tester) async {
    await tester.pumpWidget(
      wrapAmbient(preference: BackgroundPreference.aurora),
    );

    expect(find.text('Content'), findsOneWidget);
    expect(find.byType(CosmicBackground), findsNothing);
    expect(find.byType(CosmicBackgroundMirrored), findsNothing);
    expect(find.byType(AnimatedBuilder), findsAtLeastNWidgets(2));

    final backgroundContainers = tester
        .widgetList<Container>(find.byType(Container))
        .where((container) => container.color == AppColors.background)
        .toList();
    expect(backgroundContainers, isNotEmpty);

    final gradients = tester
        .widgetList<Container>(find.byType(Container))
        .map((container) => container.decoration)
        .whereType<BoxDecoration>()
        .map((decoration) => decoration.gradient)
        .whereType<RadialGradient>()
        .toList();
    expect(
      gradients.any(
        (gradient) => gradient.colors.contains(
          AppColors.greenGlow.withValues(alpha: 0.3),
        ),
      ),
      isTrue,
    );
    expect(
      gradients.any(
        (gradient) =>
            gradient.colors.contains(AppColors.redGlow.withValues(alpha: 0.25)),
      ),
      isTrue,
    );
  });

  testWidgets('default preference renders Mirror Cosmic', (tester) async {
    await tester.pumpWidget(wrapAmbient());

    expect(find.text('Content'), findsOneWidget);
    expect(find.byType(CosmicBackground), findsNothing);
    expect(find.byType(CosmicBackgroundMirrored), findsOneWidget);
    expect(find.byKey(const ValueKey('cosmic-background-root')), findsNothing);
    expect(
      find.byKey(const ValueKey('cosmic-background-mirrored-root')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('cosmic-background-mirrored-painter')),
      findsOneWidget,
    );

    final mirroredRoot = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('cosmic-background-mirrored-root')),
    );
    final decoration = mirroredRoot.decoration as BoxDecoration;
    final gradient = decoration.gradient as RadialGradient;
    expect(gradient.colors, contains(const Color(0xFF0A1124)));
    expect(gradient.colors, contains(const Color(0xFF02030A)));
  });

  // ---------------------------------------------------------------------------
  // 156 QW-2/QW-3: RepaintBoundary isolation + reduce-motion on the Aurora
  // (non-feed) glow surface.
  // ---------------------------------------------------------------------------
  testWidgets(
    'TC-03: aurora glow wraps the screen child in a RepaintBoundary',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(390, 844)),
            child: AmbientBackground(
              preference: BackgroundPreference.aurora,
              child: const KeyedSubtree(
                key: ValueKey('ambient-child'),
                child: Text('Content'),
              ),
            ),
          ),
        ),
      );

      expect(
        find.ancestor(
          of: find.byKey(const ValueKey('ambient-child')),
          matching: find.descendant(
            of: find.byType(AmbientBackground),
            matching: find.byType(RepaintBoundary),
          ),
        ),
        findsAtLeastNWidgets(1),
      );
    },
  );

  // The glow AnimatedBuilders drive off the ambient AnimationController; other
  // AnimatedBuilders in the tree (MaterialApp internals) use ValueNotifiers, so
  // filter the listenables to AnimationController to find the ambient loop.
  List<AnimationController> ambientControllers(WidgetTester tester) {
    return tester
        .widgetList<AnimatedBuilder>(find.byType(AnimatedBuilder))
        .map((ab) => ab.listenable)
        .whereType<AnimationController>()
        .toList();
  }

  testWidgets('TC-04: aurora glow honors disableAnimations', (tester) async {
    await tester.pumpWidget(
      wrapAmbient(
        preference: BackgroundPreference.aurora,
        disableAnimations: true,
      ),
    );
    await tester.pump();

    final controllers = ambientControllers(tester);
    expect(controllers, isNotEmpty);
    expect(controllers.first.isAnimating, isFalse);
  });

  testWidgets('TC-05: aurora glow DOES animate when motion enabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapAmbient(
        preference: BackgroundPreference.aurora,
        disableAnimations: false,
      ),
    );
    await tester.pump();

    final controllers = ambientControllers(tester);
    expect(controllers, isNotEmpty);
    expect(controllers.first.isAnimating, isTrue);
  });

  testWidgets(
    'aurora glow animates, is chat-suppressed, and honors OS reduce-motion',
    (tester) async {
      await tester.pumpWidget(
        wrapAmbient(
          preference: BackgroundPreference.aurora,
          disableAnimations: false,
        ),
      );
      await tester.pump();

      var controllers = ambientControllers(tester);
      expect(controllers, isNotEmpty);
      expect(controllers.first.isAnimating, isTrue);

      await tester.pumpWidget(
        wrapAmbient(
          preference: BackgroundPreference.aurora,
          chatSurface: true,
          disableAnimations: false,
        ),
      );
      await tester.pump();

      controllers = ambientControllers(tester);
      expect(controllers, isNotEmpty);
      expect(controllers.first.isAnimating, isFalse);

      await tester.pumpWidget(
        wrapAmbient(
          preference: BackgroundPreference.aurora,
          disableAnimations: true,
        ),
      );
      await tester.pump();

      controllers = ambientControllers(tester);
      expect(controllers, isNotEmpty);
      expect(controllers.first.isAnimating, isFalse);
    },
  );

  // ---------------------------------------------------------------------------
  // 158 (critic-2): steady-state idle-glow suppression on chat/group surfaces
  // for Aurora (motion-on) users, so the always-mounted chrome BackdropFilters
  // sit in front of a STILL backdrop and become cacheable at rest. Distinct from
  // the 156 OS reduce-motion gate (additive, not a replacement).
  // ---------------------------------------------------------------------------

  test('TC-158-00: only the two chat screens opt into isChatSurface', () {
    int countOptIn(String path) {
      final source = File(path).readAsStringSync();
      return 'isChatSurface: true'.allMatches(source).length;
    }

    // The two chat surfaces must each opt in exactly once.
    const chatSurfaceFiles = <String>[
      'lib/features/conversation/presentation/screens/conversation_screen.dart',
      'lib/features/groups/presentation/screens/group_conversation_screen.dart',
    ];
    for (final path in chatSurfaceFiles) {
      expect(
        countOptIn(path),
        1,
        reason:
            '$path must opt into chat-surface ambient suppression exactly once',
      );
    }

    // None of the other 14 AmbientBackground call sites may opt in (no leakage —
    // their living glow must keep animating with motion enabled).
    const nonChatAmbientSurfaceFiles = <String>[
      'lib/features/account_migration/presentation/screens/account_migration_journey_screen.dart',
      'lib/features/feed/presentation/screens/feed_screen.dart',
      'lib/features/groups/presentation/screens/contact_picker_screen.dart',
      'lib/features/groups/presentation/screens/create_group_picker_screen.dart',
      'lib/features/groups/presentation/screens/group_info_screen.dart',
      'lib/features/groups/presentation/screens/group_list_screen.dart',
      'lib/features/home/presentation/screens/first_time_experience_screen.dart',
      'lib/features/identity/presentation/screens/identity_choice_screen.dart',
      'lib/features/introduction/presentation/screens/sent_confirmation_screen.dart',
      'lib/features/orbit/presentation/screens/orbit_screen.dart',
      'lib/features/posts/presentation/screens/posts_screen.dart',
      'lib/features/qr_code/presentation/screens/qr_display_screen.dart',
      'lib/features/settings/presentation/screens/settings_screen.dart',
      'lib/features/share/presentation/screens/share_target_picker_screen.dart',
    ];
    for (final path in nonChatAmbientSurfaceFiles) {
      expect(
        countOptIn(path),
        0,
        reason:
            '$path must NOT opt into chat-surface ambient suppression (leakage)',
      );
    }
  });

  testWidgets(
    'TC-158-01: chat surface does not animate the glow with motion enabled',
    (tester) async {
      await tester.pumpWidget(
        wrapAmbient(
          preference: BackgroundPreference.aurora,
          chatSurface: true,
          disableAnimations: false,
        ),
      );
      await tester.pump();

      final controllers = ambientControllers(tester);
      expect(controllers, isNotEmpty);
      expect(controllers.first.isAnimating, isFalse);

      // A no-op rebuild keeps it static (didUpdateWidget/didChangeDependencies
      // recompute the suppression from the prop — no latched/persisted state).
      await tester.pumpWidget(
        wrapAmbient(
          preference: BackgroundPreference.aurora,
          chatSurface: true,
          disableAnimations: false,
        ),
      );
      await tester.pump();
      expect(ambientControllers(tester).first.isAnimating, isFalse);
    },
  );

  testWidgets(
    'TC-158-02: non-chat surface still animates with motion enabled',
    (tester) async {
      await tester.pumpWidget(
        wrapAmbient(
          preference: BackgroundPreference.aurora,
          chatSurface: false,
          disableAnimations: false,
        ),
      );
      await tester.pump();

      final controllers = ambientControllers(tester);
      expect(controllers, isNotEmpty);
      expect(controllers.first.isAnimating, isTrue);
    },
  );

  testWidgets(
    'TC-158-03: 156 reduce-motion gate still wins on a chat surface',
    (tester) async {
      await tester.pumpWidget(
        wrapAmbient(
          preference: BackgroundPreference.aurora,
          chatSurface: true,
          disableAnimations: true,
        ),
      );
      await tester.pump();

      final controllers = ambientControllers(tester);
      expect(controllers, isNotEmpty);
      expect(controllers.first.isAnimating, isFalse);
    },
  );

  testWidgets('exposes dark readable colors for default descendants', (
    tester,
  ) async {
    BackgroundReadableColors? observedColors;
    await tester.pumpWidget(
      MaterialApp(
        home: AmbientBackground(
          child: Builder(
            builder: (context) {
              observedColors = context.backgroundReadableColors;
              return const Text('Content');
            },
          ),
        ),
      ),
    );

    expect(observedColors, BackgroundReadableColors.dark);
    final annotatedRegion = tester
        .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
          find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
        );
    expect(annotatedRegion.value.statusBarIconBrightness, Brightness.light);
  });

  testWidgets('exposes dark readable colors for cosmic descendants', (
    tester,
  ) async {
    BackgroundReadableColors? observedColors;
    await tester.pumpWidget(
      MaterialApp(
        home: AmbientBackground(
          preference: BackgroundPreference.cosmic,
          child: Builder(
            builder: (context) {
              observedColors = context.backgroundReadableColors;
              return const Text('Content');
            },
          ),
        ),
      ),
    );

    expect(observedColors, BackgroundReadableColors.dark);
    expect(find.byType(CosmicBackground), findsOneWidget);
  });

  testWidgets('renders cosmic for any surface with cosmic preference', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapAmbient(preference: BackgroundPreference.cosmic),
    );

    expect(find.text('Content'), findsOneWidget);
    expect(find.byType(CosmicBackground), findsOneWidget);
    expect(
      find.byKey(const ValueKey('cosmic-background-root')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('cosmic-background-painter')),
      findsOneWidget,
    );

    final cosmicRoot = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('cosmic-background-root')),
    );
    final decoration = cosmicRoot.decoration as BoxDecoration;
    final gradient = decoration.gradient as RadialGradient;
    expect(gradient.colors, contains(const Color(0xFF0A1124)));
    expect(gradient.colors, contains(const Color(0xFF02030A)));
  });

  testWidgets('still renders cosmic when the legacy Feed flag is false', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapAmbient(preference: BackgroundPreference.cosmic),
    );

    expect(find.text('Content'), findsOneWidget);
    expect(find.byType(CosmicBackground), findsOneWidget);
    expect(
      find.byKey(const ValueKey('cosmic-background-root')),
      findsOneWidget,
    );
  });

  testWidgets('renders Mirror Cosmic as the default shared background', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapAmbient(preference: BackgroundPreference.defaultBackground),
    );

    expect(find.text('Content'), findsOneWidget);
    expect(find.byType(CosmicBackground), findsNothing);
    expect(find.byType(CosmicBackgroundMirrored), findsOneWidget);
    expect(find.byKey(const ValueKey('cosmic-background-root')), findsNothing);
    expect(
      find.byKey(const ValueKey('cosmic-background-mirrored-root')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('cosmic-background-mirrored-painter')),
      findsOneWidget,
    );

    final mirroredRoot = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('cosmic-background-mirrored-root')),
    );
    final decoration = mirroredRoot.decoration as BoxDecoration;
    final gradient = decoration.gradient as RadialGradient;
    expect(gradient.colors, contains(const Color(0xFF0A1124)));
    expect(gradient.colors, contains(const Color(0xFF02030A)));
  });

  testWidgets('renders daylight lagoon as a distinct shared background', (
    tester,
  ) async {
    BackgroundReadableColors? observedColors;
    await tester.pumpWidget(
      MaterialApp(
        home: AmbientBackground(
          preference: BackgroundPreference.daylightLagoon,
          child: Builder(
            builder: (context) {
              observedColors = context.backgroundReadableColors;
              return const Text('Content');
            },
          ),
        ),
      ),
    );

    expect(find.text('Content'), findsOneWidget);
    expect(find.byType(CosmicBackground), findsNothing);
    expect(find.byType(CosmicBackgroundMirrored), findsNothing);
    expect(find.byType(DaylightLagoonBackground), findsOneWidget);
    expect(
      find.byKey(const ValueKey('daylight-lagoon-background-root')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('daylight-lagoon-background-painter')),
      findsOneWidget,
    );
    expect(observedColors, BackgroundReadableColors.representativeLight);

    final annotatedRegion = tester
        .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
          find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
        );
    expect(annotatedRegion.value.statusBarIconBrightness, Brightness.dark);

    final root = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('daylight-lagoon-background-root')),
    );
    final decoration = root.decoration as BoxDecoration;
    expect(decoration.color, const Color(0xFFECE8E1));
  });

  testWidgets('Feed surface with aurora preference animates the glow', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapAmbient(preference: BackgroundPreference.aurora, isFeedSurface: true),
    );

    expect(find.byType(CosmicBackground), findsNothing);
    expect(find.byType(AnimatedBuilder), findsAtLeastNWidgets(2));
  });

  testWidgets('cosmic honors disabled animations with static paint', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapAmbient(
        preference: BackgroundPreference.cosmic,
        isFeedSurface: true,
        disableAnimations: true,
      ),
    );

    expect(find.byType(CosmicBackground), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(CosmicBackground),
        matching: find.byType(AnimatedBuilder),
      ),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('cosmic-background-painter')),
      findsOneWidget,
    );
  });

  testWidgets(
    'default Mirror Cosmic honors disabled animations with static paint',
    (tester) async {
      await tester.pumpWidget(
        wrapAmbient(
          preference: BackgroundPreference.defaultBackground,
          disableAnimations: true,
        ),
      );

      expect(find.byType(CosmicBackgroundMirrored), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(CosmicBackgroundMirrored),
          matching: find.byType(AnimatedBuilder),
        ),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('cosmic-background-mirrored-painter')),
        findsOneWidget,
      );
    },
  );

  testWidgets('daylight lagoon honors disabled animations with static paint', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapAmbient(
        preference: BackgroundPreference.daylightLagoon,
        disableAnimations: true,
      ),
    );

    expect(find.byType(DaylightLagoonBackground), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(DaylightLagoonBackground),
        matching: find.byType(AnimatedBuilder),
      ),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('daylight-lagoon-background-painter')),
      findsOneWidget,
    );
  });

  test('production code does not import the Test-Flight cosmic artifact', () {
    final dartFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in dartFiles) {
      final content = file.readAsStringSync();
      expect(content, isNot(contains('Test-Flight-Improv')), reason: file.path);
      expect(
        content,
        isNot(contains('Background-Feature/cosmic_background.dart')),
        reason: file.path,
      );
      expect(
        content,
        isNot(contains('Background-Feature/cosmic_background_mirrored.dart')),
        reason: file.path,
      );
      expect(
        content,
        isNot(contains('Background-Feature/daylight_lagoon_background.dart')),
        reason: file.path,
      );
    }
  });

  test('no background token string is branched on outside the codec', () {
    final forbiddenTokenLiterals = <String>[
      "'aurora'",
      '"aurora"',
      "'cosmic_mirrored'",
      '"cosmic_mirrored"',
    ];
    final dartFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where(
          (file) =>
              file.path !=
              'lib/features/settings/domain/models/background_preference.dart',
        );

    for (final file in dartFiles) {
      final content = file.readAsStringSync();
      for (final token in forbiddenTokenLiterals) {
        expect(content, isNot(contains(token)), reason: file.path);
      }
    }
  });

  test('current shared-background screen surfaces use AmbientBackground', () {
    const expectedSurfaceFiles = <String>[
      'lib/features/feed/presentation/screens/feed_screen.dart',
      'lib/features/conversation/presentation/screens/conversation_screen.dart',
      'lib/features/posts/presentation/screens/posts_screen.dart',
      'lib/features/settings/presentation/screens/settings_screen.dart',
      'lib/features/orbit/presentation/screens/orbit_screen.dart',
      'lib/features/share/presentation/screens/share_target_picker_screen.dart',
      'lib/features/qr_code/presentation/screens/qr_display_screen.dart',
      'lib/features/home/presentation/screens/first_time_experience_screen.dart',
      'lib/features/identity/presentation/screens/identity_choice_screen.dart',
      'lib/features/groups/presentation/screens/create_group_picker_screen.dart',
      'lib/features/groups/presentation/screens/contact_picker_screen.dart',
      'lib/features/groups/presentation/screens/group_list_screen.dart',
      'lib/features/groups/presentation/screens/group_conversation_screen.dart',
      'lib/features/groups/presentation/screens/group_info_screen.dart',
    ];

    for (final path in expectedSurfaceFiles) {
      final content = File(path).readAsStringSync();
      expect(content, contains('AmbientBackground('), reason: path);
      expect(content, contains('preference:'), reason: path);
    }
  });
}
