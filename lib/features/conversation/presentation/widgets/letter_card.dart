import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/core/utils/text_direction_utils.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/upload_progress_banner.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/linkable_text.dart';
import 'package:flutter_app/shared/widgets/media/audio_player_widget.dart';
import 'package:flutter_app/shared/widgets/media/media_grid.dart';

/// Fully-rounded outer corner radius for a bubble (136 Phase 2).
const double kBubbleRadius = 18.0;

/// Tightened "stacked" corner radius applied to the speaker-edge corners that
/// join consecutive bubbles in the same run (WhatsApp/Signal grouped look).
const double kBubbleStackRadius = 6.0;

/// 137 follow-up: in group chats the run avatar renders in a left gutter
/// OUTSIDE the bubble (WhatsApp/Signal). The gutter is reserved on EVERY
/// incoming balloon of the run so they share one left edge; the avatar is
/// painted only on the first balloon (the sender switch).
const double kBubbleAvatarSize = 32.0;
const double kBubbleAvatarGutterWidth = 40.0; // avatar (32) + 8px gap
const double _kBubbleAvatarGutterTopInset = 2.0; // nudge avatar toward the name

/// A full-width glassmorphic letter card for conversation messages.
///
/// Both received and sent messages use the same card layout.
/// Authorship is distinguished by accent edge (left=received, right=sent),
/// background opacity, and text brightness.
///
/// When [bubbleLayout] is true the card renders as a side-aligned, width-capped
/// chat balloon with position-aware stacked corner radii and (optionally)
/// suppressed header chrome — used by the 1:1 and group conversation screens to
/// group consecutive same-sender messages into a single run (136). All
/// bubble-layout params are OPTIONAL with defaults that preserve the legacy
/// full-width card, so existing call sites (incl. Feed wrappers) are untouched.
class LetterCard extends StatelessWidget {
  final String senderPeerId;
  final String senderName;
  final String text;
  final String time;
  final bool isIncoming;
  final String? status;
  final String? transport;
  final String? quotedText;
  final bool isQuoteUnavailable;
  final bool isEdited;
  final bool isForwarded;
  final bool isDeleted;
  final List<MediaAttachment> media;
  final void Function(int index)? onMediaTap;

  /// 235: per-attachment long-press with the exact index into the rendered
  /// image/video grid (same index space as [onMediaTap]). When null, tile
  /// long-presses fall through to the card-level [onLongPress].
  final void Function(int index)? onMediaLongPress;
  final List<MessageReaction> reactions;
  final String? ownPeerId;
  final VoidCallback? onLongPress;
  final void Function(String emoji)? onReactionTap;
  final VoidCallback? onRetryFailedMessage;
  final VoidCallback? onRetryFailedMedia;
  final VoidCallback? onDeleteFailedMedia;

  /// 144: a terminal "Couldn't send — …" reason for a non-retryable
  /// `send_failed` bubble. When set, the card renders the reason line and
  /// suppresses the Retry control (retry can never succeed for a terminal
  /// group state).
  final String? failedReasonText;

  /// 144: Delete affordance for a terminal `send_failed` bubble. Distinct from
  /// [onDeleteFailedMedia] (which is gated by write permission); this one stays
  /// reachable while the composer is read-only.
  final VoidCallback? onDeleteFailedMessage;
  final void Function(String attachmentId)? onRetryUnavailableMedia;
  final bool isRetryFailedMessageEnabled;
  final String? failedMessageActionKeySuffix;
  final String? failedMediaActionKeySuffix;
  final bool requireVerifiedContentHash;

  /// 128 (round 5): owned-media dir id (the conversation contact peerId, or
  /// groupId) for the render-boundary fallback to the durable owned copy.
  final String? ownedMediaPeerId;
  final Map<String, String> mediaRenderedSemanticsLabels;

  /// 136 Phase 2: render as a side-aligned chat balloon instead of the legacy
  /// full-width card. Defaults to false → exact legacy render preserved.
  final bool bubbleLayout;

  /// Whether this balloon is the FIRST message of its run (affects stacked
  /// corner radii). Defaults true (a standalone balloon).
  final bool isFirstInGroup;

  /// Whether this balloon is the LAST message of its run (affects stacked
  /// corner radii). Defaults true (a standalone balloon).
  final bool isLastInGroup;

  /// Whether to render the run avatar in the header (bubble layout only).
  final bool showAvatar;

  /// Whether to render the sender name in the header (bubble layout only).
  final bool showSenderName;

  /// 137 follow-up (bubble layout only): render the run avatar in a left gutter
  /// OUTSIDE the bubble (group chats) instead of inside the header. When true a
  /// fixed-width avatar gutter is reserved on every balloon of the run so they
  /// share one left edge; the avatar itself is painted only when [showAvatar].
  /// Defaults false → 1:1 / legacy render unchanged (avatar inside the header
  /// when [showAvatar], or no avatar at all).
  final bool avatarOutsideBubble;

  /// 155 (1:1 only): render the inline status glyph as the TRANSPORT the
  /// message travelled (relay→cell_tower, direct→device_hub, wifi→wifi,
  /// inbox→inbox) for the user's OWN outgoing messages, AND render a transport
  /// glyph for INCOMING messages (the channel they arrived on). Defaults false
  /// → the GROUP/legacy v1 status glyph (`_statusIcon`) is used and incoming
  /// shows no glyph. Set only by the 1:1 conversation screen; the delivered
  /// ✓✓ stays retired in both paths.
  final bool transportStatusGlyph;

  /// Privacy-safe presentation mounted inside the decorated message body.
  /// When present, ordinary media/audio renderers are suppressed so private
  /// bytes can never be projected into the conversation scroll.
  final Widget? privateContentSlot;

  /// Stable key for the clipped/decorated body that owns [privateContentSlot].
  /// Conversation tests use this to prove the private panel is inside the one
  /// real bubble rather than a visually detached sibling.
  final Key? decoratedBodyKey;

  /// Progress for an upload whose stable attachment id belongs to this exact
  /// message. Unlike the conversation-wide upload banner, this state is also
  /// populated by automatic retry uploads.
  final MessageUploadProgressViewState? messageUploadProgress;

  const LetterCard({
    super.key,
    required this.senderPeerId,
    required this.senderName,
    required this.text,
    required this.time,
    required this.isIncoming,
    this.status,
    this.transport,
    this.quotedText,
    this.isQuoteUnavailable = false,
    this.isEdited = false,
    this.isForwarded = false,
    this.isDeleted = false,
    this.media = const [],
    this.onMediaTap,
    this.onMediaLongPress,
    this.reactions = const [],
    this.ownPeerId,
    this.onLongPress,
    this.onReactionTap,
    this.onRetryFailedMessage,
    this.onRetryFailedMedia,
    this.onDeleteFailedMedia,
    this.failedReasonText,
    this.onDeleteFailedMessage,
    this.onRetryUnavailableMedia,
    this.isRetryFailedMessageEnabled = true,
    this.failedMessageActionKeySuffix,
    this.failedMediaActionKeySuffix,
    this.requireVerifiedContentHash = false,
    this.ownedMediaPeerId,
    this.mediaRenderedSemanticsLabels = const <String, String>{},
    this.bubbleLayout = false,
    this.isFirstInGroup = true,
    this.isLastInGroup = true,
    this.showAvatar = true,
    this.showSenderName = true,
    this.avatarOutsideBubble = false,
    this.transportStatusGlyph = false,
    this.privateContentSlot,
    this.decoratedBodyKey,
    this.messageUploadProgress,
  });

  List<MediaAttachment> get _imageVideoMedia => media
      .where((a) => a.mediaType == 'image' || a.mediaType == 'video')
      .toList();
  List<MediaAttachment> get _audioMedia =>
      media.where((a) => a.mediaType == 'audio').toList();
  bool get _showsOutgoingMediaPendingNote =>
      !isIncoming &&
      !isDeleted &&
      status == 'sending' &&
      media.any(
        (attachment) =>
            attachment.mediaType == 'image' ||
            attachment.mediaType == 'video' ||
            attachment.mediaType == 'audio',
      );

  /// 155 (1:1 only): whether to draw the INCOMING transport glyph (the channel
  /// a received message arrived on). Gated on [transportStatusGlyph] so group/
  /// legacy never shows it; `system`/`unknown`/null transports and deleted rows
  /// draw nothing. Outgoing is handled by the status-glyph block, so this never
  /// fires for own messages (no double-render).
  bool get _showsIncomingTransportGlyph =>
      transportStatusGlyph &&
      isIncoming &&
      transport != null &&
      !isDeleted &&
      transport != 'system' &&
      transport != 'unknown';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final readableColors = context.backgroundReadableColors;

    if (bubbleLayout) {
      return _buildBubble(context, readableColors, l10n);
    }

    return GestureDetector(
      onLongPress: onLongPress,
      // 156 QW-1: no BackdropFilter — the fill is already semi-opaque so the
      // blur was pure raster cost. ClipRRect still clips the corners.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Container(
          key: decoratedBodyKey,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            color: isIncoming
                ? readableColors.surfaceRaised
                : readableColors.surfaceSubtle,
            border: Border.all(color: readableColors.surfaceBorder),
          ),
          child: Stack(
            children: [
              // Accent edge glow
              if (isIncoming)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 60,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Color.fromRGBO(78, 205, 196, 0.08),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              else
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: 60,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerRight,
                          end: Alignment.centerLeft,
                          colors: [
                            Color.fromRGBO(255, 255, 255, 0.04),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              // Accent border edge
              Positioned(
                left: isIncoming ? 0 : null,
                right: isIncoming ? null : 0,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: isIncoming
                        ? const Color(0xFF4ecdc4)
                        : readableColors.border,
                    borderRadius: BorderRadius.only(
                      topLeft: isIncoming
                          ? const Radius.circular(24)
                          : Radius.zero,
                      bottomLeft: isIncoming
                          ? const Radius.circular(24)
                          : Radius.zero,
                      topRight: isIncoming
                          ? Radius.zero
                          : const Radius.circular(24),
                      bottomRight: isIncoming
                          ? Radius.zero
                          : const Radius.circular(24),
                    ),
                  ),
                ),
              ),
              // Card content
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header: avatar, name, transport
                  _buildHeader(readableColors),
                  ..._buildBodyChildren(
                    context,
                    readableColors,
                    l10n,
                    bodyTopPad: 4,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The card header (avatar + sender name + transport icon).
  ///
  /// When [hug] is true (bubble layout) the header Row shrinks to fit its
  /// content so the bubble hugs the name instead of stretching to the width
  /// cap (137). The sender name then flexes LOOSELY (it still ellipsizes when
  /// it would exceed the cap, but does not force full width). The legacy
  /// full-width card keeps `hug: false`, where `Flexible(fit: tight)` is
  /// exactly the prior `Expanded` (so its render is byte-for-byte unchanged).
  Widget _buildHeader(
    BackgroundReadableColors readableColors, {
    bool hug = false,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Row(
        mainAxisSize: hug ? MainAxisSize.min : MainAxisSize.max,
        children: [
          if (showAvatar) ...[
            UserAvatar(peerId: senderPeerId, size: kBubbleAvatarSize),
            const SizedBox(width: 10),
          ],
          if (showSenderName)
            Flexible(
              fit: hug ? FlexFit.loose : FlexFit.tight,
              child: Text(
                senderName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isIncoming ? FontWeight.w600 : FontWeight.w500,
                  color: isIncoming
                      ? readableColors.textPrimary
                      : readableColors.textSecondary,
                ),
              ),
            ),
          if (transport != null) ...[
            if (!showSenderName) const Spacer(),
            const SizedBox(width: 4),
            Icon(
              _transportIcon(transport!),
              size: 10,
              color: readableColors.iconMuted,
            ),
          ],
        ],
      ),
    );
  }

  /// The shared body content (quote / media / audio / text / failed-actions /
  /// footer) used by BOTH the legacy card and the bubble layout. [bodyTopPad]
  /// lets the bubble layout grow the body top inset when the header is hidden.
  List<Widget> _buildBodyChildren(
    BuildContext context,
    BackgroundReadableColors readableColors,
    AppLocalizations l10n, {
    required double bodyTopPad,
    bool inlineFooterMeta = false,
    bool compact = false,
  }) {
    // 137: in bubble mode the timestamp (+edited+status) folds INTO the body
    // text as a trailing WidgetSpan so it sits on the last text line and wraps
    // atomically (WhatsApp/Signal). That only works when there is real body
    // text to host the suffix span — deleted, empty-text, and media-only rows
    // have no `LinkableText`, so they keep the standalone footer timestamp.
    final metaInlined = inlineFooterMeta && !isDeleted && text.isNotEmpty;
    // The group avatar-outside bubble is vertically [compact] (tighter line
    // height + smaller bottom inset) so balloons aren't tall. The 1:1 bubble
    // and legacy card keep the looser metrics: shrinking the 1:1 body box
    // shifts the inline-time WidgetSpan under the `find.text` long-press target
    // and breaks the overlay hit-test in the conversation-screen tests.
    final bodyLineHeight = compact ? 1.35 : 1.65;
    final bodyBottomPad = compact ? 6.0 : 8.0;
    return [
      if (isForwarded && !isDeleted)
        Padding(
          padding: EdgeInsets.fromLTRB(16, bodyTopPad, 16, 2),
          child: Semantics(
            label: l10n.conversation_forwarded_marker,
            child: Text(
              l10n.conversation_forwarded_marker,
              key: const ValueKey('direct-forwarded-marker'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: readableColors.textMuted,
              ),
            ),
          ),
        ),
      // Quote bar (if quoting another message)
      if (quotedText != null || isQuoteUnavailable)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: _buildQuoteBar(readableColors),
        ),
      ?privateContentSlot,
      // Media grid (images/videos)
      if (privateContentSlot == null && _imageVideoMedia.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
          child: MediaGrid(
            media: _imageVideoMedia,
            onTap: onMediaTap,
            onLongPressItem: onMediaLongPress,
            onRetryUnavailableMedia: onRetryUnavailableMedia != null
                ? (attachment) => onRetryUnavailableMedia!(attachment.id)
                : null,
            requireVerifiedContentHash: requireVerifiedContentHash,
            ownedMediaPeerId: ownedMediaPeerId,
            renderedSemanticsLabels: mediaRenderedSemanticsLabels,
          ),
        ),
      // Audio players
      for (final audio
          in privateContentSlot == null
              ? _audioMedia
              : const <MediaAttachment>[])
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: AudioPlayerWidget(
            key: ValueKey(audio.id),
            attachment: audio,
            onRetryUnavailableMedia: onRetryUnavailableMedia != null
                ? () => onRetryUnavailableMedia!(audio.id)
                : null,
            requireVerifiedContentHash: requireVerifiedContentHash,
            renderedSemanticsLabel: mediaRenderedSemanticsLabels[audio.id],
          ),
        ),
      // Body text (only if non-empty)
      if (text.isNotEmpty)
        Padding(
          padding: EdgeInsets.fromLTRB(16, bodyTopPad, 16, bodyBottomPad),
          child: isDeleted
              ? Text(
                  text,
                  textDirection: detectTextDirection(text),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    fontStyle: FontStyle.italic,
                    color: readableColors.textMuted,
                    height: bodyLineHeight,
                    letterSpacing: 0.2,
                  ),
                )
              : LinkableText(
                  text: text,
                  textDirection: detectTextDirection(text),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    color: isIncoming
                        ? readableColors.textPrimary
                        : readableColors.textSecondary,
                    height: bodyLineHeight,
                    letterSpacing: 0.2,
                  ),
                  suffixSpans: metaInlined
                      ? [_buildInlineMetaSpan(context, readableColors, l10n)]
                      : null,
                ),
        )
      else if (isDeleted)
        Padding(
          padding: EdgeInsets.fromLTRB(16, bodyTopPad, 16, bodyBottomPad),
          child: Text(
            l10n.conversation_message_deleted,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w400,
              fontStyle: FontStyle.italic,
              color: readableColors.textMuted,
              height: bodyLineHeight,
              letterSpacing: 0.2,
            ),
          ),
        )
      else if (privateContentSlot == null && media.isNotEmpty)
        const SizedBox(height: 12),
      if (messageUploadProgress != null ||
          (privateContentSlot == null && _showsOutgoingMediaPendingNote))
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: _buildOutgoingMediaPendingNote(context, readableColors),
        ),
      // 144: terminal "Couldn't send — …" reason for a non-retryable
      // send_failed bubble. Rendered as its own Text (not part of the inline
      // WidgetSpan body), so find.text matches it directly.
      if (failedReasonText != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Text(
            failedReasonText!,
            key: ValueKey(
              'failed-message-reason-${failedMessageActionKeySuffix ?? 'message'}',
            ),
            textDirection: detectTextDirection(failedReasonText!),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFFFF8A80),
            ),
          ),
        ),
      if (onRetryFailedMessage != null ||
          onRetryFailedMedia != null ||
          onDeleteFailedMedia != null ||
          onDeleteFailedMessage != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // A terminal reason makes the row non-retryable: suppress Retry
              // even if a callback is supplied.
              if (onRetryFailedMessage != null && failedReasonText == null)
                _buildFailedMessageAction(
                  key: ValueKey(
                    'failed-message-retry-${failedMessageActionKeySuffix ?? 'message'}',
                  ),
                  icon: Icons.refresh_rounded,
                  label: l10n.btn_retry,
                  semanticLabel: l10n.failed_message_retry_semantics,
                  color: const Color(0xFF4ECDC4),
                  onTap: onRetryFailedMessage!,
                  enabled: isRetryFailedMessageEnabled,
                ),
              if (onRetryFailedMedia != null)
                _buildFailedMessageAction(
                  key: ValueKey(
                    'failed-media-retry-${failedMediaActionKeySuffix ?? 'message'}',
                  ),
                  icon: Icons.refresh_rounded,
                  label: l10n.btn_retry,
                  semanticLabel: l10n.failed_media_retry_semantics,
                  color: const Color(0xFF4ECDC4),
                  onTap: onRetryFailedMedia!,
                ),
              if (onDeleteFailedMedia != null)
                _buildFailedMessageAction(
                  key: ValueKey(
                    'failed-media-delete-${failedMediaActionKeySuffix ?? 'message'}',
                  ),
                  icon: Icons.delete_outline_rounded,
                  label: l10n.conversation_context_delete,
                  semanticLabel: l10n.failed_media_delete_semantics,
                  color: const Color(0xFFFF8A80),
                  onTap: onDeleteFailedMedia!,
                ),
              if (onDeleteFailedMessage != null)
                _buildFailedMessageAction(
                  key: ValueKey(
                    'failed-message-delete-${failedMessageActionKeySuffix ?? 'message'}',
                  ),
                  icon: Icons.delete_outline_rounded,
                  label: l10n.conversation_context_delete,
                  semanticLabel: l10n.failed_media_delete_semantics,
                  color: const Color(0xFFFF8A80),
                  onTap: onDeleteFailedMessage!,
                ),
            ],
          ),
        ),
      // Footer.
      //
      // When the metadata is inlined into the body text (bubble mode), the
      // footer carries ONLY reactions and is dropped entirely when there are
      // none — so the bubble hugs its content (137). Otherwise (legacy card,
      // and bubble deleted/empty/media-only rows) the footer keeps the inline
      // reactions + timestamp + delivery status Row unchanged.
      if (metaInlined) ...[
        if (reactions.isNotEmpty && ownPeerId != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            // No Align here: the Column's CrossAxisAlignment.start already
            // start-aligns the Wrap, and the Wrap shrink-wraps its chips — so
            // the bubble keeps hugging even when reactions are present (INV-2).
            // (An Align with the default widthFactor:null would expand to the
            // 0.78 cap and break the hug — see TC-W4.)
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: _buildReactionChipWidgets(readableColors),
            ),
          ),
      ] else
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: (reactions.isNotEmpty && ownPeerId != null)
                    ? Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: _buildReactionChipWidgets(readableColors),
                      )
                    : const SizedBox.shrink(),
              ),
              if (reactions.isNotEmpty && ownPeerId != null)
                const SizedBox(width: 8),
              Text(
                time,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  color: readableColors.textMuted,
                ),
              ),
              if (isEdited) ...[
                const SizedBox(width: 6),
                Text(
                  l10n.conversation_edited_indicator,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: readableColors.textMuted,
                  ),
                ),
              ],
              if (!isIncoming && status != null) ...[
                const SizedBox(width: 4),
                Semantics(
                  label: _resolvedStatusSemantic(context, status!),
                  child: Icon(
                    _resolvedStatusIcon(status!),
                    size: 14,
                    color: _statusColor(status!, readableColors),
                  ),
                ),
              ],
              if (_showsIncomingTransportGlyph) ...[
                const SizedBox(width: 4),
                Semantics(
                  label: _resolvedIncomingSemantic(context, transport!),
                  child: Icon(
                    _transportIcon(transport!),
                    size: 14,
                    color: readableColors.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
    ];
  }

  /// 137: the trailing inline metadata (timestamp + edited indicator +
  /// delivery status) folded into the body text as an atomic [WidgetSpan] so
  /// it sits on the last text line (WhatsApp/Signal) and wraps to a new line
  /// only when the line is full. Used only in bubble mode with real body text.
  InlineSpan _buildInlineMetaSpan(
    BuildContext context,
    BackgroundReadableColors readableColors,
    AppLocalizations l10n,
  ) {
    return _InlineMetaWidgetSpan(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 6),
          Text(
            time,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: readableColors.textMuted,
            ),
          ),
          if (isEdited) ...[
            const SizedBox(width: 6),
            Text(
              l10n.conversation_edited_indicator,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: readableColors.textMuted,
              ),
            ),
          ],
          if (!isIncoming && status != null) ...[
            const SizedBox(width: 4),
            Semantics(
              label: _resolvedStatusSemantic(context, status!),
              child: Icon(
                _resolvedStatusIcon(status!),
                size: 14,
                color: _statusColor(status!, readableColors),
              ),
            ),
          ],
          if (_showsIncomingTransportGlyph) ...[
            const SizedBox(width: 4),
            Semantics(
              label: _resolvedIncomingSemantic(context, transport!),
              child: Icon(
                _transportIcon(transport!),
                size: 14,
                color: readableColors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 136 Phase 2: side-aligned, width-capped chat balloon with position-aware
  /// stacked corner radii and optionally-suppressed header chrome.
  Widget _buildBubble(
    BuildContext context,
    BackgroundReadableColors readableColors,
    AppLocalizations l10n,
  ) {
    // In avatar-outside mode the avatar never occupies the header, so the
    // header is driven purely by the sender name; otherwise the legacy
    // in-header avatar also keeps the header visible.
    // In avatar-outside mode the bubble carries NO in-bubble header: the avatar
    // is in the gutter and the sender name (if any) is a label ABOVE the bubble
    // (built in the gutter Row below).
    final headerHidden = avatarOutsideBubble
        ? true
        : (!showAvatar && !showSenderName);
    final radius = _bubbleBorderRadius();

    // 156 QW-1: no BackdropFilter — the fill below is already semi-opaque, so
    // the per-bubble Gaussian blur was pure raster cost (and forced the raster
    // thread to work every frame). The ClipRRect still clips the corners.
    final bubble = ClipRRect(
      borderRadius: radius,
      child: Container(
        key: decoratedBodyKey,
        decoration: BoxDecoration(
          borderRadius: radius,
          color: isIncoming
              ? readableColors.surfaceRaised
              : readableColors.surfaceSubtle,
          border: Border.all(color: readableColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!headerHidden) _buildHeader(readableColors, hug: true),
            ..._buildBodyChildren(
              context,
              readableColors,
              l10n,
              // No in-bubble header → a little top inset; the group
              // avatar-outside bubble is more compact than the 1:1 bubble.
              bodyTopPad: headerHidden
                  ? (avatarOutsideBubble ? 8.0 : 12.0)
                  : 4.0,
              // Fold the timestamp/status inline and let the bubble hug.
              inlineFooterMeta: true,
              compact: avatarOutsideBubble,
            ),
          ],
        ),
      ),
    );

    // Attribute the sender to screen readers only when there is no VISIBLE name
    // (continuation balloons / 1:1). When the name is shown — the in-bubble
    // header OR the avatar-outside label above the bubble — it is already
    // announced, so the redundant Semantics wrapper is skipped.
    final attributed = (headerHidden && !showSenderName)
        ? Semantics(label: senderName, container: true, child: bubble)
        : bubble;

    final aligned = Align(
      alignment: isIncoming ? Alignment.centerLeft : Alignment.centerRight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Reserve the avatar gutter (group avatar-outside mode) before
          // capping the bubble width, so the 0.78 cap measures the bubble's own
          // available space rather than including the gutter.
          final gutter = avatarOutsideBubble ? kBubbleAvatarGutterWidth : 0.0;
          final maxWidth = constraints.maxWidth.isFinite
              ? (constraints.maxWidth - gutter) * 0.78
              : double.infinity;
          // 137: every incoming balloon (first-in-run AND continuation) is
          // flush-left so it shares the recipient's left edge. The `Align`
          // already left-aligns the bubble; in avatar-outside mode the gutter
          // (below) keeps that shared edge while moving the avatar outside.
          final capped = ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: attributed,
          );
          if (!avatarOutsideBubble) return capped;
          // The sender name (first balloon of the run) is a label ABOVE the
          // bubble, OUTSIDE it; continuation balloons have no name.
          final rightSide = showSenderName
              // Pin to LTR (like the gutter Row + physical-left Align) so the
              // name label and the bubble stay flush to the gutter under RTL
              // (CrossAxisAlignment.start is direction-relative). The body text
              // keeps its own explicit `detectTextDirection`, so Arabic message
              // text still lays out RTL inside the bubble.
              ? Directionality(
                  textDirection: TextDirection.ltr,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 12, bottom: 3),
                        child: Text(
                          senderName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: readableColors.textPrimary,
                          ),
                        ),
                      ),
                      capped,
                    ],
                  ),
                )
              : capped;
          // The avatar sits in a fixed-width gutter to the LEFT of the bubble
          // (outside it). Every balloon of the run reserves the gutter so they
          // share one left edge; the avatar is painted only on the first
          // balloon (the sender switch), continuations leave it empty.
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            // Pin the gutter leading-on-physical-left to match the physical
            // `Align.centerLeft` above, so the avatar stays on the bubble's
            // outer (screen) edge under RTL instead of flipping inward.
            textDirection: TextDirection.ltr,
            children: [
              SizedBox(
                width: kBubbleAvatarGutterWidth,
                child: showAvatar
                    ? Padding(
                        padding: const EdgeInsets.only(
                          top: _kBubbleAvatarGutterTopInset,
                        ),
                        child: UserAvatar(
                          peerId: senderPeerId,
                          size: kBubbleAvatarSize,
                        ),
                      )
                    : null,
              ),
              Flexible(child: rightSide),
            ],
          );
        },
      ),
    );

    // 137: long-press opens the context overlay anywhere on the message ROW,
    // not just on the now-hugging bubble. Because the bubble shrinks to fit its
    // content, a bubble-scoped long-press would be a tiny target; the full-row
    // gesture matches the full-row swipe-to-reply hit area. `opaque` lets the
    // empty space beside the bubble register the press; the gesture is omitted
    // entirely (and hit behavior left as default) when no handler is wired, so
    // deleted rows and the static lifted snapshot are unchanged.
    if (onLongPress == null) return aligned;
    return GestureDetector(
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: aligned,
    );
  }

  /// Position-aware stacked corner radii for the bubble. Outer corners are
  /// [kBubbleRadius]; the SPEAKER-edge corners that join consecutive bubbles
  /// collapse to [kBubbleStackRadius] (first squares the bottom speaker corner,
  /// last squares the top speaker corner, middle squares both, standalone none).
  /// Speaker edge = LEFT for incoming, RIGHT for outgoing.
  BorderRadius _bubbleBorderRadius() {
    const r = Radius.circular(kBubbleRadius);
    const sq = Radius.circular(kBubbleStackRadius);

    // Speaker-edge corners (top + bottom) for this direction.
    final topSpeaker = !isFirstInGroup ? sq : r;
    final bottomSpeaker = !isLastInGroup ? sq : r;

    if (isIncoming) {
      return BorderRadius.only(
        topLeft: topSpeaker,
        bottomLeft: bottomSpeaker,
        topRight: r,
        bottomRight: r,
      );
    }
    return BorderRadius.only(
      topRight: topSpeaker,
      bottomRight: bottomSpeaker,
      topLeft: r,
      bottomLeft: r,
    );
  }

  Widget _buildOutgoingMediaPendingNote(
    BuildContext context,
    BackgroundReadableColors readableColors,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final progress = messageUploadProgress;
    final title = progress == null
        ? l10n.upload_progress_title
        : l10n.media_sending_automatically;
    final detail = progress == null
        ? l10n.post_media_pending_upload_desc
        : progress.hasKnownTotal
        ? l10n.media_uploading_percent(progress.percent)
        : l10n.media_uploading;
    return Semantics(
      liveRegion: true,
      label: '$title. $detail',
      child: Row(
        key: progress == null
            ? null
            : ValueKey('message-upload-progress-${progress.messageId}'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFF4ecdc4),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: readableColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: TextStyle(
                    color: readableColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFailedMessageAction({
    required Key key,
    required IconData icon,
    required String label,
    required String semanticLabel,
    required Color color,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return Semantics(
      label: semanticLabel,
      button: true,
      enabled: enabled,
      child: OutlinedButton.icon(
        key: key,
        onPressed: enabled ? onTap : null,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withAlpha(140)),
          backgroundColor: color.withAlpha(20),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          visualDensity: VisualDensity.compact,
        ),
        icon: Icon(icon, size: 16),
        label: Text(label),
      ),
    );
  }

  List<Widget> _buildReactionChipWidgets(
    BackgroundReadableColors readableColors,
  ) {
    final groups = <String, List<MessageReaction>>{};
    for (final r in reactions) {
      groups.putIfAbsent(r.emoji, () => []).add(r);
    }
    return groups.entries.map((entry) {
      final emoji = entry.key;
      final list = entry.value;
      final isOwn =
          ownPeerId != null && list.any((r) => r.senderPeerId == ownPeerId);
      return GestureDetector(
        onTap: onReactionTap != null ? () => onReactionTap!(emoji) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: readableColors.surfaceSubtle,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isOwn
                  ? const Color.fromRGBO(78, 205, 196, 0.30)
                  : readableColors.border.withValues(alpha: 0.34),
            ),
          ),
          child: Text(
            list.length > 1 ? '$emoji ${list.length}' : emoji,
            style: const TextStyle(fontSize: 14),
          ),
        ),
      );
    }).toList();
  }

  Widget _buildQuoteBar(BackgroundReadableColors readableColors) {
    final displayText = isQuoteUnavailable
        ? 'Message unavailable'
        : quotedText!;
    return Row(
      children: [
        Container(
          width: 2,
          height: 16,
          decoration: BoxDecoration(
            color: readableColors.divider,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            displayText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textDirection: detectTextDirection(displayText),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              fontStyle: isQuoteUnavailable
                  ? FontStyle.italic
                  : FontStyle.normal,
              color: isQuoteUnavailable
                  ? readableColors.disabledForeground
                  : readableColors.textMuted,
            ),
          ),
        ),
      ],
    );
  }

  static IconData _transportIcon(String transport) {
    switch (transport) {
      case 'wifi':
      case 'local':
        return Icons.wifi;
      case 'direct':
      case 'reuse':
        // Keep old rows renderable after the send path stopped persisting reuse.
        return Icons.device_hub;
      case 'upgraded':
        // FDC-13: a relay->direct DCUtR upgrade is MORE direct than a native
        // direct send — give it a distinct up-arrow badge, not device_hub.
        return Icons.upgrade;
      case 'relay':
        return Icons.cell_tower;
      case 'inbox':
        return Icons.inbox;
      default:
        return Icons.help_outline;
    }
  }

  static IconData _statusIcon(String status) {
    // 155: a message that reached the relay inbox reads as a good "in the
    // inbox" state — 'inboxed' (doc-115 relay custody), 'delivered' (receiver
    // confirmed), and legacy 'queued' all render the inbox glyph. The two-tick
    // done_all is RETIRED from the UI (kept in the model for future
    // debug/read-receipt reuse), so delivery no longer visibly "pops".
    if (status == 'delivered' || status == 'queued' || status == 'inboxed') {
      return Icons.inbox_rounded;
    }
    // 'send_failed' = terminal group send (retry budget exhausted, finding 05
    // Phase 4): renders with the same error indicator as 'failed'.
    if (status == 'failed' || status == 'send_failed') {
      return Icons.error_outline_rounded;
    }
    // 210: a group message queued while the sender is OFFLINE — durably queued
    // and self-healing, NOT in-flight — rests on a CLOCK until connectivity
    // returns (distinct from 'sending'/'pending' below, which stay a single
    // tick). Group/legacy path only; the 1:1 transportStatusGlyph branch is
    // untouched (this value never reaches it).
    if (status == 'queued_offline') {
      return Icons.schedule_rounded;
    }
    // 155: 'pending' is genuinely in-flight — NOT yet in the relay inbox.
    // (Changed) in-flight now shows a single tick instead of the clock.
    if (status == 'pending') {
      return Icons.done_rounded;
    }
    return Icons.done_rounded; // 'sent', 'sending'
  }

  static Color _statusColor(
    String status,
    BackgroundReadableColors readableColors,
  ) {
    if (status == 'failed' || status == 'send_failed') {
      return readableColors.isLightSurface
          ? const Color(0xFFB42318)
          : const Color.fromRGBO(255, 100, 100, 0.60);
    }
    // 155: 'pending' alone keeps the amber "still waiting" hue; once a message
    // reaches the inbox ('inboxed'/'delivered'/'queued') it reads as a good
    // state in the neutral muted color (the default branch below, same as
    // 'sent'), not amber.
    if (status == 'pending') {
      return readableColors.isLightSurface
          ? const Color(0xFF8A4A00)
          : const Color.fromRGBO(255, 200, 100, 0.50);
    }
    // 210: 'queued_offline' is a benign waiting-to-send state (not an error and
    // not the amber in-doubt hue) — the neutral muted tone, same as 'sent'.
    if (status == 'queued_offline') {
      return readableColors.isLightSurface
          ? readableColors.iconMuted
          : const Color.fromRGBO(255, 255, 255, 0.25);
    }
    // 'sent', 'sending', 'inboxed', 'delivered', 'queued' → neutral muted.
    return readableColors.isLightSurface
        ? readableColors.iconMuted
        : const Color.fromRGBO(255, 255, 255, 0.25);
  }

  static String _statusSemantic(BuildContext context, String status) {
    final l10n = AppLocalizations.of(context)!;
    // 155: the reached-the-inbox state shares one "delivered to inbox" a11y
    // label (inboxed/delivered/queued); the underlying 'delivered' status is
    // preserved in the model — only its label and glyph changed.
    if (status == 'delivered' || status == 'queued' || status == 'inboxed') {
      return l10n.message_status_inbox;
    }
    if (status == 'failed' || status == 'send_failed') {
      return l10n.message_status_failed;
    }
    // 210: waiting-to-send while offline. Hardcoded copy mirrors the group
    // offline snackbar's hardcoded const (l10n is deferred debt for both — see
    // the 210 plan's Accepted Differences); reads "waiting to send" to a screen
    // reader via the message_status_semantics wrapper.
    if (status == 'queued_offline') return 'waiting to send';
    if (status == 'sending') return l10n.message_status_sending;
    if (status == 'sent') return l10n.message_status_sent;
    if (status == 'pending') {
      return l10n.message_status_pending_inbox;
    }
    return status;
  }

  /// 155/184: the inline status glyph for OUTGOING messages. When
  /// [transportStatusGlyph] is set (1:1 only): in-flight shows a single tick,
  /// failed shows the error glyph, a relay-CUSTODY ('inboxed') message shows the
  /// two-tick done_all (184: the honest mid-send custody milestone), and any
  /// other reached message shows the TRANSPORT it travelled (`_transportIcon`),
  /// falling back to the single check when no transport is known. Group/legacy
  /// (flag false) keeps the v1 [_statusIcon] inbox glyph — done_all is 1:1 only.
  IconData _resolvedStatusIcon(String status) {
    if (!transportStatusGlyph) return _statusIcon(status);
    if (status == 'failed' || status == 'send_failed') {
      return Icons.error_outline_rounded;
    }
    if (status == 'pending' || status == 'sending') {
      return Icons.done_rounded; // (Changed) single tick instead of the clock
    }
    // 184: relay custody confirmed → two ticks (done_all). The honest "the
    // system has it" milestone (~110 ms inbox ACK), distinct from the optimistic
    // single tick; an offline peer rests here instead of spinning. 1:1 ONLY
    // (this path) — group/legacy keeps the v1 inbox glyph. NOT a read receipt:
    // two ticks = relay custody, not recipient-device receipt.
    if (status == 'inboxed') {
      return Icons.done_all_rounded;
    }
    // Reached live (sent/delivered/queued): show how it travelled.
    final t = transport;
    if (t != null) return _transportIcon(t);
    return Icons.done_rounded;
  }

  /// 155: the a11y label for the OUTGOING status glyph. In the transport path a
  /// reached message reads "sent via `transport`"; everything else (and the
  /// group/legacy path) keeps the v1 "Message status: `state`" label.
  String _resolvedStatusSemantic(BuildContext context, String status) {
    final l10n = AppLocalizations.of(context)!;
    if (transportStatusGlyph &&
        status != 'failed' &&
        status != 'send_failed' &&
        status != 'pending' &&
        status != 'sending') {
      final t = transport;
      final via = t == null ? null : _sentViaSemantic(l10n, t);
      if (via != null) return via;
    }
    return l10n.message_status_semantics(_statusSemantic(context, status));
  }

  /// 155: the a11y label for the INCOMING transport glyph ("received via …").
  String _resolvedIncomingSemantic(BuildContext context, String transport) {
    final l10n = AppLocalizations.of(context)!;
    return _receivedViaSemantic(l10n, transport) ??
        l10n.message_status_semantics(transport);
  }

  static String? _sentViaSemantic(AppLocalizations l10n, String transport) {
    switch (transport) {
      case 'relay':
        return l10n.message_sent_via_relay;
      case 'direct':
      case 'reuse':
        return l10n.message_sent_via_direct;
      case 'upgraded':
        return l10n.message_sent_via_upgraded;
      case 'wifi':
      case 'local':
        return l10n.message_sent_via_wifi;
      case 'inbox':
        return l10n.message_sent_via_inbox;
    }
    return null;
  }

  static String? _receivedViaSemantic(AppLocalizations l10n, String transport) {
    switch (transport) {
      case 'relay':
        return l10n.message_received_via_relay;
      case 'direct':
      case 'reuse':
        return l10n.message_received_via_direct;
      case 'upgraded':
        return l10n.message_received_via_upgraded;
      case 'wifi':
      case 'local':
        return l10n.message_received_via_wifi;
      case 'inbox':
        return l10n.message_received_via_inbox;
    }
    return null;
  }
}

/// 137: a [WidgetSpan] for the inline trailing metadata (timestamp + edited +
/// delivery status) that contributes NOTHING to the host paragraph's plain
/// text. A normal [WidgetSpan] injects an object-replacement character (U+FFFC)
/// into `toPlainText()`, which would pollute the message body's text and break
/// exact-string finders / screen-reader text extraction (e.g. `find.text(body)`
/// across the conversation + group screen suites). Suppressing the placeholder
/// here keeps the body text matchable by its exact string while leaving layout
/// and semantics untouched (paragraph layout uses placeholder *dimensions*, and
/// the child renders its own semantics node — neither reads the plain-text
/// buffer).
class _InlineMetaWidgetSpan extends WidgetSpan {
  const _InlineMetaWidgetSpan({required super.child})
    : super(alignment: PlaceholderAlignment.middle);

  @override
  void computeToPlainText(
    StringBuffer buffer, {
    bool includeSemanticsLabels = true,
    bool includePlaceholders = true,
  }) {
    // Deliberately a no-op: inline metadata must not appear in the host
    // paragraph's plain-text representation.
  }
}
