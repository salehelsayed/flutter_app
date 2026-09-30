import 'dart:io';

// Shared build preparation for existing simulator integration campaigns.
// This creates fresh role binaries; device launch stays with each campaign.
Future<String> prepareIosSimulatorHarness({
  required String role,
  required String harness,
  required List<String> dartDefines,
  required Directory sharedDirectory,
  required IOSink log,
}) async {
  stderr.writeln('Preparing iOS $role before launching timed peers');
  final build = await Process.run('flutter', <String>[
    'build',
    'ios',
    '--simulator',
    '--debug',
    '--no-pub',
    '--target=$harness',
    ...dartDefines,
  ]);
  log.writeln(build.stdout);
  log.writeln(build.stderr);
  await log.flush();
  final source = Directory('build/ios/iphonesimulator/Runner.app');
  if (build.exitCode != 0 || !source.existsSync()) {
    throw StateError('iOS $role preparation failed: exit=${build.exitCode}');
  }
  // Preserve each freshly built role before the next build replaces Runner.app.
  // Flutter drive already supports this prebuilt-binary launch path. Keeping
  // builds outside the peer run preserves the original fixture deadlines.
  final artifact = '${sharedDirectory.path}/prepared-$role/Runner.app';
  await Directory('${sharedDirectory.path}/prepared-$role').create();
  final copy = await Process.run('ditto', <String>[source.path, artifact]);
  if (copy.exitCode != 0 || !Directory(artifact).existsSync()) {
    throw StateError('Unable to preserve prepared iOS $role application');
  }
  return artifact;
}
