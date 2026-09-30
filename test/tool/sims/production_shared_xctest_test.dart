import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../integration_test/support/production_shared_xctest.dart';
import '../../../tool/sims/build_orchestrator.dart';

const selector = 'RunnerUITests/NotificationTapUITests/testColdNotificationTap';
Map<String, dynamic> summary() => {
  'result': 'Passed',
  'totalTestCount': 1,
  'passedTests': 1,
  'failedTests': 0,
  'skippedTests': 0,
};
Map<String, dynamic> tree() => {
  'name': 'NotificationTapUITests',
  'children': [
    {
      'nodeType': 'Test Case',
      'name': 'testColdNotificationTap()',
      'result': 'Passed',
    },
  ],
};

class _PreparedFixture {
  _PreparedFixture(this.root);
  final Directory root;
  late Directory bundle;
  late ProductionSharedXCTest owner;
  final fixtureDirectories = <String>[];
  final commands = <List<String>>[];
  var failure = false;
  var omitResult = false;
  var restored = 0;
  var cleanupPass = true;
  var verificationPass = true;
  String currentSelector = selector;

  Future<void> create() async {
    bundle = Directory('${root.path}/bundle')..createSync();
    void file(String path, {bool executable = false}) {
      final f = File('${bundle.path}/$path');
      f.parent.createSync(recursive: true);
      f.writeAsStringSync('fixture');
      if (executable) Process.runSync('chmod', ['755', f.path]);
    }

    const product = 'TestProducts/Release-iphoneos';
    for (final entry in {
      '$product/Runner.app': 'Runner',
      '$product/Runner.app/PlugIns/Share Extension.appex': 'Share Extension',
      '$product/Runner.app/PlugIns/NotificationService.appex':
          'NotificationService',
      '$product/RunnerUITests-Runner.app': 'RunnerUITests-Runner',
      '$product/RunnerUITests-Runner.app/PlugIns/RunnerUITests.xctest':
          'RunnerUITests',
    }.entries) {
      file('${entry.key}/Info.plist');
      file('${entry.key}/${entry.value}', executable: true);
    }
    file('TestProducts/Runner_iphoneos.xctestrun');
    file('RunnerUITests.xctestrun');
    File('${bundle.path}/bundle_manifest.json').writeAsStringSync(
      jsonEncode({
        'schema': 'mknoon.sims.ios-device-production-bundle.v1',
        'profileId': 'ios.device.production',
        'applicationApp': '$product/Runner.app',
        'testProducts': 'TestProducts',
        'xctestrun': 'RunnerUITests.xctestrun',
        'centralCompileCommands': 1,
        'logicalBuildCount': 1,
        'childBuildCount': 0,
      }),
    );
    final digest = sha256
        .convert(simsPreparedArtifactDigestBytes(bundle))
        .toString();
    final attestation = File('${root.path}/attestation.json')
      ..writeAsStringSync(
        jsonEncode({
          'schemaVersion': 1,
          'profileId': 'ios.device.production',
          'inputDigest': 'a' * 64,
          'artifactDigest': digest,
          'artifactPath': bundle.path,
          'redactedCommand': ['xcodebuild', 'build-for-testing'],
          'createdAt': '2026-09-27T00:00:00Z',
        }),
      );
    owner = await ProductionSharedXCTest.open(
      bundle: bundle,
      attestationFile: attestation,
      profileId: 'ios.device.production',
      expectedInputDigest: 'a' * 64,
      expectedArtifactDigest: digest,
      codesignRunner: (exe, args, env) async => ProcessResult(1, 0, '', ''),
      process: (exe, args) async {
        commands.add([exe, ...args]);
        if (exe == 'plutil') {
          if (args.contains('json')) {
            return ProcessResult(
              1,
              0,
              jsonEncode({
                'RunnerUITests': {
                  'TestBundlePath':
                      '__TESTROOT__/Release-iphoneos/RunnerUITests-Runner.app/PlugIns/RunnerUITests.xctest',
                },
              }),
              '',
            );
          }
          return ProcessResult(1, 0, '', '');
        }
        if (exe == 'xcodebuild') {
          if (!omitResult) {
            Directory(args[args.indexOf('-resultBundlePath') + 1]).createSync();
          }
          return ProcessResult(1, failure ? 1 : 0, 'test output', '');
        }
        final value = args.contains('summary') ? summary() : tree();
        if (!args.contains('summary')) {
          value['children'][0]['name'] = '${currentSelector.split('/').last}()';
        }
        return ProcessResult(1, 0, jsonEncode(value), '');
      },
    );
  }

  Future<Map<String, Object?>> run(String id) => owner.runSelector(
    selector: currentSelector,
    deviceId: '00008110-00184D622289801E',
    fixtureId: id,
    output: root,
    prepare: (directory) async {
      fixtureDirectories.add(directory.path);
      File(
        '${directory.path}/fixture.json',
      ).writeAsStringSync(jsonEncode({'id': id}));
      return {'MKNOON_TEST_FIXTURE_ID': id};
    },
    verify: (directory) async => {
      'fixtureId': id,
      'selector': currentSelector,
      'status': verificationPass ? 'PASS' : 'FAIL',
    },
    restore: (directory) async {
      restored++;
      return {
        'fixtureId': id,
        'status': cleanupPass ? 'PASS' : 'FAIL',
        'exactRestorationVerified': cleanupPass,
      };
    },
  );
}

void main() {
  group('prepared selector execution', () {
    late _PreparedFixture fixture;
    setUp(() async {
      fixture = _PreparedFixture(
        Directory.systemTemp.createTempSync('shared-xctest-execution-'),
      );
      await fixture.create();
    });
    tearDown(() => fixture.root.deleteSync(recursive: true));
    test(
      'two runs share exact products and isolate fixtures, plist and results',
      () async {
        final before = sha256
            .convert(simsPreparedArtifactDigestBytes(fixture.bundle))
            .toString();
        final first = await fixture.run('first');
        fixture.currentSelector =
            'RunnerUITests/NotificationTapUITests/testNotificationTap';
        final second = await fixture.run('second');
        expect(first['artifactDigest'], second['artifactDigest']);
        expect(first['resultBundle'], isNot(second['resultBundle']));
        expect(fixture.fixtureDirectories.toSet(), hasLength(2));
        expect(fixture.restored, 2);
        expect(
          sha256
              .convert(simsPreparedArtifactDigestBytes(fixture.bundle))
              .toString(),
          before,
        );
        final xcode = fixture.commands
            .where((c) => c.first == 'xcodebuild')
            .toList();
        expect(xcode, hasLength(2));
        expect(xcode[0], contains('-only-testing:$selector'));
        expect(xcode[1], contains('-only-testing:${fixture.currentSelector}'));
        for (final command in xcode) {
          expect(command[1], 'test-without-building');
          expect(
            command.where((arg) => arg.startsWith('-only-testing:')),
            hasLength(1),
          );
          expect(
            command,
            contains('platform=iOS,id=00008110-00184D622289801E'),
          );
          expect(command, isNot(contains('build')));
        }
      },
    );
    test(
      'fixture reuse rejected before preparing or launching a second test',
      () async {
        await fixture.run('same');
        final count = fixture.commands.length;
        await expectLater(fixture.run('same'), throwsStateError);
        expect(fixture.commands, hasLength(count));
        expect(fixture.fixtureDirectories, hasLength(1));
      },
    );
    for (final cause in [
      'process',
      'result',
      'verification',
      'cleanup',
      'changed product',
    ]) {
      test(
        '$cause failure cannot mint a PASS and still restores fixtures',
        () async {
          if (cause == 'process') fixture.failure = true;
          if (cause == 'result') fixture.omitResult = true;
          if (cause == 'verification') fixture.verificationPass = false;
          if (cause == 'cleanup') fixture.cleanupPass = false;
          if (cause == 'changed product') {
            File('${fixture.bundle.path}/changed').writeAsStringSync('drift');
          }
          await expectLater(fixture.run('failed'), throwsStateError);
          expect(fixture.restored, 1);
          expect(
            fixture.root
                .listSync(recursive: true)
                .whereType<File>()
                .where((f) => f.path.endsWith('/receipt.json')),
            isEmpty,
          );
        },
      );
    }
  });

  test('requires exact selector and zero skipped XCTest cases', () {
    expect(validateSharedXCTestReceipt(selector, summary(), tree()), isEmpty);
  });
  for (final field in [
    'totalTestCount',
    'passedTests',
    'failedTests',
    'skippedTests',
  ]) {
    test('rejects altered $field', () {
      final value = summary();
      value[field] = 2;
      expect(validateSharedXCTestReceipt(selector, value, tree()), isNotEmpty);
    });
  }
  test('same method in foreign class is rejected', () {
    final value = tree();
    value['name'] = 'ForeignTests';
    expect(validateSharedXCTestReceipt(selector, summary(), value), isNotEmpty);
  });
  test('duplicate method receipts are rejected', () {
    final value = tree();
    value['children'].add(value['children'][0]);
    expect(validateSharedXCTestReceipt(selector, summary(), value), isNotEmpty);
  });
  test('missing and skipped method receipts are rejected', () {
    expect(validateSharedXCTestReceipt(selector, summary(), {}), isNotEmpty);
    final value = tree();
    value['children'][0]['result'] = 'Skipped';
    expect(validateSharedXCTestReceipt(selector, summary(), value), isNotEmpty);
  });
  test(
    'directory attestation includes content, permissions and links',
    () async {
      final root = Directory.systemTemp.createTempSync('shared-xctest-digest-');
      addTearDown(() => root.deleteSync(recursive: true));
      final file = File('${root.path}/product')..writeAsStringSync('one');
      String digest() =>
          sha256.convert(simsPreparedArtifactDigestBytes(root)).toString();
      final first = digest();
      file.writeAsStringSync('two');
      expect(digest(), isNot(first));
      final second = digest();
      await Process.run('chmod', ['700', file.path]);
      expect(digest(), isNot(second));
      final third = digest();
      Link('${root.path}/link').createSync('product');
      expect(digest(), isNot(third));
    },
  );
  for (final mutation in [
    'profile',
    'inputs',
    'artifact',
    'schema',
    'missing',
  ]) {
    test('rejects $mutation mismatch before any XCTest process', () async {
      final root = Directory.systemTemp.createTempSync(
        'shared-xctest-binding-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final bundle = Directory('${root.path}/bundle')..createSync();
      File('${bundle.path}/member').writeAsStringSync('prepared');
      final digest = sha256
          .convert(simsPreparedArtifactDigestBytes(bundle))
          .toString();
      final input = 'a' * 64;
      final attestation = File('${root.path}/attestation.json')
        ..writeAsStringSync(
          jsonEncode({
            'schemaVersion': mutation == 'schema' ? 9 : 1,
            'profileId': mutation == 'profile'
                ? 'ios.device.group_media_269'
                : 'ios.device.production',
            'inputDigest': mutation == 'inputs' ? 'b' * 64 : input,
            'artifactDigest': mutation == 'artifact' ? 'c' * 64 : digest,
            'artifactPath': bundle.path,
            'redactedCommand': ['xcodebuild', 'build-for-testing'],
            'createdAt': '2026-09-27T00:00:00Z',
          }),
        );
      if (mutation == 'missing') bundle.deleteSync(recursive: true);
      var calls = 0;
      await expectLater(
        ProductionSharedXCTest.open(
          bundle: bundle,
          attestationFile: attestation,
          profileId: 'ios.device.production',
          expectedInputDigest: input,
          expectedArtifactDigest: digest,
          process: (executable, args) async {
            calls++;
            return ProcessResult(1, 0, '', '');
          },
        ),
        throwsStateError,
      );
      expect(calls, 0);
    });
  }
}
