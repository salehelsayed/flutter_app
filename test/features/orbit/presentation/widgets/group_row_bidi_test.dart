import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_type_badge.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/conversation/domain/models/media_preview_descriptor.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_group.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/group_row.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

OrbitGroup _group({
  required String name,
  required String senderUsername,
  required String latestMessageText,
  int unreadCount = 2,
  GroupType type = GroupType.chat,
  DateTime? lastActivityTimestamp,
  MediaPreviewDescriptor? latestMedia,
}) {
  return OrbitGroup(
    group: GroupModel(
      id: 'group-1',
      name: name,
      type: type,
      topicName: 'topic-1',
      createdAt: DateTime(2026, 3, 9).toUtc(),
      createdBy: 'peer-admin',
      myRole: GroupRole.admin,
    ),
    latestMessageSenderUsername: senderUsername,
    latestMessageText: latestMessageText,
    unreadCount: unreadCount,
    lastActivityTimestamp: lastActivityTimestamp ?? DateTime(2026, 3, 9, 9, 30),
    latestMedia: latestMedia,
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
          testWidgets('layout correction group $locale $brightness $width $scale', (
            tester,
          ) async {
            tester.view.physicalSize = Size(width, 1200);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final semantics = tester.ensureSemantics();
            try {
              const name = 'Alexandria Very Long Synthetic Friend Name';
              final rowTaps = <int>[];

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
                                child: GroupRow(
                                  group: _group(
                                    name: name,
                                    unreadCount: count,
                                    type: count == 3
                                        ? GroupType.chat
                                        : GroupType.announcement,
                                    lastActivityTimestamp: DateTime.utc(2100),
                                    senderUsername: 'Synthetic sender',
                                    latestMessageText:
                                        'Synthetic preview long enough to exercise truncation',
                                  ),
                                  onTap: () => rowTaps.add(count),
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
                  'group-$locale-${brightness.name}-$width-$scale',
                );
              }
              for (final count in [3, 123]) {
                final row = find.byType(GroupRow).at(count == 3 ? 0 : 1);
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
                    matching: find.byType(GroupTypeBadge),
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

                await tester.tap(title);
                expect(rowTaps, [3, if (count == 123) 123]);
              }
              expect(tester.takeException(), isNull);
            } finally {
              semantics.dispose();
            }
          });
        }
      }
    }
  }

  Widget wrap(Widget child) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );
  }

  group('GroupRow', () {
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
      const name = 'Long group name with several words';
      var taps = 0;
      await tester.pumpWidget(
        wrap(
          Center(
            child: SizedBox(
              width: 440,
              child: GroupRow(
                group: _group(
                  name: name,
                  senderUsername: 'Sam',
                  latestMessageText: 'Voice message',
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
            .descendant(of: find.byType(GroupRow), matching: find.byType(Row))
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

    testWidgets(
      'renders LTR sender plus Arabic-first body with RTL body direction',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            GroupRow(
              group: _group(
                name: 'النسخة Alpha',
                senderUsername: 'Alice',
                latestMessageText: 'مرحبا Hello 123',
              ),
              onTap: () {},
            ),
          ),
        );

        expect(find.text('النسخة Alpha'), findsOneWidget);
        expect(find.text('Alice'), findsOneWidget);
        expect(find.text('مرحبا Hello 123'), findsOneWidget);
        expect(
          textFor(tester, 'مرحبا Hello 123').textDirection,
          TextDirection.rtl,
        );
        expect(find.text('2'), findsOneWidget);
      },
    );

    testWidgets(
      'renders Arabic sender plus English-first body with LTR body direction',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            GroupRow(
              group: _group(
                name: 'Team نور',
                senderUsername: 'نور',
                latestMessageText: 'Hello مرحبا 123',
                type: GroupType.announcement,
                unreadCount: 0,
              ),
              onTap: () {},
            ),
          ),
        );

        expect(find.text('Team نور'), findsOneWidget);
        expect(find.text('نور'), findsOneWidget);
        expect(find.text('Hello مرحبا 123'), findsOneWidget);
        expect(
          textFor(tester, 'Hello مرحبا 123').textDirection,
          TextDirection.ltr,
        );
        expect(find.text('Announce'), findsOneWidget);
      },
    );

    testWidgets('renders empty preview fallback when no structured message', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          GroupRow(
            group: OrbitGroup(
              group: GroupModel(
                id: 'group-2',
                name: 'No preview',
                type: GroupType.chat,
                topicName: 'topic-2',
                createdAt: DateTime(2026, 3, 9).toUtc(),
                createdBy: 'peer-admin',
                myRole: GroupRole.admin,
              ),
              unreadCount: 0,
              lastActivityTimestamp: DateTime(2026, 3, 9, 9, 30),
            ),
            onTap: () {},
          ),
        ),
      );

      expect(find.text('No preview'), findsOneWidget);
      expect(find.text('No messages yet'), findsOneWidget);
    });

    testWidgets('renders mixed-script preview content', (tester) async {
      await tester.pumpWidget(
        wrap(
          GroupRow(
            group: _group(
              name: 'النسخة Alpha',
              senderUsername: 'Alice',
              latestMessageText: 'مرحبا Hello 123',
            ),
            onTap: () {},
          ),
        ),
      );

      expect(find.text('النسخة Alpha'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('مرحبا Hello 123'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('media-only group latest shows a label after the sender', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          GroupRow(
            group: _group(
              name: 'Alpha',
              senderUsername: 'Alice',
              latestMessageText: '',
              latestMedia: const MediaPreviewDescriptor(
                type: 'image',
                count: 1,
              ),
            ),
            onTap: () {},
          ),
        ),
      );

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Photo'), findsOneWidget);
      // No dangling "Sender: " then blank.
      expect(find.text('No messages yet'), findsNothing);
    });

    testWidgets('renders announcement groups without throwing', (tester) async {
      await tester.pumpWidget(
        wrap(
          GroupRow(
            group: _group(
              name: 'إعلانات Team',
              senderUsername: 'Bob',
              latestMessageText: 'Status update',
              type: GroupType.announcement,
              unreadCount: 0,
            ),
            onTap: () {},
          ),
        ),
      );

      expect(find.text('إعلانات Team'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Status update'), findsOneWidget);
      expect(find.text('Announce'), findsOneWidget);
    });
  });
}
