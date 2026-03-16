import 'package:flutter_app/features/posts/domain/models/post_follow_on_outbox_event.dart';
import 'package:flutter_app/features/posts/domain/models/post_follow_on_outbox_recipient_delivery.dart';

class PostFollowOnOutboxJob {
  final PostFollowOnOutboxEvent event;
  final List<PostFollowOnOutboxRecipientDelivery> recipientDeliveries;

  const PostFollowOnOutboxJob({
    required this.event,
    required this.recipientDeliveries,
  });
}
