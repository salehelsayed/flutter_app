import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/app_colors.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';
import 'package:flutter_app/features/identity/presentation/widgets/cosmic_background.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrapAmbient({
    BackgroundPreference preference = BackgroundPreference.defaultBackground,
    bool isFeedSurface = false,
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
          child: const Text('Content'),
        ),
      ),
    );
  }

  testWidgets('renders child over the default background treatment', (
    tester,
  ) async {
    await tester.pumpWidget(wrapAmbient());

    expect(find.text('Content'), findsOneWidget);
    expect(find.byType(CosmicBackground), findsNothing);
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

  testWidgets('renders cosmic only for Feed surface with cosmic preference', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapAmbient(preference: BackgroundPreference.cosmic, isFeedSurface: true),
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

  testWidgets('filters cosmic to default for non-Feed surfaces', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapAmbient(preference: BackgroundPreference.cosmic),
    );

    expect(find.text('Content'), findsOneWidget);
    expect(find.byType(CosmicBackground), findsNothing);
    expect(find.byType(AnimatedBuilder), findsAtLeastNWidgets(2));

    final backgroundContainers = tester
        .widgetList<Container>(find.byType(Container))
        .where((container) => container.color == AppColors.background)
        .toList();
    expect(backgroundContainers, isNotEmpty);
  });

  testWidgets('Feed surface with default preference stays default', (
    tester,
  ) async {
    await tester.pumpWidget(wrapAmbient(isFeedSurface: true));

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
    }
  });
}
