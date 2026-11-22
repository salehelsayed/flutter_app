import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_app/features/posts/domain/thought_quote.dart';
import 'package:flutter_app/features/posts/domain/thought_reply_status.dart';

/// One answer sent from either Thought view, as an ordinary quoted
/// chat reply. Retry reuses [messageId], so the chat never holds two copies.
@immutable
class OrbitDepthSend {
  const OrbitDepthSend({
    required this.messageId,
    required this.postId,
    required this.text,
    this.reaction,
    this.sticker,
    this.inFlight = true,
    this.status,
  });

  final String messageId;
  final String postId;
  final String text;

  final ThoughtReaction? reaction;
  final ThoughtStickerSelection? sticker;
  bool get isText => reaction == null && sticker == null;
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
        sticker: sticker,
        inFlight: inFlight,
        status: status ?? this.status,
      );
}

/// A send the caller must now dispatch, and the visit that records it.
typedef OrbitDepthDispatch = ({OrbitDepthVisit visit, OrbitDepthSend send});

/// What the user has answered on either Thought view. The depth surface keeps
/// the open composer separately from answers it shares with the full card.
///
/// [sends] is the one ledger, in the order they started; which emoji is
/// pressed and which status a thought shows are read from it.
@immutable
class OrbitDepthVisit {
  const OrbitDepthVisit._({this.sends = const {}, this.composingPostId});

  static const empty = OrbitDepthVisit._();

  /// By message id.
  final Map<String, OrbitDepthSend> sends;

  /// The thought whose composer is open, if any.
  final String? composingPostId;

  /// Share answers without opening or closing the dial's composer.
  OrbitDepthVisit withAnswersFrom(OrbitDepthVisit other) =>
      OrbitDepthVisit._(sends: other.sends, composingPostId: composingPostId);

  OrbitDepthSend? latestFor(String postId) =>
      sends.values.where((send) => send.postId == postId).lastOrNull;

  OrbitDepthSend? _reaction(String postId, ThoughtReaction reaction) => sends
      .values
      .where((send) => send.postId == postId && send.reaction == reaction)
      .firstOrNull;

  OrbitDepthSend? stickerFor(String postId) => sends.values
      .where((send) => send.postId == postId && send.sticker != null)
      .firstOrNull;

  OrbitDepthDispatch? sticker(
    String postId,
    ThoughtStickerSelection selection,
    String messageId,
  ) {
    if (stickerFor(postId) != null) return null;
    return _start(
      OrbitDepthSend(
        messageId: messageId,
        postId: postId,
        text: '',
        sticker: selection,
      ),
    );
  }

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
          (send) => send.postId == postId && send.isText && send.inFlight,
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
          // A confirmed delivery is final; an older answer cannot undo it.
          status: send.status == ThoughtReplyStatus.sent ? null : status,
        ),
      },
      composingPostId: composingPostId,
    );
  }

  OrbitDepthVisit openComposer(String postId) =>
      OrbitDepthVisit._(sends: sends, composingPostId: postId);

  OrbitDepthVisit closeComposer() => OrbitDepthVisit._(sends: sends);

  OrbitDepthDispatch _start(OrbitDepthSend send, {String? composerClosed}) {
    final closing = composerClosed != null;
    return (
      visit: OrbitDepthVisit._(
        sends: {...sends, send.messageId: send},
        composingPostId: closing ? null : composingPostId,
      ),
      send: send,
    );
  }
}

/// One host's answers, shared by the ring and its full-screen Thought cards.
/// The existing visit ledger owns duplicate suppression and stable retry IDs.
class OrbitDepthAnswers extends ValueNotifier<OrbitDepthVisit> {
  OrbitDepthAnswers({
    Stream<({String messageId, ThoughtReplyStatus status})>? statusChanges,
  }) : super(OrbitDepthVisit.empty) {
    _statuses = statusChanges?.listen((update) {
      if (!_disposed && value.sends.containsKey(update.messageId)) {
        value = value.settle(update.messageId, update.status, finished: false);
      }
    });
  }

  StreamSubscription<({String messageId, ThoughtReplyStatus status})>?
  _statuses;
  bool _disposed = false;

  Future<ThoughtReplyStatus?> dispatch(
    OrbitDepthDispatch? dispatch,
    ThoughtReplySender sender, {
    ThoughtStickerReplySender? onSticker,
  }) async {
    if (_disposed || dispatch == null) return null;
    value = dispatch.visit;
    final send = dispatch.send;
    ThoughtReplyStatus status;
    try {
      final sticker = send.sticker;
      status = sticker == null
          ? await sender(send.text, send.postId, send.messageId)
          : await onSticker?.call(sticker, send.postId, send.messageId) ??
                ThoughtReplyStatus.failed;
    } catch (_) {
      status = ThoughtReplyStatus.failed;
    }
    if (_disposed) return null;
    value = value.settle(send.messageId, status);
    return value.sends[send.messageId]?.status;
  }

  @override
  void dispose() {
    _disposed = true;
    _statuses?.cancel();
    super.dispose();
  }
}
