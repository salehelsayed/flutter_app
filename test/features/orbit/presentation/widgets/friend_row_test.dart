import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/domain/models/media_preview_descriptor.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/friend_row.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

OrbitFriend _makeFriend({
  String peerId = 'peer-1234567890',
  int unreadCount = 3,
  String? lastActivity,
  String username = 'Alice',
  String? lastMessageTimestamp,
  MediaPreviewDescriptor? latestMedia,
  bool isLatestDeleted = false,
}) {
  return OrbitFriend(
    contact: ContactModel(
      peerId: peerId,
      publicKey: 'pk-1',
      rendezvous: '/dns4/relay/tcp/443',
      username: username,
      signature: 'sig-1',
      scannedAt: '2026-01-01T00:00:00.000Z',
    ),
    lastMessageTimestamp: lastMessageTimestamp,
    messageCount: 5,
    lastActivity: lastActivity,
    unreadCount: unreadCount,
    latestMedia: latestMedia,
    isLatestDeleted: isLatestDeleted,
  );
}

// Use the pinned SDK's Roboto and Noto Naskh Arabic for real glyph geometry.
// These host fonts do not certify the device's independently rendered candidate.
Future<void> _loadLayoutFont() async {
  final config = File('.dart_tool/package_config.json').absolute;
  final packages =
      (jsonDecode(await config.readAsString())
              as Map<String, dynamic>)['packages']
          as List<dynamic>;
  final flutter = packages.cast<Map<String, dynamic>>().singleWhere(
    (p) => p['name'] == 'flutter',
  );
  final sdk = Directory.fromUri(
    config.uri.resolve(flutter['rootUri'] as String),
  ).parent.parent;
  final loader = FontLoader('Ui25Roboto');
  for (final weight in ['Regular', 'Medium', 'Bold']) {
    loader.addFont(
      File(
        '${sdk.path}/bin/cache/artifacts/material_fonts/Roboto-$weight.ttf',
      ).readAsBytes().then(ByteData.sublistView),
    );
  }
  await loader.load();
  final arabic = FontLoader('Ui25Arabic')
    ..addFont(
      File(
        '${sdk.path}/engine/src/flutter/txt/third_party/fonts/NotoNaskhArabic-Regular.ttf',
      ).readAsBytes().then(ByteData.sublistView),
    );
  await arabic.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(
      File(
        '${sdk.path}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ).readAsBytes().then(ByteData.sublistView),
    );
  await icons.load();
}

Future<void> _captureLayout(WidgetTester tester, String name) async {
  const directory = String.fromEnvironment('UI25_LAYOUT_EVIDENCE');
  if (directory.isEmpty) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('layout-evidence')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File(
      '$directory/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    final geometry = <Map<String, Object?>>[];
    for (final element
        in find
            .descendant(
              of: find.byKey(const ValueKey('layout-evidence')),
              matching: find.byType(Text),
            )
            .evaluate()) {
      final text = element.widget as Text;
      final rect = tester.getRect(find.byWidget(text));
      geometry.add({
        'text': text.data,
        'rect': [rect.left, rect.top, rect.width, rect.height],
      });
    }
    await File('$directory/$name.json').writeAsString(jsonEncode(geometry));
    image.dispose();
  });
}

void main() {
  setUpAll(_loadLayoutFont);
  // Native fixture: 320/390dp content, 12dp list inset, real badges and Active now.
  for (final locale in ['en', 'de', 'ar']) {
    for (final brightness in Brightness.values) {
      for (final width in [320.0, 390.0]) {
        for (final scale in [1.0, 1.6]) {
          testWidgets(
            'layout correction friend $locale $brightness $width $scale',
            (tester) async {
              tester.view.physicalSize = Size(width, 1200);
              tester.view.devicePixelRatio = 1;
              addTearDown(tester.view.resetPhysicalSize);
              addTearDown(tester.view.resetDevicePixelRatio);
              final semantics = tester.ensureSemantics();
              try {
                const name = 'Alexandria Very Long Synthetic Friend Name';
                final rowTaps = <int>[];
                final avatarTaps = <int>[];
                await tester.pumpWidget(
                  MaterialApp(
                    locale: Locale(locale),
                    localizationsDelegates:
                        AppLocalizations.localizationsDelegates,
                    supportedLocales: AppLocalizations.supportedLocales,
                    theme: ThemeData(
                      fontFamily: 'Ui25Roboto',
                      fontFamilyFallback: const ['Ui25Arabic'],
                      brightness: brightness,
                      extensions: [
                        brightness == Brightness.light
                            ? BackgroundReadableColors.representativeLight
                            : BackgroundReadableColors.dark,
                      ],
                    ),
                    home: Scaffold(
                      body: RepaintBoundary(
                        key: const ValueKey('layout-evidence'),
                        child: MediaQuery(
                          data: MediaQueryData(
                            textScaler: TextScaler.linear(scale),
                          ),
                          child: ListView(
                            padding: const EdgeInsets.all(12),
                            children: [
                              for (final count in [3, 123])
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: FriendRow(
                                    friend: _makeFriend(
                                      username: name,
                                      peerId: 'ui25-synthetic-$count',
                                      unreadCount: count,
                                      lastMessageTimestamp:
                                          '2100-01-01T00:00:00Z',
                                      lastActivity:
                                          'Synthetic preview long enough to exercise truncation',
                                    ),
                                    showInnerCircleBadge: true,
                                    onTap: () => rowTaps.add(count),
                                    onAvatarTap: () => avatarTaps.add(count),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
                await tester.pumpAndSettle();
                if ((width == 390 && scale == 1) ||
                    (width == 320 && scale == 1.6)) {
                  await _captureLayout(
                    tester,
                    'friend-$locale-${brightness.name}-$width-$scale',
                  );
                }
                final l10n = AppLocalizations.of(
                  tester.element(find.byType(FriendRow).first),
                )!;
                for (final count in [3, 123]) {
                  final row = find.byType(FriendRow).at(count == 3 ? 0 : 1);
                  final title = find.descendant(
                    of: row,
                    matching: find.text(name),
                  );
                  final paragraph = tester.renderObject<RenderParagraph>(
                    find.descendant(of: title, matching: find.byType(RichText)),
                  );
                  // Each of the first four source characters must survive ellipsis,
                  // with its entire box inside the painted paragraph and card.
                  for (var index = 0; index < 4; index++) {
                    final boxes = paragraph.getBoxesForSelection(
                      TextSelection(baseOffset: index, extentOffset: index + 1),
                    );
                    expect(
                      boxes,
                      hasLength(1),
                      reason: 'Missing name character $index',
                    );
                    final glyph = boxes.single.toRect();
                    expect(glyph.width, greaterThan(0));
                    expect(glyph.height, greaterThan(0));
                    final paragraphBounds = Offset.zero & paragraph.size;
                    final cardBounds = tester.getRect(row);
                    for (final corner in [
                      glyph.topLeft,
                      glyph.topRight,
                      glyph.bottomLeft,
                      glyph.bottomRight,
                    ]) {
                      expect(
                        paragraphBounds.inflate(.01).contains(corner),
                        isTrue,
                      );
                      expect(
                        cardBounds.contains(paragraph.localToGlobal(corner)),
                        isTrue,
                      );
                    }
                  }
                  final titleRect = tester.getRect(title);
                  final badgeRect = tester.getRect(
                    find.descendant(
                      of: row,
                      matching: find.text(l10n.orbit_inner_circle_badge),
                    ),
                  );
                  final timeRect = tester.getRect(
                    find.descendant(of: row, matching: find.text('Active now')),
                  );
                  expect(titleRect.overlaps(badgeRect), isFalse);
                  expect(titleRect.overlaps(timeRect), isFalse);
                  expect(badgeRect.overlaps(timeRect), isFalse);
                  for (final rect in [titleRect, badgeRect, timeRect]) {
                    expect(tester.getRect(row).contains(rect.topLeft), isTrue);
                    expect(
                      tester.getRect(row).contains(rect.bottomRight),
                      isTrue,
                    );
                  }
                  expect(tester.getSize(row).height, greaterThanOrEqualTo(48));
                  expect(
                    find.descendant(
                      of: row,
                      matching: find.text(count == 3 ? '3' : '99+'),
                    ),
                    findsOneWidget,
                  );
                  expect(find.bySemanticsLabel(RegExp(name)), findsNWidgets(2));
                  final avatar = find.descendant(
                    of: row,
                    matching: find.byType(UserAvatar),
                  );
                  expect(tester.getSize(avatar), const Size(48, 48));
                  await tester.tap(avatar);
                  expect(avatarTaps, [3, if (count == 123) 123]);
                  expect(rowTaps.length, count == 3 ? 0 : 1);
                  await tester.tap(title);
                  expect(rowTaps, [3, if (count == 123) 123]);
                }
                expect(tester.takeException(), isNull);
              } finally {
                semantics.dispose();
              }
            },
          );
        }
      }
    }
  }

  group('FriendRow', () {
    Widget wrap(Widget child) => MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

    Text textFor(WidgetTester tester, String text) {
      final finder = find.byWidgetPredicate(
        (widget) => widget is Text && widget.data == text,
        description: 'Text("$text")',
      );
      expect(finder, findsOneWidget);
      return tester.widget<Text>(finder);
    }

    testWidgets('UI25 06.1 title and metadata retain readable spacing', (
      tester,
    ) async {
      const name = 'Alexandra Montgomery-Williams';
      var taps = 0;
      await tester.pumpWidget(
        wrap(
          Center(
            child: SizedBox(
              width: 360,
              child: FriendRow(
                friend: _makeFriend(
                  username: name,
                  lastActivity: 'Voice message',
                ),
                onTap: () => taps++,
              ),
            ),
          ),
        ),
      );
      final title = find.text(name);
      expect(tester.widget<Text>(title).maxLines, 1);
      expect(tester.widget<Text>(title).overflow, TextOverflow.ellipsis);
      final row = tester.widget<Row>(
        find
            .descendant(of: find.byType(FriendRow), matching: find.byType(Row))
            .first,
      );
      final gutter = row.children[row.children.length - 2] as SizedBox;
      expect(gutter.width, 10);
      expect(
        tester.getTopLeft(find.text('Voice message')).dy -
            tester.getBottomLeft(title).dy,
        closeTo(4, 0.01),
      );
      await tester.tap(title);
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows unread badge by default when unreadCount > 0', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(FriendRow(friend: _makeFriend(unreadCount: 3), onTap: () {})),
      );
      await tester.pumpAndSettle();

      // UnreadCountBadge renders the count as text
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('hides unread badge when hideUnreadBadge is true', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          FriendRow(
            friend: _makeFriend(unreadCount: 3),
            hideUnreadBadge: true,
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The count text should not appear
      expect(find.text('3'), findsNothing);
    });

    testWidgets('shows chevron when no unread messages', (tester) async {
      await tester.pumpWidget(
        wrap(FriendRow(friend: _makeFriend(unreadCount: 0), onTap: () {})),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('Arabic lastActivity drives RTL', (tester) async {
      const lastActivity = 'مرحبا';

      await tester.pumpWidget(
        wrap(
          FriendRow(
            friend: _makeFriend(lastActivity: lastActivity, unreadCount: 0),
            onTap: () {},
          ),
        ),
      );

      expect(textFor(tester, lastActivity).textDirection, TextDirection.rtl);
    });

    testWidgets('Arabic-first mixed lastActivity drives RTL', (tester) async {
      const lastActivity = 'مرحبا Hello 123';

      await tester.pumpWidget(
        wrap(
          FriendRow(
            friend: _makeFriend(lastActivity: lastActivity, unreadCount: 0),
            onTap: () {},
          ),
        ),
      );

      expect(textFor(tester, lastActivity).textDirection, TextDirection.rtl);
    });

    testWidgets('English-first mixed lastActivity drives LTR', (tester) async {
      const lastActivity = 'Hello مرحبا 123';

      await tester.pumpWidget(
        wrap(
          FriendRow(
            friend: _makeFriend(lastActivity: lastActivity, unreadCount: 0),
            onTap: () {},
          ),
        ),
      );

      expect(textFor(tester, lastActivity).textDirection, TextDirection.ltr);
    });

    testWidgets('media-only voice note shows a localized label', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          FriendRow(
            friend: _makeFriend(
              lastActivity: '',
              unreadCount: 0,
              latestMedia: const MediaPreviewDescriptor(
                type: 'audio',
                count: 1,
              ),
            ),
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Voice message'), findsOneWidget);
    });

    testWidgets('multiple images show a counted label', (tester) async {
      await tester.pumpWidget(
        wrap(
          FriendRow(
            friend: _makeFriend(
              lastActivity: '',
              unreadCount: 0,
              latestMedia: const MediaPreviewDescriptor(
                type: 'image',
                count: 2,
              ),
            ),
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('2 photos'), findsOneWidget);
    });

    testWidgets('caption wins over the media label', (tester) async {
      await tester.pumpWidget(
        wrap(
          FriendRow(
            friend: _makeFriend(
              lastActivity: 'My caption',
              unreadCount: 0,
              latestMedia: const MediaPreviewDescriptor(
                type: 'image',
                count: 1,
              ),
            ),
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('My caption'), findsOneWidget);
      expect(find.text('Photo'), findsNothing);
    });

    testWidgets('deleted latest shows the deleted placeholder', (tester) async {
      await tester.pumpWidget(
        wrap(
          FriendRow(
            friend: _makeFriend(
              lastActivity: null,
              unreadCount: 0,
              isLatestDeleted: true,
            ),
            onTap: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('This message was deleted'), findsOneWidget);
    });

    testWidgets('Arabic locale media label is RTL', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: FriendRow(
              friend: _makeFriend(
                lastActivity: '',
                unreadCount: 0,
                latestMedia: const MediaPreviewDescriptor(
                  type: 'audio',
                  count: 1,
                ),
              ),
              onTap: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(textFor(tester, 'رسالة صوتية').textDirection, TextDirection.rtl);
    });
  });

  group('AnimatedFriendRow', () {
    Widget wrap(Widget child) => MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

    double fadeOpacity(WidgetTester tester) => tester
        .widget<FadeTransition>(
          find.descendant(
            of: find.byType(AnimatedFriendRow),
            matching: find.byType(FadeTransition),
          ),
        )
        .opacity
        .value;

    testWidgets('TC-202-11 AnimatedFriendRow is instant under reduce-motion', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: AnimatedFriendRow(
                index: 40,
                child: FriendRow(friend: _makeFriend(), onTap: () {}),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        fadeOpacity(tester),
        1.0,
        reason: 'reduce-motion jumps the entrance straight to the end',
      );
    });

    testWidgets('TC-202-12 entrance stagger is clamped', (tester) async {
      await tester.pumpWidget(
        wrap(
          AnimatedFriendRow(
            index: 100,
            child: FriendRow(friend: _makeFriend(), onTap: () {}),
          ),
        ),
      );
      // Clamp ceiling = min(index, 12) * 20ms = 240ms delay; + 400ms entrance.
      // Stepped bounded pumps (a single long pump can leave opacity ~0 because
      // the ticker bases elapsed from its first post-delay tick).
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        fadeOpacity(tester),
        1.0,
        reason: 'a clamped stagger completes well within 1s',
      );
    });
  });
}
