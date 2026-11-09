import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// Records every launch instead of leaving the app.
class FakeUrlLauncher extends Fake
    with MockPlatformInterfaceMixin
    implements UrlLauncherPlatform {
  final launches = <(String, PreferredLaunchMode)>[];

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launches.add((url, options.mode));
    return true;
  }

  /// Stands in for the platform launcher until the test ends.
  static FakeUrlLauncher install() {
    final previous = UrlLauncherPlatform.instance;
    final fake = FakeUrlLauncher();
    UrlLauncherPlatform.instance = fake;
    addTearDown(() => UrlLauncherPlatform.instance = previous);
    return fake;
  }
}

/// Taps the middle of the first [words] inside the text under [within], the
/// way a finger does, so every recognizer in the way competes for it.
Future<void> tapWords(WidgetTester tester, Finder within, String words) async {
  final paragraph = tester
      .renderObjectList<RenderParagraph>(
        find.descendant(
          of: within,
          matching: find.byType(RichText),
          matchRoot: true,
        ),
      )
      .firstWhere(
        (paragraph) => paragraph.text.toPlainText().contains(words),
        orElse: () => throw StateError('"$words" is not in the text'),
      );
  final start = paragraph.text.toPlainText().indexOf(words);
  final box = paragraph
      .getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: start + words.length),
      )
      .first;
  await tester.tapAt(paragraph.localToGlobal(box.toRect().center));
  await tester.pump();
}

/// The text spans under [within] that a tap acts on, as their words.
List<String> tappableWords(WidgetTester tester, Finder within) {
  final words = <String>[];
  for (final rich in tester.widgetList<RichText>(
    find.descendant(of: within, matching: find.byType(RichText)),
  )) {
    rich.text.visitChildren((span) {
      if (span is TextSpan && span.recognizer != null) words.add(span.text!);
      return true;
    });
  }
  return words;
}
