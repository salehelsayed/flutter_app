import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_app/core/theme/feed_colors.dart';
import 'package:flutter_app/core/utils/text_search.dart';
import 'package:flutter_app/core/utils/thought_tags.dart';
import 'package:flutter_app/core/utils/url_parser.dart';
import 'package:url_launcher/url_launcher.dart';

/// Renders text with tappable, styled URL links.
///
/// URLs are detected automatically using [parseUrls] and rendered with
/// underline decoration and teal color. Tapping a link opens it in the
/// device browser (or invokes [onLinkTap] if provided).
class LinkableText extends StatefulWidget {
  final String text;
  final TextStyle? style;

  /// Merged over [style], so a link keeps the size of the words around it.
  final TextStyle? linkStyle;

  /// When set, each #tag outside a link is drawn in this style.
  final TextStyle? tagStyle;

  /// When set with [tagStyle], draws each #tag instead, for example as a
  /// tappable chip.
  final InlineSpan Function(ThoughtTag tag, String label)? tagSpan;

  /// When set, only URLs written exactly like one of these are links; any
  /// other URL stays plain text.
  final Set<String>? onlyLinks;
  final void Function(String url)? onLinkTap;
  final int? maxLines;
  final TextOverflow? overflow;
  final List<InlineSpan>? prefixSpans;
  final List<InlineSpan>? suffixSpans;
  final TextDirection? textDirection;

  /// When set with [markStyle], every match of these words (any case) is
  /// drawn in [markStyle] on top of its usual style.
  final String? markQuery;
  final TextStyle? markStyle;

  const LinkableText({
    super.key,
    required this.text,
    this.style,
    this.linkStyle,
    this.tagStyle,
    this.tagSpan,
    this.onlyLinks,
    this.onLinkTap,
    this.maxLines,
    this.overflow,
    this.prefixSpans,
    this.suffixSpans,
    this.textDirection,
    this.markQuery,
    this.markStyle,
  });

  @override
  State<LinkableText> createState() => _LinkableTextState();
}

class _LinkableTextState extends State<LinkableText> {
  List<InlineSpan> _spans = [];
  List<TextSegment> _links = const [];
  final List<TapGestureRecognizer> _recognizers = [];

  /// Where [LinkableText.markQuery] occurs in the whole text, so a phrase
  /// crossing a link boundary is marked on both sides.
  List<({int start, int end})> _marks = const [];

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(LinkableText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.style != widget.style ||
        oldWidget.linkStyle != widget.linkStyle ||
        oldWidget.tagStyle != widget.tagStyle ||
        oldWidget.tagSpan != widget.tagSpan ||
        !setEquals(oldWidget.onlyLinks, widget.onlyLinks) ||
        oldWidget.onLinkTap != widget.onLinkTap ||
        oldWidget.markQuery != widget.markQuery ||
        oldWidget.markStyle != widget.markStyle) {
      _disposeRecognizers();
      _parse();
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  void _parse() {
    final onlyLinks = widget.onlyLinks;
    final segments = [
      for (final segment in parseUrls(widget.text))
        segment.isUrl && onlyLinks != null && !onlyLinks.contains(segment.text)
            ? TextSegment(segment.text)
            : segment,
    ];
    final spans = <InlineSpan>[];
    _marks = widget.markStyle == null
        ? const []
        : textSearchRanges(widget.text, widget.markQuery ?? '');

    final linkStyle =
        widget.linkStyle ??
        TextStyle(
          color: FeedColors.accentTeal,
          decoration: TextDecoration.underline,
          decorationColor: FeedColors.accentTeal.withValues(alpha: 0.5),
        );

    var offset = 0;
    for (final segment in segments) {
      if (segment.isUrl) {
        final recognizer = TapGestureRecognizer()
          ..onTap = () => _handleTap(segment);
        _recognizers.add(recognizer);

        spans.addAll(
          _mark(
            segment.text,
            offset,
            widget.style?.merge(linkStyle) ?? linkStyle,
            recognizer: recognizer,
          ),
        );
      } else {
        spans.addAll(_withTags(segment.text, offset));
      }
      offset += segment.text.length;
    }

    _spans = spans;
    _links = [
      for (final segment in segments)
        if (segment.isUrl) segment,
    ];
  }

  Iterable<InlineSpan> _withTags(String text, int offset) sync* {
    final tagStyle = widget.tagStyle;
    final tags = tagStyle == null
        ? const <ThoughtTag>[]
        : parseThoughtTags(text);
    var at = 0;
    for (final tag in tags) {
      if (tag.start > at) {
        yield* _mark(text.substring(at, tag.start), offset + at, widget.style);
      }
      final label = text.substring(tag.start, tag.end);
      if (widget.tagSpan case final tagSpan?) {
        yield tagSpan(tag, label);
      } else {
        yield* _mark(label, offset + tag.start, tagStyle);
      }
      at = tag.end;
    }
    if (at < text.length || tags.isEmpty) {
      yield* _mark(text.substring(at), offset + at, widget.style);
    }
  }

  /// [text] starts at [offset] in the whole message; it is drawn in [style]
  /// with the parts inside [_marks] in the mark style.
  Iterable<TextSpan> _mark(
    String text,
    int offset,
    TextStyle? style, {
    GestureRecognizer? recognizer,
  }) sync* {
    final markStyle = widget.markStyle;
    final ranges = [
      for (final mark in _marks)
        if (mark.end > offset && mark.start < offset + text.length)
          (
            start: (mark.start - offset).clamp(0, text.length),
            end: (mark.end - offset).clamp(0, text.length),
          ),
    ];
    if (ranges.isEmpty) {
      yield TextSpan(text: text, style: style, recognizer: recognizer);
      return;
    }
    final marked = style?.merge(markStyle) ?? markStyle;
    var at = 0;
    for (final range in ranges) {
      if (range.start > at) {
        yield TextSpan(
          text: text.substring(at, range.start),
          style: style,
          recognizer: recognizer,
        );
      }
      yield TextSpan(
        text: text.substring(range.start, range.end),
        style: marked,
        recognizer: recognizer,
      );
      at = range.end;
    }
    if (at < text.length) {
      yield TextSpan(
        text: text.substring(at),
        style: style,
        recognizer: recognizer,
      );
    }
  }

  void _handleTap(TextSegment link) {
    if (widget.onLinkTap case final onLinkTap?) {
      onLinkTap(link.text);
    } else {
      launchUrl(link.uri!, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allSpans = <InlineSpan>[
      if (widget.prefixSpans != null) ...widget.prefixSpans!,
      ..._spans,
      if (widget.suffixSpans != null) ...widget.suffixSpans!,
    ];

    final richText = Text.rich(
      TextSpan(children: allSpans),
      maxLines: widget.maxLines,
      overflow: widget.overflow ?? TextOverflow.clip,
      textDirection: widget.textDirection,
    );
    if (_links.isEmpty) return richText;
    // A link's recognizer splits RichText into accessibility fragments. Merge
    // the complete message while retaining inline timestamp/status widgets.
    return MergeSemantics(
      child: Semantics(
        onTap: _links.length == 1 ? () => _handleTap(_links.single) : null,
        customSemanticsActions: _links.length > 1
            ? {
                for (final link in _links)
                  CustomSemanticsAction(label: link.text): () =>
                      _handleTap(link),
              }
            : null,
        child: richText,
      ),
    );
  }
}
