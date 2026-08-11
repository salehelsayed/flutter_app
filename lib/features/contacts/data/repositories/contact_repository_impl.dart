import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/notifications/direct_reaction_notification_projection.dart';

import '../../domain/models/contact_model.dart';
import '../../domain/repositories/contact_repository.dart';
import '../../domain/repositories/direct_contact_conversation_purge.dart';

/// Implementation of ContactRepository using database helper functions.
class ContactRepositoryImpl
    implements ContactRepository, DirectContactConversationPurgeCapability {
  final Future<List<Map<String, Object?>>> Function() dbLoadAllContacts;
  final Future<Map<String, Object?>?> Function(String peerId) dbLoadContact;
  final Future<void> Function(Map<String, Object?> row) dbUpsertContact;
  final Future<void> Function(String peerId) dbDeleteContact;

  /// 361: the exact final serialized purge owner (nullable so incumbent test
  /// construction sites stay untouched; production wires the real helper).
  final Future<DirectContactConversationPurgeSummary> Function(String peerId)?
  dbPurgeDirectContactConversationAndContact;
  final Future<int> Function() dbGetContactCount;
  final Future<bool> Function(String peerId) dbContactExists;
  final Future<void> Function(String peerId) dbArchiveContact;
  final Future<void> Function(String peerId) dbUnarchiveContact;
  final Future<List<Map<String, Object?>>> Function() dbLoadActiveContacts;
  final Future<List<Map<String, Object?>>> Function() dbLoadArchivedContacts;
  final Future<void> Function(String peerId) dbBlockContact;
  final Future<void> Function(String peerId) dbUnblockContact;
  final Future<void> Function(String peerId) dbDismissIntroBanner;
  final Future<void> Function(String peerId, String timestamp)
  dbSetIntrosSentAt;
  final DirectReactionNotificationProjection? directReactionProjection;
  final void Function()? onPushEligibilityChanged;

  ContactRepositoryImpl({
    required this.dbLoadAllContacts,
    required this.dbLoadContact,
    required this.dbUpsertContact,
    required this.dbDeleteContact,
    required this.dbGetContactCount,
    required this.dbContactExists,
    required this.dbArchiveContact,
    required this.dbUnarchiveContact,
    required this.dbLoadActiveContacts,
    required this.dbLoadArchivedContacts,
    required this.dbBlockContact,
    required this.dbUnblockContact,
    required this.dbDismissIntroBanner,
    required this.dbSetIntrosSentAt,
    this.dbPurgeDirectContactConversationAndContact,
    this.directReactionProjection,
    this.onPushEligibilityChanged,
  });

  @override
  bool get supportsDirectContactConversationPurge =>
      dbPurgeDirectContactConversationAndContact != null;

  @override
  Future<DirectContactConversationPurgeSummary>
  purgeDirectContactConversationAndContact(String peerId) async {
    final delegate = dbPurgeDirectContactConversationAndContact;
    if (delegate == null) {
      throw StateError('direct contact conversation purge is unavailable');
    }
    final summary = await delegate(peerId);
    await directReactionProjection?.removeContact(peerId);
    _notifyPushEligibilityChanged();
    return summary;
  }

  @override
  Future<void> addContact(ContactModel contact) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACTS_REPO_ADD_START',
      details: {'peerId': contact.peerId.substring(0, 10)},
    );

    try {
      await dbUpsertContact(contact.toMap());
      await directReactionProjection?.upsertContact(contact);
      _notifyPushEligibilityChanged();

      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACTS_REPO_ADD_SUCCESS',
        details: {'peerId': contact.peerId.substring(0, 10)},
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACTS_REPO_ADD_ERROR',
        details: {'error': e.toString()},
      );
      rethrow;
    }
  }

  @override
  Future<ContactModel?> getContact(String peerId) async {
    final row = await dbLoadContact(peerId);
    if (row == null) return null;
    return ContactModel.fromMap(row);
  }

  @override
  Future<List<ContactModel>> getAllContacts() async {
    final rows = await dbLoadAllContacts();
    return rows.map((row) => ContactModel.fromMap(row)).toList();
  }

  @override
  Future<void> deleteContact(String peerId) async {
    await dbDeleteContact(peerId);
    await directReactionProjection?.removeContact(peerId);
    _notifyPushEligibilityChanged();
  }

  @override
  Future<bool> contactExists(String peerId) async {
    return await dbContactExists(peerId);
  }

  @override
  Future<int> getContactCount() async {
    return await dbGetContactCount();
  }

  @override
  Future<void> archiveContact(String peerId) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACTS_REPO_ARCHIVE_START',
      details: {'peerId': peerId.substring(0, 10)},
    );

    try {
      await dbArchiveContact(peerId);
      await _mirrorContactForPush(peerId);
      _notifyPushEligibilityChanged();

      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACTS_REPO_ARCHIVE_SUCCESS',
        details: {'peerId': peerId.substring(0, 10)},
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACTS_REPO_ARCHIVE_ERROR',
        details: {'error': e.toString()},
      );
      rethrow;
    }
  }

  @override
  Future<void> unarchiveContact(String peerId) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACTS_REPO_UNARCHIVE_START',
      details: {'peerId': peerId.substring(0, 10)},
    );

    try {
      await dbUnarchiveContact(peerId);
      await _mirrorContactForPush(peerId);
      _notifyPushEligibilityChanged();

      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACTS_REPO_UNARCHIVE_SUCCESS',
        details: {'peerId': peerId.substring(0, 10)},
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACTS_REPO_UNARCHIVE_ERROR',
        details: {'error': e.toString()},
      );
      rethrow;
    }
  }

  @override
  Future<List<ContactModel>> getActiveContacts() async {
    final rows = await dbLoadActiveContacts();
    return rows.map((row) => ContactModel.fromMap(row)).toList();
  }

  @override
  Future<List<ContactModel>> getArchivedContacts() async {
    final rows = await dbLoadArchivedContacts();
    return rows.map((row) => ContactModel.fromMap(row)).toList();
  }

  @override
  Future<void> blockContact(String peerId) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACTS_REPO_BLOCK_START',
      details: {'peerId': peerId.substring(0, 10)},
    );

    try {
      await dbBlockContact(peerId);
      await _mirrorContactForPush(peerId, forcedBlocked: true);
      _notifyPushEligibilityChanged();

      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACTS_REPO_BLOCK_SUCCESS',
        details: {'peerId': peerId.substring(0, 10)},
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACTS_REPO_BLOCK_ERROR',
        details: {'error': e.toString()},
      );
      rethrow;
    }
  }

  @override
  Future<void> unblockContact(String peerId) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACTS_REPO_UNBLOCK_START',
      details: {'peerId': peerId.substring(0, 10)},
    );

    try {
      await dbUnblockContact(peerId);
      await _mirrorContactForPush(peerId, forcedBlocked: false);
      _notifyPushEligibilityChanged();

      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACTS_REPO_UNBLOCK_SUCCESS',
        details: {'peerId': peerId.substring(0, 10)},
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACTS_REPO_UNBLOCK_ERROR',
        details: {'error': e.toString()},
      );
      rethrow;
    }
  }

  /// Launch-time self-healing backfill for contacts created before the iOS NSE
  /// direct-reaction projection existed.
  Future<void> mirrorAllDirectReactionContacts() async {
    final projection = directReactionProjection;
    if (projection == null) return;
    try {
      final rows = await dbLoadAllContacts();
      await projection.replaceContacts(rows.map(ContactModel.fromMap));
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACTS_REPO_REACTION_PROJECTION_BACKFILL_ERROR',
        details: {'error': error.toString()},
      );
    }
  }

  Future<void> _mirrorContactForPush(
    String peerId, {
    bool? forcedBlocked,
  }) async {
    final projection = directReactionProjection;
    if (projection == null) return;
    try {
      final row = await dbLoadContact(peerId);
      if (row == null) {
        await projection.removeContact(peerId);
        return;
      }
      final contact = ContactModel.fromMap(row);
      await projection.upsertContact(
        contact.copyWith(isBlocked: forcedBlocked ?? contact.isBlocked),
      );
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACTS_REPO_REACTION_PROJECTION_ERROR',
        details: {'error': error.toString()},
      );
    }
  }

  void _notifyPushEligibilityChanged() {
    try {
      onPushEligibilityChanged?.call();
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACTS_REPO_PUSH_ELIGIBILITY_CALLBACK_ERROR',
        details: {'error': error.toString()},
      );
    }
  }

  @override
  Future<void> dismissIntroBanner(String peerId) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACTS_REPO_DISMISS_INTRO_BANNER_START',
      details: {'peerId': peerId.substring(0, 10)},
    );

    try {
      await dbDismissIntroBanner(peerId);

      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACTS_REPO_DISMISS_INTRO_BANNER_SUCCESS',
        details: {'peerId': peerId.substring(0, 10)},
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACTS_REPO_DISMISS_INTRO_BANNER_ERROR',
        details: {'error': e.toString()},
      );
      rethrow;
    }
  }

  @override
  Future<void> setIntrosSentAt(String peerId, String timestamp) async {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONTACTS_REPO_SET_INTROS_SENT_AT_START',
      details: {'peerId': peerId.substring(0, 10)},
    );

    try {
      await dbSetIntrosSentAt(peerId, timestamp);

      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACTS_REPO_SET_INTROS_SENT_AT_SUCCESS',
        details: {'peerId': peerId.substring(0, 10)},
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONTACTS_REPO_SET_INTROS_SENT_AT_ERROR',
        details: {'error': e.toString()},
      );
      rethrow;
    }
  }
}
