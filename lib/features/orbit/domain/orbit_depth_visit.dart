import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/stickers/domain/sticker_catalog.dart';
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
    this.fromPicker = false,
    this.restored = false,
    this.inFlight = true,
    this.status,
  });

  final String messageId;
  final String postId;
  final String text;

  final ThoughtReaction? reaction;
  final ThoughtStickerSelection? sticker;
  final bool fromPicker;
  final bool restored;
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
        fromPicker: fromPicker,
        restored: restored,
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
  const OrbitDepthVisit._({
    this.sends = const {},
    this.composingPostId,
    this.recentEmoji = const [],
    this.personalEmoji,
  });

  static const empty = OrbitDepthVisit._();

  /// By message id.
  final Map<String, OrbitDepthSend> sends;

  /// The thought whose composer is open, if any.
  final String? composingPostId;

  final List<ThoughtReaction> recentEmoji;
  final ThoughtReaction? personalEmoji;

  Iterable<OrbitDepthSend> sentOn(String postId) => sends.values.where(
    (send) =>
        send.postId == postId &&
        !send.isText &&
        send.status == ThoughtReplyStatus.sent,
  );

  /// Share answers without opening or closing the dial's composer.
  OrbitDepthVisit withAnswersFrom(OrbitDepthVisit other) => OrbitDepthVisit._(
    sends: other.sends,
    composingPostId: composingPostId,
    recentEmoji: other.recentEmoji,
    personalEmoji: other.personalEmoji,
  );

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
    String messageId, {
    bool fromPicker = false,
  }) {
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
        fromPicker: fromPicker,
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
        recentEmoji: recentEmoji,
        personalEmoji: personalEmoji,
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
    final emoji =
        status == ThoughtReplyStatus.sent &&
            send.status != ThoughtReplyStatus.sent
        ? send.reaction
        : null;
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
      recentEmoji: emoji == null
          ? recentEmoji
          : [
              emoji,
              ...recentEmoji.where((recent) => recent != emoji),
            ].take(14).toList(growable: false),
      personalEmoji: emoji != null && send.fromPicker && !emoji.isFixed
          ? emoji
          : personalEmoji,
    );
  }

  OrbitDepthVisit openComposer(String postId) => OrbitDepthVisit._(
    sends: sends,
    composingPostId: postId,
    recentEmoji: recentEmoji,
    personalEmoji: personalEmoji,
  );

  OrbitDepthVisit closeComposer() => OrbitDepthVisit._(
    sends: sends,
    recentEmoji: recentEmoji,
    personalEmoji: personalEmoji,
  );

  OrbitDepthDispatch _start(OrbitDepthSend send, {String? composerClosed}) {
    final closing = composerClosed != null;
    return (
      visit: OrbitDepthVisit._(
        sends: {...sends, send.messageId: send},
        composingPostId: closing ? null : composingPostId,
        recentEmoji: recentEmoji,
        personalEmoji: personalEmoji,
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
        final send = value.sends[update.messageId]!;
        value = value.settle(update.messageId, update.status, finished: false);
        if (!send.isText) unawaited(_persistHistory());
      }
    });
  }

  StreamSubscription<({String messageId, ThoughtReplyStatus status})>?
  _statuses;
  bool _disposed = false;

  final _historyExpiries = <String, DateTime>{};
  SecureKeyStore? _historyStore;
  String? _historyKey;
  DateTime Function() _historyClock = DateTime.now;
  Future<void> _historyWrites = Future<void>.value();
  Timer? _historyExpiryTimer;

  /// Incoming reply history is local to the active account and stays with a
  /// live Thought. Text uses the chat repository and never enters this data.
  Future<void> restoreHistory({
    required SecureKeyStore store,
    required String accountPeerId,
    DateTime Function()? nowProvider,
    Future<ThoughtReplyStatus?> Function(String)? loadMessageStatus,
    Future<String?> Function(String)? loadStickerPath,
  }) async {
    final key =
        'thought_reply_history_v1.${Uri.encodeComponent(accountPeerId)}';
    if (_disposed || (_historyStore == store && _historyKey == key)) return;
    if (_historyKey != null) value = OrbitDepthVisit.empty;
    _historyExpiries.clear();
    _historyExpiryTimer?.cancel();
    _historyStore = store;
    _historyKey = key;
    _historyClock = nowProvider ?? DateTime.now;
    final now = _historyClock();
    bool current() =>
        !_disposed && _historyKey == key && _historyStore == store;
    try {
      final raw = await store.read(key);
      if (!current() || raw == null) return;
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic>) return;
      final recent = _storedReactions(data['recent']);
      final personal = ThoughtReaction.fromText(
        data['personal'] as String? ?? '',
      );
      final restored = <String, OrbitDepthSend>{};
      final expiries = <String, DateTime>{};
      final resolved = <String, ThoughtReplyStatus>{};
      final rows = data['sends'];
      if (rows is List) {
        for (final row in rows) {
          if (row is! Map<String, dynamic>) continue;
          final id = row['id'] as String?;
          final postId = row['post'] as String?;
          final expiry = DateTime.tryParse(row['until'] as String? ?? '');
          if (id == null ||
              postId == null ||
              expiry == null ||
              !expiry.isAfter(now)) {
            continue;
          }
          final reaction = ThoughtReaction.fromText(
            row['emoji'] as String? ?? '',
          );
          final asset = row['asset'] as String?;
          final marker = row['marker'] as String?;
          final custom = row['custom'] as String?;
          final status =
              ThoughtReplyStatus.values
                  .where((status) => status.name == row['status'])
                  .firstOrNull ??
              ThoughtReplyStatus.failed;
          if (status != ThoughtReplyStatus.sent && loadMessageStatus != null) {
            final effective = await loadMessageStatus(id);
            if (!current()) return;
            if (effective != null) resolved[id] = effective;
          }
          ThoughtStickerSelection? sticker;
          if (asset != null && marker != null) {
            sticker = ThoughtStickerSelection.bundled(
              StickerEntry(id: marker, assetPath: asset),
            );
          } else if (custom != null) {
            final path =
                await loadStickerPath?.call(id) ?? row['path'] as String?;
            if (!current()) return;
            if (path != null) {
              sticker = ThoughtStickerSelection.custom(custom, path);
            }
          }
          if (reaction == null && sticker == null) continue;
          expiries[postId] = expiry;
          restored[id] = OrbitDepthSend(
            messageId: id,
            postId: postId,
            text: reaction?.glyph ?? '',
            reaction: reaction,
            sticker: sticker,
            fromPicker: row['picker'] == true,
            restored: true,
            inFlight: false,
            status: status,
          );
        }
      }
      if (!current()) return;
      _historyExpiries.addAll(expiries);
      _scheduleHistoryExpiry();
      var updated = OrbitDepthVisit._(
        sends: {...restored, ...value.sends},
        recentEmoji: recent,
        personalEmoji: personal?.isFixed == false ? personal : null,
        composingPostId: value.composingPostId,
      );
      for (final entry in resolved.entries) {
        updated = updated.settle(entry.key, entry.value);
      }
      value = updated;
      await _persistHistory();
    } catch (_) {
      // The active chat can still send when its local preference store fails.
    }
  }

  bool hasHistory(String postId) => _historyExpiries.containsKey(postId);

  void forgetHistory(String postId) {
    if (_disposed || _historyExpiries.remove(postId) == null) return;
    _removeHistoryFor({postId});
    _scheduleHistoryExpiry();
    unawaited(_persistHistory());
  }

  void pruneHistory() {
    if (_disposed) return;
    final now = _historyClock();
    final expired = {
      for (final entry in _historyExpiries.entries)
        if (!entry.value.isAfter(now)) entry.key,
    };
    if (expired.isEmpty) {
      _scheduleHistoryExpiry();
      return;
    }
    _historyExpiries.removeWhere((id, _) => expired.contains(id));
    _removeHistoryFor(expired);
    _scheduleHistoryExpiry();
    unawaited(_persistHistory());
  }

  void _scheduleHistoryExpiry() {
    _historyExpiryTimer?.cancel();
    DateTime? first;
    for (final expiry in _historyExpiries.values) {
      if (first == null || expiry.isBefore(first)) first = expiry;
    }
    if (first != null) {
      _historyExpiryTimer = Timer(
        first.difference(_historyClock()),
        pruneHistory,
      );
    }
  }

  void _removeHistoryFor(Set<String> postIds) {
    value = OrbitDepthVisit._(
      sends: {
        for (final entry in value.sends.entries)
          if (entry.value.isText || !postIds.contains(entry.value.postId))
            entry.key: entry.value,
      },
      recentEmoji: value.recentEmoji,
      personalEmoji: value.personalEmoji,
      composingPostId: value.composingPostId,
    );
  }

  Future<void> _persistHistory() {
    final store = _historyStore;
    final key = _historyKey;
    if (store == null || key == null) return Future<void>.value();
    final now = _historyClock();
    final rows = <Map<String, Object?>>[];
    for (final send in value.sends.values) {
      final expiry = _historyExpiries[send.postId];
      if (send.isText || expiry == null || !expiry.isAfter(now)) continue;
      final sticker = send.sticker;
      rows.add({
        'id': send.messageId,
        'post': send.postId,
        'until': expiry.toUtc().toIso8601String(),
        'status': send.status?.name ?? ThoughtReplyStatus.failed.name,
        if (send.reaction != null) 'emoji': send.reaction!.glyph,
        if (send.fromPicker) 'picker': true,
        if (sticker?.entry case final entry?) ...{
          'marker': entry.id,
          'asset': entry.assetPath,
        },
        if (sticker?.customId case final custom?) ...{
          'custom': custom,
          'path': sticker!.customFilePath,
        },
      });
    }
    final recent = value.recentEmoji.map((emoji) => emoji.glyph).toList();
    final payload = jsonEncode({
      'sends': rows,
      'recent': recent,
      'personal': value.personalEmoji?.glyph,
    });
    _historyWrites = _historyWrites
        .then(
          (_) => rows.isEmpty && recent.isEmpty
              ? store.delete(key)
              : store.write(key, payload),
        )
        .catchError((Object _) {});
    return _historyWrites;
  }

  List<ThoughtReaction> _storedReactions(Object? source) => source is List
      ? [
          for (final raw in source.whereType<String>().take(14))
            ?ThoughtReaction.fromText(raw),
        ]
      : const [];

  Future<ThoughtReplyStatus?> dispatch(
    OrbitDepthDispatch? dispatch,
    ThoughtReplySender sender, {
    ThoughtStickerReplySender? onSticker,
    PostModel? post,
  }) async {
    if (_disposed || dispatch == null) return null;
    value = dispatch.visit;
    final send = dispatch.send;
    final expiry = DateTime.tryParse(post?.expiresAt ?? '');
    if (_historyStore != null &&
        !send.isText &&
        post?.id == send.postId &&
        expiry != null &&
        expiry.isAfter(_historyClock())) {
      _historyExpiries[send.postId] = expiry;
      _scheduleHistoryExpiry();
      await _persistHistory();
      if (_disposed) return null;
    }
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
    final current = value.sends[send.messageId]?.status;
    if (!send.isText) await _persistHistory();
    return current;
  }

  @override
  void dispose() {
    _disposed = true;
    _statuses?.cancel();
    _historyExpiryTimer?.cancel();
    super.dispose();
  }
}
