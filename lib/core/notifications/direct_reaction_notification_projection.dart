import 'dart:convert';

import 'package:flutter_app/core/notifications/ios_nse_inbox_projection.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';

/// Shared-Keychain records consumed by the iOS notification service extension.
///
/// The projection deliberately contains only recipient-owned display/eligibility
/// state. Reaction emoji and sender-authored display names never enter it.
const String sharedDirectReactionContactsKey = 'direct_reaction_contacts_v1';
const String sharedDirectReactionAuthoredTargetsKey =
    'direct_reaction_authored_targets_v1';
const String _simsFixtureDigestKey = 'simsFixtureDigest';

class DirectReactionNotificationProjection {
  final SecureKeyStore _store;
  final int maxAuthoredTargets;
  final int maxAuthorizedTransportsPerContact;
  Future<void> _tail = Future<void>.value();
  String? _expectedAccountPeerId;
  final Map<String, String> _simsCleanupTombstones = <String, String>{};

  DirectReactionNotificationProjection({
    required SecureKeyStore store,
    this.maxAuthoredTargets = 256,
    this.maxAuthorizedTransportsPerContact = 32,
  }) : assert(maxAuthoredTargets > 0),
       assert(maxAuthorizedTransportsPerContact > 0),
       _store = store;

  /// Establishes the account generation that owns both direct documents.
  ///
  /// A different account replaces contacts and authored targets with empty,
  /// account-bound documents before any later backfill can repopulate them.
  /// Partial shared-key writes remain fail-closed because Swift requires both
  /// direct documents and the group identity document to name the same account.
  Future<void> replaceLocalIdentity({required String? accountPeerId}) {
    final normalizedAccount = _nonEmpty(accountPeerId);
    if (_expectedAccountPeerId != normalizedAccount) {
      _simsCleanupTombstones.clear();
    }
    _expectedAccountPeerId = normalizedAccount;
    return _enqueue(() async {
      if (normalizedAccount == null) {
        await _deleteAllDocuments();
        return;
      }

      final contacts = await _readContactsDocument();
      final targets = await _readTargetsDocument();
      final preservesCurrentGeneration =
          contacts.accountPeerId == normalizedAccount &&
          targets.accountPeerId == normalizedAccount;
      if (!preservesCurrentGeneration) {
        // Delete both old-owner documents before publishing either new-owner
        // document. A later write failure therefore leaves Swift with missing
        // or mismatched state, never a readable old eligible generation.
        await _deleteAllDocuments();
      }
      await _writeContacts(
        normalizedAccount,
        preservesCurrentGeneration
            ? contacts.contacts
            : <String, Map<String, Object?>>{},
      );
      await _writeTargets(
        normalizedAccount,
        preservesCurrentGeneration
            ? targets.targets
            : <_ProjectedAuthoredTarget>[],
      );
    }, propagateError: true);
  }

  Future<void> clearForLogout() {
    _expectedAccountPeerId = null;
    _simsCleanupTombstones.clear();
    return _enqueue(_deleteAllDocuments, propagateError: true);
  }

  Future<void> upsertContact(ContactModel contact) => _enqueue(() async {
    final document = await _readContactsDocument();
    if (!_owns(document.accountPeerId)) return;
    final currentAuthority = _authorizedTransportPeerIds(
      document.contacts[contact.peerId],
    );
    document.contacts[contact.peerId] = <String, Object?>{
      'username': contact.username.trim(),
      'blocked': contact.isBlocked,
      'archived': contact.isArchived,
      'authorizedTransportPeerIds': currentAuthority,
    };
    await _writeContacts(document.accountPeerId!, document.contacts);
  });

  Future<void> setContactBlocked({
    required String peerId,
    required String username,
    required bool blocked,
    bool archived = false,
  }) => _enqueue(() async {
    final document = await _readContactsDocument();
    if (!_owns(document.accountPeerId)) return;
    document.contacts[peerId] = <String, Object?>{
      'username': username.trim(),
      'blocked': blocked,
      'archived': archived,
      'authorizedTransportPeerIds': _authorizedTransportPeerIds(
        document.contacts[peerId],
      ),
    };
    await _writeContacts(document.accountPeerId!, document.contacts);
  });

  Future<void> removeContact(String peerId) => _enqueue(() async {
    final document = await _readContactsDocument();
    if (!_owns(document.accountPeerId)) return;
    document.contacts.remove(peerId);
    await _writeContacts(document.accountPeerId!, document.contacts);
  });

  Future<void> replaceContacts(Iterable<ContactModel> contacts) =>
      _enqueue(() async {
        final current = await _readContactsDocument();
        if (!_owns(current.accountPeerId)) return;
        final projection = <String, Map<String, Object?>>{};
        for (final contact in contacts) {
          final exactSimsDigest = _exactSimsFixtureDigest(contact);
          if (exactSimsDigest != null &&
              _simsCleanupTombstones[contact.peerId] == exactSimsDigest) {
            continue;
          }
          final value = <String, Object?>{
            'username': contact.username.trim(),
            'blocked': contact.isBlocked,
            'archived': contact.isArchived,
            'authorizedTransportPeerIds': _authorizedTransportPeerIds(
              current.contacts[contact.peerId],
            ),
          };
          final simsDigest = _simsFixtureDigestForBackfill(
            contact,
            current.contacts[contact.peerId],
          );
          if (simsDigest != null) {
            value[_simsFixtureDigestKey] = simsDigest;
          }
          projection[contact.peerId] = value;
        }
        await _writeContacts(current.accountPeerId!, projection);
      });

  /// Removes one contact's physical-sender admission before authoritative trust
  /// changes. Storage failure propagates and invalidates the shared documents,
  /// so callers must abort the database mutation.
  Future<void> retireContactTransportAuthority(
    String peerId,
  ) => _enqueue(() async {
    final document = await _readContactsDocument();
    if (!_owns(document.accountPeerId)) {
      throw StateError('direct notification projection owner is unavailable');
    }
    final normalized = peerId.trim();
    final current = document.contacts[normalized];
    if (current != null) {
      current['authorizedTransportPeerIds'] = <String>[];
      await _writeContacts(document.accountPeerId!, document.contacts);
    }
    final readBack = await _readContactsDocument();
    if (!_owns(readBack.accountPeerId) ||
        _authorizedTransportPeerIds(readBack.contacts[normalized]).isNotEmpty) {
      throw StateError('direct transport authority retirement was not durable');
    }
  }, propagateError: true);

  /// Publishes only the committed current trust readback for one contact.
  Future<void> replaceContactTransportAuthority({
    required String peerId,
    required Iterable<String> authorizedTransportPeerIds,
  }) => _enqueue(() async {
    final document = await _readContactsDocument();
    if (!_owns(document.accountPeerId)) {
      throw StateError('direct notification projection owner is unavailable');
    }
    final normalized = peerId.trim();
    final current = document.contacts[normalized];
    if (normalized.isEmpty || current == null) return;
    final expected = _boundedAuthorizedTransports(authorizedTransportPeerIds);
    current['authorizedTransportPeerIds'] = expected;
    await _writeContacts(document.accountPeerId!, document.contacts);
    final readBack = await _readContactsDocument();
    if (!_owns(readBack.accountPeerId) ||
        !_sameStrings(
          _authorizedTransportPeerIds(readBack.contacts[normalized]),
          expected,
        )) {
      throw StateError('direct transport authority read-back failed');
    }
  }, propagateError: true);

  /// Launch-time atomic replacement from display rows plus committed device
  /// trust. No old authority field survives when a loader omits a contact.
  Future<void> replaceContactsWithTransportAuthority({
    required Iterable<ContactModel> contacts,
    required Map<String, Iterable<String>> authorizedTransportsByContact,
  }) => _enqueue(() async {
    final current = await _readContactsDocument();
    if (!_owns(current.accountPeerId)) {
      throw StateError('direct notification projection owner is unavailable');
    }
    final replacement = <String, Map<String, Object?>>{};
    for (final contact in contacts) {
      replacement[contact.peerId] = <String, Object?>{
        'username': contact.username.trim(),
        'blocked': contact.isBlocked,
        'archived': contact.isArchived,
        'authorizedTransportPeerIds': _boundedAuthorizedTransports(
          authorizedTransportsByContact[contact.peerId] ?? const <String>[],
        ),
      };
    }
    await _writeContacts(current.accountPeerId!, replacement);
    final readBack = await _readContactsDocument();
    if (!_owns(readBack.accountPeerId) ||
        jsonEncode(readBack.contacts) != jsonEncode(replacement)) {
      throw StateError('direct transport authority backfill read-back failed');
    }
  }, propagateError: true);

  /// Test-only targeted insert used by the private physical-iOS SIMS seam.
  ///
  /// Unlike ordinary production mutations, this operation propagates a write
  /// failure without invalidating either shared document. It also refuses to
  /// replace an existing peer entry. The generation digest is ignored by the
  /// NSE but lets cleanup distinguish this exact disposable seed from a real
  /// contact that was created or updated concurrently.
  Future<bool> insertSimsFixtureContactIfAbsent({
    required String peerId,
    required String username,
    required String fixtureDigest,
  }) => _enqueueIsolated(() async {
    if (_nonEmpty(peerId) == null ||
        _nonEmpty(username) == null ||
        !_isSha256(fixtureDigest)) {
      return false;
    }
    final document = await _readContactsDocument();
    if (!_owns(document.accountPeerId) ||
        document.contacts.containsKey(peerId)) {
      return false;
    }
    final next = Map<String, Map<String, Object?>>.from(document.contacts);
    next[peerId] = <String, Object?>{
      'username': username.trim(),
      'blocked': false,
      'archived': false,
      'authorizedTransportPeerIds': <String>[],
      _simsFixtureDigestKey: fixtureDigest,
    };
    await _writeContacts(document.accountPeerId!, next);
    if (_simsCleanupTombstones[peerId] == fixtureDigest) {
      _simsCleanupTombstones.remove(peerId);
    }
    return true;
  });

  /// Test-only exact-generation removal paired with
  /// [insertSimsFixtureContactIfAbsent]. Any changed field fails closed.
  Future<bool> removeSimsFixtureContactIfExact({
    required String peerId,
    required String username,
    required String fixtureDigest,
  }) => _enqueueIsolated(() async {
    if (!_isSha256(fixtureDigest)) return false;
    final document = await _readContactsDocument();
    if (!_owns(document.accountPeerId)) return false;
    final current = document.contacts[peerId];
    if (current == null) {
      _simsCleanupTombstones[peerId] = fixtureDigest;
      return true;
    }
    if (!_isExactSimsFixtureProjection(
      current,
      username: username,
      fixtureDigest: fixtureDigest,
    )) {
      return false;
    }
    _simsCleanupTombstones[peerId] = fixtureDigest;
    final next = Map<String, Map<String, Object?>>.from(document.contacts)
      ..remove(peerId);
    await _writeContacts(document.accountPeerId!, next);
    return true;
  });

  Future<void> upsertAuthoredTarget(ConversationMessage message) {
    if (message.isIncoming ||
        message.deletedAt != null ||
        message.hiddenAt != null) {
      return removeAuthoredTarget(message.id);
    }
    return _enqueue(() async {
      final document = await _readTargetsDocument();
      if (!_owns(document.accountPeerId)) return;
      document.targets.removeWhere((target) => target.id == message.id);
      document.targets.add(
        _ProjectedAuthoredTarget(
          id: message.id,
          peerId: message.contactPeerId,
          timestamp: message.timestamp,
        ),
      );
      await _writeTargets(
        document.accountPeerId!,
        _boundedTargets(document.targets),
      );
    });
  }

  Future<void> removeAuthoredTarget(String messageId) => _enqueue(() async {
    final document = await _readTargetsDocument();
    if (!_owns(document.accountPeerId)) return;
    document.targets.removeWhere((target) => target.id == messageId);
    await _writeTargets(document.accountPeerId!, document.targets);
  });

  Future<void> removeAuthoredTargetsForContact(String peerId) =>
      _enqueue(() async {
        final document = await _readTargetsDocument();
        if (!_owns(document.accountPeerId)) return;
        document.targets.removeWhere((target) => target.peerId == peerId);
        await _writeTargets(document.accountPeerId!, document.targets);
      });

  Future<void> replaceAuthoredTargets(Iterable<ConversationMessage> messages) =>
      _enqueue(() async {
        final current = await _readTargetsDocument();
        if (!_owns(current.accountPeerId)) return;
        final targets = messages
            .where(
              (message) =>
                  !message.isIncoming &&
                  message.deletedAt == null &&
                  message.hiddenAt == null,
            )
            .map(
              (message) => _ProjectedAuthoredTarget(
                id: message.id,
                peerId: message.contactPeerId,
                timestamp: message.timestamp,
              ),
            )
            .toList(growable: true);
        await _writeTargets(current.accountPeerId!, _boundedTargets(targets));
      });

  /// Test/diagnostic read. Production eligibility is consumed by the NSE.
  Future<Map<String, Map<String, Object?>>> readContacts() async =>
      (await _readContactsDocument()).contacts;

  /// Test/diagnostic read. Production eligibility is consumed by the NSE.
  Future<List<Map<String, String>>> readAuthoredTargets() async =>
      (await _readTargetsDocument()).targets
          .map((target) => target.toJson())
          .toList(growable: false);

  /// Test/diagnostic ownership read spanning both direct documents.
  Future<String?> readLocalAccountPeerId() async {
    final contacts = await _readContactsDocument();
    final targets = await _readTargetsDocument();
    return contacts.accountPeerId == targets.accountPeerId
        ? contacts.accountPeerId
        : null;
  }

  Future<void> _enqueue(
    Future<void> Function() action, {
    bool propagateError = false,
  }) {
    final next = _tail.then((_) async {
      try {
        await action();
      } catch (error) {
        Object? invalidationError;
        try {
          await _deleteAllDocuments();
        } catch (failure) {
          invalidationError = failure;
        }
        emitFlowEvent(
          layer: 'FL',
          event: 'DIRECT_REACTION_PUSH_PROJECTION_ERROR',
          details: {
            'error': error.toString(),
            if (invalidationError != null)
              'invalidationError': invalidationError.toString(),
          },
        );
        if (propagateError) rethrow;
      }
    });
    _tail = next.catchError((Object _) {});
    return next;
  }

  Future<T> _enqueueIsolated<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<_DirectContactsDocument> _readContactsDocument() async {
    final raw = await _store.read(sharedDirectReactionContactsKey);
    if (raw == null || raw.isEmpty) return _DirectContactsDocument.empty();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> ||
          decoded['version'] != 1 ||
          _nonEmpty(decoded['localAccountPeerId']) == null) {
        return _DirectContactsDocument.empty();
      }
      final accountPeerId = _nonEmpty(decoded['localAccountPeerId'])!;
      final values = decoded['contacts'];
      if (values is! Map<String, dynamic>) {
        return _DirectContactsDocument.empty();
      }
      final result = <String, Map<String, Object?>>{};
      for (final entry in values.entries) {
        final value = entry.value;
        if (value is! Map) continue;
        final contact = Map<String, Object?>.from(value);
        final username = value['username']?.toString().trim() ?? '';
        if (entry.key.trim().isEmpty || username.isEmpty) continue;
        result[entry.key] = <String, Object?>{
          'username': username,
          'blocked': value['blocked'] == true,
          'archived': value['archived'] == true,
          'authorizedTransportPeerIds': _authorizedTransportPeerIds(contact),
          if (_isSha256(value[_simsFixtureDigestKey]?.toString() ?? ''))
            _simsFixtureDigestKey: value[_simsFixtureDigestKey].toString(),
        };
      }
      return _DirectContactsDocument(
        accountPeerId: accountPeerId,
        contacts: result,
      );
    } catch (_) {
      return _DirectContactsDocument.empty();
    }
  }

  Future<void> _writeContacts(
    String accountPeerId,
    Map<String, Map<String, Object?>> contacts,
  ) => _store.write(
    sharedDirectReactionContactsKey,
    jsonEncode(<String, Object?>{
      'version': 1,
      'localAccountPeerId': accountPeerId,
      'contacts': contacts,
    }),
  );

  Future<_DirectTargetsDocument> _readTargetsDocument() async {
    final raw = await _store.read(sharedDirectReactionAuthoredTargetsKey);
    if (raw == null || raw.isEmpty) return _DirectTargetsDocument.empty();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> ||
          decoded['version'] != 1 ||
          _nonEmpty(decoded['localAccountPeerId']) == null) {
        return _DirectTargetsDocument.empty();
      }
      final accountPeerId = _nonEmpty(decoded['localAccountPeerId'])!;
      final values = decoded['targets'];
      if (values is! List) return _DirectTargetsDocument.empty();
      final targets = values
          .whereType<Map>()
          .map(_ProjectedAuthoredTarget.fromJson)
          .whereType<_ProjectedAuthoredTarget>()
          .toList(growable: true);
      return _DirectTargetsDocument(
        accountPeerId: accountPeerId,
        targets: targets,
      );
    } catch (_) {
      return _DirectTargetsDocument.empty();
    }
  }

  Future<void> _writeTargets(
    String accountPeerId,
    List<_ProjectedAuthoredTarget> targets,
  ) => _store.write(
    sharedDirectReactionAuthoredTargetsKey,
    jsonEncode(<String, Object?>{
      'version': 1,
      'localAccountPeerId': accountPeerId,
      'targets': targets.map((target) => target.toJson()).toList(),
    }),
  );

  Future<void> _deleteAllDocuments() async {
    Object? firstError;
    try {
      await _store.delete(sharedDirectReactionContactsKey);
    } catch (error) {
      firstError = error;
    }
    try {
      await _store.delete(sharedDirectReactionAuthoredTargetsKey);
    } catch (error) {
      firstError ??= error;
    }
    if (firstError != null) throw firstError;
  }

  bool _owns(String? accountPeerId) =>
      _expectedAccountPeerId != null && accountPeerId == _expectedAccountPeerId;

  List<_ProjectedAuthoredTarget> _boundedTargets(
    List<_ProjectedAuthoredTarget> targets,
  ) {
    final byId = <String, _ProjectedAuthoredTarget>{
      for (final target in targets) target.id: target,
    };
    final sorted = byId.values.toList(growable: false)
      ..sort((left, right) {
        final timestampOrder = right.timestamp.compareTo(left.timestamp);
        if (timestampOrder != 0) return timestampOrder;
        return left.id.compareTo(right.id);
      });
    return sorted.take(maxAuthoredTargets).toList(growable: false);
  }

  List<String> _boundedAuthorizedTransports(Iterable<String> values) {
    final result = <String>[];
    final seen = <String>{};
    for (final value in values) {
      if (!isNativeCompatibleIosNsePeerId(value) || !seen.add(value)) {
        throw const FormatException(
          'direct notification transport authority is non-canonical',
        );
      }
      result.add(value);
    }
    result.sort();
    if (result.length > maxAuthorizedTransportsPerContact) {
      throw StateError('direct notification transport authority exceeds bound');
    }
    return result;
  }
}

bool _sameStrings(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

List<String> _authorizedTransportPeerIds(Map<String, Object?>? value) {
  final raw = value?['authorizedTransportPeerIds'];
  if (raw is! List) return <String>[];
  final result = <String>[];
  final seen = <String>{};
  for (final item in raw) {
    if (!isNativeCompatibleIosNsePeerId(item) || !seen.add(item)) {
      return <String>[];
    }
    result.add(item);
  }
  final sorted = List<String>.from(result)..sort();
  if (!_sameStrings(result, sorted)) return <String>[];
  return result;
}

bool _isExactSimsFixtureProjection(
  Map<String, Object?>? value, {
  required String username,
  required String fixtureDigest,
}) =>
    value != null &&
    value.length == 5 &&
    value['username'] == username.trim() &&
    value['blocked'] == false &&
    value['archived'] == false &&
    _authorizedTransportPeerIds(value).isEmpty &&
    value[_simsFixtureDigestKey] == fixtureDigest;

bool _isSha256(String value) => RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

String? _simsFixtureDigestForBackfill(
  ContactModel contact,
  Map<String, Object?>? projected,
) {
  final digest = _exactSimsFixtureDigest(contact);
  if (digest == null) return null;
  final username = contact.username.trim();
  if (projected == null ||
      (projected.length != 4 && projected.length != 5) ||
      projected['username'] != username ||
      projected['blocked'] != false ||
      projected['archived'] != false) {
    return null;
  }
  final projectedDigest = projected[_simsFixtureDigestKey];
  return projectedDigest == null || projectedDigest == digest ? digest : null;
}

String? _exactSimsFixtureDigest(ContactModel contact) {
  const signaturePrefix = 'mknoon-sims-ios:';
  if (!contact.signature.startsWith(signaturePrefix)) return null;
  final digest = contact.signature.substring(signaturePrefix.length);
  final username = contact.username.trim();
  if (!_isSha256(digest) ||
      contact.peerId.trim().isEmpty ||
      username.isEmpty ||
      contact.publicKey != 'mknoon-sims-projection-only' ||
      contact.rendezvous != '/mknoon/sims/projection-only' ||
      contact.scannedAt != '1970-01-01T00:00:00.000Z' ||
      contact.avatarPath != null ||
      contact.avatarVersion != null ||
      contact.mlKemPublicKey != null ||
      contact.mlKemKeyUpdatedTs != null ||
      contact.isArchived ||
      contact.archivedAt != null ||
      contact.isBlocked ||
      contact.blockedAt != null ||
      contact.introsBannerDismissed ||
      contact.introsSentAt != null ||
      contact.introducedBy != null ||
      contact.introducedByPeerId != null) {
    return null;
  }
  return digest;
}

class _DirectContactsDocument {
  final String? accountPeerId;
  final Map<String, Map<String, Object?>> contacts;

  _DirectContactsDocument({
    required this.accountPeerId,
    required this.contacts,
  });

  factory _DirectContactsDocument.empty() => _DirectContactsDocument(
    accountPeerId: null,
    contacts: <String, Map<String, Object?>>{},
  );
}

class _DirectTargetsDocument {
  final String? accountPeerId;
  final List<_ProjectedAuthoredTarget> targets;

  _DirectTargetsDocument({required this.accountPeerId, required this.targets});

  factory _DirectTargetsDocument.empty() => _DirectTargetsDocument(
    accountPeerId: null,
    targets: <_ProjectedAuthoredTarget>[],
  );
}

String? _nonEmpty(Object? value) {
  if (value is! String) return null;
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

class _ProjectedAuthoredTarget {
  final String id;
  final String peerId;
  final String timestamp;

  const _ProjectedAuthoredTarget({
    required this.id,
    required this.peerId,
    required this.timestamp,
  });

  static _ProjectedAuthoredTarget? fromJson(Map<Object?, Object?> value) {
    final id = value['id']?.toString().trim() ?? '';
    final peerId = value['peerId']?.toString().trim() ?? '';
    final timestamp = value['timestamp']?.toString().trim() ?? '';
    if (id.isEmpty || peerId.isEmpty || timestamp.isEmpty) return null;
    return _ProjectedAuthoredTarget(
      id: id,
      peerId: peerId,
      timestamp: timestamp,
    );
  }

  Map<String, String> toJson() => <String, String>{
    'id': id,
    'peerId': peerId,
    'timestamp': timestamp,
  };
}
