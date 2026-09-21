import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/settings/presentation/widgets/settings_group.dart';
import 'package:flutter_app/features/settings/presentation/widgets/media_download_matrix_control.dart';
import 'package:flutter_app/features/settings/domain/models/media_download_preferences.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

Text _segmentText(ButtonSegment<MediaDownloadNetworkChoice> segment) {
  final label = segment.label!;
  return label is Padding ? label.child! as Text : label as Text;
}

// Read the installed renderer's resolved border and its actual paint inset.
// Bounding-rectangle containment alone misses the tall stadium clipping defect.
OutlinedBorder _expectLabelsInsidePaintedShape(
  WidgetTester tester,
  Finder control, {
  String? onlyLabel,
}) {
  final renderWidget = find.descendant(
    of: control,
    matching: find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString().startsWith(
        '_SegmentedButtonRenderWidget',
      ),
    ),
  );
  final dynamic renderer = tester.renderObject(renderWidget);
  final box = renderer as RenderBox;
  final border = (renderer as dynamic).enabledBorder as OutlinedBorder;
  final padding = (renderer as dynamic).tapTargetVerticalPadding as double;
  final rect = Rect.fromLTWH(
    0,
    padding / 2,
    box.size.width,
    box.size.height - padding,
  );
  final clip = border.getInnerPath(
    rect,
    textDirection: (renderer as dynamic).textDirection as TextDirection,
  );
  final labels = find.descendant(
    of: control,
    matching: onlyLabel == null ? find.byType(Text) : find.text(onlyLabel),
  );
  for (final element in labels.evaluate()) {
    final text = element.widget as Text;
    final label = find.byWidget(text);
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: label, matching: find.byType(RichText)),
    );
    final origin = paragraph.localToGlobal(Offset.zero, ancestor: box);
    for (var i = 0; i < text.data!.length; i++) {
      if (text.data![i].trim().isEmpty) continue;
      final glyphs = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: i, extentOffset: i + 1),
      );
      expect(
        glyphs,
        isNotEmpty,
        reason: 'Missing visible character $i in ${text.data}',
      );
      for (final glyph in glyphs) {
        final bounds = glyph.toRect().shift(origin).deflate(.01);
        for (final point in [
          bounds.topLeft,
          bounds.topRight,
          bounds.bottomLeft,
          bounds.bottomRight,
        ]) {
          expect(
            clip.contains(point),
            isTrue,
            reason:
                '${text.data} character $i at $point outside actual $border clip $rect',
          );
        }
      }
    }
  }
  return border;
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
  // Differential specifically isolates shape clipping. Deliberately no target
  // gate: originals' FittedBox/small targets must not mask this assertion.
  for (final locale in ['en', 'de', 'ar']) {
    for (final brightness in Brightness.values) {
      for (final choice in MediaDownloadNetworkChoice.values) {
        for (final selectedOnly in [false, true]) {
          testWidgets(
            '${selectedOnly ? 'selected-shape' : 'shape-only'} differential $locale $brightness ${choice.name}',
            (tester) async {
              tester.view.physicalSize = const Size(320, 1200);
              tester.view.devicePixelRatio = 1;
              addTearDown(tester.view.resetPhysicalSize);
              addTearDown(tester.view.resetDevicePixelRatio);
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
                    body: MediaQuery(
                      data: const MediaQueryData(
                        textScaler: TextScaler.linear(1.6),
                      ),
                      child: SingleChildScrollView(
                        child: MediaDownloadMatrixControl(
                          preferences: MediaDownloadMatrixControl.applyChoice(
                            const MediaDownloadPreferences.defaults(),
                            MediaConversationKind.oneToOne,
                            'image',
                            choice,
                          ),
                          onChanged: (_) {},
                        ),
                      ),
                    ),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              final control = find.byKey(
                const ValueKey('media-download-oneToOne-image'),
              );
              final widget = tester
                  .widget<SegmentedButton<MediaDownloadNetworkChoice>>(control);
              _expectLabelsInsidePaintedShape(
                tester,
                control,
                onlyLabel: selectedOnly
                    ? _segmentText(
                        widget.segments.firstWhere((s) => s.value == choice),
                      ).data
                    : null,
              );
              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    }
  }

  for (final locale in ['en', 'de', 'ar']) {
    for (final brightness in Brightness.values) {
      for (final width in [320.0, 390.0]) {
        for (final scale in [1.0, 1.6, 2.0]) {
          testWidgets(
            'layout correction matrix $locale $brightness $width $scale',
            (tester) async {
              tester.view.physicalSize = Size(width, 1200);
              tester.view.devicePixelRatio = 1;
              addTearDown(tester.view.resetPhysicalSize);
              addTearDown(tester.view.resetDevicePixelRatio);
              final semantics = tester.ensureSemantics();
              try {
                var prefs = const MediaDownloadPreferences.defaults();
                var changes = 0;
                late StateSetter update;
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
                          child: SingleChildScrollView(
                            child: StatefulBuilder(
                              builder: (context, setState) {
                                update = setState;
                                return MediaDownloadMatrixControl(
                                  preferences: prefs,
                                  onChanged: (next) => setState(() {
                                    prefs = next;
                                    changes++;
                                  }),
                                );
                              },
                            ),
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
                    'matrix-$locale-${brightness.name}-$width-$scale',
                  );
                }
                final control = find.byKey(
                  const ValueKey('media-download-oneToOne-image'),
                );
                final targets = <Size>[];
                for (final choice in MediaDownloadNetworkChoice.values) {
                  final previous = prefs;
                  final widget = tester
                      .widget<SegmentedButton<MediaDownloadNetworkChoice>>(
                        control,
                      );
                  final label = _segmentText(
                    widget.segments.firstWhere((s) => s.value == choice),
                  ).data!;
                  final target = find.descendant(
                    of: control,
                    matching: find.widgetWithText(TextButton, label),
                  );
                  targets.add(tester.getRect(target).size);
                  await tester.tap(target);
                  await tester.pumpAndSettle();
                  final border = _expectLabelsInsidePaintedShape(
                    tester,
                    control,
                  );
                  if (width == 390 && scale == 1) {
                    expect(border, isA<StadiumBorder>());
                  }
                  debugPrint(
                    'shape-contained $locale $brightness $width $scale ${choice.name} ${border.runtimeType}',
                  );
                  final segmentSemantics = find
                      .descendant(
                        of: control,
                        matching: find.byType(MergeSemantics),
                      )
                      .at(choice.index);
                  final accessibleLabels = <String>[];
                  void collectLabels(SemanticsNode node) {
                    accessibleLabels.add(node.label);
                    node.visitChildren((child) {
                      collectLabels(child);
                      return true;
                    });
                  }

                  collectLabels(tester.getSemantics(segmentSemantics));
                  expect(accessibleLabels, contains(label));
                  expect(
                    prefs.toStorageString(),
                    MediaDownloadMatrixControl.applyChoice(
                      previous,
                      MediaConversationKind.oneToOne,
                      'image',
                      choice,
                    ).toStorageString(),
                  );
                  // Rollback preserves the complete 12-choice model and selected UI.
                  final chosen = prefs;
                  update(() => prefs = previous);
                  await tester.pumpAndSettle();
                  expect(prefs.toStorageString(), previous.toStorageString());
                  expect(
                    tester
                        .widget<SegmentedButton<MediaDownloadNetworkChoice>>(
                          control,
                        )
                        .selected,
                    {
                      MediaDownloadMatrixControl.choiceFor(
                        previous,
                        MediaConversationKind.oneToOne,
                        'image',
                      ),
                    },
                  );
                  update(() => prefs = chosen);
                  await tester.pumpAndSettle();
                }
                for (final target in targets) {
                  expect(target.width, greaterThanOrEqualTo(48));
                  expect(target.height, greaterThanOrEqualTo(48));
                }
                expect(changes, 3);
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

  Widget wrap(Widget child, {String locale = 'en', double scale = 1}) =>
      MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: SingleChildScrollView(child: child),
          ),
        ),
      );
  testWidgets(
    'UI25 06.2 subtitle grows and preserves full copy, clamp and control',
    (tester) async {
      const copy =
          'Shares only an approximate location with direct friends. No live maps, and never strangers.';
      var changes = 0;
      Widget row() => SettingsListRow(
        icon: Icons.search,
        label: 'Share People Nearby',
        subtitle: copy,
        value: 'Off',
        trailing: Switch(value: false, onChanged: (_) => changes++),
      );
      await tester.pumpWidget(wrap(SizedBox(width: 360, child: row())));
      final subtitle = tester.widget<Text>(find.text(copy));
      expect(subtitle.style!.fontSize, 12);
      expect(subtitle.maxLines, 2);
      expect(subtitle.overflow, TextOverflow.ellipsis);
      expect(subtitle.style!.height, 1.3);
      expect(
        tester.getTopLeft(find.text(copy)).dy -
            tester.getBottomLeft(find.text('Share People Nearby')).dy,
        2,
      );
      final height = tester.getSize(find.byType(SettingsListRow)).height;
      expect(height, greaterThanOrEqualTo(44));
      await tester.tap(find.byType(Switch));
      expect(changes, 1);
      await tester.pumpWidget(
        wrap(SizedBox(width: 360, child: row()), scale: 2),
      );
      expect(
        tester.getSize(find.byType(SettingsListRow)).height,
        greaterThan(height),
      );
      expect(find.text(copy), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final locale in ['en', 'de', 'ar']) {
    testWidgets(
      'UI25 08.4 readable full-width choices preserve mapping $locale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var prefs = const MediaDownloadPreferences.defaults();
        var changes = 0;
        await tester.pumpWidget(
          wrap(
            StatefulBuilder(
              builder: (context, setState) => MediaDownloadMatrixControl(
                preferences: prefs,
                onChanged: (next) => setState(() {
                  prefs = next;
                  changes++;
                }),
              ),
            ),
            locale: locale,
            scale: 2,
          ),
        );
        final l10n = AppLocalizations.of(
          tester.element(find.byType(MediaDownloadMatrixControl)),
        )!;
        final control = find.byKey(
          const ValueKey('media-download-oneToOne-image'),
        );
        final widget = tester
            .widget<SegmentedButton<MediaDownloadNetworkChoice>>(control);
        expect(widget.showSelectedIcon, isTrue);
        expect(tester.getSize(control).width, closeTo(280, 0.01));
        expect(
          find.ancestor(of: control, matching: find.byType(FittedBox)),
          findsNothing,
        );
        final label = find.text(l10n.settings_media_type_image).first;
        expect(
          tester.getRect(label).bottom,
          lessThan(tester.getRect(control).top),
        );
        for (final segment in widget.segments) {
          expect(_segmentText(segment).style!.fontSize, 13);
          expect(_segmentText(segment).maxLines, isNull);
        }
        for (final choice in MediaDownloadNetworkChoice.values) {
          final current = tester
              .widget<SegmentedButton<MediaDownloadNetworkChoice>>(control);
          final text = _segmentText(
            current.segments.firstWhere((s) => s.value == choice),
          ).data!;
          await tester.tap(
            find.descendant(of: control, matching: find.text(text)),
          );
          await tester.pump();
          expect(
            tester
                .widget<SegmentedButton<MediaDownloadNetworkChoice>>(control)
                .selected,
            {choice},
          );
          expect(
            prefs.isAutoDownloadEnabled(
              kind: MediaConversationKind.oneToOne,
              mediaType: 'image',
              network: MediaDownloadNetwork.wifi,
            ),
            choice != MediaDownloadNetworkChoice.off,
          );
          expect(
            prefs.isAutoDownloadEnabled(
              kind: MediaConversationKind.oneToOne,
              mediaType: 'image',
              network: MediaDownloadNetwork.cellular,
            ),
            choice == MediaDownloadNetworkChoice.all,
          );
          expect(
            prefs.isAutoDownloadEnabled(
              kind: MediaConversationKind.discussion,
              mediaType: 'video',
              network: MediaDownloadNetwork.cellular,
            ),
            isTrue,
          );
        }
        expect(changes, 3);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
