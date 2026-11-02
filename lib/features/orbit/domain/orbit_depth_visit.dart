import 'package:flutter/foundation.dart';
import 'package:flutter_app/features/posts/domain/thought_quote.dart';
import 'package:flutter_app/features/posts/domain/thought_reply_status.dart';

/// One reaction or typed reply sent from the 3D view, as an ordinary quoted
/// chat reply. Retry reuses [messageId], so the chat never holds two copies.
@immutable
class OrbitDepthSend {
  const OrbitDepthSend({
    required this.messageId,
    required this.postId,
    required this.text,
    this.reaction,
    this.inFlight = true,
    this.status,
  });

  final String messageId;
  final String postId;
  final String text;

  /// Null for a typed reply.
  final ThoughtReaction? reaction;
  final bool inFlight;

  /// The last known delivery state; null until the first answer.
  final ThoughtReplyStatus? status;

  bool get canRetry => !inFlight && status != ThoughtReplyStatus.sent;

  OrbitDepthSend _with({required bool inFlight, ThoughtReplyStatus? status}) =>
      OrbitDepthSend(
        messageId: messageId,
        postId: postId,
        text: text,
        reaction: reaction,
        inFlight: inFlight,
        status: status ?? this.status,
      );
}

/// A send the caller must now dispatch, and the visit that records it.
typedef OrbitDepthDispatch = ({OrbitDepthVisit visit, OrbitDepthSend send});

/// What the user has answered on the ring's thoughts during one visit to the
/// 3D view. The visit ends when the user leaves 3D, and all of it goes.
///
/// [sends] is the one ledger, in the order they started; which emoji is
/// pressed and which status a thought shows are read from it.
@immutable
class OrbitDepthVisit {
  const OrbitDepthVisit._({
    this.sends = const {},
    this.drafts = const {},
    this.composingPostId,
  });

  static const empty = OrbitDepthVisit._();

  /// By message id.
  final Map<String, OrbitDepthSend> sends;

  /// Unsent text per thought, kept while the composer is closed.
  final Map<String, String> drafts;

  /// The thought whose composer is open, if any.
  final String? composingPostId;

  OrbitDepthSend? latestFor(String postId) =>
      sends.values.where((send) => send.postId == postId).lastOrNull;

  OrbitDepthSend? _reaction(String postId, ThoughtReaction reaction) => sends
      .values
      .where((send) => send.postId == postId && send.reaction == reaction)
      .firstOrNull;

  /// Whether [reaction] shows pressed on [postId]: sent, or on its way.
  bool pressed(String postId, ThoughtReaction reaction) {
    final send = _reaction(postId, reaction);
    return send != null &&
        (send.inFlight || send.status != ThoughtReplyStatus.failed);
  }

  /// Null when [reaction] already went to [postId] in this visit. One that
  /// failed is sent again under its first message id.
  OrbitDepthDispatch? react(
    String postId,
    ThoughtReaction reaction,
    String messageId,
  ) {
    final earlier = _reaction(postId, reaction);
    if (earlier != null) {
      return earlier.status == ThoughtReplyStatus.failed
          ? retry(earlier.messageId)
          : null;
    }
    return _start(
      OrbitDepthSend(
        messageId: messageId,
        postId: postId,
        text: reaction.glyph,
        reaction: reaction,
      ),
    );
  }

  /// Sends [text] and closes the composer. Null for blank text or while an
  /// earlier typed reply to [postId] is still on its way.
  OrbitDepthDispatch? reply(String postId, String text, String messageId) {
    final trimmed = text.trim();
    if (trimmed.isEmpty ||
        sends.values.any(
          (send) =>
              send.postId == postId && send.reaction == null && send.inFlight,
        )) {
      return null;
    }
    return _start(
      OrbitDepthSend(messageId: messageId, postId: postId, text: trimmed),
      composerClosed: postId,
    );
  }

  OrbitDepthDispatch? retry(String messageId) {
    final send = sends[messageId];
    if (send == null || !send.canRetry) return null;
    final again = send._with(inFlight: true);
    // Moved to the end: the retried send is the thought's latest again.
    final next = {...sends}..remove(messageId);
    return (
      visit: OrbitDepthVisit._(
        sends: {...next, messageId: again},
        drafts: drafts,
        composingPostId: composingPostId,
      ),
      send: again,
    );
  }

  /// [finished] is false for a delivery update that arrives while the send
  /// itself has not returned yet.
  OrbitDepthVisit settle(
    String messageId,
    ThoughtReplyStatus status, {
    bool finished = true,
  }) {
    final send = sends[messageId];
    if (send == null) return this;
    return OrbitDepthVisit._(
      sends: {
        ...sends,
        messageId: send._with(
          inFlight: finished ? false : send.inFlight,
          status: status,
        ),
      },
      drafts: drafts,
      composingPostId: composingPostId,
    );
  }

  OrbitDepthVisit openComposer(String postId) =>
      OrbitDepthVisit._(sends: sends, drafts: drafts, composingPostId: postId);

  OrbitDepthVisit closeComposer(String draft) {
    final postId = composingPostId;
    if (postId == null) return this;
    final next = {...drafts}..remove(postId);
    if (draft.isNotEmpty) next[postId] = draft;
    return OrbitDepthVisit._(sends: sends, drafts: next);
  }

  OrbitDepthDispatch _start(OrbitDepthSend send, {String? composerClosed}) {
    final closing = composerClosed != null;
    return (
      visit: OrbitDepthVisit._(
        sends: {...sends, send.messageId: send},
        drafts: closing ? ({...drafts}..remove(composerClosed)) : drafts,
        composingPostId: closing ? null : composingPostId,
      ),
      send: send,
    );
  }
}
