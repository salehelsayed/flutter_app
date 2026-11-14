import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/config/custom_stickers_flag.dart';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/features/account_migration/domain/models/account_migration_authority_state.dart';
import 'package:flutter_app/features/stickers/application/account_custom_sticker_library.dart';
import 'package:flutter_app/features/stickers/application/custom_sticker_library.dart';
import 'package:flutter_app/features/stickers/application/normalize_custom_sticker_asset.dart';
import 'package:flutter_app/features/stickers/data/sqlite_custom_sticker_library.dart';
import 'package:flutter_app/features/stickers/domain/custom_sticker.dart';
import 'package:flutter_app/features/stickers/domain/custom_sticker_asset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _progressLimit = Duration(seconds: 10);

Matcher _error(CustomStickerErrorCode code) =>
    isA<CustomStickerException>().having((error) => error.code, 'code', code);

// Attaches the error observer immediately, including while a gate is held.
final class _Probe<T> {
  _Probe(Future<T> operation) {
    result = operation.then<Object?>(
      (value) {
        completed = true;
        return value;
      },
      onError: (Object error) {
        completed = true;
        return error;
      },
    );
  }

  bool completed = false;
  late final Future<Object?> result;
}

final class _Gate {
  final entered = Completer<void>();
  final _release = Completer<void>();

  Future<void> hold() async {
    if (!entered.isCompleted) entered.complete();
    await _release.future;
  }

  Future<void> waitFor(Future<Object?> operation) => Future.any<void>([
    entered.future,
    operation.then<void>((outcome) {
      fail('Operation finished before reaching its causal gate: $outcome');
    }),
  ]).timeout(_progressLimit);

  void unblock() {
    if (!_release.isCompleted) _release.complete();
  }
}

final class _NormalizerGate {
  final gate = _Gate();
  int calls = 0;

  Future<NormalizedStickerAsset> call(
    NormalizedStickerAsset input, {
    required Directory temporaryDirectory,
  }) async {
    final callNumber = ++calls;
    final normalized = await normalizeCustomStickerAsset(
      input,
      temporaryDirectory: temporaryDirectory,
    );
    if (callNumber == 1) await gate.hold();
    return normalized;
  }
}

Future<void> _turn() => Future<void>.delayed(Duration.zero);

Future<List<String>> _files(Directory directory) async {
  if (!await directory.exists()) return <String>[];
  final entries = await directory
      .list(recursive: true, followLinks: false)
      .where((entry) => entry is File || entry is Link)
      .map((entry) => p.relative(entry.path, from: directory.path))
      .toList();
  return entries..sort();
}

/// Real DB/files/normalizer fixture. The guard models only this test's passive
/// identity, binding and migration snapshots; production policy stays in
/// bootstrap. No identity loader, network runtime, push or role gate is used.
final class _AccountFiles {
  _AccountFiles(
    this.root,
    this.documents,
    this.temporary,
    this.producer,
    this.db,
  );

  final Directory root;
  final Directory documents;
  final Directory temporary;
  final Directory producer;
  final Database db;
  final libraries = <SqliteCustomStickerLibrary>[];
  final facades = <AccountCustomStickerLibrary>[];
  final subscriptions = <StreamSubscription<void>>[];
  final gates = <_Gate>[];
  final pending = <Future<Object?>>[];
  String? peer = 'logical-account-A';
  String? binding = 'opaque-account-A';
  AccountMigrationAuthorityRecord? authority =
      const AccountMigrationAuthorityRecord(
        state: AccountMigrationAuthorityState.active,
        accountPeerId: 'logical-account-A',
      );
  int _sourceNumber = 0;

  static Future<_AccountFiles> open() async {
    final root = await Directory.systemTemp.createTemp(
      'account-sticker-lifecycle-',
    );
    final documents = await Directory(p.join(root.path, 'documents')).create();
    final temporary = await Directory(p.join(root.path, 'temporary')).create();
    final producer = await Directory(p.join(root.path, 'producer')).create();
    await File(p.join(documents.path, 'unrelated.txt'))
        .writeAsString('documents canary');
    await File(p.join(temporary.path, 'unrelated.txt'))
        .writeAsString('temporary canary');
    final db = await databaseFactoryFfiNoIsolate.openDatabase(
      p.join(root.path, 'identity.db'),
      options: OpenDatabaseOptions(
        version: currentIdentityDatabaseVersion,
        singleInstance: false,
        onCreate: runProductionOnCreate,
        onUpgrade: runProductionOnUpgrade,
      ),
    );
    return _AccountFiles(root, documents, temporary, producer, db);
  }

  _Probe<T> watch<T>(Future<T> operation) {
    final probe = _Probe(operation);
    pending.add(probe.result);
    return probe;
  }

  _Gate gate() {
    final value = _Gate();
    gates.add(value);
    return value;
  }

  _NormalizerGate normalizerGate() {
    final value = _NormalizerGate();
    gates.add(value.gate);
    return value;
  }

  AccountCustomStickerLibrary facade(
    Future<SqliteCustomStickerLibrary?> Function(bool Function()) create,
  ) {
    final value = AccountCustomStickerLibrary(
      createLibrary: create,
      enabled: true,
    );
    facades.add(value);
    return value;
  }

  SqliteCustomStickerLibrary library(
    bool Function() isCurrent, {
    _NormalizerGate? normalizer,
  }) {
    final expectedPeer = peer;
    final expectedBinding = binding;
    final value = SqliteCustomStickerLibrary(
      db: db,
      documentsDirectory: documents,
      temporaryDirectory: temporary,
      enabled: true,
      mayUseAccount: () async {
        final record = authority;
        return isCurrent() &&
            expectedPeer != null &&
            peer == expectedPeer &&
            binding == expectedBinding &&
            (record == null ||
                (!record.isFailClosed &&
                    (record.accountPeerId == null ||
                        record.accountPeerId == expectedPeer) &&
                    record.state.allowsNormalStartup));
      },
      normalizeAsset: normalizer?.call,
    );
    libraries.add(value);
    return value;
  }

  List<int> observe(Stream<void> changes, {void Function()? onDone}) {
    final events = <int>[];
    subscriptions.add(
      changes.listen((_) => events.add(events.length), onDone: onDone),
    );
    return events;
  }

  Future<NormalizedStickerAsset> input(int variant) async {
    final pixels = img.Image(width: 6, height: 4, numChannels: 4);
    for (var y = 0; y < pixels.height; y++) {
      for (var x = 0; x < pixels.width; x++) {
        pixels.setPixelRgba(x, y, 30 + x + variant * 15, 80 + y, 140, 255);
      }
    }
    final bytes = img.encodeWebP(pixels, lossless: true);
    final file = File(p.join(producer.path, 'source-${_sourceNumber++}.webp'));
    await file.writeAsBytes(bytes, flush: true);
    return NormalizedStickerAsset(
      filePath: file.path,
      sha256Hex: sha256.convert(bytes).toString(),
      mime: 'image/webp',
      byteLength: bytes.length,
      width: pixels.width,
      height: pixels.height,
      frameCount: 1,
      durationMs: 0,
    );
  }

  Future<List<Map<String, Object?>>> rows() =>
      db.query('custom_stickers', orderBy: 'position ASC, id ASC');

  void setAuthority(AccountMigrationAuthorityState state) {
    authority = AccountMigrationAuthorityRecord(
      state: state,
      accountPeerId: peer,
    );
  }

  Future<void> close() async {
    // Always release owned gates before draining, including after a RED assertion.
    for (final gate in gates) {
      gate.unblock();
    }
    await Future.wait(pending).timeout(_progressLimit);
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    for (final facade in facades) {
      await facade.retire().timeout(_progressLimit);
    }
    for (final library in libraries) {
      await library.retire().timeout(_progressLimit);
    }
    await db.close();
    await root.delete(recursive: true);
  }
}

void main() {
  sqfliteFfiInit();

  test('default-disabled facade is inert across reads subscriptions and lifecycle calls', () async {
    expect(
      kCustomStickersEnabled,
      isFalse,
      reason: 'Run the suite with the default false flag.',
    );
    var factoryCalls = 0;
    final value = AccountCustomStickerLibrary(
      createLibrary: (_) async {
        factoryCalls++;
        throw StateError(
          'Disabled code must not touch identity, DB or path providers.',
        );
      },
    );
    final events = <int>[];
    final subscription = value.changes.listen((_) => events.add(events.length));
    addTearDown(subscription.cancel);
    expect(await value.list(), isEmpty);
    const unusedAsset = NormalizedStickerAsset(
      filePath: '/never-open-disabled-source.webp',
      sha256Hex: '',
      mime: 'image/webp',
      byteLength: 0,
      width: 0,
      height: 0,
      frameCount: 1,
      durationMs: 0,
    );
    await expectLater(
      value.admit(unusedAsset),
      throwsA(_error(CustomStickerErrorCode.disabled)),
    );
    await expectLater(
      value.remove('unused'),
      throwsA(_error(CustomStickerErrorCode.disabled)),
    );
    await expectLater(
      value.reorder(const []),
      throwsA(_error(CustomStickerErrorCode.disabled)),
    );
    await expectLater(
      value.prepareSend(
        'unused',
        representation: CustomStickerSendRepresentation.canonical,
      ),
      throwsA(_error(CustomStickerErrorCode.disabled)),
    );
    await value.drainForExport();
    await value.retire();
    await value.activate();
    expect(await value.list(), isEmpty);
    await _turn();
    expect(factoryCalls, 0);
    expect(events, isEmpty);
  });

  group('real account library lifecycle', () {
    late _AccountFiles files;

    setUp(() async {
      files = await _AccountFiles.open();
    });
    tearDown(() => files.close());

    test(
      'enabled construction subscription and export drain remain lazy',
      () async {
        var calls = 0;
        final value = files.facade((isCurrent) async {
          calls++;
          return files.library(isCurrent);
        });
        files.observe(value.changes);
        final documentsBefore = await _files(files.documents);
        final temporaryBefore = await _files(files.temporary);
        await value.drainForExport();
        await _turn();
        expect(calls, 0);
        expect(await _files(files.documents), documentsBefore);
        expect(await _files(files.temporary), temporaryBefore);
        expect(await value.list(), isEmpty);
        expect(calls, 1);
      },
    );

    test(
      'concurrent first use shares one real library initialization',
      () async {
        final gate = files.gate();
        var calls = 0;
        final value = files.facade((isCurrent) async {
          calls++;
          await gate.hold();
          return files.library(isCurrent);
        });
        final source = await files.input(1);
        final listing = files.watch(value.list());
        await gate.waitFor(listing.result);
        final admission = files.watch(value.admit(source));
        await _turn();
        expect(calls, 1);
        expect(listing.completed, isFalse);
        expect(admission.completed, isFalse);
        gate.unblock();
        expect(await listing.result, isA<List<CustomSticker>>());
        expect(await admission.result, isA<CustomSticker>());
        expect(await files.rows(), hasLength(1));
        expect(files.libraries, hasLength(1));
        expect(calls, 1);
      },
    );

    test(
      'initial no-identity result is retryable without explicit activation',
      () async {
        files.peer = null;
        files.binding = null;
        files.authority = null;
        var calls = 0;
        final value = files.facade((isCurrent) async {
          calls++;
          return files.peer == null ? null : files.library(isCurrent);
        });
        await expectLater(
          value.list(),
          throwsA(_error(CustomStickerErrorCode.unavailable)),
        );
        expect(files.libraries, isEmpty);
        files.peer = 'legacy-logical-account';
        files.binding = 'opaque-legacy-account';
        // Missing migration records are legitimate for an established legacy identity.
        expect(await value.list(), isEmpty);
        final stored = await value.admit(await files.input(2));
        files.setAuthority(AccountMigrationAuthorityState.noAccount);
        expect((await value.list()).single.id, stored.id);
        expect(calls, 2);
      },
    );

    test(
      'retire before first use blocks lazy reopening until explicit activation',
      () async {
        var calls = 0;
        final value = files.facade((isCurrent) async {
          calls++;
          return files.library(isCurrent);
        });
        await value.retire();
        await expectLater(
          value.list(),
          throwsA(_error(CustomStickerErrorCode.unavailable)),
        );
        await expectLater(
          value.admit(await files.input(1)),
          throwsA(_error(CustomStickerErrorCode.unavailable)),
        );
        expect(calls, 0);
        await value.activate();
        expect(
          calls,
          1,
          reason: 'Explicit activation creates the replacement, not the next list call.',
        );
        expect(await value.list(), isEmpty);
        expect(calls, 1);
      },
    );

    test('export drain waits for normalized file work and restored authority reuses the delegate', () async {
      final gate = files.normalizerGate();
      var calls = 0;
      late bool Function() token;
      final value = files.facade((isCurrent) async {
        calls++;
        token = isCurrent;
        return files.library(isCurrent, normalizer: gate);
      });
      final events = files.observe(value.changes);
      final source = await files.input(1);
      final original = await File(source.filePath).readAsBytes();
      final temporaryBefore = await _files(files.temporary);
      final admission = files.watch(value.admit(source));
      await gate.gate.waitFor(admission.result);
      expect(
        (await _files(files.temporary)).length,
        greaterThan(temporaryBefore.length),
      );
      files.setAuthority(
        AccountMigrationAuthorityState.migrationExportingNetworkPaused,
      );
      final drained = files.watch(value.drainForExport());
      await _turn();
      expect(
        drained.completed,
        isFalse,
        reason: 'Snapshot must wait for the owned normalized file to settle.',
      );
      expect(
        token(),
        isTrue,
        reason: 'An export pause must not retire this generation.',
      );
      gate.gate.unblock();
      expect(
        await admission.result,
        _error(CustomStickerErrorCode.unavailable),
      );
      expect(await drained.result, isNull);
      await expectLater(
        value.admit(source),
        throwsA(_error(CustomStickerErrorCode.unavailable)),
      );
      expect(gate.calls, 1);
      expect(await files.rows(), isEmpty);
      expect(await _files(files.documents), ['unrelated.txt']);
      expect(await _files(files.temporary), temporaryBefore);
      expect(
        await File(source.filePath).readAsBytes(),
        orderedEquals(original),
      );
      expect(events, isEmpty);
      files.setAuthority(
        AccountMigrationAuthorityState.migrationFailedActiveRestored,
      );
      final stored = await value.admit(source);
      await _turn();
      expect((await value.list()).single.id, stored.id);
      expect(events, hasLength(1));
      expect(calls, 1);
      expect(token(), isTrue);
    });

    test('export drain waits for initialization already in flight', () async {
      final gate = files.gate();
      var calls = 0;
      final value = files.facade((isCurrent) async {
        calls++;
        await gate.hold();
        return files.library(isCurrent);
      });
      final listing = files.watch(value.list());
      await gate.waitFor(listing.result);
      files.setAuthority(
        AccountMigrationAuthorityState.migrationExportingNetworkPaused,
      );
      final drained = files.watch(value.drainForExport());
      await _turn();
      expect(drained.completed, isFalse);
      gate.unblock();
      expect(await listing.result, _error(CustomStickerErrorCode.unavailable));
      expect(await drained.result, isNull);
      files.setAuthority(
        AccountMigrationAuthorityState.migrationFailedActiveRestored,
      );
      expect(await value.list(), isEmpty);
      expect(calls, 1);
    });

    test('retire revokes the token synchronously and drains real admission cleanup', () async {
      final gate = files.normalizerGate();
      late bool Function() token;
      final value = files.facade((isCurrent) async {
        token = isCurrent;
        return files.library(isCurrent, normalizer: gate);
      });
      final events = files.observe(value.changes);
      final source = await files.input(1);
      final original = await File(source.filePath).readAsBytes();
      final temporaryBefore = await _files(files.temporary);
      final admission = files.watch(value.admit(source));
      await gate.gate.waitFor(admission.result);
      final retired = files.watch(value.retire());
      expect(
        token(),
        isFalse,
        reason: 'Revocation must precede the first await in retire.',
      );
      final refused = files.watch(value.admit(source));
      await _turn();
      expect(retired.completed, isFalse);
      expect(
        refused.completed,
        isTrue,
        reason: 'Retired admission must not wait behind old file work.',
      );
      expect(await refused.result, _error(CustomStickerErrorCode.unavailable));
      gate.gate.unblock();
      expect(
        await admission.result,
        _error(CustomStickerErrorCode.unavailable),
      );
      expect(await retired.result, isNull);
      expect(await files.rows(), isEmpty);
      expect(await _files(files.documents), ['unrelated.txt']);
      expect(await _files(files.temporary), temporaryBefore);
      expect(
        await File(source.filePath).readAsBytes(),
        orderedEquals(original),
      );
      expect(events, isEmpty);
      expect(gate.calls, 1);
      await expectLater(
        value.list(),
        throwsA(_error(CustomStickerErrorCode.unavailable)),
      );
    });

    test(
      'retire waits for and permanently retires a late-created delegate',
      () async {
        final gate = files.gate();
        final delegateClosed = Completer<void>();
        late bool Function() token;
        var calls = 0;
        final value = files.facade((isCurrent) async {
          calls++;
          token = isCurrent;
          await gate.hold();
          final library = files.library(isCurrent);
          files.observe(library.changes, onDone: delegateClosed.complete);
          return library;
        });
        final listing = files.watch(value.list());
        await gate.waitFor(listing.result);
        final retired = files.watch(value.retire());
        expect(token(), isFalse);
        await _turn();
        expect(retired.completed, isFalse);
        expect(files.libraries, isEmpty);
        gate.unblock();
        expect(
          await listing.result,
          _error(CustomStickerErrorCode.unavailable),
        );
        expect(await retired.result, isNull);
        await delegateClosed.future.timeout(_progressLimit);
        await expectLater(
          value.list(),
          throwsA(_error(CustomStickerErrorCode.unavailable)),
        );
        expect(calls, 1);
      },
    );

    test('activation after late initialization cannot publish the retired generation', () async {
      final gate = files.gate();
      final tokens = <bool Function()>[];
      var calls = 0;
      final value = files.facade((isCurrent) async {
        final call = ++calls;
        tokens.add(isCurrent);
        if (call == 1) await gate.hold();
        return files.library(isCurrent);
      });
      final oldListing = files.watch(value.list());
      await gate.waitFor(oldListing.result);
      final retired = files.watch(value.retire());
      final activated = files.watch(value.activate());
      expect(tokens.first(), isFalse);
      await _turn();
      expect(
        activated.completed,
        isFalse,
        reason: 'A successor must wait for the old retirement barrier.',
      );
      gate.unblock();
      expect(
        await oldListing.result,
        _error(CustomStickerErrorCode.unavailable),
      );
      expect(await retired.result, isNull);
      expect(await activated.result, isNull);
      expect(calls, 2);
      expect(tokens.first(), isFalse);
      expect(tokens.last(), isTrue);
      final stored = await value.admit(await files.input(3));
      expect((await value.list()).single.id, stored.id);
      await expectLater(
        files.libraries.first.list(),
        throwsA(_error(CustomStickerErrorCode.unavailable)),
      );
      expect(
        calls,
        2,
        reason: 'An old completion must not evict or overwrite its successor.',
      );
    });

    test('retire supersedes an in-flight explicit activation', () async {
      final gate = files.gate();
      final tokens = <bool Function()>[];
      final secondDelegateClosed = Completer<void>();
      var calls = 0;
      final value = files.facade((isCurrent) async {
        final call = ++calls;
        tokens.add(isCurrent);
        if (call == 2) await gate.hold();
        final library = files.library(isCurrent);
        if (call == 2) {
          files.observe(library.changes, onDone: secondDelegateClosed.complete);
        }
        return library;
      });
      expect(await value.list(), isEmpty);
      await value.retire();
      final activation = files.watch(value.activate());
      await gate.waitFor(activation.result);
      final retirement = files.watch(value.retire());
      expect(tokens.last(), isFalse);
      await _turn();
      expect(retirement.completed, isFalse);
      gate.unblock();
      expect(
        await activation.result,
        _error(CustomStickerErrorCode.unavailable),
      );
      expect(await retirement.result, isNull);
      await secondDelegateClosed.future.timeout(_progressLimit);
      await expectLater(
        value.list(),
        throwsA(_error(CustomStickerErrorCode.unavailable)),
      );
      expect(calls, 2);
      await value.activate();
      expect(calls, 3);
      expect(tokens[1](), isFalse);
      expect(tokens[2](), isTrue);
      expect(await value.list(), isEmpty);
    });

    for (final sameAccount in [false, true]) {
      final replacement = sameAccount ? 'same-account' : 'different-account';
      test(
        '$replacement replacement reaches captured references and preserves the changes subscription',
        () async {
          final tokens = <bool Function()>[];
          var calls = 0;
          final value = files.facade((isCurrent) async {
            calls++;
            tokens.add(isCurrent);
            return files.library(isCurrent);
          });
          final CustomStickerLibrary captured = value;
          final changes = captured.changes;
          var closed = false;
          final events = files.observe(changes, onDone: () => closed = true);
          final first = await captured.admit(await files.input(1));
          await _turn();
          expect(events, hasLength(1));
          final paused = changes.listen((_) {});
          files.subscriptions.add(paused);
          paused.pause();
          await value.retire().timeout(_progressLimit);
          expect(tokens.single(), isFalse);
          await _turn();
          expect(
            closed,
            isFalse,
            reason:
                'Routes retain this subscription across account activation.',
          );
          expect(identical(changes, captured.changes), isTrue);

          // Simulate a committed import AFTER retirement, on the same DB object
          // and Documents root used by production import. No migration code is mocked.
          final originalBinding = files.binding;
          await files.db.delete('custom_stickers');
          await Directory(p.join(files.documents.path, 'stickers'))
              .delete(recursive: true);
          if (!sameAccount) {
            files.peer = 'logical-account-B';
            files.binding = 'opaque-account-B';
          }
          files.setAuthority(AccountMigrationAuthorityState.active);
          final importedLibrary = files.library(() => true);
          final imported = await importedLibrary.admit(await files.input(2));
          await importedLibrary.retire();
          final importedBytes = await File(imported.asset.filePath)
              .readAsBytes();
          final eventsBeforeActivation = events.length;
          await value.activate();
          await _turn();
          expect(calls, 2);
          expect(tokens.first(), isFalse);
          expect(tokens.last(), isTrue);
          if (sameAccount) expect(files.binding, originalBinding);
          expect(identical(changes, captured.changes), isTrue);
          expect(closed, isFalse);
          expect((await captured.list()).single.id, imported.id);
          expect(await File(first.asset.filePath).exists(), isFalse);
          expect(events.length, greaterThanOrEqualTo(eventsBeforeActivation));
          final beforeMutation = events.length;
          final added = await captured.admit(await files.input(3));
          await _turn();
          expect(
            events.length,
            beforeMutation + 1,
            reason: 'The original subscriber must receive the new delegate event exactly once.',
          );
          await captured.reorder([imported.id, added.id]);
          expect((await captured.list()).map((item) => item.id), [
            imported.id,
            added.id,
          ]);
          final sent = await captured.prepareSend(
            imported.id,
            representation: CustomStickerSendRepresentation.canonical,
          );
          expect(sent.file.path, isNot(imported.asset.filePath));
          expect(await sent.file.readAsBytes(), orderedEquals(importedBytes));
          await sent.file.delete();
          await captured.remove(added.id);
          expect((await captured.list()).single.id, imported.id);
          paused.resume();
          await _turn();
          expect(closed, isFalse);
          expect(
            await File(p.join(files.documents.path, 'unrelated.txt'))
                .readAsString(),
            'documents canary',
          );
          expect(
            await File(p.join(files.temporary.path, 'unrelated.txt'))
                .readAsString(),
            'temporary canary',
          );
        },
      );
    }

    for (final throwsDuringActivation in [false, true]) {
      final cause = throwsDuringActivation ? 'throwing' : 'empty';
      test(
        'failed $cause activation stays closed until explicit retry',
        () async {
          var failActivation = false;
          var calls = 0;
          final tokens = <bool Function()>[];
          final value = files.facade((isCurrent) async {
            calls++;
            tokens.add(isCurrent);
            if (failActivation) {
              if (throwsDuringActivation) {
                throw StateError('private provider failure details');
              }
              return null;
            }
            return files.library(isCurrent);
          });
          expect(await value.list(), isEmpty);
          await value.retire();
          failActivation = true;
          await expectLater(
            value.activate(),
            throwsA(_error(CustomStickerErrorCode.unavailable)),
          );
          expect(calls, 2);
          expect(tokens[1](), isFalse);
          failActivation = false;
          await expectLater(
            value.list(),
            throwsA(_error(CustomStickerErrorCode.unavailable)),
          );
          await expectLater(
            value.admit(await files.input(1)),
            throwsA(_error(CustomStickerErrorCode.unavailable)),
          );
          await expectLater(
            value.prepareSend(
              'old-id',
              representation: CustomStickerSendRepresentation.canonical,
            ),
            throwsA(_error(CustomStickerErrorCode.unavailable)),
          );
          await value.drainForExport();
          expect(
            calls,
            2,
            reason: 'Ordinary operations and export drain must not reopen a failed activation.',
          );
          expect(await files.rows(), isEmpty);
          expect(await _files(files.documents), ['unrelated.txt']);
          expect(await _files(files.temporary), ['unrelated.txt']);
          await value.activate();
          expect(calls, 3);
          expect(tokens[1](), isFalse);
          expect(tokens[2](), isTrue);
          expect(await value.list(), isEmpty);
        },
      );
    }

    test('initial factory failure is unavailable and cannot reopen by ordinary calls', () async {
      var calls = 0;
      var failFactory = true;
      final value = files.facade((isCurrent) async {
        calls++;
        if (failFactory) throw StateError('private identity provider failure');
        return files.library(isCurrent);
      });
      await expectLater(
        value.list(),
        throwsA(_error(CustomStickerErrorCode.unavailable)),
      );
      failFactory = false;
      await expectLater(
        value.list(),
        throwsA(_error(CustomStickerErrorCode.unavailable)),
      );
      expect(calls, 1);
      await value.activate();
      expect(calls, 2);
      expect(await value.list(), isEmpty);
    });
  });
}
