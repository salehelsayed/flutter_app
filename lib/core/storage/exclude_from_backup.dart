import 'dart:io';

import 'package:flutter/services.dart';

const _channel = MethodChannel('mknoon/gemma_preview');

/// Marks [path] and everything under it as excluded from iCloud backup.
///
/// Returns true only when iOS confirms the exclusion. Android backup is off
/// app-wide in the manifest rules, so other platforms report true.
Future<bool> excludeDirectoryFromBackup(String path) async {
  if (!Platform.isIOS) return true;
  return await _channel.invokeMethod<bool>('excludeFromBackup', {
        'path': path,
      }) ==
      true;
}
