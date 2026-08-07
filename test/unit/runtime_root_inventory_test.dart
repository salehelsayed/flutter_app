import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/runtime_roots/runtime_root_inventory.dart';

void main() {
  test(
    'resolves package relative export part conditional and cyclic directives without comment/string decoys',
    () {
      final fixture = _Fixture(<String, String>{
        'pubspec.yaml': 'name: fixture_app\n',
        'lib/main.dart': '''
import 'entry.dart'
    deferred
    as entry
    show run;
void main() => entry.run();
''',
        'lib/entry.dart': '''
import 'package:fixture_app/src/package_target.dart';
import './src/../src/relative_target.dart';
import 'src/default_target.dart'
  if (dart.library.io) 'src/io_target.dart'
  if (dart.library.html) 'src/web_target.dart';
import 'src/cycle_a.dart';
export 'src/exported.dart'
  show Exported;
part 'src/piece.dart';
// import 'src/comment_decoy.dart';
const decoy = "export 'src/string_decoy.dart';";
void run() => cycleA();
''',
        'lib/src/package_target.dart': 'class PackageTarget {}\n',
        'lib/src/relative_target.dart': 'class RelativeTarget {}\n',
        'lib/src/default_target.dart': 'class DefaultTarget {}\n',
        'lib/src/io_target.dart': 'class IoTarget {}\n',
        'lib/src/web_target.dart': 'class WebTarget {}\n',
        'lib/src/exported.dart': 'class Exported {}\n',
        'lib/src/piece.dart': "part of '../entry.dart';\n",
        'lib/src/cycle_a.dart': "import 'cycle_b.dart';\nvoid cycleA() {}\n",
        'lib/src/cycle_b.dart': "import 'cycle_a.dart';\n",
      });
      addTearDown(fixture.dispose);

      final result = fixture.scan();
      expect(result.trustworthy, isTrue, reason: _issues(result));
      for (final path in <String>[
        'lib/entry.dart',
        'lib/src/package_target.dart',
        'lib/src/relative_target.dart',
        'lib/src/default_target.dart',
        'lib/src/io_target.dart',
        'lib/src/web_target.dart',
        'lib/src/exported.dart',
        'lib/src/piece.dart',
        'lib/src/cycle_a.dart',
        'lib/src/cycle_b.dart',
      ]) {
        expect(_file(result, path).bucket, ReachabilityBucket.mainReachable);
      }
      expect(
        result.files.map((entry) => entry.path),
        isNot(contains('lib/src/comment_decoy.dart')),
      );

      for (final invalid in <String, String>{
        'wrong-case': "import 'src/Package_Target.dart';\n",
        'unresolved': "import 'src/missing.dart';\n",
        'absolute': "import '/tmp/outside.dart';\n",
        'escaping': "import '../../outside.dart';\n",
        'malformed': "import 'src/package_target.dart'\nvoid broken( {\n",
      }.entries) {
        fixture.write('lib/main.dart', invalid.value);
        final failed = fixture.scan();
        expect(
          failed.trustworthy,
          isFalse,
          reason: '${invalid.key}: ${_issues(failed)}',
        );
      }
    },
  );

  test(
    'main manual tooling test and unrooted buckets stay separate from dispositions',
    () {
      final fixture = _Fixture(<String, String>{
        'pubspec.yaml': 'name: roots_fixture\n',
        'lib/main.dart': "import 'shared.dart';\nvoid main() {}\n",
        'lib/shared.dart': 'class Shared {}\n',
        'lib/manual_only.dart': 'class ManualOnly {}\n',
        'lib/tool_only.dart': 'class ToolOnly {}\n',
        'lib/test_only.dart': 'class TestOnly {}\n',
        'lib/island_a.dart': "import 'island_b.dart';\n",
        'lib/island_b.dart': 'class IslandB {}\n',
        'lib/non_root_script_dependency.dart': 'class NonRootDependency {}\n',
        'lib/smoke_test_main.dart': '''
/// Run with: flutter run -t lib/smoke_test_main.dart
import 'manual_only.dart';
import 'shared.dart';
void main() {}
''',
        'lib/smoke_test_messages.dart': '''
/// Run with: flutter run -t lib/smoke_test_messages.dart
void main() {}
''',
        'lib/smoke_test_restore.dart': '''
/// Run with: flutter run -t lib/smoke_test_restore.dart
void main() {}
''',
        'tool/run.dart': '''
import 'package:roots_fixture/tool_only.dart';
import 'package:roots_fixture/shared.dart';
void main() {}
''',
        'scripts/run.sh': '''
#!/usr/bin/env bash
flutter run --target tool/run.dart
''',
        'test/only_test.dart': '''
import 'package:roots_fixture/test_only.dart';
import 'package:roots_fixture/shared.dart';
void main() {}
''',
        'integration_test/scripts/not_a_root.dart': '''
import 'package:roots_fixture/non_root_script_dependency.dart';
void main() {}
''',
        'packages/nested/pubspec.yaml': 'name: nested\n',
        'packages/nested/lib/nested.dart': 'class NestedLibrary {}\n',
        'packages/nested/test/nested_test.dart': '''
import 'package:roots_fixture/island_a.dart';
void main() {}
''',
        'third_party/vendor/pubspec.yaml': 'name: vendor\n',
        'third_party/vendor/lib/vendor.dart': 'class VendorLibrary {}\n',
        'third_party/vendor/tool/run.dart': '''
import 'package:roots_fixture/island_a.dart';
void main() {}
''',
      });
      addTearDown(fixture.dispose);
      final manifest = _manifest(
        manualRoots: _manualRoots(),
        externalEntrypoints: <Map<String, Object?>>[
          _external(
            'tool/run.dart',
            seedsTooling: true,
            evidence: <Map<String, Object?>>[
              <String, Object?>{
                'kind': 'command-argument',
                'source': 'scripts/run.sh',
                'option': '--target',
                'target': 'tool/run.dart',
              },
            ],
          ),
          _external('integration_test/scripts/not_a_root.dart'),
        ],
        declarations: <Map<String, Object?>>[
          _declaration('lib/manual_only.dart', disposition: 'candidate'),
          _declaration(
            'lib/tool_only.dart',
            disposition: 'explained-root',
            rootKinds: <String>['tooling'],
            evidence: <Map<String, Object?>>[
              <String, Object?>{'kind': 'computed-origin', 'origin': 'tooling'},
            ],
          ),
          _declaration(
            'lib/test_only.dart',
            disposition: 'explained-root',
            evidence: <Map<String, Object?>>[
              <String, Object?>{
                'kind': 'computed-origin',
                'origin': 'test/integration',
              },
            ],
          ),
          _declaration('lib/island_a.dart', disposition: 'candidate'),
          _declaration('lib/island_b.dart', disposition: 'candidate'),
          _declaration(
            'lib/non_root_script_dependency.dart',
            disposition: 'candidate',
          ),
          for (final path in RuntimeRootInventory.allowedManualRootPaths)
            _declaration(
              path,
              disposition: 'explained-root',
              rootKinds: <String>['manual-entrypoint'],
              evidence: <Map<String, Object?>>[
                <String, Object?>{'kind': 'manual-policy', 'target': path},
              ],
            ),
        ],
      );

      final result = fixture.scan(manifest);
      expect(result.trustworthy, isTrue, reason: _issues(result));
      expect(_file(result, 'lib/shared.dart').origins, <RuntimeRootOrigin>{
        RuntimeRootOrigin.main,
        RuntimeRootOrigin.manual,
        RuntimeRootOrigin.tooling,
        RuntimeRootOrigin.testIntegration,
      });
      expect(
        _file(result, 'lib/shared.dart').bucket,
        ReachabilityBucket.mainReachable,
      );
      expect(
        _file(result, 'lib/manual_only.dart').bucket,
        ReachabilityBucket.manualRootReachable,
        reason: 'candidate disposition must not rewrite computed origins',
      );
      expect(
        _file(result, 'lib/tool_only.dart').bucket,
        ReachabilityBucket.toolingReachable,
      );
      expect(
        _file(result, 'lib/test_only.dart').bucket,
        ReachabilityBucket.testIntegrationReachable,
      );
      expect(
        _file(result, 'lib/non_root_script_dependency.dart').bucket,
        ReachabilityBucket.unrooted,
      );
      expect(_file(result, 'lib/island_b.dart').incomingEdges, <String>[
        'lib/island_a.dart',
      ]);
      expect(result.descendantPackageRoots, <String>[
        'packages/nested',
        'third_party/vendor',
      ]);

      final originalManual = fixture.read('lib/smoke_test_main.dart');
      for (final invalidManual in <String, String>{
        'string-only metadata': '''
const runCommand = 'Run with: flutter run -t lib/smoke_test_main.dart';
void main() {}
''',
        'comment after code': '''
void helper() {}
/// Run with: flutter run -t lib/smoke_test_main.dart
void main() {}
''',
        'wrong leading target': '''
/// Run with: flutter run -t lib/smoke_test_restore.dart
void main() {}
''',
      }.entries) {
        fixture.write('lib/smoke_test_main.dart', invalidManual.value);
        final invalid = fixture.scan(manifest);
        expect(
          invalid.issues
              .where(
                (entry) =>
                    entry.code == 'invalid-manual-policy' &&
                    entry.path == 'lib/smoke_test_main.dart',
              )
              .isNotEmpty,
          isTrue,
          reason: '${invalidManual.key}: ${_issues(invalid)}',
        );
        expect(
          _file(
            invalid,
            'lib/smoke_test_main.dart',
          ).origins.contains(RuntimeRootOrigin.manual),
          isFalse,
          reason: invalidManual.key,
        );
      }
      fixture.write('lib/smoke_test_main.dart', originalManual);

      fixture.write(
        'packages/nested/pubspec.yaml',
        'description: missing package name\n',
      );
      final malformedBoundary = fixture.scan(manifest);
      expect(malformedBoundary.trustworthy, isFalse);
      expect(
        malformedBoundary.issues.map((entry) => entry.code),
        contains('invalid-descendant-pubspec'),
      );
      expect(
        malformedBoundary.descendantPackageRoots,
        isNot(contains('packages/nested')),
        reason: 'a malformed pubspec must not hide its descendant Dart tree',
      );
    },
  );

  test(
    'vm and convention callbacks require both declaration and registration evidence',
    () {
      final fixture = _Fixture(<String, String>{
        'pubspec.yaml': 'name: callback_fixture\n',
        'lib/main.dart': '''
import 'background.dart';
void main() {
  FirebaseMessaging.onBackgroundMessage(backgroundHandler);
}
class FirebaseMessaging {
  static void onBackgroundMessage(Object callback) {}
}
''',
        'lib/background.dart': '''
@pragma('vm:entry-point')
void backgroundHandler(Object message) {}
''',
        'lib/native_background.dart': '''
@pragma('vm:entry-point')
void nativeBackgroundHandler(List<String> arguments) {}
''',
        'android/Worker.kt': '''
fun launch(loader: Loader) {
  DartEntrypoint(loader.findAppBundlePath(), "nativeBackgroundHandler")
}
''',
        'test/flutter_test_config.dart': '''
Future<void> testExecutable(Future<void> Function() body) async {
  await body();
}
''',
      });
      addTearDown(fixture.dispose);
      final restricted = <Map<String, Object?>>[
        _restricted(
          'callback.vm',
          'lib/background.dart',
          'vm-callback',
          <Map<String, Object?>>[
            <String, Object?>{
              'kind': 'dart-annotation',
              'source': 'lib/background.dart',
              'symbol': 'backgroundHandler',
              'annotation': 'pragma',
              'value': 'vm:entry-point',
            },
            <String, Object?>{
              'kind': 'dart-call-argument',
              'source': 'lib/main.dart',
              'callee': 'FirebaseMessaging.onBackgroundMessage',
              'argument': 'backgroundHandler',
            },
          ],
        ),
        _restricted(
          'callback.test-config',
          'test/flutter_test_config.dart',
          'convention-callback',
          <Map<String, Object?>>[
            <String, Object?>{
              'kind': 'dart-symbol',
              'source': 'test/flutter_test_config.dart',
              'symbol': 'testExecutable',
            },
          ],
        ),
        _restricted(
          'callback.native-vm',
          'lib/native_background.dart',
          'vm-callback',
          <Map<String, Object?>>[
            <String, Object?>{
              'kind': 'dart-annotation',
              'source': 'lib/native_background.dart',
              'symbol': 'nativeBackgroundHandler',
              'annotation': 'pragma',
              'value': 'vm:entry-point',
            },
            <String, Object?>{
              'kind': 'source-call-token',
              'source': 'android/Worker.kt',
              'callee': 'DartEntrypoint',
              'argument': 'nativeBackgroundHandler',
            },
          ],
        ),
      ];
      final green = fixture.scan(_manifest(restrictedRoots: restricted));
      expect(
        green.issues.where((entry) => entry.code.contains('callback')),
        isEmpty,
        reason: _issues(green),
      );
      expect(green.restrictedRoots, hasLength(3));
      expect(green.restrictedRoots.every((entry) => entry.validated), isTrue);
      expect(
        <String, RuntimeRootKind>{
          for (final entry in green.restrictedRoots) entry.id: entry.rootKind,
        },
        <String, RuntimeRootKind>{
          'callback.test-config': RuntimeRootKind.conventionCallback,
          'callback.vm': RuntimeRootKind.vmCallback,
          'callback.native-vm': RuntimeRootKind.vmCallback,
        },
      );

      fixture.write('android/Worker.kt', '''
// DartEntrypoint(loader.findAppBundlePath(), "nativeBackgroundHandler")
const val decoy = "DartEntrypoint(nativeBackgroundHandler)"
''');
      final nativeRed = fixture.scan(_manifest(restrictedRoots: restricted));
      expect(
        nativeRed.issues.map((entry) => entry.code),
        contains('stale-source-call-token'),
      );
      fixture.write('android/Worker.kt', '''
fun launch(loader: Loader) {
  DartEntrypoint(loader.findAppBundlePath(), "nativeBackgroundHandler")
}
''');

      fixture.write('lib/main.dart', '''
import 'background.dart';
// FirebaseMessaging.onBackgroundMessage(backgroundHandler);
const decoy = 'FirebaseMessaging.onBackgroundMessage(backgroundHandler)';
void main() {}
''');
      final red = fixture.scan(_manifest(restrictedRoots: restricted));
      expect(
        red.issues.map((entry) => entry.code),
        contains('stale-dart-call-argument'),
      );
    },
  );

  test(
    'native manifest and principal-class evidence yields native-registration tags',
    () {
      final fixture = _Fixture(<String, String>{
        'pubspec.yaml': 'name: native_fixture\n',
        'lib/main.dart': 'void main() {}\n',
        'android/app/src/main/AndroidManifest.xml': '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <application>
    <activity android:name=".MainActivity" />
    <service android:name=".KeepAliveService" />
    <provider android:name=".MediaProvider" />
  </application>
</manifest>
''',
        'ios/Extension/Info.plist': '''
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>NSExtensionPrincipalClass</key><string>\$(PRODUCT_MODULE_NAME).Service</string>
</dict></plist>
''',
      });
      addTearDown(fixture.dispose);
      final roots = <Map<String, Object?>>[
        _restricted(
          'native.android.activity',
          'android/app/src/main/AndroidManifest.xml',
          'native-registration',
          <Map<String, Object?>>[
            <String, Object?>{
              'kind': 'xml-attribute',
              'source': 'android/app/src/main/AndroidManifest.xml',
              'element': 'activity',
              'attribute': 'android:name',
              'value': '.MainActivity',
            },
          ],
        ),
        _restricted(
          'native.apple.extension',
          'ios/Extension/Info.plist',
          'native-registration',
          <Map<String, Object?>>[
            <String, Object?>{
              'kind': 'plist-key-value',
              'source': 'ios/Extension/Info.plist',
              'key': 'NSExtensionPrincipalClass',
              'value': r'$(PRODUCT_MODULE_NAME).Service',
            },
          ],
        ),
      ];
      final green = fixture.scan(_manifest(restrictedRoots: roots));
      expect(green.issues, isEmpty, reason: _issues(green));
      expect(
        green.restrictedRoots.map((entry) => entry.rootKind).toSet(),
        <RuntimeRootKind>{RuntimeRootKind.nativeRegistration},
      );
      expect(green.restrictedRoots.every((entry) => entry.validated), isTrue);
      fixture.write('android/app/src/main/AndroidManifest.xml', '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
<!-- <activity android:name=".MainActivity" /> -->
<application><activity android:label=".MainActivity" /></application>
</manifest>
''');
      expect(
        fixture
            .scan(_manifest(restrictedRoots: roots))
            .issues
            .map((entry) => entry.code),
        contains('stale-xml-attribute'),
      );
    },
  );

  test(
    'generated localization desktop and web roots require generator ownership and invocation evidence',
    () {
      final fixture = _Fixture(<String, String>{
        'pubspec.yaml': 'name: generated_fixture\n',
        'lib/main.dart': 'void main() {}\n',
        'l10n.yaml': '''
arb-dir: lib/l10n
output-localization-file: app_localizations.dart
''',
        'macos/Runner/Main.swift':
            'RegisterGeneratedPlugins(registry: flutterController)\n',
        'web/manifest.json': '{"name":"generated_fixture"}\n',
      });
      addTearDown(fixture.dispose);
      final roots = <Map<String, Object?>>[
        _restricted(
          'generated.localization',
          'l10n.yaml',
          'generated',
          <Map<String, Object?>>[
            <String, Object?>{
              'kind': 'yaml-value',
              'source': 'l10n.yaml',
              'keyPath': 'output-localization-file',
              'value': 'app_localizations.dart',
            },
          ],
        ),
        _restricted(
          'generated.desktop',
          'macos/Runner/Main.swift',
          'generated',
          <Map<String, Object?>>[
            <String, Object?>{
              'kind': 'source-call-token',
              'source': 'macos/Runner/Main.swift',
              'callee': 'RegisterGeneratedPlugins',
              'argument': 'flutterController',
            },
          ],
        ),
        _restricted(
          'generated.web',
          'web/manifest.json',
          'generated',
          <Map<String, Object?>>[
            <String, Object?>{
              'kind': 'json-value',
              'source': 'web/manifest.json',
              'keyPath': 'name',
              'value': 'generated_fixture',
            },
          ],
        ),
      ];
      final green = fixture.scan(_manifest(restrictedRoots: roots));
      expect(green.issues, isEmpty, reason: _issues(green));
      expect(green.restrictedRoots.map((entry) => entry.id).toSet(), <String>{
        'generated.desktop',
        'generated.localization',
        'generated.web',
      });
      expect(green.restrictedRoots.every((entry) => entry.validated), isTrue);
      fixture.write(
        'macos/Runner/Main.swift',
        '// RegisterGeneratedPlugins(registry: flutterController)\n',
      );
      expect(
        fixture
            .scan(_manifest(restrictedRoots: roots))
            .issues
            .map((entry) => entry.code),
        contains('stale-source-call-token'),
      );
      fixture.write(
        'macos/Runner/Main.swift',
        'let decoy = "RegisterGeneratedPlugins(registry: flutterController)"\n',
      );
      expect(
        fixture
            .scan(_manifest(restrictedRoots: roots))
            .issues
            .map((entry) => entry.code),
        contains('stale-source-call-token'),
        reason: 'a string literal cannot satisfy generated call evidence',
      );
    },
  );

  test(
    'headless plugin requires app dependency package pluginClass native class and shared channel evidence',
    () {
      final fixture = _Fixture(<String, String>{
        'pubspec.yaml': '''
name: plugin_fixture
dependencies:
  background_push_crypto:
    path: packages/background_push_crypto
''',
        'lib/main.dart': 'void main() {}\n',
        'packages/background_push_crypto/pubspec.yaml': '''
name: background_push_crypto
flutter:
  plugin:
    platforms:
      android:
        pluginClass: BackgroundPushCryptoPlugin
''',
        'packages/background_push_crypto/android/Plugin.kt': '''
class BackgroundPushCryptoPlugin {
  fun attach(binding: Binding) {
    MethodChannel(binding.messenger, CHANNEL_NAME)
  }
}
''',
      });
      addTearDown(fixture.dispose);
      final roots = <Map<String, Object?>>[
        _restricted(
          'headless.plugin',
          'packages/background_push_crypto/pubspec.yaml',
          'headless-plugin',
          <Map<String, Object?>>[
            <String, Object?>{
              'kind': 'yaml-value',
              'source': 'pubspec.yaml',
              'keyPath': 'dependencies.background_push_crypto.path',
              'value': 'packages/background_push_crypto',
            },
            <String, Object?>{
              'kind': 'yaml-value',
              'source': 'packages/background_push_crypto/pubspec.yaml',
              'keyPath': 'flutter.plugin.platforms.android.pluginClass',
              'value': 'BackgroundPushCryptoPlugin',
            },
            <String, Object?>{
              'kind': 'source-call-token',
              'source': 'packages/background_push_crypto/android/Plugin.kt',
              'callee': 'MethodChannel',
              'argument': 'CHANNEL_NAME',
            },
          ],
        ),
      ];
      final green = fixture.scan(_manifest(restrictedRoots: roots));
      expect(green.issues, isEmpty, reason: _issues(green));
      expect(green.restrictedRoots.single.validated, isTrue);
      expect(
        green.restrictedRoots.single.rootKind,
        RuntimeRootKind.headlessPlugin,
      );

      fixture.write('packages/background_push_crypto/android/Plugin.kt', '''
// MethodChannel(binding.messenger, CHANNEL_NAME)
class BackgroundPushCryptoPlugin {}
''');
      expect(
        fixture
            .scan(_manifest(restrictedRoots: roots))
            .issues
            .map((entry) => entry.code),
        contains('stale-source-call-token'),
      );
      fixture.write('packages/background_push_crypto/android/Plugin.kt', '''
class BackgroundPushCryptoPlugin {
  val decoy = "MethodChannel(binding.messenger, CHANNEL_NAME)"
}
''');
      expect(
        fixture
            .scan(_manifest(restrictedRoots: roots))
            .issues
            .map((entry) => entry.code),
        contains('stale-source-call-token'),
        reason: 'a string literal cannot satisfy headless call evidence',
      );
    },
  );

  test(
    'tool command roots its closure while an uncalled support file remains retained-unresolved',
    () {
      final fixture = _Fixture(<String, String>{
        'pubspec.yaml': 'name: tool_fixture\n',
        'lib/main.dart': 'void main() {}\n',
        'lib/tool_dependency.dart': 'class ToolDependency {}\n',
        'lib/orphan_support.dart': 'class OrphanSupport {}\n',
        'tool/runner.dart': '''
import 'package:tool_fixture/tool_dependency.dart';
void main() {}
''',
        'tool/uncalled.dart': '''
import 'package:tool_fixture/orphan_support.dart';
void main() {}
''',
        'scripts/run.sh':
            'dart run tool/runner.dart --target tool/runner.dart\n',
      });
      addTearDown(fixture.dispose);
      final manifest = _manifest(
        externalEntrypoints: <Map<String, Object?>>[
          _external(
            'tool/runner.dart',
            seedsTooling: true,
            evidence: <Map<String, Object?>>[
              <String, Object?>{
                'kind': 'command-argument',
                'source': 'scripts/run.sh',
                'option': '--target',
                'target': 'tool/runner.dart',
              },
            ],
          ),
          _external('tool/uncalled.dart'),
        ],
        declarations: <Map<String, Object?>>[
          _declaration(
            'lib/tool_dependency.dart',
            disposition: 'explained-root',
            rootKinds: <String>['tooling'],
            evidence: <Map<String, Object?>>[
              <String, Object?>{'kind': 'computed-origin', 'origin': 'tooling'},
            ],
          ),
          _declaration(
            'lib/orphan_support.dart',
            disposition: 'retained-unresolved',
          ),
        ],
      );
      final result = fixture.scan(manifest);
      expect(
        _file(result, 'lib/tool_dependency.dart').bucket,
        ReachabilityBucket.toolingReachable,
      );
      expect(
        _file(result, 'lib/orphan_support.dart').bucket,
        ReachabilityBucket.unrooted,
      );
      expect(
        _file(result, 'lib/orphan_support.dart').disposition,
        ReviewDisposition.retainedUnresolved,
      );
      expect(
        result.externalEntrypoints
            .firstWhere((entry) => entry.path == 'tool/uncalled.dart')
            .invoked,
        isFalse,
      );

      fixture.write('scripts/run.sh', '''
# dart run tool/runner.dart --target tool/runner.dart
decoy="dart run tool/runner.dart --target tool/runner.dart"
''');
      final decoyOnly = fixture.scan(manifest);
      expect(
        decoyOnly.issues.map((entry) => entry.code),
        contains('stale-command-argument'),
        reason: 'shell comments and assignment strings cannot seed tooling',
      );
      expect(
        decoyOnly.externalEntrypoints
            .firstWhere((entry) => entry.path == 'tool/runner.dart')
            .invoked,
        isFalse,
      );
    },
  );

  test(
    'compatibility registries and export facades remain protected by exact evidence',
    () {
      final fixture = _Fixture(<String, String>{
        'pubspec.yaml': 'name: compatibility_fixture\n',
        'lib/main.dart': "import 'registry.dart';\nvoid main() {}\n",
        'lib/registry.dart': '''
class MigrationEntry {
  const MigrationEntry(this.version);
  final int version;
}
final entries = <MigrationEntry>[
  MigrationEntry(1),
  MigrationEntry(2),
];
''',
        'lib/facade.dart': "export 'shared.dart';\n",
        'lib/shared.dart': 'class Shared {}\n',
      });
      addTearDown(fixture.dispose);
      final roots = <Map<String, Object?>>[
        _restricted(
          'compat.registry',
          'lib/registry.dart',
          'compatibility',
          <Map<String, Object?>>[
            <String, Object?>{
              'kind': 'dart-call-argument',
              'source': 'lib/registry.dart',
              'callee': 'MigrationEntry',
              'argument': '2',
            },
          ],
        ),
        _restricted(
          'compat.facade',
          'lib/facade.dart',
          'compatibility',
          <Map<String, Object?>>[
            <String, Object?>{
              'kind': 'dart-directive',
              'source': 'lib/facade.dart',
              'target': 'lib/shared.dart',
            },
          ],
        ),
      ];
      final green = fixture.scan(_manifest(restrictedRoots: roots));
      expect(
        green.issues.where((entry) => entry.code.startsWith('stale-')),
        isEmpty,
        reason: _issues(green),
      );
      expect(
        green.restrictedRoots.map((entry) => entry.rootKind).toSet(),
        <RuntimeRootKind>{RuntimeRootKind.compatibility},
      );
      expect(green.restrictedRoots.every((entry) => entry.validated), isTrue);
      fixture.write('lib/registry.dart', '''
// MigrationEntry(2)
const token = 'MigrationEntry(2)';
''');
      expect(
        fixture
            .scan(_manifest(restrictedRoots: roots))
            .issues
            .map((entry) => entry.code),
        contains('stale-dart-call-argument'),
      );
    },
  );

  test(
    'resource roots require exact manifest or catalog ownership evidence',
    () {
      final fixture = _Fixture(<String, String>{
        'pubspec.yaml': '''
name: resource_fixture
flutter:
  assets:
    - assets/icons/
''',
        'lib/main.dart': 'void main() {}\n',
        'web/manifest.json': '{"icons":[{"src":"icons/Icon-192.png"}]}\n',
        'ios/Assets.xcassets/AppIcon.appiconset/Contents.json':
            '{"info":{"author":"xcode"}}\n',
      });
      addTearDown(fixture.dispose);
      final roots = <Map<String, Object?>>[
        _restricted(
          'resource.assets',
          'pubspec.yaml',
          'resource',
          <Map<String, Object?>>[
            <String, Object?>{
              'kind': 'yaml-value',
              'source': 'pubspec.yaml',
              'keyPath': 'flutter.assets.0',
              'value': 'assets/icons/',
            },
          ],
        ),
        _restricted(
          'resource.web-icon',
          'web/manifest.json',
          'resource',
          <Map<String, Object?>>[
            <String, Object?>{
              'kind': 'json-value',
              'source': 'web/manifest.json',
              'keyPath': 'icons.0.src',
              'value': 'icons/Icon-192.png',
            },
          ],
        ),
      ];
      final green = fixture.scan(_manifest(restrictedRoots: roots));
      expect(green.issues, isEmpty, reason: _issues(green));
      expect(
        green.restrictedRoots.map((entry) => entry.rootKind).toSet(),
        <RuntimeRootKind>{RuntimeRootKind.resource},
      );
      expect(green.restrictedRoots.every((entry) => entry.validated), isTrue);
      fixture.write('web/manifest.json', '{"wrongKey":"icons/Icon-192.png"}\n');
      expect(
        fixture
            .scan(_manifest(restrictedRoots: roots))
            .issues
            .map((entry) => entry.code),
        contains('stale-json-value'),
      );
    },
  );

  test(
    'required restricted-root ratchet reports removal for every root kind',
    () {
      final fixture = _Fixture(<String, String>{
        'pubspec.yaml': 'name: ratchet_fixture\n',
        'lib/main.dart': 'void main() {}\n',
      });
      addTearDown(fixture.dispose);

      for (final rootKind in RuntimeRootKind.values) {
        final id = 'required.${rootKind.wireName}';
        final result = fixture.scan(
          _manifest(
            requiredRestrictedRoots: <Map<String, Object?>>[
              <String, Object?>{'id': id, 'rootKind': rootKind.wireName},
            ],
          ),
        );
        expect(
          result.issues.any(
            (entry) =>
                entry.code == 'missing-required-restricted-root' &&
                entry.path == id,
          ),
          isTrue,
          reason: '${rootKind.wireName}: ${_issues(result)}',
        );
      }
    },
  );

  test(
    'manifest rejects escapes broad globs duplicates overlaps ownerless rows stale evidence and stale candidates',
    () {
      final fixture = _Fixture(<String, String>{
        'pubspec.yaml': 'name: validation_fixture\n',
        'lib/main.dart': "import 'live.dart';\nvoid main() {}\n",
        'lib/live.dart': 'class Live {}\n',
        'lib/test_only.dart': 'class TestOnly {}\n',
        'lib/unrelated.dart': 'class Unrelated {}\n',
        'test/only_test.dart':
            "import 'package:validation_fixture/test_only.dart';\nvoid main() {}\n",
      });
      addTearDown(fixture.dispose);

      final broad = fixture.scan(
        _manifest(
          declarations: <Map<String, Object?>>[
            _declaration('lib/*.dart', disposition: 'candidate'),
          ],
        ),
      );
      expect(
        broad.issues.map((entry) => entry.code),
        contains('unsafe-manifest-path'),
      );

      final duplicate = fixture.scan(
        _manifest(
          declarations: <Map<String, Object?>>[
            _declaration('lib/test_only.dart', disposition: 'candidate'),
            _declaration('lib/test_only.dart', disposition: 'candidate'),
          ],
        ),
      );
      expect(
        duplicate.issues.map((entry) => entry.code),
        contains('duplicate-declaration'),
      );

      final staleCandidate = fixture.scan(
        _manifest(
          declarations: <Map<String, Object?>>[
            _declaration('lib/live.dart', disposition: 'candidate'),
            _declaration(
              'lib/test_only.dart',
              disposition: 'explained-root',
              evidence: <Map<String, Object?>>[
                <String, Object?>{
                  'kind': 'computed-origin',
                  'origin': 'test/integration',
                },
              ],
            ),
          ],
        ),
      );
      expect(
        staleCandidate.issues.map((entry) => entry.code),
        contains('stale-candidate'),
      );

      final conventionGreen = fixture.scan(
        _manifest(
          declarations: <Map<String, Object?>>[
            _declaration(
              'lib/test_only.dart',
              disposition: 'explained-root',
              evidence: <Map<String, Object?>>[
                <String, Object?>{
                  'kind': 'computed-origin',
                  'origin': 'test/integration',
                },
              ],
            ),
          ],
        ),
      );
      expect(
        conventionGreen.issues.where(
          (entry) => entry.path == 'lib/test_only.dart',
        ),
        isEmpty,
        reason: _issues(conventionGreen),
      );

      final unrelatedEvidence = fixture.scan(
        _manifest(
          declarations: <Map<String, Object?>>[
            _declaration(
              'lib/test_only.dart',
              disposition: 'explained-root',
              evidence: <Map<String, Object?>>[
                <String, Object?>{
                  'kind': 'computed-origin',
                  'origin': 'test/integration',
                },
              ],
            ),
            _declaration(
              'lib/unrelated.dart',
              disposition: 'explained-root',
              rootKinds: <String>['resource'],
              evidence: <Map<String, Object?>>[
                <String, Object?>{
                  'kind': 'yaml-value',
                  'source': 'pubspec.yaml',
                  'keyPath': 'name',
                  'value': 'validation_fixture',
                },
              ],
            ),
          ],
        ),
      );
      expect(
        unrelatedEvidence.issues
            .where((entry) => entry.path == 'lib/unrelated.dart')
            .map((entry) => entry.code),
        containsAll(<String>[
          'incompatible-root-evidence',
          'explained-root-without-proof',
        ]),
        reason:
            'valid but unrelated evidence cannot explain an unrooted subject',
      );

      expect(
        () => RuntimeRootsManifest.fromJsonString(
          jsonEncode(
            _manifest(
              declarations: <Map<String, Object?>>[
                <String, Object?>{
                  ..._declaration(
                    'lib/test_only.dart',
                    disposition: 'candidate',
                  ),
                  'owner': '',
                },
              ],
            ),
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => RuntimeRootsManifest.fromJsonString(
          jsonEncode(
            _manifest(
              declarations: <Map<String, Object?>>[
                <String, Object?>{
                  ..._declaration(
                    'lib/test_only.dart',
                    disposition: 'candidate',
                  ),
                  'disposition': 'deletion-safe',
                },
              ],
            ),
          ),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'report returns zero for candidate deferred-review and retained-unresolved rows without deletion verdicts',
    () {
      final fixture = _Fixture(<String, String>{
        'pubspec.yaml': 'name: advisory_fixture\n',
        'lib/main.dart': 'void main() {}\n',
        'lib/candidate.dart': 'class Candidate {}\n',
        'lib/deferred.dart': "import 'retained.dart';\n",
        'lib/retained.dart': 'class Retained {}\n',
      });
      addTearDown(fixture.dispose);
      final manifest = _manifest(
        declarations: <Map<String, Object?>>[
          _declaration('lib/candidate.dart', disposition: 'candidate'),
          _declaration(
            'lib/deferred.dart',
            disposition: 'deferred-review',
            evidence: <Map<String, Object?>>[
              <String, Object?>{
                'kind': 'dart-directive',
                'source': 'lib/deferred.dart',
                'target': 'lib/retained.dart',
              },
            ],
          ),
          _declaration('lib/retained.dart', disposition: 'retained-unresolved'),
        ],
      );
      final result = fixture.scan(manifest);
      expect(result.exitCodeFor(check: false), 0, reason: _issues(result));
      expect(result.exitCodeFor(check: true), 0, reason: _issues(result));
      expect(
        result.files.map((entry) => entry.disposition),
        containsAll(<ReviewDisposition>[
          ReviewDisposition.candidate,
          ReviewDisposition.deferredReview,
          ReviewDisposition.retainedUnresolved,
        ]),
      );
      final rendered = '${result.renderJson()}\n${result.renderText()}';
      expect(rendered, isNot(contains('deletion-safe')));
      expect(rendered, isNot(contains('\tdead\t')));
    },
  );

  test('DTR-04 retires approved visible leaves and obsolete SUT-only tests', () {
    final repo = Directory.current.absolute;
    final manifest = RuntimeRootsManifest.loadSync(
      File('${repo.path}/tool/runtime_roots/runtime_roots.json'),
    );
    final legacyOverlayPath = <String>[
      'lib/features/conversation/presentation/widgets/',
      'recording_overlay.dart',
    ].join();
    final retiredProductionPaths = <String>{
      'lib/features/feed/presentation/widgets/feed_ring_avatar.dart',
      'lib/features/groups/presentation/widgets/group_compose_area.dart',
      'lib/features/settings/presentation/widgets/settings_move_account_card.dart',
      'lib/features/conversation/presentation/widgets/amplitude_bars.dart',
      'lib/features/settings/presentation/widgets/settings_peer_id_card.dart',
      'lib/features/settings/presentation/widgets/posts_nearby_settings_card.dart',
      'lib/features/identity/presentation/widgets/identity_loading_card.dart',
      legacyOverlayPath,
    };
    final retiredTestPaths = <String>{
      'test/features/conversation/presentation/widgets/amplitude_bars_test.dart',
      'test/features/settings/presentation/widgets/settings_peer_id_card_test.dart',
      'test/features/settings/presentation/widgets/posts_nearby_settings_card_test.dart',
      'test/features/identity/presentation/widgets/identity_loading_card_test.dart',
    };
    final remainingPaths = <String>[
      ...retiredProductionPaths,
      ...retiredTestPaths,
    ].where((path) => File('${repo.path}/$path').existsSync()).toList();
    final retiredDeclarationPaths = retiredProductionPaths.difference(<String>{
      legacyOverlayPath,
    });
    final remainingDeclarations = manifest.declarations
        .map((entry) => entry.path)
        .where(retiredDeclarationPaths.contains)
        .toList();
    const compatibilityId = 'compatibility.recording-overlay-export';
    final remainingCompatibilityRecords = <String>[
      ...manifest.requiredRestrictedRoots
          .where((entry) => entry.id == compatibilityId)
          .map((_) => 'requiredRestrictedRoots'),
      ...manifest.restrictedRoots
          .where((entry) => entry.id == compatibilityId)
          .map((_) => 'restrictedRoots'),
    ];

    expect(
      <String>[
        ...remainingPaths,
        ...remainingDeclarations,
        ...remainingCompatibilityRecords,
      ],
      isEmpty,
      reason: 'DTR04-RED: approved retirement paths or records remain',
    );
  });

  test(
    'DTR-07 retires the Group-list UI island and preserves the Orbit all-chats replacement',
    () {
      final repo = Directory.current.absolute;
      final manifest = RuntimeRootsManifest.loadSync(
        File('${repo.path}/tool/runtime_roots/runtime_roots.json'),
      );
      const retiredProductionPaths = <String>{
        'lib/features/groups/presentation/screens/group_list_wired.dart',
        'lib/features/groups/presentation/screens/group_list_screen.dart',
        'lib/features/groups/presentation/widgets/group_card.dart',
      };
      const retiredTestPaths = <String>{
        'test/features/groups/presentation/group_list_wired_test.dart',
        'test/features/groups/presentation/group_list_screen_test.dart',
        'test/features/groups/presentation/group_list_screen_bidi_test.dart',
        'test/features/groups/presentation/group_card_test.dart',
        'test/features/groups/presentation/group_card_bidi_test.dart',
      };
      const replacementAnchorsByPath = <String, List<String>>{
        'lib/features/orbit/presentation/screens/orbit_screen.dart': <String>[
          '_buildAllChatsListSurface(',
          '_buildGroupRow(',
        ],
        'lib/features/orbit/presentation/widgets/orbit_view_toggle_button.dart':
            <String>["ValueKey('orbit-view-toggle')"],
        'lib/features/orbit/presentation/widgets/group_row.dart': <String>[
          'class GroupRow extends StatelessWidget',
        ],
      };
      final violations = <String>[
        ...retiredProductionPaths
            .where((path) => File('${repo.path}/$path').existsSync())
            .map((path) => 'source:$path'),
        ...retiredTestPaths
            .where((path) => File('${repo.path}/$path').existsSync())
            .map((path) => 'test:$path'),
        ...manifest.declarations
            .map((entry) => entry.path)
            .where(retiredProductionPaths.contains)
            .map((path) => 'manifest:$path'),
      ];

      for (final entry in replacementAnchorsByPath.entries) {
        final file = File('${repo.path}/${entry.key}');
        if (!file.existsSync()) {
          violations.add('replacement-file:${entry.key}');
          continue;
        }
        final source = file.readAsStringSync();
        for (final anchor in entry.value) {
          if (!source.contains(anchor)) {
            violations.add('replacement-anchor:${entry.key}:$anchor');
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'DTR07-RED: retired Group-list paths or declarations remain, or '
            'the Orbit all-chats replacement is incomplete',
      );
    },
  );

  test(
    'DTR08-COMP-002 consumers import the shared recording overlay before facade retirement',
    () {
      final repo = Directory.current.absolute;
      final oldImport = <String>[
        "import 'package:flutter_app/features/conversation/presentation/widgets/",
        "recording_overlay.dart';",
      ].join();
      const sharedImport =
          "import 'package:flutter_app/shared/widgets/media/recording_overlay.dart';";
      final consumers = <String>[
        'lib/features/conversation/presentation/widgets/compose_area.dart',
        'test/features/conversation/presentation/widgets/recording_overlay_test.dart',
        'test/features/conversation/presentation/screens/conversation_wired_test.dart',
      ];
      final violations = <String>[];
      for (final path in consumers) {
        final source = File('${repo.path}/$path').readAsStringSync();
        if (source.contains(oldImport) || !source.contains(sharedImport)) {
          violations.add(path);
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'DTR08-COMP-002-RED: legacy recording overlay imports remain',
      );
    },
  );

  test(
    'DTR-10 retires superseded leave-local-history coordinator after durable fixture migration',
    () {
      final repo = Directory.current.absolute;
      final retiredType = <String>[
        'LeaveGroupAndDelete',
        'LocalHistoryUseCase',
      ].join();
      final retiredSourceStem = <String>[
        'leave_group_and_delete_',
        'local_history_use_case',
      ].join();
      final retiredSourcePath =
          'lib/features/groups/application/$retiredSourceStem.dart';
      final legacyFixtureStem = <String>[
        'legacy_group_exit_',
        'coordinator_fixture',
      ].join();
      final legacyFixturePath = 'test/shared/helpers/$legacyFixtureStem.dart';
      final legacyFixtureInstaller = <String>[
        'installLegacyGroupExit',
        'CoordinatorFixture',
      ].join();
      final actionTestPath =
          'test/features/groups/application/group_exit_actions_test.dart';
      final flowInventoryPath = 'test/core/utils/flow_event_emitter_test.dart';
      final groupInfoTestPath =
          'test/features/groups/presentation/group_info_wired_test.dart';
      final orbitTestPath =
          'test/features/orbit/presentation/screens/orbit_wired_test.dart';
      final violations = <String>[];

      String relativePath(File file) => file.path
          .substring(repo.path.length + 1)
          .replaceAll(Platform.pathSeparator, '/');

      const excludedOwnedDartDirectoryNames = <String>{
        '.dart_tool',
        '.git',
        '.tmp',
        'build',
        'coverage',
        'doc',
        'docs',
        'generated',
        'temp',
        'tmp',
      };

      Iterable<File> dartSourcesIn(Directory directory) sync* {
        for (final entity in directory.listSync(followLinks: false)) {
          if (entity is Directory) {
            final directoryName = entity.path
                .split(Platform.pathSeparator)
                .last
                .toLowerCase();
            if (excludedOwnedDartDirectoryNames.contains(directoryName)) {
              continue;
            }
            yield* dartSourcesIn(entity);
          } else if (entity is File && entity.path.endsWith('.dart')) {
            yield entity;
          }
        }
      }

      Iterable<File> dartSourcesUnder(String directoryPath) sync* {
        final directory = Directory('${repo.path}/$directoryPath');
        if (directory.existsSync()) yield* dartSourcesIn(directory);
      }

      Iterable<File> ownedDartSources() sync* {
        for (final root in <String>[
          'lib',
          'test',
          'integration_test',
          'test_driver',
          'scripts',
          'tool',
        ]) {
          yield* dartSourcesUnder(root);
        }
        for (final entity in repo.listSync(followLinks: false)) {
          if (entity is File && entity.path.endsWith('.dart')) {
            yield entity;
          }
        }
      }

      int occurrences(String source, String needle) {
        var count = 0;
        var offset = 0;
        while (true) {
          final match = source.indexOf(needle, offset);
          if (match < 0) return count;
          count++;
          offset = match + needle.length;
        }
      }

      for (final path in <String>[retiredSourcePath, legacyFixturePath]) {
        if (File('${repo.path}/$path').existsSync()) {
          violations.add('retired-file:$path');
        }
      }

      final manifest = RuntimeRootsManifest.loadSync(
        File('${repo.path}/tool/runtime_roots/runtime_roots.json'),
      );
      if (manifest.declarations.any(
        (declaration) => declaration.path == retiredSourcePath,
      )) {
        violations.add('manifest-declaration:$retiredSourcePath');
      }

      for (final file in ownedDartSources()) {
        final source = file.readAsStringSync();
        final path = relativePath(file);
        if (source.contains(retiredType)) {
          violations.add('retired-symbol:$path');
        }
        if (source.contains(retiredSourceStem)) {
          violations.add('retired-source-reference:$path');
        }
        if (source.contains(legacyFixtureStem) ||
            source.contains(legacyFixtureInstaller)) {
          violations.add('legacy-fixture-reference:$path');
        }
      }

      final actionTest = File(
        '${repo.path}/$actionTestPath',
      ).readAsStringSync();
      final obsoleteTestNames = <String>[
        <String>[
          'active exit completes durable prework before native ',
          'leave and target cleanup',
        ].join(),
        <String>[
          'active exit distinguishes degraded notice native and ',
          'post-commit cleanup outcomes',
        ].join(),
        <String>[
          'completed cleanup does not skip native leave after a later ',
          'rejoin',
        ].join(),
        <String>[
          'incomplete cleanup marker is scoped to the membership that ',
          'left',
        ].join(),
        <String>[
          'cleanup retry never deletes a current group with unresolved ',
          'membership',
        ].join(),
        <String>[
          'rapid active exit calls coalesce before publish and native ',
          'leave',
        ].join(),
        <String>[
          'active exit blocks while an exact role transition is ',
          'pending',
        ].join(),
        <String>[
          'active exit rechecks pending role sync at the native leave ',
          'boundary',
        ].join(),
        <String>[
          'last-admin race rolls back its exact tentative leave ',
          'timeline',
        ].join(),
        <String>[
          'leave rollback deletes only its own timeline when a later ',
          'event arrives',
        ].join(),
        <String>[
          'snapshot and rollback repository errors remain typed ',
          'failures',
        ].join(),
      ];
      for (final name in obsoleteTestNames) {
        if (actionTest.contains(name)) {
          violations.add('obsolete-test:$name');
        }
      }
      final obsoleteHelperNames = <String>[
        <String>['_Hanging', 'LeaveBridge'].join(),
        <String>['_CleanupFailing', 'GroupRepository'].join(),
        <String>['_CleanupFailsOnce', 'GroupRepository'].join(),
        <String>['_DeleteGroupFailsOnce', 'Repository'].join(),
        <String>['_ConcurrentRemoval', 'MessageRepository'].join(),
        <String>['_SnapshotFailing', 'GroupRepository'].join(),
        <String>['_RollbackFailing', 'GroupRepository'].join(),
      ];
      for (final name in obsoleteHelperNames) {
        if (actionTest.contains(name)) {
          violations.add('obsolete-helper:$name');
        }
      }
      if (!actionTest.contains('_AfterFirstSignBridge')) {
        violations.add('retained-helper:_AfterFirstSignBridge');
      }

      final flowInventory = File(
        '${repo.path}/$flowInventoryPath',
      ).readAsStringSync();
      final obsoleteFlowEvents = <String>[
        <String>['GROUP_ACTIVE_EXIT_', 'SNAPSHOT_FAILED'].join(),
        <String>['GROUP_ACTIVE_EXIT_', 'PREWORK_FAILED'].join(),
        <String>['GROUP_ACTIVE_EXIT_', 'NATIVE_UNCERTAIN'].join(),
        <String>['GROUP_ACTIVE_EXIT_', 'CLEANUP_INCOMPLETE'].join(),
        <String>['GROUP_ACTIVE_EXIT_', 'ROLLBACK_FAILED'].join(),
      ];
      for (final event in obsoleteFlowEvents) {
        if (flowInventory.contains(event)) {
          violations.add('obsolete-flow-event:$event');
        }
      }
      if (flowInventory.contains(retiredSourcePath)) {
        violations.add('obsolete-flow-source:$retiredSourcePath');
      }

      const modernSources = <String, String>{
        'lib/features/groups/application/group_exit_intent_coordinator.dart':
            'class GroupExitIntentCoordinator',
        'lib/features/groups/application/group_exit_intent_runner.dart':
            'class GroupExitIntentRunner',
        'lib/features/groups/application/group_exit_intent_sink.dart':
            'setGroupExitIntentActionSinks(',
        'lib/features/groups/application/group_exit_policy.dart':
            'resolveGroupExitSnapshot(',
        'lib/features/groups/application/group_exit_terminal_diagnostics.dart':
            'class DiagnosingDeleteSelfRemovedGroupShellAction',
        'test/shared/helpers/durable_group_exit_surface_harness.dart':
            'createForSurface(',
      };
      for (final entry in modernSources.entries) {
        final file = File('${repo.path}/${entry.key}');
        if (!file.existsSync()) {
          violations.add('modern-source:${entry.key}');
          continue;
        }
        if (!file.readAsStringSync().contains(entry.value)) {
          violations.add('modern-anchor:${entry.key}:${entry.value}');
        }
      }

      final groupInfoTest = File(
        '${repo.path}/$groupInfoTestPath',
      ).readAsStringSync();
      final orbitTest = File('${repo.path}/$orbitTestPath').readAsStringSync();
      const retainedGroupInfoSelectors = <String>[
        'GCA-009 leave group deletes local messages and pops to first route',
        'sole admin leave stays on screen and shows an error',
        'BB-010 native leave failure starts durable retry and pops from info',
        'GCA-010 native leave failure retains exact durable intent and local history for native-only retry',
        'writer Leave tears down local membership even when rotation is deferred',
        'multi-admin leave broadcasts self-removal, rotates key, and pops to first route',
        'writer leave broadcasts a durable left-the-group event before local cleanup',
      ];
      const retainedOrbitSelectors = <String>[
        'removed-member stuck row uses guarded local delete while ordinary stuck leave is preserved',
        'first sole-admin Leave opens recovery without destructive work',
        'leaving one Orbit group preserves friends and other groups',
        'user-B scenario: leaving one Orbit group keeps both 1:1 chat threads with friends intact',
      ];
      for (final selector in retainedGroupInfoSelectors) {
        if (!groupInfoTest.contains(selector)) {
          violations.add('group-info-selector:$selector');
        }
      }
      for (final selector in retainedOrbitSelectors) {
        if (!orbitTest.contains(selector)) {
          violations.add('orbit-selector:$selector');
        }
      }

      const durableFactoryCall =
          'DurableGroupExitSurfaceHarness.createForSurface(';
      final durableFactoryCounts = <String, int>{
        groupInfoTestPath: occurrences(groupInfoTest, durableFactoryCall),
        orbitTestPath: occurrences(orbitTest, durableFactoryCall),
      };
      const expectedDurableFactoryCounts = <String, int>{
        'test/features/groups/presentation/group_info_wired_test.dart': 7,
        'test/features/orbit/presentation/screens/orbit_wired_test.dart': 4,
      };
      for (final entry in expectedDurableFactoryCounts.entries) {
        final actual = durableFactoryCounts[entry.key];
        if (actual != entry.value) {
          violations.add(
            'durable-factory-count:${entry.key}:$actual!=${entry.value}',
          );
        }
      }
      if (durableFactoryCounts.values.fold<int>(
            0,
            (sum, count) => sum + count,
          ) !=
          11) {
        violations.add('durable-factory-total:${durableFactoryCounts.values}');
      }

      const platformHandlers = <String>[
        'android/app/src/main/kotlin/com/mknoon/app/GoBridge.kt',
        'ios/Runner/GoBridge.swift',
        'macos/Runner/MainFlutterWindow.swift',
      ];
      for (final path in platformHandlers) {
        final file = File('${repo.path}/$path');
        if (!file.existsSync()) {
          violations.add('platform-handler:$path');
          continue;
        }
        if (!file.readAsStringSync().contains('groupLeaveTopic')) {
          violations.add('platform-handler-token:$path:groupLeaveTopic');
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'DTR10-RED: obsolete coordinator artifacts remain or durable '
            'replacement/UI/native preservation is incomplete:\n'
            '${violations.join('\n')}',
      );
    },
  );

  test('DTR-10 retires dormant leaveGroup and default-false active-delete branch', () {
    final repo = Directory.current.absolute;
    final retiredFunction = <String>['leave', 'Group'].join();
    final retiredStem = <String>['leave_group_', 'use_case'].join();
    final retiredSourcePath =
        'lib/features/groups/application/$retiredStem.dart';
    final retiredTestPath =
        'test/features/groups/application/${retiredStem}_test.dart';
    final retiredSourceReference =
        'features/groups/application/$retiredStem.dart';
    final retiredBranchFlag = <String>['deleteLocally', 'IfDissolved'].join();
    final oldDeclaration = RegExp(
      r'Future\s*<\s*void\s*>\s*' + RegExp.escape(retiredFunction) + r'\s*\(',
    );
    final directOldCall = RegExp(
      r'(^|[^.A-Za-z0-9_])' +
          RegExp.escape(retiredFunction) +
          r'\s*\(\s*(bridge|groupRepo|groupId)\s*:',
      multiLine: true,
    );
    final aliasedOldCall = <String>[
      'group_leave.',
      retiredFunction,
      '(',
    ].join();
    final violations = <String>[];

    String relativePath(File file) => file.path
        .substring(repo.path.length + 1)
        .replaceAll(Platform.pathSeparator, '/');

    const excludedDirectoryNames = <String>{
      '.dart_tool',
      '.git',
      '.tmp',
      'build',
      'coverage',
      'doc',
      'docs',
      'generated',
      'temp',
      'tmp',
    };

    Iterable<File> dartSourcesIn(Directory directory) sync* {
      for (final entity in directory.listSync(followLinks: false)) {
        if (entity is Directory) {
          final name = entity.path
              .split(Platform.pathSeparator)
              .last
              .toLowerCase();
          if (!excludedDirectoryNames.contains(name)) {
            yield* dartSourcesIn(entity);
          }
        } else if (entity is File && entity.path.endsWith('.dart')) {
          yield entity;
        }
      }
    }

    Iterable<File> ownedDartSources() sync* {
      for (final root in <String>[
        'lib',
        'test',
        'integration_test',
        'test_driver',
        'scripts',
        'tool',
      ]) {
        final directory = Directory('${repo.path}/$root');
        if (directory.existsSync()) yield* dartSourcesIn(directory);
      }
    }

    String? requiredSource(String path) {
      final file = File('${repo.path}/$path');
      if (!file.existsSync()) {
        violations.add('required-file:$path');
        return null;
      }
      return file.readAsStringSync();
    }

    String? boundedSection(
      String source, {
      required String path,
      required String start,
      required String end,
    }) {
      final startOffset = source.indexOf(start);
      final endOffset = source.indexOf(
        end,
        startOffset < 0 ? 0 : startOffset + start.length,
      );
      if (startOffset < 0 || endOffset < 0) {
        violations.add('driver-section:$path:$start->$end');
        return null;
      }
      return source.substring(startOffset, endOffset);
    }

    for (final path in <String>[retiredSourcePath, retiredTestPath]) {
      if (File('${repo.path}/$path').existsSync()) {
        violations.add('retired-file:$path');
      }
    }

    final manifest = RuntimeRootsManifest.loadSync(
      File('${repo.path}/tool/runtime_roots/runtime_roots.json'),
    );
    if (manifest.declarations.any(
      (declaration) => declaration.path == retiredSourcePath,
    )) {
      violations.add('manifest-declaration:$retiredSourcePath');
    }

    for (final file in ownedDartSources()) {
      final source = file.readAsStringSync();
      final path = relativePath(file);
      if (source.contains(retiredSourceReference)) {
        violations.add('retired-import:$path');
      }
      if (source.contains(retiredBranchFlag)) {
        violations.add('retired-branch:$path');
      }
      if (path != 'test/shared/fakes/group_test_user.dart' &&
          oldDeclaration.hasMatch(source)) {
        violations.add('retired-declaration:$path');
      }
      if (directOldCall.hasMatch(source) || source.contains(aliasedOldCall)) {
        violations.add('direct-old-call:$path');
      }
    }

    final deleteUseCasePath =
        'lib/features/groups/application/delete_group_and_messages_use_case.dart';
    final deleteUseCase = requiredSource(deleteUseCasePath);
    if (deleteUseCase != null) {
      const requiredAnchors = <String>[
        'Future<void> deleteGroupAndMessages({',
        'DissolvedGroupDeleteStateChangedException',
        'strictDissolvedLocalDeleteRequiredMessage',
        'await groupMessageRepo.deleteMessagesForGroup(groupId);',
        'await groupRepo.deleteGroup(groupId);',
        'await discardGroupPendingBroadcasts(groupId);',
      ];
      for (final anchor in requiredAnchors) {
        if (!deleteUseCase.contains(anchor)) {
          violations.add('strict-delete-anchor:$anchor');
        }
      }
      final oldBridgeParameter = <String>['required ', 'Bridge bridge'].join();
      if (deleteUseCase.contains(oldBridgeParameter)) {
        violations.add('strict-delete-bridge-parameter');
      }
    }

    final deleteUseCaseTestPath =
        'test/features/groups/application/delete_group_and_messages_use_case_test.dart';
    final deleteUseCaseTest = requiredSource(deleteUseCaseTestPath);
    if (deleteUseCaseTest != null) {
      const obsoleteSelectors = <String>[
        'leaves group then deletes its messages',
        'LP003 active delete dispatches one group leave',
        'preserves messages when leave is blocked',
        'BB-010 active delete preserves group messages when native leave fails',
        'does not delete messages for other groups',
        'propagates errors from message deletion',
      ];
      for (final selector in obsoleteSelectors) {
        if (deleteUseCaseTest.contains(selector)) {
          violations.add('obsolete-branch-test:$selector');
        }
      }
    }

    const compatibilityMessage =
        "You can't leave this group because you're the only admin.";
    const policyPath = 'lib/features/groups/application/group_exit_policy.dart';
    final policy = requiredSource(policyPath);
    if (policy != null &&
        (!policy.contains('const lastAdminLeaveBlockedMessage =') ||
            !policy.contains(compatibilityMessage))) {
      violations.add('compatibility-owner:$policyPath');
    }
    const policyImport = 'features/groups/application/group_exit_policy.dart';
    for (final path in <String>[
      'lib/features/groups/presentation/screens/group_info_wired.dart',
      'lib/features/orbit/presentation/screens/orbit_wired.dart',
    ]) {
      final source = requiredSource(path);
      if (source != null &&
          (!source.contains(policyImport) ||
              !source.contains('lastAdminLeaveBlockedMessage'))) {
        violations.add('compatibility-consumer:$path');
      }
    }

    const preservedSources = <String, String>{
      'lib/features/groups/application/group_exit_intent_coordinator.dart':
          'class GroupExitIntentCoordinator',
      'lib/features/groups/application/group_exit_intent_runner.dart':
          'class GroupExitIntentRunner',
      'lib/features/groups/application/group_exit_intent_sink.dart':
          'setGroupExitIntentActionSinks(',
      'lib/features/groups/application/group_exit_terminal_diagnostics.dart':
          'class DiagnosingDeleteSelfRemovedGroupShellAction',
      'lib/core/bridge/bridge_group_helpers.dart':
          'Future<void> callGroupLeave(',
      'lib/core/database/app_database_version.dart':
          'const int currentIdentityDatabaseVersion = 109;',
    };
    for (final entry in preservedSources.entries) {
      final source = requiredSource(entry.key);
      if (source != null && !source.contains(entry.value)) {
        violations.add('preservation-anchor:${entry.key}:${entry.value}');
      }
    }

    const driverPath = 'test/shared/helpers/durable_group_exit_driver.dart';
    final driver = requiredSource(driverPath);
    if (driver != null) {
      for (final anchor in const <String>[
        'class DurableGroupExitDriver',
        'static DurableGroupExitDriver compose({',
        'requestLeave(',
      ]) {
        if (!driver.contains(anchor)) {
          violations.add('durable-driver-anchor:$anchor');
        }
      }
    }

    const groupUserPath = 'test/shared/fakes/group_test_user.dart';
    final groupUser = requiredSource(groupUserPath);
    if (groupUser != null) {
      final leaveWrapper = boundedSection(
        groupUser,
        path: groupUserPath,
        start: <String>[
          'Future<void> ',
          retiredFunction,
          '(String groupId)',
        ].join(),
        end: '/// Sends a message to a group',
      );
      if (leaveWrapper != null) {
        for (final anchor in const <String>[
          'DurableGroupExitSurfaceHarness.createForSurface(',
          'requestLeaveForTest(',
        ]) {
          if (!leaveWrapper.contains(anchor)) {
            violations.add('host-driver-anchor:$anchor');
          }
        }
        for (final bypass in <String>[
          'buildMemberRemovedTimelineMessage(',
          aliasedOldCall,
          'callGroupLeave(',
          '.removeAllMembers(',
          '.removeAllKeys(',
          '.deleteGroup(',
        ]) {
          if (leaveWrapper.contains(bypass)) {
            violations.add('host-driver-bypass:$bypass');
          }
        }
      }
    }

    const deviceStackPath =
        'integration_test/group_multi_device_real_harness.dart';
    final deviceStack = requiredSource(deviceStackPath);
    if (deviceStack != null) {
      const composeCall = 'DurableGroupExitDriver.compose(';
      if (!deviceStack.contains('durable_group_exit_driver.dart') ||
          !deviceStack.contains(composeCall)) {
        violations.add('device-durable-driver:$deviceStackPath');
      }
      if (deviceStack.indexOf(composeCall) !=
          deviceStack.lastIndexOf(composeCall)) {
        violations.add('device-durable-driver-compose-count:$deviceStackPath');
      }
    }

    const deviceHarnessPath =
        'integration_test/group_multi_party_device_real_harness.dart';
    final deviceHarness = requiredSource(deviceHarnessPath);
    if (deviceHarness != null) {
      for (final bounds in const <(String, String)>[
        (
          'Future<void> _runVoluntaryLeaveConvergenceCharlie(',
          'Future<void> _runI01Alice(',
        ),
        ('Future<void> _runGm015Alice(', 'Future<void> _runGm015Bob('),
      ]) {
        final section = boundedSection(
          deviceHarness,
          path: deviceHarnessPath,
          start: bounds.$1,
          end: bounds.$2,
        );
        if (section == null) continue;
        for (final bypass in <String>[
          'broadcastVoluntaryLeaveAndRotateKey(',
          'callGroupLeave(',
          aliasedOldCall,
          '.removeAllMembers(',
          '.removeAllKeys(',
          '.deleteGroup(',
        ]) {
          if (section.contains(bypass)) {
            violations.add('device-driver-bypass:${bounds.$1}:$bypass');
          }
        }
        if (!section.contains('stack.durableGroupExitDriver.requestLeave(')) {
          violations.add('device-driver-anchor:${bounds.$1}');
        }
      }
    }

    const retainedSelectors = <String, List<String>>{
      'test/features/groups/integration/group_membership_smoke_test.dart': <String>[
        'sole admin cannot leave while only writer members remain',
        'GM-015 creator/admin self-removal and leave are blocked with healthy writers',
        'multi-admin leave keeps remaining admin healthy and synchronized',
        'writer leave emits a durable left-the-group event for remaining members',
      ],
      'test/features/groups/integration/group_startup_rejoin_smoke_test.dart':
          <String>[
            'GM-016 deleted removed-member state is not rejoined from stale pubsub state',
          ],
      'test/features/groups/application/member_removal_integration_test.dart':
          <String>[
            'GM-015 blocked creator leave keeps remaining-member sends healthy',
            'voluntary leave rotation excludes leaver and remaining members send on rotated epoch',
          ],
      'test/features/groups/integration/group_edge_cases_smoke_test.dart': <String>[
        'DTR-10 durable voluntary leave stops delivery and cleans leaver history',
      ],
      'test/integration/group_multi_party_device_criteria_test.dart': <String>[
        'accepts H-01 exact durable exit evidence',
        'rejects H-01 missing or duplicate durable exit phases',
        'accepts GM-015 durable last-admin refusal evidence',
        'rejects GM-015 post-authority durable or native work',
      ],
    };
    for (final entry in retainedSelectors.entries) {
      final source = requiredSource(entry.key);
      if (source == null) continue;
      for (final selector in entry.value) {
        if (!source.contains(selector)) {
          violations.add('retained-selector:${entry.key}:$selector');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'DTR10-RED: dormant leave artifacts, manual proof bypasses, or '
          'missing strict/durable/compatibility preservation remain:\n'
          '${violations.join('\n')}',
    );
  });

  test('DTR-10 retires orphan GroupInboxCursor model only', () {
    final repo = Directory.current.absolute;
    const retiredSourcePath =
        'lib/features/groups/domain/models/group_inbox_cursor.dart';
    final manifest = RuntimeRootsManifest.loadSync(
      File('${repo.path}/tool/runtime_roots/runtime_roots.json'),
    );
    final violations = <String>[];

    if (File('${repo.path}/$retiredSourcePath').existsSync()) {
      violations.add('retired-source:$retiredSourcePath');
    }
    if (manifest.declarations.any(
      (declaration) => declaration.path == retiredSourcePath,
    )) {
      violations.add('retired-declaration:$retiredSourcePath');
    }

    const retainedAnchorsByPath = <String, List<String>>{
      'lib/core/database/migrations/066_group_sync_receipts.dart': <String>[
        'CREATE TABLE IF NOT EXISTS group_inbox_cursors (',
        "cursor TEXT NOT NULL DEFAULT ''",
        'CREATE TABLE IF NOT EXISTS group_message_receipts (',
      ],
      'lib/core/database/helpers/group_sync_receipts_db_helpers.dart': <String>[
        'Future<Map<String, Object?>?> dbLoadGroupInboxCursor(',
        'Future<void> dbUpsertGroupInboxCursor(',
        'Future<void> dbApplyGroupInboxPageTransaction(',
      ],
      'lib/features/groups/data/repositories/group_message_repository_impl.dart':
          <String>[
            'final Future<String?> Function(String groupId)? dbLoadGroupInboxCursorFn;',
            'Future<String?> getInboxCursor(String groupId) async {',
            'return fn == null ? null : fn(groupId);',
          ],
      'lib/features/groups/application/drain_group_offline_inbox_use_case.dart':
          <String>[
            "String cursor = (await msgRepo.getInboxCursor(groupId)) ?? '';",
            'await msgRepo.runInboxPageTransaction(',
          ],
      'lib/app/bootstrap/production_application_bootstrap.dart': <String>[
        'dbLoadGroupInboxCursorFn: (groupId) async {',
        'final row = await dbLoadGroupInboxCursor(executor, groupId);',
        "return row?['cursor'] as String?;",
      ],
      'lib/features/account_migration/domain/models/migration_group_manifest.dart':
          <String>['class MigrationGroupInboxCursorMetadata'],
    };
    for (final entry in retainedAnchorsByPath.entries) {
      final file = File('${repo.path}/${entry.key}');
      if (!file.existsSync()) {
        violations.add('retained-source:${entry.key}');
        continue;
      }
      final source = file.readAsStringSync();
      for (final anchor in entry.value) {
        if (!source.contains(anchor)) {
          violations.add('retained-anchor:${entry.key}:$anchor');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'DTR10-RED: the orphan cursor model/declaration remains or the live '
          'cursor persistence/composition boundary was removed:\n'
          '${violations.join('\n')}',
    );
  });

  test('DTR-04 preserves owner-gated group and posts candidates', () {
    final repo = Directory.current.absolute;
    final manifest = RuntimeRootsManifest.loadSync(
      File('${repo.path}/tool/runtime_roots/runtime_roots.json'),
    );
    final expected = <String, (String, String)>{
      'lib/features/posts/application/post_pass_follow_on_support.dart': (
        'DTR-06 / posts',
        'DTR-06 must resolve the Posts product decision before removal.',
      ),
    };

    for (final entry in expected.entries) {
      expect(File('${repo.path}/${entry.key}').existsSync(), isTrue);
      final declaration = manifest.declarations.singleWhere(
        (candidate) => candidate.path == entry.key,
      );
      expect(declaration.owner, entry.value.$1);
      expect(declaration.condition, entry.value.$2);
    }
  });

  test(
    'repository manifest accounts for current non-main sources and keeps known candidates advisory',
    () {
      final repo = Directory.current.absolute;
      final manifest = RuntimeRootsManifest.loadSync(
        File('${repo.path}/tool/runtime_roots/runtime_roots.json'),
      );
      final first = RuntimeRootInventory(
        repoRoot: repo.path,
        manifest: manifest,
      ).scan();
      final second = RuntimeRootInventory(
        repoRoot: repo.path,
        manifest: manifest,
      ).scan();

      expect(first.trustworthy, isTrue, reason: _issues(first));
      expect(first.hasDrift, isFalse, reason: _issues(first));
      expect(first.renderJson(), second.renderJson());
      expect(
        <String, RuntimeRootKind>{
          for (final entry in first.restrictedRoots) entry.id: entry.rootKind,
        },
        <String, RuntimeRootKind>{
          for (final entry in manifest.requiredRestrictedRoots)
            entry.id: entry.rootKind,
        },
      );
      expect(first.restrictedRoots.every((entry) => entry.validated), isTrue);
      expect(
        first.files
            .where((entry) => entry.disposition == ReviewDisposition.candidate)
            .map((entry) => entry.path)
            .toSet(),
        <String>{
          'lib/features/posts/application/post_pass_follow_on_support.dart',
        },
      );
      expect(
        _file(first, 'lib/core/debug/smoke_test_runner.dart').disposition,
        ReviewDisposition.retainedUnresolved,
      );
      final retainedSmokeRunner = manifest.declarations.singleWhere(
        (entry) => entry.path == 'lib/core/debug/smoke_test_runner.dart',
      );
      expect(retainedSmokeRunner.rootKinds, isEmpty);
      expect(retainedSmokeRunner.evidence, isEmpty);
      expect(retainedSmokeRunner.reason, contains('DTR13-AUTH-01'));
      expect(retainedSmokeRunner.condition, contains('current uncalled state'));
      for (final path in RuntimeRootInventory.allowedManualRootPaths) {
        expect(
          _file(first, path).bucket,
          ReachabilityBucket.manualRootReachable,
        );
      }
      expect(
        first.externalEntrypoints
            .firstWhere(
              (entry) => entry.path == 'test_driver/integration_test.dart',
            )
            .invoked,
        isTrue,
      );
      final retiredDtr03Paths = <String>{
        <String>['lib/core/services/', 'chat_', 'message.dart'].join(),
        <String>[
          'lib/core/services/',
          'contact_request_',
          'listener.dart',
        ].join(),
      };
      expect(
        first.files
            .map((entry) => entry.path)
            .toSet()
            .intersection(retiredDtr03Paths),
        isEmpty,
        reason: 'DTR-03 retired paths must be absent from the final tree',
      );
    },
  );
}

class _Fixture {
  _Fixture(Map<String, String> files)
    : directory = Directory.systemTemp.createTempSync(
        'runtime roots fixture ',
      ) {
    for (final entry in files.entries) {
      write(entry.key, entry.value);
    }
  }

  final Directory directory;

  void write(String path, String contents) {
    final file = File(
      '${directory.path}/${path.replaceAll('/', Platform.pathSeparator)}',
    );
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
  }

  String read(String path) => File(
    '${directory.path}/${path.replaceAll('/', Platform.pathSeparator)}',
  ).readAsStringSync();

  List<String> get paths {
    final result = <String>[];
    for (final entity in directory.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File && entity is! Link) continue;
      result.add(
        entity.path
            .substring(directory.path.length + 1)
            .replaceAll(Platform.pathSeparator, '/'),
      );
    }
    result.sort();
    return result;
  }

  RuntimeRootInventoryResult scan([Map<String, Object?>? manifestJson]) =>
      RuntimeRootInventory(
        repoRoot: directory.path,
        manifest: RuntimeRootsManifest.fromJsonString(
          jsonEncode(manifestJson ?? _manifest()),
        ),
        gitPathLister: (_) => paths,
      ).scan();

  void dispose() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }
}

DartFileInventory _file(RuntimeRootInventoryResult result, String path) =>
    result.files.firstWhere((entry) => entry.path == path);

String _issues(RuntimeRootInventoryResult result) =>
    result.issues.map((entry) => '${entry.code}:${entry.path}').join(', ');

Map<String, Object?> _manifest({
  List<Map<String, Object?>> manualRoots = const <Map<String, Object?>>[],
  List<Map<String, Object?>> externalEntrypoints =
      const <Map<String, Object?>>[],
  List<Map<String, Object?>> declarations = const <Map<String, Object?>>[],
  List<Map<String, Object?>>? requiredRestrictedRoots,
  List<Map<String, Object?>> restrictedRoots = const <Map<String, Object?>>[],
}) => <String, Object?>{
  'schemaVersion': 1,
  'manualRoots': manualRoots,
  'externalEntrypoints': externalEntrypoints,
  'declarations': declarations,
  'requiredRestrictedRoots':
      requiredRestrictedRoots ??
      restrictedRoots
          .map(
            (entry) => <String, Object?>{
              'id': entry['id'],
              'rootKind': entry['rootKind'],
            },
          )
          .toList(),
  'restrictedRoots': restrictedRoots,
};

List<Map<String, Object?>> _manualRoots() => RuntimeRootInventory
    .allowedManualRootPaths
    .map(
      (path) => <String, Object?>{
        'path': path,
        'owner': 'DTR-13 / QA+release',
        'reason': 'Fixture manual root.',
        'condition': 'Fixture replacement proof.',
      },
    )
    .toList();

Map<String, Object?> _external(
  String path, {
  bool seedsTooling = false,
  List<Map<String, Object?>>? evidence,
}) => <String, Object?>{
  'path': path,
  'owner': 'QA / release',
  'reason': 'Fixture external entrypoint.',
  'condition': 'Fixture replacement proof.',
  'seedsTooling': seedsTooling,
  'evidence':
      evidence ??
      <Map<String, Object?>>[
        <String, Object?>{'kind': 'dart-main', 'source': path},
      ],
};

Map<String, Object?> _declaration(
  String path, {
  required String disposition,
  List<String> rootKinds = const <String>[],
  List<Map<String, Object?>> evidence = const <Map<String, Object?>>[],
}) => <String, Object?>{
  'path': path,
  'rootKinds': rootKinds,
  'disposition': disposition,
  'owner': 'Fixture owner',
  'reason': 'Fixture reviewed reason.',
  'condition': 'Fixture removal or revisit condition.',
  'evidence': evidence,
};

Map<String, Object?> _restricted(
  String id,
  String path,
  String rootKind,
  List<Map<String, Object?>> evidence,
) => <String, Object?>{
  'id': id,
  'path': path,
  'rootKind': rootKind,
  'owner': 'Fixture owner',
  'reason': 'Fixture restricted-root reason.',
  'condition': 'Fixture replacement condition.',
  'evidence': evidence,
};
