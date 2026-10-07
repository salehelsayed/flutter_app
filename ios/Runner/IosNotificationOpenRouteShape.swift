import Foundation

/// The pure gate for whether a tapped APNs notification is forwarded to Dart
/// over `mknoon/ios_notification_open`. Payloads that fail it are skipped as
/// `not_route_shaped`, so the app opens without routing.
///
/// Every `type` that Dart's `NotificationRouteTarget.fromRemoteMessageData`
/// routes needs a case here, with the same required fields. A direct reaction
/// (`message_reaction`) was missing: tapping one from the background opened
/// Orbit instead of the reacted conversation.
enum IosNotificationOpenRouteShape {
  static func isRouteShaped(_ payload: [String: Any]) -> Bool {
    guard let type = trimmedString(payload["type"]) else {
      return false
    }

    switch type {
    case "new_message":
      return trimmedString(payload["sender_id"]) != nil ||
        trimmedString(payload["from"]) != nil
    case "message_reaction":
      let targetMessageId = trimmedString(payload["target_message_id"]) ??
        trimmedString(payload["targetMessageId"])
      let senderId = trimmedString(payload["sender_id"]) ??
        trimmedString(payload["from"])
      return targetMessageId != nil &&
        senderId != nil &&
        trimmedString(payload["action"]) == "add"
    case "contact_request":
      return trimmedString(payload["sender_id"]) != nil ||
        trimmedString(payload["peer_id"]) != nil ||
        trimmedString(payload["peerId"]) != nil ||
        trimmedString(payload["from"]) != nil ||
        trimmedString(payload["ns"]) != nil
    case "group_message":
      return trimmedString(payload["groupId"]) != nil
    case "group_reaction":
      let groupId = trimmedString(payload["groupId"])
      let eventId = trimmedString(payload["event_id"])
      let targetMessageId = trimmedString(payload["target_message_id"])
      let reactorPeerId = trimmedString(payload["reactor_peer_id"])
      return groupId != nil &&
        eventId != nil &&
        targetMessageId != nil &&
        reactorPeerId != nil &&
        trimmedString(payload["action"]) == "add"
    case "group_invite":
      return trimmedString(payload["groupId"]) != nil
    case "intros":
      return true
    case "post_create", "post_reaction", "post_comment_reaction":
      return trimmedString(payload["postId"]) != nil ||
        trimmedString(payload["post_id"]) != nil
    case "post_comment":
      let postId = trimmedString(payload["postId"]) ??
        trimmedString(payload["post_id"])
      let commentId = trimmedString(payload["commentId"]) ??
        trimmedString(payload["comment_id"])
      return postId != nil && commentId != nil
    default:
      return false
    }
  }

  static func trimmedString(_ value: Any?) -> String? {
    if let string = value as? String {
      let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    }
    if let number = value as? NSNumber {
      return number.stringValue
    }
    return nil
  }
}
