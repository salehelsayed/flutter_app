// ⚠️ TEMPORARY DEV-ONLY — one-shot Keychain / EncryptedSharedPreferences wipe.
// Purpose: get a *truly* fresh install (uninstall does NOT clear the Keychain).
// DELETE this file and its call in main.dart when you're done.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'flutter_secure_key_store.dart' show mknoonSharedAppleAccessGroup;

/// Wipes every secure-storage entry exactly once, then drops a marker file so
/// it never runs again — otherwise it would nuke the identity you create on the
/// very next relaunch.
///
/// Clears BOTH keychain access groups this app uses:
///   - the default group (identity secrets, db_encryption_key, sentinels)
///   - the shared push group ([mknoonSharedAppleAccessGroup])
///
/// The marker lives in [docDirPath] (the app sandbox), which iOS clears on
/// uninstall — so a future reinstall correctly re-arms the one-shot.
Future<void> wipeKeychainOnce(String docDirPath) async {
  if (!kDebugMode) {
    return; // never wipe a release build's keychain
  }

  final marker = File('$docDirPath/.dev_keychain_wiped');
  if (await marker.exists()) {
    return;
  }

  // Default keychain access group (no groupId).
  await const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  ).deleteAll();

  // Shared push-token keychain access group.
  await const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
      groupId: mknoonSharedAppleAccessGroup,
    ),
  ).deleteAll();

  await marker.writeAsString('wiped');
  debugPrint(
    '⚠️  DEV: Keychain wiped (one-shot). Remove dev_keychain_wipe.dart now.',
  );
}
