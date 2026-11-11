import 'dart:async';
import 'dart:io';

import 'package:flutter_app/app/bootstrap/custom_sticker_library_composition.dart';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_authority_repository_impl.dart';
import 'package:flutter_app/features/account_migration/domain/models/account_migration_authority_state.dart';
import 'package:flutter_app/features/stickers/data/sqlite_custom_sticker_library.dart';
import 'package:flutter_app/features/stickers/domain/custom_sticker_asset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../secure_storage/fake_secure_key_store.dart';

Matcher get unavailable => throwsA(
  isA<CustomStickerException>().having(
    (error) => error.code,
    'code',
    CustomStickerErrorCode.unavailable,
  ),
);

void main() {
  sqfliteFfiInit();
  late Directory root;
  late Directory documents;
  late Directory temporary;
  late Database db;
  late FakeSecureKeyStore keys;
  late SecureKeyStoreAccountMigrationAuthorityRepository authority;
  final delegates = <SqliteCustomStickerLibrary>[];
  var current = true;
  String? binding = 'binding-A';
  var temporaryCalls = 0;
  var authorityReads = 0;
  var bindingReads = 0;

  Future<void> setAuthority(AccountMigrationAuthorityState state) =>
      authority.saveAuthority(
        AccountMigrationAuthorityRecord(
          state: state,
          accountPeerId: 'account-A',
        ),
      );

  Future<SqliteCustomStickerLibrary?> create({
    bool enabled = true,
    bool mobileBinding = true,
    Future<Directory> Function()? temporaryProvider,
    Future<String?> Function()? bindingProvider,
  }) async {
    final value = await createBoundCustomStickerLibrary(
      db: db,
      documentsDirectory: documents,
      temporaryDirectory:
          temporaryProvider ??
          () async {
            temporaryCalls++;
            return temporary;
          },
      readAuthority: () async {
        authorityReads++;
        return authority.loadAuthority();
      },
      isCurrent: () => current,
      readAccountBinding: !mobileBinding
          ? null
          : bindingProvider ??
                () async {
                  bindingReads++;
                  return binding;
                },
      enabled: enabled,
    );
    if (value != null) delegates.add(value);
    return value;
  }

  Future<SqliteCustomStickerLibrary> ready({bool mobileBinding = true}) async {
    final value = await create(mobileBinding: mobileBinding);
    expect(
      value,
      isNotNull,
      reason: 'A committed local account must have a library.',
    );
    expect(await value!.list(), isEmpty);
    return value;
  }

  setUp(() async {
    current = true;
    binding = 'binding-A';
    temporaryCalls = authorityReads = bindingReads = 0;
    delegates.clear();
    root = await Directory.systemTemp.createTemp('sticker-composition-');
    documents = await Directory(p.join(root.path, 'documents')).create();
    temporary = await Directory(p.join(root.path, 'temporary')).create();
    await File(p.join(documents.path, 'canary')).writeAsString('keep');
    db = await databaseFactoryFfiNoIsolate.openDatabase(
      p.join(root.path, 'identity.db'),
      options: OpenDatabaseOptions(
        version: currentIdentityDatabaseVersion,
        singleInstance: false,
        onCreate: runProductionOnCreate,
        onUpgrade: runProductionOnUpgrade,
      ),
    );
    await db.insert('identity', {
      'id': 1,
      'peer_id': 'account-A',
      'public_key': 'public-A',
      'private_key': '',
      'mnemonic12': '',
      'username': 'Alice',
      'created_at': '2026-11-11T00:00:00Z',
      'updated_at': '2026-11-11T00:00:00Z',
    });
    keys = FakeSecureKeyStore();
    authority = SecureKeyStoreAccountMigrationAuthorityRepository(
      secureKeyStore: keys,
    );
    await setAuthority(AccountMigrationAuthorityState.active);
  });

  tearDown(() async {
    for (final delegate in delegates) {
      await delegate.retire();
    }
    if (db.isOpen) await db.close();
    await root.delete(recursive: true);
  });

  test(
    'disabled composition reads no database provider binding or authority',
    () async {
      await db.close();
      await documents.delete(recursive: true);
      expect(await create(enabled: false), isNull);
      expect(authorityReads, 0);
      expect(bindingReads, 0);
      expect(temporaryCalls, 0);
      expect(await documents.exists(), isFalse);
    },
  );

  test('missing identity never opens a filesystem provider', () async {
    await db.delete('identity');
    expect(await create(), isNull);
    expect(temporaryCalls, 0);
  });

  for (final state in <AccountMigrationAuthorityState?>[
    null,
    AccountMigrationAuthorityState.noAccount,
    AccountMigrationAuthorityState.active,
    AccountMigrationAuthorityState.migrationFailedActiveRestored,
  ]) {
    test(
      'existing local identity remains eligible with authority $state',
      () async {
        if (state == null) {
          await authority.clearAuthority();
        } else {
          await setAuthority(state);
        }
        final before = await keys.readAll();
        final row = await db.query('identity');
        await ready();
        expect(temporaryCalls, 1);
        expect(
          await keys.readAll(),
          before,
          reason: 'Eligibility is a passive read.',
        );
        expect(await db.query('identity'), row);
        expect(
          await Directory(p.join(documents.path, 'stickers')).exists(),
          isFalse,
        );
      },
    );
  }

  for (final state in AccountMigrationAuthorityState.values.where(
    (state) => !state.allowsNormalStartup,
  )) {
    test(
      'a live delegate refuses $state and resumes only after restored authority',
      () async {
        final value = await ready();
        await setAuthority(state);
        await expectLater(value.list(), unavailable);
        expect(await create(), isNull);
        expect(temporaryCalls, 1);
        await setAuthority(
          AccountMigrationAuthorityState.migrationFailedActiveRestored,
        );
        expect(await value.list(), isEmpty);
        expect(
          await File(p.join(documents.path, 'canary')).readAsString(),
          'keep',
        );
      },
    );
  }

  test(
    'malformed persisted authority and another account fail closed',
    () async {
      final value = await ready();
      await keys.write(
        SecureKeyStoreAccountMigrationAuthorityRepository.storageKey,
        '{bad',
      );
      await expectLater(value.list(), unavailable);
      expect(await create(), isNull);
      await authority.saveAuthority(
        const AccountMigrationAuthorityRecord(
          state: AccountMigrationAuthorityState.active,
          accountPeerId: 'account-B',
        ),
      );
      await expectLater(value.list(), unavailable);
      expect(await create(), isNull);
      expect(temporaryCalls, 1);
    },
  );

  test(
    'replacement or deletion of the committed identity closes old access',
    () async {
      final value = await ready();
      await db.update('identity', {'peer_id': 'account-B'}, where: 'id = 1');
      await expectLater(value.list(), unavailable);
      await db.delete('identity');
      await expectLater(value.list(), unavailable);
    },
  );

  for (final replacement in <String?>[null, '', 'binding-B']) {
    test('a changed mobile binding $replacement closes old access', () async {
      final value = await ready();
      binding = replacement;
      await expectLater(value.list(), unavailable);
      if (replacement == null || replacement.isEmpty) {
        expect(await create(), isNull);
        expect(temporaryCalls, 1);
      }
    });
  }

  test('nonmobile composition uses the same identity and generation without a binding provider', () async {
    final value = await ready(mobileBinding: false);
    expect(bindingReads, 0);
    current = false;
    await expectLater(value.list(), unavailable);
    expect(await create(mobileBinding: false), isNull);
    expect(temporaryCalls, 1);
  });

  test(
    'revocation during a binding read cannot construct a stale delegate',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final operation = create(
        bindingProvider: () async {
          if (!entered.isCompleted) entered.complete();
          await release.future;
          return binding;
        },
      );
      try {
        await Future.any<void>([
          entered.future,
          operation.then(
            (_) => fail('Factory completed before the binding gate.'),
          ),
        ]).timeout(const Duration(seconds: 10));
        current = false;
      } finally {
        if (!release.isCompleted) release.complete();
      }
      expect(await operation, isNull);
      expect(temporaryCalls, 0);
    },
  );

  test('revocation during temporary-directory resolution cannot publish a stale delegate', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final operation = create(
      temporaryProvider: () async {
        temporaryCalls++;
        entered.complete();
        await release.future;
        return temporary;
      },
    );
    try {
      await Future.any<void>([
        entered.future,
        operation.then(
          (_) => fail('Factory completed before the directory gate.'),
        ),
      ]).timeout(const Duration(seconds: 10));
      current = false;
    } finally {
      if (!release.isCompleted) release.complete();
    }
    expect(await operation, isNull);
    expect(temporaryCalls, 1);
    expect(
      await Directory(p.join(documents.path, 'stickers')).exists(),
      isFalse,
    );
  });
}
