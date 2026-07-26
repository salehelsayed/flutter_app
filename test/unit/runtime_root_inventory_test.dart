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
      ];
      final green = fixture.scan(_manifest(restrictedRoots: restricted));
      expect(
        green.issues.where((entry) => entry.code.contains('callback')),
        isEmpty,
        reason: _issues(green),
      );
      expect(green.restrictedRoots, hasLength(2));
      expect(green.restrictedRoots.every((entry) => entry.validated), isTrue);
      expect(
        <String, RuntimeRootKind>{
          for (final entry in green.restrictedRoots) entry.id: entry.rootKind,
        },
        <String, RuntimeRootKind>{
          'callback.test-config': RuntimeRootKind.conventionCallback,
          'callback.vm': RuntimeRootKind.vmCallback,
        },
      );

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

  test('DTR-04 preserves owner-gated group and posts candidates', () {
    final repo = Directory.current.absolute;
    final manifest = RuntimeRootsManifest.loadSync(
      File('${repo.path}/tool/runtime_roots/runtime_roots.json'),
    );
    final expected = <String, (String, String)>{
      'lib/features/groups/domain/models/group_inbox_cursor.dart': (
        'DTR-10 / groups',
        'DTR-10 must resolve group compatibility ownership before removal.',
      ),
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
          'lib/features/groups/domain/models/group_inbox_cursor.dart',
          'lib/features/posts/application/post_pass_follow_on_support.dart',
        },
      );
      expect(
        _file(first, 'lib/core/debug/smoke_test_runner.dart').disposition,
        ReviewDisposition.retainedUnresolved,
      );
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
