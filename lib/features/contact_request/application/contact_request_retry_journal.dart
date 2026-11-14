import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/contact_request/application/send_contact_request_use_case.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_repair_repository.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';

const contactRequestRetryJournalKey = 'contact_request_retry_journal_v1';
const _maxEntries = 200;
const _ttl = Duration(days: 7);

typedef ContactRetryStatus = ({
  Set<String> stoppedPeerIds,
  int? nextChangeAtMs,
});

/// Local custody for dormant, keyless retries only. The retry owner serializes
/// reconciliation, reservation and publication before doing network work.
final class ContactRequestRetryJournal {
  ContactRequestRetryJournal._(this.store, this.identity, this.entries);

  final SecureKeyStore store;
  final IdentityModel identity;
  final Map<String, ContactRequestRetryEntry> entries;

  static String generation(IdentityModel identity, ContactModel contact) =>
      sha256
          .convert(
            utf8.encode(
              jsonEncode([
                identity.peerId,
                identity.publicKey,
                identity.mlKemPublicKey,
                contact.peerId,
                contact.publicKey,
                contact.scannedAt,
              ]),
            ),
          )
          .toString();

  static bool consentAllows(ContactRelationshipConsent? consent) =>
      consent == null || consent.state == ContactRelationshipState.active;

  static Future<ContactRequestRetryJournal> reconcile({
    required SecureKeyStore store,
    required IdentityModel identity,
    required List<ContactModel> contacts,
    required Map<String, ContactRelationshipConsent?> consents,
    required int nowMs,
  }) async {
    final raw = await store.read(contactRequestRetryJournalKey);
    final entries = <String, ContactRequestRetryEntry>{};
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        if (decoded['account'] is! String ||
            (decoded['account'] as String).isEmpty) {
          throw const FormatException();
        }
        if (decoded['account'] == identity.peerId) {
          final rows = decoded['entries'] as List<dynamic>;
          if (rows.length > _maxEntries) throw const FormatException();
          for (final row in rows) {
            final entry = ContactRequestRetryEntry.fromJson(
              row as Map<String, dynamic>,
            );
            if (entries.containsKey(entry.peerId)) {
              throw const FormatException();
            }
            final envelope = entry.envelope;
            if (envelope != null &&
                (envelope.senderPeerId != identity.peerId ||
                    envelope.targetPeerId != entry.peerId ||
                    !envelope.encrypted ||
                    envelope.msgId == null ||
                    envelope.signedAtMs == null)) {
              throw const FormatException();
            }
            if (envelope != null) {
              final wire =
                  jsonDecode(envelope.messageJson) as Map<String, dynamic>;
              if (wire['intent'] != 'key_exchange_retry' ||
                  wire['version'] != '2' ||
                  wire['msgId'] != envelope.msgId ||
                  envelope.msgId!.isEmpty ||
                  envelope.signedAtMs! < entry.cycleStartedAtMs ||
                  entry.expiresAtMs >
                      envelope.signedAtMs! + _ttl.inMilliseconds) {
                throw const FormatException();
              }
            }
            entries[entry.peerId] = entry;
          }
        }
      } on Object {
        // Do not erase corruption and mint replacement IDs, or expose stored
        // envelope contents in the retry owner's diagnostic error text.
        throw const FormatException('Invalid contact retry journal');
      }
    }
    final journal = ContactRequestRetryJournal._(store, identity, entries);
    final current = {for (final contact in contacts) contact.peerId: contact};
    entries.removeWhere((peerId, entry) {
      final contact = current[peerId];
      return contact == null ||
          contact.mlKemPublicKey != null ||
          !consentAllows(consents[peerId]) ||
          entry.generation != generation(identity, contact) ||
          nowMs >= entry.expiresAtMs;
    });
    // Persist a removal/account change before any candidate can be sent.
    if (raw != journal._encoded()) await journal.persist();
    return journal;
  }

  Future<ContactRequestRetryEntry?> reserve(
    ContactModel contact,
    int nowMs,
  ) async {
    final scannedAt = DateTime.tryParse(
      contact.scannedAt,
    )?.millisecondsSinceEpoch;
    var entry = entries[contact.peerId];
    final startedAt = entry?.cycleStartedAtMs ?? scannedAt;
    if (startedAt == null ||
        nowMs < startedAt ||
        nowMs >= (entry?.expiresAtMs ?? startedAt + _ttl.inMilliseconds)) {
      return null;
    }
    if (entry != null && nowMs < entry.nextAttemptAtMs) return null;
    if (entry == null) {
      // Never evict a live ID to admit another one. Expired/retired entries
      // were removed by reconcile; a full journal defers new automatic work.
      if (entries.length >= _maxEntries) return null;
      entry = ContactRequestRetryEntry(
        peerId: contact.peerId,
        generation: generation(identity, contact),
        scannedAtMs: scannedAt!,
        expiresAtMs: startedAt + _ttl.inMilliseconds,
        attempts: 0,
        nextAttemptAtMs: nowMs,
      );
      entries[contact.peerId] = entry;
    }
    entry.attempts++;
    final hours = switch (entry.attempts) {
      1 => 1,
      2 => 6,
      _ => 24,
    };
    entry.nextAttemptAtMs = nowMs + Duration(hours: hours).inMilliseconds;
    // Reserve before build/send, including failed attempts and process death.
    await persist();
    return entry;
  }

  /// A local interest event can restart only an expired cycle. Persist its
  /// intent before network readiness, so reconnect can perform the first send.
  Future<bool> restartOnInterest(ContactModel contact, int nowMs) async {
    final scannedAt = DateTime.tryParse(
      contact.scannedAt,
    )?.millisecondsSinceEpoch;
    if (scannedAt == null ||
        nowMs < scannedAt + _ttl.inMilliseconds ||
        entries.containsKey(contact.peerId) ||
        entries.length >= _maxEntries) {
      return false;
    }
    entries[contact.peerId] = ContactRequestRetryEntry(
      peerId: contact.peerId,
      generation: generation(identity, contact),
      scannedAtMs: scannedAt,
      interestStartedAtMs: nowMs,
      expiresAtMs: nowMs + _ttl.inMilliseconds,
      attempts: 0,
      nextAttemptAtMs: nowMs,
    );
    await persist();
    return true;
  }

  ContactRetryStatus status(
    List<ContactModel> contacts,
    Map<String, ContactRelationshipConsent?> consents,
    int nowMs,
  ) {
    final stopped = <String>{};
    int? next;
    for (final contact in contacts) {
      if (contact.mlKemPublicKey != null ||
          contact.isBlocked ||
          contact.isArchived ||
          !consentAllows(consents[contact.peerId])) {
        continue;
      }
      final scannedAt = DateTime.tryParse(
        contact.scannedAt,
      )?.millisecondsSinceEpoch;
      if (scannedAt == null || nowMs < scannedAt) continue;
      final expires =
          entries[contact.peerId]?.expiresAtMs ??
          scannedAt + _ttl.inMilliseconds;
      if (nowMs >= expires) {
        stopped.add(contact.peerId);
      } else {
        next = next == null ? expires : min(next, expires);
      }
    }
    return (stoppedPeerIds: Set.unmodifiable(stopped), nextChangeAtMs: next);
  }

  Future<bool> saveEnvelope(
    ContactRequestRetryEntry entry,
    BuiltContactRequestEnvelope envelope,
    int nowMs, {
    String? materialFingerprint,
  }) async {
    final signedAt = envelope.signedAtMs;
    // A wall-clock rollback during build cannot authorize an older request
    // than this contact generation. Keep its backoff reservation, send nothing.
    if (signedAt == null ||
        signedAt < entry.cycleStartedAtMs ||
        envelope.senderPeerId != identity.peerId ||
        envelope.targetPeerId != entry.peerId ||
        !envelope.encrypted) {
      return false;
    }
    final expires = min(entry.expiresAtMs, signedAt + _ttl.inMilliseconds);
    if (nowMs >= expires) return false;
    entry.expiresAtMs = expires;
    entry.envelope = envelope;
    entry.materialFingerprint = materialFingerprint;
    await persist();
    return true;
  }

  Future<void> remove(String peerId) async {
    if (entries.remove(peerId) != null) await persist();
  }

  String? _encoded() => entries.isEmpty
      ? null
      : jsonEncode({
          'account': identity.peerId,
          'entries': [for (final entry in entries.values) entry.toJson()],
        });

  Future<void> persist() async {
    final encoded = _encoded();
    if (encoded == null) {
      await store.delete(contactRequestRetryJournalKey);
    } else {
      await store.write(contactRequestRetryJournalKey, encoded);
    }
  }
}

final class ContactRequestRetryEntry {
  ContactRequestRetryEntry({
    required this.peerId,
    required this.generation,
    required this.scannedAtMs,
    required this.expiresAtMs,
    required this.attempts,
    required this.nextAttemptAtMs,
    this.envelope,
    this.materialFingerprint,
    this.interestStartedAtMs,
  });

  final String peerId;
  final String generation;
  final int scannedAtMs;
  final int? interestStartedAtMs;
  int get cycleStartedAtMs => interestStartedAtMs ?? scannedAtMs;
  int expiresAtMs;
  int attempts;
  int nextAttemptAtMs;
  BuiltContactRequestEnvelope? envelope;
  String? materialFingerprint;

  factory ContactRequestRetryEntry.fromJson(Map<String, dynamic> json) {
    final entry = ContactRequestRetryEntry(
      peerId: json['peerId'] as String,
      generation: json['generation'] as String,
      scannedAtMs: json['scannedAtMs'] as int,
      expiresAtMs: json['expiresAtMs'] as int,
      attempts: json['attempts'] as int,
      nextAttemptAtMs: json['nextAttemptAtMs'] as int,
      materialFingerprint: json['materialFingerprint'] as String?,
      interestStartedAtMs: json['interestStartedAtMs'] as int?,
      envelope: json['envelope'] == null
          ? null
          : BuiltContactRequestEnvelope.fromJson(
              json['envelope'] as Map<String, dynamic>,
            ),
    );
    if (entry.peerId.isEmpty ||
        entry.generation.isEmpty ||
        entry.attempts < (entry.interestStartedAtMs == null ? 1 : 0) ||
        (entry.interestStartedAtMs != null &&
            entry.interestStartedAtMs! <
                entry.scannedAtMs + _ttl.inMilliseconds) ||
        (entry.attempts == 0 &&
            (entry.envelope != null ||
                entry.nextAttemptAtMs != entry.cycleStartedAtMs)) ||
        entry.expiresAtMs > entry.cycleStartedAtMs + _ttl.inMilliseconds ||
        entry.expiresAtMs <= entry.cycleStartedAtMs) {
      throw const FormatException();
    }
    return entry;
  }

  Map<String, Object?> toJson() => {
    'peerId': peerId,
    'generation': generation,
    'scannedAtMs': scannedAtMs,
    'expiresAtMs': expiresAtMs,
    'attempts': attempts,
    'nextAttemptAtMs': nextAttemptAtMs,
    'envelope': envelope?.toJson(),
    if (materialFingerprint != null) 'materialFingerprint': materialFingerprint,
    if (interestStartedAtMs != null) 'interestStartedAtMs': interestStartedAtMs,
  };
}
