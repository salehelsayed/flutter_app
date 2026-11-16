import 'dart:convert';
import 'dart:typed_data';

typedef EngagementChatScope = ({
  String profileBinding,
  int consentEpoch,
  String week,
});

enum EngagementChatPhase { collecting, qualifiedPending, qualifiedRetained }

/// Its identity is one runtime generation, captured before producer awaits.
final class EngagementChatCapture {
  EngagementChatCapture._(this.scope);

  final EngagementChatScope scope;
}

/// A known outgoing tuple captured before its durable staging starts.
final class EngagementChatIntent {
  EngagementChatIntent._({
    required this.owner,
    required this.contactAccount,
    required this.messageId,
    required this.generationId,
  });

  final EngagementChatCapture owner;
  final String contactAccount;
  final String messageId;
  final String generationId;
}

/// Private synchronous witnesses. Callers supply committed primitive facts.
final class EngagementChatWitness {
  EngagementChatWitness({required EngagementChatScope scope})
    : _scope = scope,
      _capture = EngagementChatCapture._(scope);

  EngagementChatScope _scope;
  EngagementChatCapture? _capture;
  EngagementChatPhase _phase = EngagementChatPhase.collecting;
  Map<String, _ContactWitness> _contacts = {};

  static const _maxContacts = 64;
  static const _maxReferences = 256;
  static const _maxIdentifierBytes = 256;
  static const _maxSnapshotBytes = 256 * 1024;

  EngagementChatPhase get phase => _phase;

  EngagementChatCapture? captureOwner() => _capture;

  void reset(EngagementChatScope scope) {
    _scope = scope;
    _capture = EngagementChatCapture._(scope);
    _phase = EngagementChatPhase.collecting;
    _contacts = {};
  }

  void revoke() {
    _capture = null;
    _phase = EngagementChatPhase.collecting;
    _contacts = {};
  }

  EngagementChatIntent? reserve(
    EngagementChatCapture capture, {
    required String contactAccount,
    required String messageId,
    required String generationId,
  }) {
    if (!_acceptsFact(capture) ||
        !_validIdentifier(contactAccount) ||
        !_validIdentifier(messageId) ||
        !_validIdentifier(generationId)) {
      return null;
    }
    final contact = _contacts[contactAccount];
    final key = (messageId: messageId, generationId: generationId);
    if (contact?.deliveredOutgoingSeen == true ||
        contact?.references.containsKey(key) == true) {
      return null;
    }
    final intent = EngagementChatIntent._(
      owner: capture,
      contactAccount: contactAccount,
      messageId: messageId,
      generationId: generationId,
    );
    final next = _ContactWitness.copy(contact);
    next.references[key] = _PendingReference(intent);
    return _replaceContact(contactAccount, next) ? intent : null;
  }

  void admitted(EngagementChatIntent intent) {
    if (!_acceptsFact(intent.owner)) {
      return;
    }
    final contact = _contacts[intent.contactAccount];
    final key = (
      messageId: intent.messageId,
      generationId: intent.generationId,
    );
    final pending = contact?.references[key];
    // A cancelled intent cannot authorize a replacement with the same tuple.
    if (pending == null ||
        !identical(pending.intent, intent) ||
        pending.admitted) {
      return;
    }
    final next = _ContactWitness.copy(contact);
    if (pending.delivered) {
      next.deliveredOutgoingSeen = true;
      next.references.clear();
    } else {
      next.references[key] = _PendingReference(intent, admitted: true);
    }
    _replaceContact(intent.contactAccount, next);
  }

  void cancel(EngagementChatIntent intent) {
    if (!_acceptsFact(intent.owner)) {
      return;
    }
    final contact = _contacts[intent.contactAccount];
    final key = (
      messageId: intent.messageId,
      generationId: intent.generationId,
    );
    final pending = contact?.references[key];
    if (pending == null ||
        !identical(pending.intent, intent) ||
        pending.admitted) {
      return;
    }
    final next = _ContactWitness.copy(contact);
    next.references.remove(key);
    _replaceContact(intent.contactAccount, next);
  }

  void delivered(
    EngagementChatCapture capture, {
    required String contactAccount,
    required String messageId,
    required String generationId,
  }) {
    if (!_acceptsFact(capture) ||
        !_validIdentifier(contactAccount) ||
        !_validIdentifier(messageId) ||
        !_validIdentifier(generationId)) {
      return;
    }
    final contact = _contacts[contactAccount];
    final key = (messageId: messageId, generationId: generationId);
    final pending = contact?.references[key];
    if (pending == null || pending.delivered) {
      return;
    }
    final next = _ContactWitness.copy(contact);
    if (pending.admitted) {
      next.deliveredOutgoingSeen = true;
      next.references.clear();
    } else {
      next.references[key] = _PendingReference(pending.intent, delivered: true);
    }
    _replaceContact(contactAccount, next);
  }

  void incoming(
    EngagementChatCapture capture, {
    required String contactAccount,
  }) {
    if (!_acceptsFact(capture) || !_validIdentifier(contactAccount)) {
      return;
    }
    final contact = _contacts[contactAccount];
    if (contact?.incomingSeen == true) {
      return;
    }
    final next = _ContactWitness.copy(contact)..incomingSeen = true;
    _replaceContact(contactAccount, next);
  }

  void confirmRetained(EngagementChatCapture capture) {
    if (_isCurrent(capture) &&
        _phase == EngagementChatPhase.qualifiedPending) {
      _phase = EngagementChatPhase.qualifiedRetained;
    }
  }

  bool _isCurrent(EngagementChatCapture capture) =>
      identical(capture, _capture);

  bool _acceptsFact(EngagementChatCapture capture) =>
      _isCurrent(capture) && _phase == EngagementChatPhase.collecting;

  bool _replaceContact(String account, _ContactWitness next) {
    final contacts = Map<String, _ContactWitness>.of(_contacts);
    if (!next.incomingSeen &&
        !next.deliveredOutgoingSeen &&
        next.references.isEmpty) {
      contacts.remove(account);
    } else {
      contacts[account] = next;
    }
    final referenceCount = contacts.values.fold<int>(
      0,
      (count, contact) => count + contact.references.length,
    );
    if (contacts.length > _maxContacts || referenceCount > _maxReferences) {
      return false;
    }
    final qualifies = next.incomingSeen && next.deliveredOutgoingSeen;
    final nextPhase = qualifies
        ? EngagementChatPhase.qualifiedPending
        : EngagementChatPhase.collecting;
    final retainedContacts = qualifies
        ? <String, _ContactWitness>{}
        : contacts;
    if (_encode(nextPhase, retainedContacts).length > _maxSnapshotBytes) {
      return false;
    }
    _contacts = retainedContacts;
    _phase = nextPhase;
    return true;
  }

  Uint8List encodeSnapshot() => _encode(_phase, _contacts);

  Uint8List _encode(
    EngagementChatPhase phase,
    Map<String, _ContactWitness> contacts,
  ) {
    final records = <Map<String, Object?>>[];
    for (final entry in contacts.entries) {
      final contact = entry.value;
      final outgoing = <Map<String, String>>[
        for (final reference in contact.references.entries)
          if (reference.value.admitted)
            {
              'message': reference.key.messageId,
              'generation': reference.key.generationId,
            },
      ];
      // Unconfirmed runtime reservations never create a persisted contact.
      if (!contact.incomingSeen &&
          !contact.deliveredOutgoingSeen &&
          outgoing.isEmpty) {
        continue;
      }
      records.add({
        'account': entry.key,
        'incomingSeen': contact.incomingSeen,
        'deliveredOutgoingSeen': contact.deliveredOutgoingSeen,
        'outgoing': outgoing,
      });
    }
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'version': 1,
          'scope': {
            'profileBinding': _scope.profileBinding,
            'consentEpoch': _scope.consentEpoch,
            'week': _scope.week,
          },
          'phase': switch (phase) {
            EngagementChatPhase.collecting => 'collecting',
            EngagementChatPhase.qualifiedPending => 'qualified_pending',
            EngagementChatPhase.qualifiedRetained => 'qualified_retained',
          },
          'contacts': records,
        }),
      ),
    );
  }

  bool restoreSnapshot(EngagementChatCapture capture, List<int> bytes) {
    if (!_isCurrent(capture) ||
        bytes.length > _maxSnapshotBytes ||
        bytes.any((value) => value < 0 || value > 255)) {
      return false;
    }
    try {
      final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
      if (decoded is! Map<String, dynamic> ||
          !_hasKeys(decoded, const ['version', 'scope', 'phase', 'contacts']) ||
          decoded['version'] is! int ||
          decoded['version'] != 1 ||
          !_matchesScope(decoded['scope'])) {
        return false;
      }
      final phase = switch (decoded['phase']) {
        'collecting' => EngagementChatPhase.collecting,
        'qualified_pending' => EngagementChatPhase.qualifiedPending,
        'qualified_retained' => EngagementChatPhase.qualifiedRetained,
        _ => null,
      };
      final records = decoded['contacts'];
      if (phase == null ||
          records is! List<dynamic> ||
          records.length > _maxContacts ||
          (phase != EngagementChatPhase.collecting && records.isNotEmpty)) {
        return false;
      }
      final contacts = <String, _ContactWitness>{};
      var referenceCount = 0;
      for (final record in records) {
        if (record is! Map<String, dynamic> ||
            !_hasKeys(record, const [
              'account',
              'incomingSeen',
              'deliveredOutgoingSeen',
              'outgoing',
            ])) {
          return false;
        }
        final account = record['account'];
        final incoming = record['incomingSeen'];
        final delivered = record['deliveredOutgoingSeen'];
        final outgoing = record['outgoing'];
        if (account is! String ||
            !_validIdentifier(account) ||
            contacts.containsKey(account) ||
            incoming is! bool ||
            delivered is! bool ||
            outgoing is! List<dynamic> ||
            (incoming && delivered) ||
            (delivered && outgoing.isNotEmpty)) {
          return false;
        }
        referenceCount += outgoing.length;
        if (referenceCount > _maxReferences) {
          return false;
        }
        final contact = _ContactWitness.copy(null)
          ..incomingSeen = incoming
          ..deliveredOutgoingSeen = delivered;
        for (final reference in outgoing) {
          if (reference is! Map<String, dynamic> ||
              !_hasKeys(reference, const ['message', 'generation'])) {
            return false;
          }
          final message = reference['message'];
          final generation = reference['generation'];
          if (message is! String ||
              generation is! String ||
              !_validIdentifier(message) ||
              !_validIdentifier(generation)) {
            return false;
          }
          final key = (messageId: message, generationId: generation);
          if (contact.references.containsKey(key)) {
            return false;
          }
          contact.references[key] = _PendingReference(
            EngagementChatIntent._(
              owner: capture,
              contactAccount: account,
              messageId: message,
              generationId: generation,
            ),
            admitted: true,
          );
        }
        if (!incoming && !delivered && outgoing.isEmpty) {
          return false;
        }
        contacts[account] = contact;
      }
      if (_encode(phase, contacts).length > _maxSnapshotBytes) {
        return false;
      }
      // Install only the fully accepted candidate; failed restore changes nothing.
      _contacts = contacts;
      _phase = phase;
      return true;
    } catch (_) {
      return false;
    }
  }

  bool _matchesScope(Object? value) {
    if (value is! Map<String, dynamic> ||
        !_hasKeys(value, const ['profileBinding', 'consentEpoch', 'week'])) {
      return false;
    }
    final binding = value['profileBinding'];
    final epoch = value['consentEpoch'];
    final week = value['week'];
    return binding is String &&
        _validIdentifier(binding) &&
        binding == _scope.profileBinding &&
        epoch is int &&
        epoch > 0 &&
        epoch == _scope.consentEpoch &&
        week is String &&
        RegExp(r'^\d{4}-W(?:0[1-9]|[1-4]\d|5[0-3])$').hasMatch(week) &&
        week == _scope.week;
  }

  static bool _hasKeys(Map<String, dynamic> value, List<String> keys) =>
      value.length == keys.length && keys.every(value.containsKey);

  static bool _validIdentifier(String value) {
    if (value.isEmpty || value.length > _maxIdentifierBytes) {
      return false;
    }
    final bytes = utf8.encode(value);
    return bytes.length <= _maxIdentifierBytes && utf8.decode(bytes) == value;
  }
}

typedef _MessageKey = ({String messageId, String generationId});

final class _ContactWitness {
  _ContactWitness.copy(_ContactWitness? previous)
    : incomingSeen = previous?.incomingSeen ?? false,
      deliveredOutgoingSeen = previous?.deliveredOutgoingSeen ?? false,
      references = Map<_MessageKey, _PendingReference>.of(
        previous?.references ?? const {},
      );

  bool incomingSeen;
  bool deliveredOutgoingSeen;
  final Map<_MessageKey, _PendingReference> references;
}

final class _PendingReference {
  const _PendingReference(
    this.intent, {
    this.admitted = false,
    this.delivered = false,
  });

  final EngagementChatIntent intent;
  final bool admitted;
  final bool delivered;
}
