import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';

/// Determines whether the "introduce your friends" banner should be shown
/// in a conversation.
///
/// The banner is shown when ALL of these conditions are true:
/// 1. Contact is not blocked
/// 2. Contact is not archived
/// 3. Banner has not been dismissed ([ContactModel.introsBannerDismissed] is false)
/// 4. Introductions have not already been sent ([ContactModel.introsSentAt] is null)
/// 5. User has at least 1 other active, non-blocked contact to introduce
/// 6. Fewer than 3 messages exist in the conversation
Future<bool> shouldShowIntroBanner({
  required ContactRepository contactRepo,
  required ContactModel contact,
  required int messageCount,
}) async {
  if (contact.isBlocked) return false;
  if (contact.isArchived) return false;
  if (contact.introsBannerDismissed) return false;
  if (contact.introsSentAt != null) return false;
  if (messageCount >= 3) return false;

  final activeContacts = await contactRepo.getActiveContacts();
  // Must have at least 1 other active, non-blocked contact to introduce
  final otherFriends = activeContacts
      .where((c) => c.peerId != contact.peerId && !c.isBlocked)
      .toList();
  if (otherFriends.isEmpty) return false;

  emitFlowEvent(
    layer: 'UC',
    event: 'INTRO_BANNER_ELIGIBLE',
    details: {
      'contactPeerId': contact.peerId.length > 10
          ? contact.peerId.substring(0, 10)
          : contact.peerId,
      'otherFriendsCount': otherFriends.length,
    },
  );

  return true;
}
