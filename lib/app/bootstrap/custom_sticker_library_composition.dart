import 'dart:io';

import 'package:flutter_app/core/config/custom_stickers_flag.dart';
import 'package:flutter_app/core/database/helpers/identity_db_helpers.dart';
import 'package:flutter_app/features/account_migration/domain/models/account_migration_authority_state.dart';
import 'package:flutter_app/features/stickers/data/sqlite_custom_sticker_library.dart';
import 'package:sqflite_common/sqlite_api.dart';

/// Binds one concrete library to the committed logical account and the facade's
/// generation. All account readers are passive; no identity publication or
/// transport-role startup is needed for access to this local library.
Future<SqliteCustomStickerLibrary?> createBoundCustomStickerLibrary({
  required Database db,
  required Directory documentsDirectory,
  required Future<Directory> Function() temporaryDirectory,
  required Future<AccountMigrationAuthorityRecord?> Function() readAuthority,
  required bool Function() isCurrent,
  Future<String?> Function()? readAccountBinding,
  bool enabled = kCustomStickersEnabled,
}) async {
  if (!enabled || !isCurrent()) return null;

  final identity = await dbLoadIdentityRow(db);
  if (!isCurrent()) return null;
  final expectedPeer = identity?['peer_id'];
  if (expectedPeer is! String || expectedPeer.trim().isEmpty) return null;

  final expectedBinding = readAccountBinding == null
      ? null
      : await readAccountBinding();
  if (!isCurrent()) return null;
  if (readAccountBinding != null &&
      (expectedBinding == null || expectedBinding.trim().isEmpty)) {
    return null;
  }

  Future<bool> mayUseAccount() async {
    if (!isCurrent()) return false;
    final authority = await readAuthority();
    if (!isCurrent()) return false;
    if (authority != null &&
        (authority.isFailClosed ||
            !authority.state.allowsNormalStartup ||
            (authority.accountPeerId != null &&
                authority.accountPeerId != expectedPeer))) {
      return false;
    }

    final currentIdentity = await dbLoadIdentityRow(db);
    if (!isCurrent() || currentIdentity?['peer_id'] != expectedPeer) {
      return false;
    }
    if (readAccountBinding != null) {
      final currentBinding = await readAccountBinding();
      if (!isCurrent() || currentBinding != expectedBinding) return false;
    }
    return isCurrent();
  }

  // Missing/noAccount migration records do not invalidate a committed legacy
  // identity. Export pauses and blocked migration states are rejected by the
  // fresh authority check, allowing this delegate to resume after restoration.
  if (!await mayUseAccount() || !isCurrent()) return null;
  final temporary = await temporaryDirectory();
  if (!isCurrent()) return null;
  if (!await mayUseAccount() || !isCurrent()) return null;

  return SqliteCustomStickerLibrary(
    db: db,
    documentsDirectory: documentsDirectory,
    temporaryDirectory: temporary,
    mayUseAccount: mayUseAccount,
    enabled: enabled,
  );
}
