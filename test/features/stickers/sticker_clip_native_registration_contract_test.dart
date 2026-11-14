import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source wiring/build-membership contract only. Native messenger tests carry
/// close/replacement behavior; this file does not claim engine execution.
void main() {
  final android = File(
    'android/app/src/main/kotlin/com/mknoon/app/MainActivity.kt',
  ).readAsStringSync();
  final ios = File('ios/Runner/AppDelegate.swift').readAsStringSync();
  final appDelegate = ios.substring(ios.indexOf('class AppDelegate:'));

  test('Android configures the real frame helper on the foreground messenger', () {
    final body = _body(android, 'override fun configureFlutterEngine(');
    expect(
      RegExp(
        r'\bsetupStickerClipFrameBridge\(\s*'
        r'flutterEngine\.dartExecutor\.binaryMessenger\s*,?\s*\)',
      ).allMatches(body),
      hasLength(1),
    );
  });

  test('Android detach closes frames before every deferred call-runtime branch', () {
    final body = _body(android, 'override fun cleanUpFlutterEngine(');
    expect(
      _withoutComments(body).trimLeft(),
      startsWith('closeStickerClipFrameBridge()'),
      reason: 'Frame extraction must stop before the RELEASED early return or '
          'deferred canonical runtime shutdown; the call bridge keeps its '
          'existing independent lifetime.',
    );
  });

  test('iOS implicit engine publishes and retains its own frame plugin', () {
    final body = _withoutComments(
      _body(appDelegate, 'func didInitializeImplicitFlutterEngine('),
    );
    expect(
      body,
      matches(
        RegExp(
          r'engineBridge\.pluginRegistry\.registrar\(\s*'
          r'forPlugin:\s*"StickerClipFramePlugin"\s*\)',
        ),
      ),
    );
    final construction = RegExp(
      r'let\s+(\w+)\s*=\s*StickerClipFramePlugin\(\s*messenger:',
    ).firstMatch(body);
    expect(construction, isNotNull, reason: 'Retain a per-engine plugin owner.');
    final owner = construction!.group(1)!;
    expect(body, matches(RegExp(r'\bpublish\(\s*' + owner + r'\s*\)')));
    expect(body, matches(RegExp(r'\bstickerClipFramePlugin\s*=\s*' + owner + r'\b')));
  });

  test('iOS closes the previous owner before constructing its replacement', () {
    final body = _withoutComments(
      _body(appDelegate, 'func didInitializeImplicitFlutterEngine('),
    );
    final close = body.indexOf('stickerClipFramePlugin?.close()');
    final create = body.indexOf('StickerClipFramePlugin(messenger:');
    // Permit a line break between the initializer and its argument label.
    final flexibleCreate = RegExp(r'StickerClipFramePlugin\(\s*messenger:')
        .firstMatch(body)?.start ?? create;
    expect(close, greaterThanOrEqualTo(0));
    expect(flexibleCreate, greaterThan(close));
    expect(
      _braceDepth(body.substring(0, close)),
      0,
      reason: 'Close the retired owner even if a new registrar is unavailable.',
    );
  });

  test('iOS delegate deinit closes and repeated notification setup does not replace', () {
    expect(
      _withoutComments(_body(appDelegate, 'deinit')),
      contains('stickerClipFramePlugin?.close()'),
    );
    final repeatedSetup = _withoutComments(
      _body(appDelegate, 'private func configureIosNotificationOpenBridgeFromRootViewController('),
    );
    expect(repeatedSetup, isNot(contains('StickerClipFrame')));
    expect(repeatedSetup, isNot(contains('stickerClipFrame')));
  });

  test('Xcode explicitly builds the helper and the native registration tests', () {
    final project = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    final objects = _pbxObjects(project);
    _expectMembership(objects, 'StickerClipFrameBridge.swift', 'Runner');
    if (File('ios/Runner/StickerClipFramePlugin.swift').existsSync()) {
      _expectMembership(objects, 'StickerClipFramePlugin.swift', 'Runner');
    }
    _expectMembership(objects, 'StickerClipFramePluginTests.swift', 'RunnerTests');
  });
}

String _withoutComments(String source) => source
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

String _body(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, greaterThanOrEqualTo(0), reason: 'Missing $signature');
  final open = source.indexOf('{', start);
  expect(open, greaterThanOrEqualTo(0), reason: 'Missing body for $signature');
  var depth = 1;
  for (var i = open + 1; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') depth--;
    if (depth == 0) return source.substring(open + 1, i);
  }
  throw StateError('Unterminated body for $signature');
}

int _braceDepth(String source) =>
    '{'.allMatches(source).length - '}'.allMatches(source).length;

Map<String, String> _pbxObjects(String source) {
  final result = <String, String>{};
  final headers = RegExp(
    r'^\s*([A-Fa-f0-9]{24}) /\* [^\n]*? \*/ = \{',
    multiLine: true,
  );
  for (final match in headers.allMatches(source)) {
    result[match.group(1)!] = _body(source.substring(match.start), match.group(0)!);
  }
  return result;
}

void _expectMembership(Map<String, String> objects, String file, String targetName) {
  final reference = objects.entries.singleWhere(
    (e) => e.value.contains('isa = PBXFileReference;') &&
        RegExp(r'\bpath = "?' + RegExp.escape(file) + r'"?;').hasMatch(e.value),
    orElse: () => throw TestFailure('$file has no unique PBXFileReference'),
  );
  final group = objects.entries.singleWhere(
    (e) => e.value.contains('isa = PBXGroup;') &&
        RegExp(r'\b(?:path|name) = "?' + targetName + r'"?;').hasMatch(e.value),
  );
  expect(_withoutComments(group.value), contains(reference.key));
  final target = objects.entries.singleWhere(
    (e) => e.value.contains('isa = PBXNativeTarget;') &&
        RegExp(r'\bname = "?' + targetName + r'"?;').hasMatch(e.value),
  );
  final sourcesId = RegExp(r'([A-Fa-f0-9]{24}) /\* Sources \*/')
      .firstMatch(target.value)?.group(1);
  expect(sourcesId, isNotNull, reason: '$targetName must have an explicit Sources phase');
  final sources = objects[sourcesId];
  expect(sources, isNotNull);
  expect(sources, contains('isa = PBXSourcesBuildPhase;'));
  final buildFiles = objects.entries.where(
    (e) => e.value.contains('isa = PBXBuildFile;') &&
        RegExp(r'\bfileRef = ' + reference.key + r'\b').hasMatch(e.value),
  );
  expect(
    buildFiles.any((e) => _withoutComments(sources!).contains(e.key)),
    isTrue,
    reason: '$file must be an actual member of $targetName Sources, not only a comment/reference',
  );
}
