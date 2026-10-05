#!/usr/bin/env python3
"""Snapshot only the production sources needed by the isolated iPhone fixture.

UI automation cannot inspect flock or pause a production callback. This adapter
provides those observations in its own container; Appium/Maestro own the UI.
It never signs, installs, or touches an existing app.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess


ROOT = Path(__file__).resolve().parents[2]
ENTRY = ROOT / 'integration_test/notification_lock_fixture.dart'
FIXTURE_GROUP = 'group.com.mknoon.fixture.notificationLock'
FIXTURE_BUNDLE = 'com.mknoon.fixture.notificationLockFixture'


def prepare_shared_boundary(destination, native, receipt):
    """Prepare an unsigned isolated Runner/NSE pair; never provision or install."""
    old = '''result(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
          .appendingPathComponent("NotificationLockFixture").path)'''
    replacement = f'''guard let root = FileManager.default.containerURL(
          forSecurityApplicationGroupIdentifier: "{FIXTURE_GROUP}") else {{
          return result(FlutterError(code: "fixture_group_unavailable",
            message: "Isolated fixture App Group entitlement unavailable", details: nil))
        }}
        result(root.appendingPathComponent("NotificationLockFixture").path)'''
    if native.count(old) != 1:
        raise ValueError('Fixture directory adapter changed; review the shared variant')
    native = native.replace(old, replacement)
    entry = '  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {'
    native = native.replace(entry, entry + '\n    UIApplication.shared.registerForRemoteNotifications()')
    delegate = '''
  override func application(_ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent(".fixture-apns-token")
    let token = deviceToken.map { String(format: "%02x", $0) }.joined()
    try? Data(token.utf8).write(to: file, options: .atomic)
    try? FileManager.default.setAttributes([.posixPermissions: 0o600,
      .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: file.path)
  }
'''
    native = native.replace('  private var admission = true', delegate + '\n  private var admission = true')
    service_dir = destination / 'ios/FixtureNotificationService'
    service_dir.mkdir(exist_ok=True)
    service = ROOT / 'integration_test/support/notification_lock_fixture_service.swift'
    snapshot = ROOT / 'ios/NotificationService/IosAppVisibilitySnapshot.swift'
    for source in (service, snapshot):
        shutil.copyfile(source, service_dir / source.name)
        receipt[str(source.relative_to(ROOT))] = hashlib.sha256(source.read_bytes()).hexdigest()
    service_info = {
        'CFBundleIdentifier': '$(PRODUCT_BUNDLE_IDENTIFIER)',
        'CFBundleExecutable': '$(EXECUTABLE_NAME)',
        'CFBundleName': '$(PRODUCT_NAME)', 'CFBundlePackageType': 'XPC!',
        'CFBundleShortVersionString': '1.0.0', 'CFBundleVersion': '1',
        'FixtureAppGroup': FIXTURE_GROUP,
        'NSExtension': {'NSExtensionPointIdentifier': 'com.apple.usernotifications.service',
                        'NSExtensionPrincipalClass': 'NotificationService'},
    }
    groups = {'com.apple.security.application-groups': [FIXTURE_GROUP]}
    (service_dir / 'Info.plist').write_bytes(plistlib.dumps(service_info))
    (service_dir / 'FixtureBoundary.entitlements').write_bytes(plistlib.dumps(groups))
    runner = destination / 'ios/Runner'
    (runner / 'FixtureBoundary.entitlements').write_bytes(plistlib.dumps({
        **groups, 'aps-environment': 'development'}))
    info = plistlib.loads((runner / 'Info.plist').read_bytes())
    info['FixtureAppGroup'] = FIXTURE_GROUP
    (runner / 'Info.plist').write_bytes(plistlib.dumps(info))
    ruby = '''
      project = Xcodeproj::Project.open(ARGV[0])
      runner = project.targets.find { |t| t.name == 'Runner' }
      extension = project.targets.find { |t| t.name == 'FixtureNotificationService' }
      unless extension
        extension = project.new_target(:app_extension, 'FixtureNotificationService', :ios, '15.0')
        group = project.main_group.new_group('FixtureNotificationService', 'FixtureNotificationService')
        extension.add_file_references(['notification_lock_fixture_service.swift',
          'IosAppVisibilitySnapshot.swift'].map { |name| group.new_file(name) })
      end
      extension.build_configurations.each do |config|
        config.build_settings.merge!({
          'PRODUCT_BUNDLE_IDENTIFIER' => ARGV[1] + '.NotificationService',
          'PRODUCT_NAME' => 'FixtureNotificationService',
          'PRODUCT_MODULE_NAME' => 'FixtureNotificationService',
          'INFOPLIST_FILE' => 'FixtureNotificationService/Info.plist',
          'CODE_SIGN_ENTITLEMENTS' => 'FixtureNotificationService/FixtureBoundary.entitlements',
          'CODE_SIGN_STYLE' => 'Manual', 'SWIFT_VERSION' => '5.0',
          'APPLICATION_EXTENSION_API_ONLY' => 'YES', 'SKIP_INSTALL' => 'YES',
          'TARGETED_DEVICE_FAMILY' => '1,2', 'CURRENT_PROJECT_VERSION' => '1',
          'MARKETING_VERSION' => '1.0.0'})
      end
      runner.build_configurations.each do |config|
        config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Runner/FixtureBoundary.entitlements'
        config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = ARGV[1]
      end
      runner.add_dependency(extension) unless runner.dependencies.any? { |d| d.target == extension }
      embed = runner.copy_files_build_phases.find { |p| p.name == 'Embed Fixture Notification Service' }
      embed ||= runner.new_copy_files_build_phase('Embed Fixture Notification Service')
      embed.dst_subfolder_spec = '13'
      unless embed.files.any? { |f| f.file_ref == extension.product_reference }
        embed.add_file_reference(extension.product_reference).settings = {
          'ATTRIBUTES' => ['RemoveHeadersOnCopy', 'CodeSignOnCopy']}
      end
      # Flutter's thinning phase scans the final app, including PlugIns. Copy
      # the extension first to avoid an Info.plist/thinning dependency cycle.
      thin = runner.shell_script_build_phases.find { |p| p.name == 'Thin Binary' }
      if thin
        runner.build_phases.delete(embed)
        runner.build_phases.insert(runner.build_phases.index(thin), embed)
      end
      project.save
    '''
    project = destination / 'ios/Runner.xcodeproj'
    # Idempotence: regeneration updates configuration without duplicate targets.
    subprocess.run(['ruby', '-rxcodeproj', '-e', ruby, str(project), FIXTURE_BUNDLE], check=True)
    (destination / 'shared-boundary-proposal.json').write_text(json.dumps({
        'runner': FIXTURE_BUNDLE, 'nse': FIXTURE_BUNDLE + '.NotificationService',
        'appGroup': FIXTURE_GROUP, 'signingRequired': True,
        'status': 'prepared_unsigned_not_provisioned_not_installed',
        'payload': {'aps': {'alert': {'title': 'Fixture probe', 'body': 'Fixture probe'},
                            'mutable-content': 1}, 'fixture': 'notification-lock-v1',
                    'probe': '<64 lowercase hex characters>'},
        'limits': 'Shared production guard in an actual NSE, not full production APNs/business-effect certification',
        'generatedRunnerSourceSha256': hashlib.sha256(native.encode()).hexdigest(),
    }, indent=2) + '\n')
    return native


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--destination', required=True, type=Path)
    parser.add_argument('--shared-boundary', action='store_true',
                        help='Prepare unsigned isolated App Group/NSE configuration; no provisioning')
    args = parser.parse_args()
    destination = args.destination.resolve()
    artifacts = (ROOT / '.codex-test-logs').resolve()
    if artifacts not in destination.parents or destination.is_symlink():
        parser.error('destination must be inside the ignored .codex-test-logs directory')
    if not (destination / 'pubspec.yaml').exists():
        subprocess.run(['flutter', 'create', '--platforms=ios',
                        '--project-name', 'notification_lock_fixture', '--org',
                        'com.mknoon.fixture', str(destination)], check=True)
    pending, sources, packages = [ENTRY], set(), set()
    while pending:
        source = pending.pop().resolve()
        if source in sources:
            continue
        sources.add(source)
        for uri in re.findall(r"(?:import|export)\s+['\"]([^'\"]+)", source.read_text()):
            if uri.startswith('package:flutter_app/'):
                pending.append(ROOT / 'lib' / uri.removeprefix('package:flutter_app/'))
            elif uri.startswith('package:'):
                packages.add(uri.split(':')[1].split('/')[0])
            elif not uri.startswith('dart:'):
                pending.append(source.parent / uri)
    receipt = {}
    for source in sorted(sources):
        target = destination / ('lib/main.dart' if source == ENTRY else source.relative_to(ROOT))
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(source.read_bytes())
        receipt[str(source.relative_to(ROOT))] = hashlib.sha256(source.read_bytes()).hexdigest()
    locked = ROOT.joinpath('pubspec.lock').read_text()
    dependencies = ['  flutter:', '    sdk: flutter']
    for package in sorted(packages - {'flutter'}):
        block = re.search(r'^  ' + re.escape(package) + r':\n(.*?)(?=^  \w|\Z)', locked, re.M | re.S)
        version = re.search(r'^    version: "([^"]+)"', block[1], re.M)[1]
        dependencies.append(f'  {package}: {version}')
    (destination / 'pubspec.yaml').write_text(
        'name: flutter_app\npublish_to: none\nversion: 1.0.0+1\n'
        'environment:\n  sdk: ">=3.9.0 <4.0.0"\ndependencies:\n' +
        '\n'.join(dependencies) + '\nflutter:\n  uses-material-design: true\n')
    bridge = ROOT / 'ios/Runner/GoBridge.swift'
    snapshot = ROOT / 'ios/NotificationService/IosAppVisibilitySnapshot.swift'
    adapter = ROOT / 'integration_test/support/notification_lock_fixture_native.swift'
    native = bridge.read_text().split('#if canImport(GoMknoon)')[0]
    native += '\n' + snapshot.read_text() + '\n' + adapter.read_text()
    if args.shared_boundary:
        native = prepare_shared_boundary(destination, native, receipt)
    (destination / 'ios/Runner/AppDelegate.swift').write_text(native)
    for source in (bridge, snapshot, adapter):
        receipt[str(source.relative_to(ROOT))] = hashlib.sha256(source.read_bytes()).hexdigest()
    (destination / 'source-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(f'Snapshotted {len(sources)} Dart sources; plugins: {sorted(packages)}')
    subprocess.run(['flutter', 'pub', 'get'], cwd=destination, check=True)


if __name__ == '__main__':
    main()
