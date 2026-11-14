import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source callsite contract only. Native bridge/plugin tests own messenger,
/// cancellation, replacement and detach behavior; this does not run an engine.
void main() {
  final android = _withoutComments(
    File(
      'android/app/src/main/kotlin/com/mknoon/app/MainActivity.kt',
    ).readAsStringSync(),
  );
  final ios = _withoutComments(
    File('ios/Runner/AppDelegate.swift').readAsStringSync(),
  );
  final appDelegate = ios.substring(ios.indexOf('class AppDelegate:'));

  test('Android configures cutout once on the foreground engine messenger', () {
    final body = _body(android, 'override fun configureFlutterEngine(');
    final setup = RegExp(
      r'\bsetupStickerCutoutBridge\(\s*'
      r'flutterEngine\.dartExecutor\.binaryMessenger\s*,?\s*\)',
    );
    expect(setup.allMatches(body), hasLength(1));
    expect(
      RegExp(r'\bsetupStickerCutoutBridge\s*\(').allMatches(body),
      hasLength(1),
    );
    expect(_braceDepth(body.substring(0, setup.firstMatch(body)!.start)), 0);
  });

  test(
    'Android detach closes clip then cutout before other cleanup branches',
    () {
      final body = _body(android, 'override fun cleanUpFlutterEngine(');
      expect(
        body,
        matches(
          RegExp(
            r'^\s*closeStickerClipFrameBridge\(\s*\)\s*;?\s*'
            r'closeStickerCutoutBridge\(\s*\)',
          ),
        ),
        reason:
            'Keep clip cleanup first and make cutout cleanup unconditional '
            'before the RELEASED early return and deferred call-runtime shutdown.',
      );
    },
  );

  test(
    'iOS implicit engine registers one retained cutout plugin beside clip',
    () {
      final body = _body(
        appDelegate,
        'func didInitializeImplicitFlutterEngine(',
      );
      final registrarPattern = RegExp(
        r'if\s+let\s+(\w+)\s*=\s*engineBridge\.pluginRegistry\.registrar\(\s*'
        r'forPlugin:\s*"StickerCutoutPlugin"\s*\)',
      );
      expect(registrarPattern.allMatches(body), hasLength(1));
      final registration = registrarPattern.firstMatch(body)!;
      expect(_braceDepth(body.substring(0, registration.start)), 0);
      final registrar = registration.group(1)!;
      final block = _body(
        body.substring(registration.start),
        registration.group(0)!,
      );
      final constructionPattern = RegExp(
        r'let\s+(\w+)\s*=\s*StickerCutoutPlugin\(\s*messenger:\s*' +
            registrar +
            r'\.messenger\(\s*\)\s*,?\s*\)',
      );
      expect(constructionPattern.allMatches(block), hasLength(1));
      final owner = constructionPattern.firstMatch(block)!.group(1)!;
      expect(
        RegExp(
          r'\b' + registrar + r'\.publish\(\s*' + owner + r'\s*\)',
        ).allMatches(block),
        hasLength(1),
      );
      expect(
        block,
        matches(RegExp(r'\bstickerCutoutPlugin\s*=\s*' + owner + r'\b')),
      );
      expect(
        appDelegate,
        matches(
          RegExp(r'\bvar\s+stickerCutoutPlugin:\s*StickerCutoutPlugin\?'),
        ),
      );
      expect(body, matches(RegExp(r'forPlugin:\s*"StickerClipFramePlugin"')));
      expect(
        RegExp(r'forPlugin:\s*"StickerCutoutPlugin"').allMatches(appDelegate),
        hasLength(1),
      );
      expect(
        RegExp(r'\bStickerCutoutPlugin\(\s*messenger:').allMatches(appDelegate),
        hasLength(1),
      );
      expect(
        appDelegate,
        isNot(matches(RegExp(r'\bStickerCutoutBridge\s*\('))),
      );
    },
  );

  test('iOS retires the old cutout owner before replacement and on deinit', () {
    final body = _body(appDelegate, 'func didInitializeImplicitFlutterEngine(');
    final close = body.indexOf('stickerCutoutPlugin?.close()');
    final clear = RegExp(
      r'\bstickerCutoutPlugin\s*=\s*nil\b',
    ).firstMatch(body)?.start;
    final create = RegExp(
      r'\bStickerCutoutPlugin\(\s*messenger:',
    ).firstMatch(body)?.start;
    expect(close, greaterThanOrEqualTo(0));
    expect(clear, isNotNull);
    expect(create, isNotNull);
    expect(clear!, greaterThan(close));
    expect(create!, greaterThan(clear));
    expect(
      _braceDepth(body.substring(0, close)),
      0,
      reason:
          'Retire the previous owner even when the replacement registrar is unavailable.',
    );
    expect(
      _body(appDelegate, 'deinit'),
      contains('stickerCutoutPlugin?.close()'),
    );
  });
}

// The same bounded-body extraction pattern as the existing clip registration
// contract. Comments are removed before assertions so they cannot satisfy calls.
String _withoutComments(String source) => source
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

String _body(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, greaterThanOrEqualTo(0), reason: 'Missing $signature');
  final open = source.indexOf('{', start);
  expect(open, greaterThanOrEqualTo(0), reason: 'Missing body for $signature');
  var depth = 1;
  for (var index = open + 1; index < source.length; index++) {
    if (source[index] == '{') depth++;
    if (source[index] == '}') depth--;
    if (depth == 0) return source.substring(open + 1, index);
  }
  throw StateError('Unterminated body for $signature');
}

int _braceDepth(String source) =>
    '{'.allMatches(source).length - '}'.allMatches(source).length;
