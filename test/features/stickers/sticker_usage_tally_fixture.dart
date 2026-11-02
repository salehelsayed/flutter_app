import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/diagnostics/app_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

final _stickerTallyDay = DateTime(2026, 11, 2, 12);
final stickerTallyDayEndMs = DateTime(2026, 11, 3).millisecondsSinceEpoch - 1;

/// Installs a consenting diagnostics collector in a temp dir, so a widget
/// built without a recorder tallies through its production default.
Future<Directory> installStickerDiagnostics(WidgetTester tester) async {
  final directory = Directory.systemTemp.createTempSync('sticker_tally_');
  await tester.runAsync(
    () => AppDiagnostics.installForTesting(
      directory: directory,
      now: () => _stickerTallyDay,
    ),
  );
  addTearDown(() {
    unawaited(
      AppDiagnostics.instance.dispose().whenComplete(() {
        if (directory.existsSync()) directory.deleteSync(recursive: true);
      }),
    );
  });
  return directory;
}

Future<Object?> stickerUsageTally(
  WidgetTester tester,
  Directory directory,
) async => (await tester.runAsync(() async {
  await AppDiagnostics.instance.flush();
  final state =
      jsonDecode(File('${directory.path}/state.json').readAsStringSync())
          as Map<String, dynamic>;
  await AppDiagnostics.instance.dispose();
  return state['stickerUsage'];
}));
