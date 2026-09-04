import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/call/domain/call_wake_handle_grant.dart';
import 'package:flutter_app/features/call/domain/received_call_wake_handle_store.dart';

const receivedCallWakeHandlesSecureStorageKey =
    'vc2_received_call_wake_handles_v1';

final class ReceivedCallWakeHandleStoreImpl
    implements ReceivedCallWakeHandleStore {
  ReceivedCallWakeHandleStoreImpl({required SecureKeyStore secureKeyStore})
    : _secureKeyStore = secureKeyStore;

  final SecureKeyStore _secureKeyStore;
  Map<String, CallWakeHandleGrant>? _cache;
  Future<Map<String, CallWakeHandleGrant>>? _loading;
  Future<void> _mutationTail = Future<void>.value();

  @override
  Future<CallWakeHandleGrant?> readForIssuer(String issuerAccountPeerId) async {
    await _mutationTail;
    return (await _ensureLoaded())[issuerAccountPeerId];
  }

  @override
  Future<bool> storeIfStrictlyNewer({
    required String issuerAccountPeerId,
    required CallWakeHandleGrant grant,
    required int nowMs,
  }) => _mutate<bool>((grants) async {
    if (!CallWakeHandleGrant.hasValidPeerIdGrammar(issuerAccountPeerId) ||
        !grant.isValidAt(nowMs)) {
      return false;
    }
    final prior = grants[issuerAccountPeerId];
    if (prior != null && !grant.isStrictlyNewerThan(prior)) {
      return false;
    }
    grants[issuerAccountPeerId] = grant;
    await _persist(grants);
    return true;
  });

  @override
  Future<void> removeForIssuer(String issuerAccountPeerId) =>
      _mutate<void>((grants) async {
        if (grants.remove(issuerAccountPeerId) != null) {
          await _persist(grants);
        }
      });

  @override
  Future<void> clear() => _mutate<void>((grants) async {
    grants.clear();
    await _secureKeyStore.delete(receivedCallWakeHandlesSecureStorageKey);
  });

  Future<Map<String, CallWakeHandleGrant>> _ensureLoaded() {
    final cached = _cache;
    if (cached != null) return Future.value(cached);
    return _loading ??= _load();
  }

  Future<Map<String, CallWakeHandleGrant>> _load() async {
    try {
      final raw = await _secureKeyStore.read(
        receivedCallWakeHandlesSecureStorageKey,
      );
      if (raw == null || raw.isEmpty) {
        return _cache = <String, CallWakeHandleGrant>{};
      }
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map ||
            decoded.length != 2 ||
            decoded['version'] != 1 ||
            decoded['grants'] is! Map) {
          throw const FormatException();
        }
        final grants = <String, CallWakeHandleGrant>{};
        for (final entry in (decoded['grants']! as Map).entries) {
          if (entry.key is! String ||
              grants.containsKey(entry.key) ||
              !CallWakeHandleGrant.hasValidPeerIdGrammar(
                entry.key! as String,
              )) {
            throw const FormatException();
          }
          grants[entry.key! as String] = CallWakeHandleGrant.fromCanonicalMap(
            entry.value,
          );
        }
        return _cache = grants;
      } catch (_) {
        await _secureKeyStore.delete(receivedCallWakeHandlesSecureStorageKey);
        return _cache = <String, CallWakeHandleGrant>{};
      }
    } finally {
      _loading = null;
    }
  }

  Future<void> _persist(Map<String, CallWakeHandleGrant> grants) async {
    if (grants.isEmpty) {
      await _secureKeyStore.delete(receivedCallWakeHandlesSecureStorageKey);
      return;
    }
    final encodedGrants = SplayTreeMap<String, Object>.from(
      grants.map(
        (issuerPeerId, grant) => MapEntry(issuerPeerId, grant.toCanonicalMap()),
      ),
    );
    await _secureKeyStore.write(
      receivedCallWakeHandlesSecureStorageKey,
      jsonEncode(<String, Object>{'version': 1, 'grants': encodedGrants}),
    );
  }

  Future<T> _mutate<T>(
    Future<T> Function(Map<String, CallWakeHandleGrant>) action,
  ) {
    final completer = Completer<T>();
    _mutationTail = _mutationTail.then<void>((_) async {
      try {
        final staged = Map<String, CallWakeHandleGrant>.of(
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
