import 'dart:ui' show SemanticsAction, SemanticsRole, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/features/conversation/presentation/screens/direct_private_media_viewer.dart';
import 'package:flutter_app/features/feed/presentation/widgets/swipe_to_quote_bubble.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

const _visualKey = ValueKey('private-media-card-visual');
const _modeLabelKey = ValueKey('private-media-mode-label');
const _openKey = ValueKey('private-media-open');

Finder get _visual => find.byKey(_visualKey);
Finder get _modeLabel => find.byKey(_modeLabelKey);
Finder get _openButton => find.byKey(_openKey);

Future<void> _pumpPlaceholder(
  WidgetTester tester, {
  required PrivateMediaPolicy policy,
  required VoidCallback? onOpen,
  PrivateMediaAttachmentKind kind = PrivateMediaAttachmentKind.image,
  bool opening = false,
  Widget Function(Widget child)? wrap,
}) async {
  Widget child = DirectPrivateMediaOpenPlaceholder(
    onOpen: onOpen,
    contactDisplayName: 'pixel',
    opening: opening,
    policy: policy,
    kind: kind,
  );
  child = wrap?.call(child) ?? child;

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(child: SizedBox(width: 360, child: child)),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _withSemantics(
  WidgetTester tester,
  Future<void> Function() body,
) async {
  final handle = tester.ensureSemantics();
  try {
    await body();
  } finally {
    handle.dispose();
  }
}

List<SemanticsNode> _semanticsNodesWhere(
  WidgetTester tester,
  bool Function(SemanticsData data) predicate, {
  SemanticsNode? below,
}) {
  final matches = <SemanticsNode>[];

  bool visit(SemanticsNode node) {
    if (predicate(node.getSemanticsData())) {
      matches.add(node);
    }
    node.visitChildren(visit);
    return true;
  }

  visit(
    below ??
        tester
            .binding
            .renderViews
            .single
            .owner!
            .semanticsOwner!
            .rootSemanticsNode!,
  );
  return matches;
}

AnimatedScale _tileScale(WidgetTester tester) {
  final scale = find.ancestor(
    of: _visual,
    matching: find.byType(AnimatedScale),
  );
  expect(scale, findsOneWidget);
  return tester.widget<AnimatedScale>(scale);
}

void _expectEnabledTileSemantics(WidgetTester tester, {required String label}) {
  final matchingNodes = _semanticsNodesWhere(
    tester,
    (data) => data.label == label,
  );
  expect(
    matchingNodes,
    hasLength(1),
    reason: 'the label and button action must be co-located on one node',
  );

  final tileNode = tester.getSemantics(_visual);
  expect(tileNode.id, matchingNodes.single.id);
  final data = tileNode.getSemanticsData();
  expect(data.flagsCollection.isButton, isTrue);
  expect(data.flagsCollection.isEnabled, Tristate.isTrue);
  expect(data.hasAction(SemanticsAction.tap), isTrue);
}

void main() {
  testWidgets('tapping the tile opens a received protected photo', (
    tester,
  ) async {
    var opens = 0;
    await _pumpPlaceholder(
      tester,
      policy: const PrivateMediaPolicy.protected(),
      onOpen: () => opens++,
    );

    await tester.tap(_visual);

    expect(opens, 1);
  });

  testWidgets(
    'received protected card removes visible title button and orphan title spacing',
    (tester) async {
      await _pumpPlaceholder(
        tester,
        policy: const PrivateMediaPolicy.protected(),
        onOpen: () {},
      );

      expect(_modeLabel, findsNothing);
      expect(find.text('Protected photo'), findsNothing);
      expect(_openButton, findsNothing);

      final body = find.textContaining(
        "pixel doesn't allow saving or sharing.",
      );
      expect(body, findsOneWidget);
      expect(
        tester.getTopLeft(body).dy - tester.getBottomLeft(_visual).dy,
        closeTo(10, 0.001),
        reason: 'only the tile-to-body gap should remain',
      );
    },
  );

  testWidgets('received protected body is one exact sender-attributed line', (
    tester,
  ) async {
    await _pumpPlaceholder(
      tester,
      policy: const PrivateMediaPolicy.protected(),
      onOpen: () {},
    );

    expect(find.text("pixel doesn't allow saving or sharing."), findsOneWidget);
    expect(find.textContaining('You can view it again.'), findsNothing);
  });

  testWidgets(
    'disappearing card keeps one expiry announcement and opens from the tile',
    (tester) => _withSemantics(tester, () async {
      var opens = 0;
      const expiryTitle = 'Photo · disappears after 1 hour';

      await _pumpPlaceholder(
        tester,
        policy: PrivateMediaPolicy.disappearing(3600),
        onOpen: () => opens++,
      );

      expect(find.text(expiryTitle), findsOneWidget);
      expect(_modeLabel, findsOneWidget);
      expect(_openButton, findsNothing);
      expect(
        _semanticsNodesWhere(tester, (data) => data.label == expiryTitle),
        hasLength(1),
        reason: 'the visible expiry title must not be announced twice',
      );
      _expectEnabledTileSemantics(tester, label: expiryTitle);

      await tester.tap(_visual);

      expect(opens, 1);
    }),
  );

  testWidgets(
    'opening tile is dimmed busy disabled and has no tap or child spinner semantics',
    (tester) => _withSemantics(tester, () async {
      var opens = 0;

      await _pumpPlaceholder(
        tester,
        policy: const PrivateMediaPolicy.protected(),
        onOpen: () => opens++,
        opening: true,
      );

      expect(
        find.descendant(
          of: _visual,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      final dimmer = find.ancestor(of: _visual, matching: find.byType(Opacity));
      expect(dimmer, findsOneWidget);
      expect(tester.widget<Opacity>(dimmer).opacity, lessThan(1));

      final tileNode = tester.getSemantics(_visual);
      final data = tileNode.getSemanticsData();
      expect(data.label, 'Protected photo');
      expect(data.value, 'Opening private media…');
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.flagsCollection.isEnabled, Tristate.isFalse);
      expect(data.hasAction(SemanticsAction.tap), isFalse);
      expect(
        _semanticsNodesWhere(
          tester,
          (candidate) => candidate.value == 'Opening private media…',
        ),
        hasLength(1),
      );
      expect(
        _semanticsNodesWhere(
          tester,
          (candidate) => candidate.role == SemanticsRole.loadingSpinner,
          below: tileNode,
        ),
        isEmpty,
        reason: 'the visual spinner must not create a second a11y node',
      );

      await tester.tap(_visual);

      expect(opens, 0);
    }),
  );

  testWidgets(
    'enabled protected tile is one labeled semantic button with a tap action',
    (tester) => _withSemantics(tester, () async {
      await _pumpPlaceholder(
        tester,
        policy: const PrivateMediaPolicy.protected(),
        onOpen: () {},
      );

      _expectEnabledTileSemantics(tester, label: 'Protected photo');
    }),
  );

  testWidgets('tile tap preserves ancestor long press and swipe to quote', (
    tester,
  ) async {
    var opens = 0;
    var longPresses = 0;
    var quotes = 0;
    await _pumpPlaceholder(
      tester,
      policy: const PrivateMediaPolicy.protected(),
      onOpen: () => opens++,
      wrap: (child) => SwipeToQuoteBubble(
        onQuoteTriggered: () => quotes++,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress: () => longPresses++,
          child: child,
        ),
      ),
    );

    await tester.tap(_visual);
    expect(opens, 1);
    expect(longPresses, 0);
    expect(quotes, 0);

    await tester.longPress(_visual);
    expect(opens, 1);
    expect(longPresses, 1);
    expect(quotes, 0);

    final drag = await tester.startGesture(tester.getCenter(_visual));
    await tester.pump();
    expect(_tileScale(tester).scale, 0.975);
    await drag.moveBy(const Offset(40, 0));
    await tester.pump();
    expect(_tileScale(tester).scale, 1);
    await drag.moveBy(const Offset(40, 0));
    await tester.pump();
    await drag.up();
    await tester.pumpAndSettle();

    expect(opens, 1);
    expect(longPresses, 1);
    expect(quotes, 1);
  });

  testWidgets('tile is 150px only when openable', (tester) async {
    await _pumpPlaceholder(
      tester,
      policy: const PrivateMediaPolicy.protected(),
      onOpen: () {},
    );
    expect(tester.getSize(_visual).height, 150);

    await _pumpPlaceholder(
      tester,
      policy: const PrivateMediaPolicy.protected(),
      onOpen: null,
    );
    expect(tester.getSize(_visual).height, 88);
  });

  testWidgets(
    'not-openable protected card keeps title 88px tile and disabled button',
    (tester) => _withSemantics(tester, () async {
      await _pumpPlaceholder(
        tester,
        policy: const PrivateMediaPolicy.protected(),
        onOpen: null,
      );

      expect(_modeLabel, findsOneWidget);
      expect(find.text('Protected photo'), findsOneWidget);
      expect(tester.getSize(_visual).height, 88);
      expect(_openButton, findsOneWidget);
      expect(tester.widget<FilledButton>(_openButton).onPressed, isNull);

      final tileData = tester.getSemantics(_visual).getSemanticsData();
      expect(tileData.flagsCollection.isButton, isFalse);
      expect(tileData.hasAction(SemanticsAction.tap), isFalse);
    }),
  );

  testWidgets('tap feedback scales to 0.975 and resets on up and cancel', (
    tester,
  ) async {
    await _pumpPlaceholder(
      tester,
      policy: const PrivateMediaPolicy.protected(),
      onOpen: () {},
    );

    var gesture = await tester.startGesture(tester.getCenter(_visual));
    await tester.pump();
    expect(_tileScale(tester).duration, const Duration(milliseconds: 120));
    expect(_tileScale(tester).scale, 0.975);

    await gesture.up();
    await tester.pump();
    expect(_tileScale(tester).scale, 1);
    await tester.pump(const Duration(milliseconds: 120));

    gesture = await tester.startGesture(tester.getCenter(_visual));
    await tester.pump();
    expect(_tileScale(tester).scale, 0.975);

    await gesture.cancel();
    await tester.pump();
    expect(_tileScale(tester).scale, 1);
    await tester.pump(const Duration(milliseconds: 120));
  });

  testWidgets(
    'protected and disappearing tap tile covers image and video while legacy GIF keeps the old branch',
    (tester) => _withSemantics(tester, () async {
      var opens = 0;
      var expectedOpens = 0;

      final cases =
          <
            ({
              PrivateMediaPolicy policy,
              PrivateMediaAttachmentKind kind,
              String label,
              bool keepsTitle,
            })
          >[
            (
              policy: const PrivateMediaPolicy.protected(),
              kind: PrivateMediaAttachmentKind.image,
              label: 'Protected photo',
              keepsTitle: false,
            ),
            (
              policy: const PrivateMediaPolicy.protected(),
              kind: PrivateMediaAttachmentKind.video,
              label: 'Protected video',
              keepsTitle: false,
            ),
            (
              policy: PrivateMediaPolicy.disappearing(3600),
              kind: PrivateMediaAttachmentKind.image,
              label: 'Photo · disappears after 1 hour',
              keepsTitle: true,
            ),
            (
              policy: PrivateMediaPolicy.disappearing(3600),
              kind: PrivateMediaAttachmentKind.video,
              label: 'Video · disappears after 1 hour',
              keepsTitle: true,
            ),
          ];

      for (final testCase in cases) {
        await _pumpPlaceholder(
          tester,
          policy: testCase.policy,
          kind: testCase.kind,
          onOpen: () => opens++,
        );

        expect(
          tester.getSize(_visual).height,
          150,
          reason: '${testCase.policy.mode}/${testCase.kind}',
        );
        expect(_openButton, findsNothing);
        expect(_modeLabel, testCase.keepsTitle ? findsOneWidget : findsNothing);
        expect(
          find.text(testCase.label),
          testCase.keepsTitle ? findsOneWidget : findsNothing,
        );
        expect(
          find.text("pixel doesn't allow saving or sharing."),
          findsOneWidget,
        );
        _expectEnabledTileSemantics(tester, label: testCase.label);

        await tester.tap(_visual);
        expectedOpens++;
        expect(opens, expectedOpens);
      }

      await _pumpPlaceholder(
        tester,
        policy: const PrivateMediaPolicy.protected(),
        kind: PrivateMediaAttachmentKind.gif,
        onOpen: () => opens++,
      );

      expect(tester.getSize(_visual).height, 88);
      expect(_modeLabel, findsOneWidget);
      expect(find.text('Protected photo'), findsOneWidget);
      expect(_openButton, findsOneWidget);
      expect(
        find.text(
          "You can view it again. pixel doesn't allow saving or sharing.",
        ),
        findsOneWidget,
      );
      expect(find.text("pixel doesn't allow saving or sharing."), findsNothing);
      final legacyTileData = tester.getSemantics(_visual).getSemanticsData();
      expect(legacyTileData.flagsCollection.isButton, isFalse);
      expect(legacyTileData.hasAction(SemanticsAction.tap), isFalse);

      await tester.tap(_visual);
      expect(opens, expectedOpens);
      await tester.tap(_openButton);
      expect(opens, expectedOpens + 1);
    }),
  );
}
