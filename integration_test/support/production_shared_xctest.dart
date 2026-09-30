import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../tool/sims/build_cache.dart';
import '../../tool/sims/build_orchestrator.dart';
import 'ios_xctestrun_relocator.dart';

typedef SharedXCTestProcess =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// Existing fresh-build owners remain intact. This additive consumer accepts
/// only a centrally attested compatible physical-iOS app/XCTest bundle and has
/// no build command or build fallback. Callers retain device leases and own
/// scenario-specific fixture preparation, assertions and exact restoration.
final class ProductionSharedXCTest {
  ProductionSharedXCTest._(
    this.bundle,
    this.products,
    this.application,
    this.xctestrun,
    this.attestation,
    this.runner,
  );

  final Directory bundle, products, application;
  final File xctestrun;
  final BuildAttestation attestation;
  final SharedXCTestProcess runner;
  final _fixtureIds = <String>{};

  static Future<ProductionSharedXCTest> open({
    required Directory bundle,
    required File attestationFile,
    required String profileId,
    required String expectedInputDigest,
    required String expectedArtifactDigest,
    SharedXCTestProcess? process,
    SimsIosCodesignRunner? codesignRunner,
  }) async {
    const profiles = {
      'ios.device.production': 'mknoon.sims.ios-device-production-bundle.v1',
      'ios.device.group_media_269':
          'mknoon.sims.ios-device-group-media-269-bundle.v1',
    };
    if (!profiles.containsKey(profileId) || !bundle.existsSync()) {
      throw StateError('compatible prepared XCTest bundle missing');
    }
    final attestation = BuildAttestation.fromJson(
      Map<String, Object?>.from(
        jsonDecode(await attestationFile.readAsString()) as Map,
      ),
    );
    final actualDigest = sha256
        .convert(simsPreparedArtifactDigestBytes(bundle))
        .toString();
    if (attestation.schemaVersion != 1 ||
        attestation.profileId != profileId ||
        attestation.inputDigest != expectedInputDigest ||
        attestation.artifactDigest != expectedArtifactDigest ||
        actualDigest != expectedArtifactDigest) {
      throw StateError(
        'prepared XCTest source/configuration/artifact binding rejected',
      );
    }
    final manifest =
        jsonDecode(
              await File('${bundle.path}/bundle_manifest.json').readAsString(),
            )
            as Map;
    if (manifest['schema'] != profiles[profileId] ||
        manifest['profileId'] != profileId ||
        manifest['logicalBuildCount'] != 1 ||
        manifest['centralCompileCommands'] != 1 ||
        manifest['childBuildCount'] != 0 ||
        manifest['testProducts'] != 'TestProducts' ||
        manifest['xctestrun'] != 'RunnerUITests.xctestrun') {
      throw StateError('prepared XCTest product manifest rejected');
    }
    final products = Directory('${bundle.path}/TestProducts');
    final validation = await validateSimsIosDeviceBuildProducts(
      products: products,
      codesignRunner: codesignRunner,
    );
    if (!validation.ok ||
        manifest['applicationApp'] !=
            'TestProducts/${validation.relativeApplication}') {
      throw StateError(
        'prepared XCTest product validation rejected: ${validation.detail}',
      );
    }
    final xctestrun = File('${bundle.path}/RunnerUITests.xctestrun');
    if (!xctestrun.existsSync() || await xctestrun.length() == 0) {
      throw StateError('prepared XCTest run file missing');
    }
    return ProductionSharedXCTest._(
      bundle,
      products,
      validation.application!,
      xctestrun,
      attestation,
      process ?? (executable, args) => Process.run(executable, args),
    );
  }

  /// Fixture callbacks are mandatory: sharing compilation does not share test
  /// state. Cleanup runs after preparation failures and failed/missing results.
  /// The caller must verify availability and own this pinned USB device.
  Future<Map<String, Object?>> runSelector({
    required String selector,
    required String deviceId,
    required String fixtureId,
    required Directory output,
    required Future<Map<String, String>> Function(Directory directory) prepare,
    required Future<Map<String, Object?>> Function(Directory directory) verify,
    required Future<Map<String, Object?>> Function(Directory directory) restore,
  }) async {
    final exactSelector = validatedIosUiTestSelector(selector);
    if (!RegExp(r'^[A-Za-z0-9-]+$').hasMatch(deviceId) ||
        !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(fixtureId) ||
        !_fixtureIds.add(fixtureId)) {
      throw StateError('pinned target and unused fixture identity required');
    }
    final attempt = await output.createTemp('xctest-$fixtureId-');
    final fixtures = await Directory('${attempt.path}/fixtures').create();
    final resultBundle = Directory('${attempt.path}/result.xcresult');
    Map<String, Object?>? receipt;
    try {
      final environment = await prepare(fixtures);
      if (environment.isEmpty) {
        throw StateError('selector fixture environment missing');
      }
      // Recheck the immutable product immediately before each selector. A
      // prior successful selector cannot authorize later changed products.
      if (sha256.convert(simsPreparedArtifactDigestBytes(bundle)).toString() !=
          attestation.artifactDigest) {
        throw StateError('prepared XCTest bundle changed');
      }
      final read = await runner('plutil', [
        '-convert',
        'json',
        '-o',
        '-',
        xctestrun.path,
      ]);
      if (read.exitCode != 0) {
        throw StateError('cannot read prepared XCTest plist');
      }
      final relocated = relocateIosXctestrun(
        plist: Map<String, Object?>.from(jsonDecode('${read.stdout}') as Map),
        cachedProducts: products,
        cachedApplication: application,
        uiEnvironment: environment,
        uiTargetBundleIdentifier:
            attestation.profileId == 'ios.device.group_media_269'
            ? 'com.mknoon.sims.groupmedia269'
            : 'com.mknoon.app',
      );
      if (relocated.uiTargetsPatched != 1) {
        throw StateError('exactly one UI target required');
      }
      final plist = File('${attempt.path}/selector.xctestrun');
      await plist.writeAsString(jsonEncode(relocated.plist));
      final convert = await runner('plutil', ['-convert', 'xml1', plist.path]);
      if (convert.exitCode != 0) {
        throw StateError('cannot encode selector XCTest plist');
      }
      final result = await runner(
        'xcodebuild',
        iosTestWithoutBuildingArguments(
          xctestrun: plist,
          receiverDeviceId: deviceId,
          selector: exactSelector,
          resultBundle: resultBundle,
        ),
      );
      await File(
        '${attempt.path}/xcodebuild.log',
      ).writeAsString('${result.stdout}\n${result.stderr}');
      if (result.exitCode != 0 || !resultBundle.existsSync()) {
        throw StateError('selector failed or result bundle missing');
      }
      final summary = await runner('xcrun', [
        'xcresulttool',
        'get',
        'test-results',
        'summary',
        '--path',
        resultBundle.path,
        '--compact',
      ]);
      final tests = await runner('xcrun', [
        'xcresulttool',
        'get',
        'test-results',
        'tests',
        '--path',
        resultBundle.path,
        '--compact',
      ]);
      await File(
        '${attempt.path}/summary.json',
      ).writeAsString('${summary.stdout}');
      await File('${attempt.path}/tests.json').writeAsString('${tests.stdout}');
      if (summary.exitCode != 0 ||
          tests.exitCode != 0 ||
          validateSharedXCTestReceipt(
            exactSelector,
            jsonDecode('${summary.stdout}'),
            jsonDecode('${tests.stdout}'),
          ).isNotEmpty) {
        throw StateError(
          'selector has missing, foreign, duplicate or non-passing tests',
        );
      }
      final fixtureEvidence = await verify(fixtures);
      if (fixtureEvidence['fixtureId'] != fixtureId ||
          fixtureEvidence['selector'] != exactSelector ||
          fixtureEvidence['status'] != 'PASS') {
        throw StateError('selector fixture assertions missing or unbound');
      }
      receipt = {
        'selector': exactSelector,
        'fixtureId': fixtureId,
        'deviceId': deviceId,
        'profileId': attestation.profileId,
        'inputDigest': attestation.inputDigest,
        'artifactDigest': attestation.artifactDigest,
        'childBuilds': 0,
        'resultBundle': resultBundle.path,
        'fixtureEvidence': fixtureEvidence,
        'status': 'PASS',
      };
    } catch (error, stack) {
      await File(
        '${attempt.path}/first-failure.txt',
      ).writeAsString('$error\n$stack');
      rethrow;
    } finally {
      try {
        final cleanup = await restore(fixtures);
        if (cleanup['status'] != 'PASS' ||
            cleanup['fixtureId'] != fixtureId ||
            cleanup['exactRestorationVerified'] != true) {
          throw StateError('selector fixture restoration not verified');
        }
        await File(
          '${attempt.path}/cleanup.json',
        ).writeAsString(jsonEncode({'status': 'PASS', 'fixtureId': fixtureId}));
      } catch (error, stack) {
        await File('${attempt.path}/cleanup.json').writeAsString(
          jsonEncode({
            'status': 'FAIL',
            'fixtureId': fixtureId,
            'detail': '$error',
          }),
        );
        Error.throwWithStackTrace(error, stack);
      }
    }
    await File(
      '${attempt.path}/receipt.json',
    ).writeAsString(jsonEncode(receipt));
    return receipt;
  }
}

List<String> validateSharedXCTestReceipt(
  String selector,
  Object? summary,
  Object? tree,
) {
  final failures = <String>[];
  if (summary is! Map ||
      summary['result'] != 'Passed' ||
      summary['totalTestCount'] != 1 ||
      summary['passedTests'] != 1 ||
      summary['failedTests'] != 0 ||
      summary['skippedTests'] != 0) {
    failures.add('exactly one passing test and zero skips required');
  }
  final cases = <Map>[];
  final classes = <List<String>>[];
  void walk(Object? value, List<String> ancestors) {
    if (value is Map) {
      if (value['nodeType'] == 'Test Case') {
        cases.add(value);
        classes.add(ancestors);
      }
      for (final child in value.values) {
        walk(child, [
          ...ancestors,
          if (value['name'] is String) value['name'] as String,
        ]);
      }
    } else if (value is List) {
      for (final child in value) {
        walk(child, ancestors);
      }
    }
  }

  walk(tree, const []);
  final method = selector.split('/').last;
  final testClass = selector.split('/')[1];
  if (cases.length != 1 ||
      cases.single['result'] != 'Passed' ||
      !{method, '$method()'}.contains(cases.single['name']) ||
      !classes.single.contains(testClass)) {
    failures.add('exact named XCTest method receipt required');
  }
  return failures;
}
