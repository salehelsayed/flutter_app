import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/theme/app_theme.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_safety_number.dart';
import 'package:flutter_app/features/contact_profile/presentation/screens/contact_profile_screen.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

void main() {
  const peerId = '12D3KooWQYV9dRtTtGS4aXq1example0peer0id0abcdef0123456789';

  ContactModel buildContact({
    String username = 'Aurora Vex',
    bool isBlocked = false,
    bool isArchived = false,
    String? introducedBy,
  }) {
    return ContactModel(
      peerId: peerId,
      publicKey: 'cHVibGljLWtleS1iYXNlNjQ=',
      rendezvous: '/ip4/127.0.0.1/tcp/4001',
      username: username,
      signature: 'c2lnbmF0dXJl',
      scannedAt: '2026-01-15T10:30:00.000Z',
      mlKemPublicKey: 'bWxrZW0tcHVibGljLWtleQ==',
      isBlocked: isBlocked,
      isArchived: isArchived,
      introducedBy: introducedBy,
    );
  }

  Widget wrap(ContactModel contact, {VoidCallback? onMessage}) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ContactProfileScreen(contact: contact, onMessage: onMessage),
    );
  }

  testWidgets('renders nickname, peer ID and safety number', (tester) async {
    await tester.pumpWidget(wrap(buildContact()));
    // Advance the staggered entrance (the orbit animation repeats forever, so
    // pumpAndSettle must not be used).
    await tester.pump(const Duration(milliseconds: 1000));

    expect(find.text('Aurora Vex'), findsOneWidget);
    expect(find.text(peerId), findsOneWidget);
    // Card labels render upper-cased.
    expect(find.text('PEER ID'), findsOneWidget);
    expect(find.text('Verified peer'), findsOneWidget);
    expect(find.text('SAFETY NUMBER'), findsOneWidget);
    // Connection date is derived from scannedAt (Jan 2026).
    expect(find.textContaining('2026'), findsWidgets);
  });

  // TC-24 (156, preservation sentinel — GREEN on HEAD and after fix): the
  // friend-profile orbit rides its own ..repeat() controller and must keep
  // rotating even under reduce-motion. 156 QW-3 confines its reduce-motion gate
  // to ambient_background.dart and QW-13 hides only the orbit2/3 prototype tabs;
  // neither must freeze this orbit.
  testWidgets(
    'TC-24: friend-profile orbit keeps rotating even under disableAnimations',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(400, 800),
              disableAnimations: true,
            ),
            child: ContactProfileScreen(contact: buildContact()),
          ),
        ),
      );
      // Let the staggered entrance finish; the orbit repeats forever.
      await tester.pump(const Duration(milliseconds: 1200));

      final controllers = tester
          .widgetList<AnimatedBuilder>(find.byType(AnimatedBuilder))
          .map((ab) => ab.listenable)
          .whereType<AnimationController>()
          .toList();
      expect(controllers, isNotEmpty);
      expect(
        controllers.any((c) => c.isAnimating),
        isTrue,
        reason: 'the friend-profile orbit must keep animating under '
            'reduce-motion',
      );
    },
  );

  testWidgets('peer ID and safety-number copy use the shared quiet pill', (
    tester,
  ) async {
    final List<MethodCall> platformCalls = [];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        platformCalls.add(call);
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    await tester.pumpWidget(wrap(buildContact()));
    await tester.pump(const Duration(milliseconds: 1000));

    await tester.tap(find.text(peerId));
    await tester.pump(); // run the copy + show the SnackBar
    await tester.pump(const Duration(milliseconds: 600));

    final copyCall = platformCalls.firstWhere(
      (c) => c.method == 'Clipboard.setData',
      orElse: () => const MethodCall('none'),
    );
    expect(copyCall.method, 'Clipboard.setData');
    expect((copyCall.arguments as Map)['text'], peerId);
    expect(find.text('Peer ID copied'), findsOneWidget);
    expect(find.byKey(const ValueKey('quiet-confirm')), findsOneWidget);
    expect(
      tester.widgetList<SnackBar>(find.byType(SnackBar)).every(
        (bar) => bar.key == const ValueKey('quiet-confirm'),
      ),
      isTrue,
    );

    final safetyNumber = ContactSafetyNumber.build(
      peerId: peerId,
      publicKey: buildContact().publicKey,
      mlKemPublicKey: buildContact().mlKemPublicKey,
    );
    expect(safetyNumber, isNotNull);
    await tester.ensureVisible(find.text(safetyNumber!));
    await tester.pump();
    await tester.tap(find.text(safetyNumber));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final copyCalls = platformCalls
        .where((call) => call.method == 'Clipboard.setData')
        .toList();
    expect(copyCalls, hasLength(2));
    expect((copyCalls.last.arguments as Map)['text'], safetyNumber);
    expect(find.text('Copied to clipboard'), findsOneWidget);
    expect(find.byKey(const ValueKey('quiet-confirm')), findsOneWidget);
  });

  testWidgets('shows the message button only when onMessage is provided', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(buildContact()));
    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.text('Message'), findsNothing);

    var tapped = false;
    await tester.pumpWidget(wrap(buildContact(), onMessage: () => tapped = true));
    await tester.pump(const Duration(milliseconds: 1000));

    expect(find.text('Message'), findsOneWidget);
    // The button sits below the test viewport; scroll it into view first.
    await tester.ensureVisible(find.text('Message'));
    await tester.pump();
    await tester.tap(find.text('Message'));
    expect(tapped, isTrue);
  });

  testWidgets('renders blocked and introduced-by metadata', (tester) async {
    await tester.pumpWidget(
      wrap(buildContact(isBlocked: true, introducedBy: 'Mona')),
    );
    await tester.pump(const Duration(milliseconds: 1000));

    expect(find.text('Blocked'), findsOneWidget);
    expect(find.text('Introduced by'), findsOneWidget);
    expect(find.text('Mona'), findsOneWidget);
  });

  // Pushes a base screen whose button opens the profile, so we can pop back.
  Widget wrapPushable({TargetPlatform? platform}) {
    return MaterialApp(
      locale: const Locale('en'),
      theme: platform == null ? null : ThemeData(platform: platform),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () =>
                  ContactProfileScreen.open(context, contact: buildContact()),
              child: const Text('open-profile'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('the back button pops the screen', (tester) async {
    await tester.pumpWidget(wrapPushable());
    await tester.tap(find.text('open-profile'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600)); // finish push
    expect(find.text('Aurora Vex'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_left_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600)); // finish pop

    expect(find.text('Aurora Vex'), findsNothing);
    expect(find.text('open-profile'), findsOneWidget);
  });

  // TC-248-15: a Contact Profile pushed under a Signal light root must inherit
  // the warm light ThemeData + extensions (it reads context.backgroundReadableColors
  // and does NOT wrap itself in AmbientBackground, so it falls back to the root).
  testWidgets(
    'pushed Contact Profile inherits Signal light ThemeData and warm scaffold',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          // The exact theme trio the AppShellThemeBinding produces for Signal.
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.light,
          home: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () =>
                    ContactProfileScreen.open(context, contact: buildContact()),
                child: const Text('open-profile'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open-profile'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700)); // push + theme fade

      final profileContext = tester.element(find.byType(ContactProfileScreen));
      final theme = Theme.of(profileContext);
      expect(theme.brightness, Brightness.light);

      final readable = theme.extension<BackgroundReadableColors>();
      expect(readable, isNotNull);
      expect(
        readable!.isLightSurface,
        isTrue,
        reason: 'pushed route must resolve the light readable extension',
      );

      final scaffold = tester.widget<Scaffold>(
        find.descendant(
          of: find.byType(ContactProfileScreen),
          matching: find.byType(Scaffold),
        ),
      );
      expect(
        scaffold.backgroundColor,
        readable.surfaceBase,
        reason: 'scaffold uses the light warm surface, not a dark island',
      );
    },
  );

  testWidgets('iOS edge-swipe pops the screen', (tester) async {
    // Reset the platform override before the test body returns (the foundation
    // debug-var invariant check runs before addTearDown callbacks).
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await tester.pumpWidget(wrapPushable(platform: TargetPlatform.iOS));
      await tester.tap(find.text('open-profile'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1)); // fully finish push
      expect(find.text('Aurora Vex'), findsOneWidget);

      // Drag from the left edge across the screen → Cupertino back gesture.
      final gesture = await tester.startGesture(const Offset(5, 200));
      await gesture.moveBy(const Offset(40, 0)); // engage the back recognizer
      await tester.pump();
      expect(
        Navigator.of(
          tester.element(find.text('Aurora Vex')),
        ).userGestureInProgress,
        isTrue,
        reason: 'left-edge drag should be claimed by the back gesture',
      );
      await gesture.moveBy(const Offset(400, 0)); // drag across past threshold
      await tester.pump();
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1)); // finish pop

      expect(find.text('Aurora Vex'), findsNothing);
      expect(find.text('open-profile'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
