import 'dart:io';

import 'package:flutter_app/core/config/custom_stickers_flag.dart';
import 'package:flutter_app/features/account_migration/domain/models/account_migration_authority_state.dart';
import 'package:flutter_app/features/stickers/data/sqlite_custom_sticker_library.dart';
import 'package:sqflite_common/sqlite_api.dart';

/// RED scaffold. The account facade supplies its generation token; bootstrap
/// supplies passive authority/binding readers. This is not wired into startup.
Future<SqliteCustomStickerLibrary?> createBoundCustomStickerLibrary({
  required Database db,
  required Directory documentsDirectory,
  required Future<Directory> Function() temporaryDirectory,
  required Future<AccountMigrationAuthorityRecord?> Function() readAuthority,
  required bool Function() isCurrent,
  Future<String?> Function()? readAccountBinding,
  bool enabled = kCustomStickersEnabled,
}) async => null;
