import 'package:flutter_app/features/conversation/domain/models/audio_recording.dart';
import 'package:flutter_app/features/posts/domain/thought_emoji_catalog.dart';

/// A chat message points at a thought through its quoted-message id, as
/// `thought:<postId>`. Nothing of the thought is copied into the message: each
/// side looks it up live, so it still disappears everywhere after 24 h.
const _thoughtQuotePrefix = 'thought:';

String thoughtQuoteId(String postId) => '$_thoughtQuotePrefix$postId';

/// The thought's post id, or null when [quotedMessageId] quotes a message.
String? thoughtIdFromQuote(String? quotedMessageId) {
  if (quotedMessageId == null ||
      !quotedMessageId.startsWith(_thoughtQuotePrefix)) {
    return null;
  }
  final postId = quotedMessageId.substring(_thoughtQuotePrefix.length);
  return postId.isEmpty ? null : postId;
}

/// One-tap answers to a thought. A reply to a thought whose whole text is one
/// of these glyphs is shown as a reaction line instead of a bubble, so older
/// builds still see the glyph as an ordinary message.
class ThoughtReaction {
  const ThoughtReaction._(this.glyph, [this._fixedName]);

  static const love = ThoughtReaction._('❤️', 'love');
  static const laugh = ThoughtReaction._('😂', 'laugh');
  static const fire = ThoughtReaction._('🔥', 'fire');
  static const applause = ThoughtReaction._('👏', 'applause');
  static const values = [love, laugh, fire, applause];

  final String glyph;
  final String? _fixedName;

  String get name => _fixedName ?? glyph;
  bool get isFixed => _fixedName != null;

  static ThoughtReaction? fromText(String text) {
    final glyph = canonicalThoughtEmoji(text);
    if (glyph == null) return null;
    for (final reaction in values) {
      if (glyph == reaction.glyph) return reaction;
    }
    return ThoughtReaction._(glyph);
  }

  @override
  bool operator ==(Object other) =>
      other is ThoughtReaction && other.glyph == glyph;

  @override
  int get hashCode => glyph.hashCode;
}

/// What a chat shows for a quoted thought it found stored here. A quote the
/// phone cannot find, or one past [expiresAt], reads as no longer available.
class ThoughtQuotePreview {
  const ThoughtQuotePreview({
    required this.text,
    required this.mediaKind,
    required this.expiresAt,
    this.imagePath,
  });

  final String text;

  /// 'none', 'image', 'video' or 'voice', as on the stored thought.
  final String mediaKind;
  final DateTime expiresAt;

  /// The thought's first photo, once it is on this phone.
  final String? imagePath;

  bool isLiveAt(DateTime now) => expiresAt.isAfter(now);
}

/// A reply typed on a friend's thought card, sent when its chat opens. [text]
/// may be a lone [ThoughtReaction] glyph.
class ThoughtReply {
  const ThoughtReply({required this.text, required this.postId});

  final String text;
  final String postId;

  String get quotedMessageId => thoughtQuoteId(postId);
}

/// A voice reply recorded on a friend's thought card, sent when its chat
/// opens. [autoStopped] recordings wait in the chat for Send or Discard.
class ThoughtVoiceReply {
  const ThoughtVoiceReply({
    required this.recording,
    required this.waveform,
    required this.postId,
    this.autoStopped = false,
  });

  final AudioRecording recording;
  final List<double> waveform;
  final String postId;
  final bool autoStopped;

  String get quotedMessageId => thoughtQuoteId(postId);
}
