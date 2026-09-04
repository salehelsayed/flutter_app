import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/call/domain/issued_call_wake_handle_store.dart';

const issuedCallWakeHandlesSecureStorageKey = 'vc2_issued_call_wake_handles_v1';

final class IssuedCallWakeHandleStoreImpl implements IssuedCallWakeHandleStore {
  IssuedCallWakeHandleStoreImpl({required SecureKeyStore secureKeyStore})
    : _secureKeyStore = secureKeyStore;

  final SecureKeyStore _secureKeyStore;
  Map<String, CallIssuedWakeHandleRecord>? _cache;
  Future<Map<String, CallIssuedWakeHandleRecord>>? _loading;
  Future<void> _mutationTail = Future<void>.value();

  @override
  Future<List<CallIssuedWakeHandleRecord>> readAll() async {
    await _mutationTail;
    final records = await _ensureLoaded();
    return records.values.toList(growable: false);
  }

  @override
  Future<CallIssuedWakeHandleRecord?> readForContact(
    String contactAccountPeerId,
  ) async {
    await _mutationTail;
    return (await _ensureLoaded())[contactAccountPeerId];
  }

  @override
  Future<void> write(CallIssuedWakeHandleRecord record) =>
      _mutate<void>((records) async {
        records[record.contactAccountPeerId] = record;
        await _persist(records);
      });

  @override
  Future<void> removeForContact(String contactAccountPeerId) =>
      _mutate<void>((records) async {
        if (records.remove(contactAccountPeerId) != null) {
          await _persist(records);
        }
      });

  @override
  Future<void> clear() => _mutate<void>((records) async {
    records.clear();
    await _secureKeyStore.delete(issuedCallWakeHandlesSecureStorageKey);
  });

  Future<Map<String, CallIssuedWakeHandleRecord>> _ensureLoaded() {
    final cached = _cache;
    if (cached != null) return Future.value(cached);
    return _loading ??= _load();
  }

  Future<Map<String, CallIssuedWakeHandleRecord>> _load() async {
    try {
      final raw = await _secureKeyStore.read(
        issuedCallWakeHandlesSecureStorageKey,
      );
      if (raw == null || raw.isEmpty) {
        return _cache = <String, CallIssuedWakeHandleRecord>{};
      }
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map ||
            decoded.length != 2 ||
            decoded['version'] != 1 ||
            decoded['records'] is! Map) {
          throw const FormatException();
        }
        final records = <String, CallIssuedWakeHandleRecord>{};
        for (final entry in (decoded['records']! as Map).entries) {
          if (entry.key is! String || records.containsKey(entry.key)) {
            throw const FormatException();
          }
          final record = CallIssuedWakeHandleRecord.fromCanonicalMap(
            entry.value,
          );
          if (record.contactAccountPeerId != entry.key) {
            throw const FormatException();
          }
          records[entry.key! as String] = record;
        }
        return _cache = records;
      } catch (_) {
        await _secureKeyStore.delete(issuedCallWakeHandlesSecureStorageKey);
        return _cache = <String, CallIssuedWakeHandleRecord>{};
      }
    } finally {
      _loading = null;
    }
  }

  Future<void> _persist(Map<String, CallIssuedWakeHandleRecord> records) async {
    if (records.isEmpty) {
      await _secureKeyStore.delete(issuedCallWakeHandlesSecureStorageKey);
      return;
    }
    final encodedRecords = SplayTreeMap<String, Object>.from(
      records.map(
        (contactPeerId, record) =>
            MapEntry(contactPeerId, record.toCanonicalMap()),
      ),
    );
    await _secureKeyStore.write(
      issuedCallWakeHandlesSecureStorageKey,
      jsonEncode(<String, Object>{'version': 1, 'records': encodedRecords}),
    );
  }

  Future<T> _mutate<T>(
    Future<T> Function(Map<String, CallIssuedWakeHandleRecord>) action,
  ) {
    final completer = Completer<T>();
    _mutationTail = _mutationTail.then<void>((_) async {
      try {
        final staged = Map<String, CallIssuedWakeHandleRecord>.of(
          await _ensureLoaded(),
        );
        final result = await action(staged);
        _cache = staged;
        completer.complete(result);
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}
