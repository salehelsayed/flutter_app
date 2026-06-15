import 'dart:convert';

import 'package:flutter_app/features/account_migration/domain/models/migration_qr_payload.dart';

typedef MigrationQrScannedHandler = Future<void> Function(String qrData);

bool isAccountMigrationPairingQr(String qrData) {
  try {
    final decoded = jsonDecode(qrData);
    return decoded is Map<String, dynamic> &&
        decoded['kind'] == accountMigrationPairingQrKind;
  } catch (_) {
    return false;
  }
}
