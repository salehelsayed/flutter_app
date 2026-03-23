import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/feed_colors.dart';
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
  final TextStyle? linkStyle;
  final void Function(String url)? onLinkTap;
  final int? maxLines;
  final TextOverflow? overflow;
  final List<InlineSpan>? prefixSpans;
  final List<InlineSpan>? suffixSpans;
  final TextDirection? textDirection;

  const LinkableText({
    super.key,
    required this.text,
    this.style,
    this.linkStyle,
    this.onLinkTap,
    this.maxLines,
    this.overflow,
    this.prefixSpans,
    this.suffixSpans,
    this.textDirection,
  });

  @override
  State<LinkableText> createState() => _LinkableTextState();
}

class _LinkableTextState extends State<LinkableText> {
  List<InlineSpan> _spans = [];
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(LinkableText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.onLinkTap != widget.onLinkTap) {
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
    final segments = parseUrls(widget.text);
    final spans = <InlineSpan>[];

    final defaultLinkStyle = TextStyle(
      color: FeedColors.accentTeal,
      decoration: TextDecoration.underline,
      decorationColor: FeedColors.accentTeal.withValues(alpha: 0.5),
    );

    for (final segment in segments) {
      if (segment.isUrl) {
        final recognizer = TapGestureRecognizer()
          ..onTap = () => _handleTap(segment.text);
        _recognizers.add(recognizer);

        spans.add(
          TextSpan(
            text: segment.text,
            style: widget.linkStyle ?? defaultLinkStyle,
            recognizer: recognizer,
          ),
        );
      } else {
        spans.add(TextSpan(text: segment.text, style: widget.style));
      }
    }

    _spans = spans;
  }

  void _handleTap(String url) {
    if (widget.onLinkTap != null) {
      widget.onLinkTap!(url);
    } else {
      _launchDefault(url);
    }
  }

  void _launchDefault(String url) {
    final uriString = url.startsWith('www.') ? 'https://$url' : url;
    final uri = Uri.tryParse(uriString);
    if (uri != null) {
      launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allSpans = <InlineSpan>[
      if (widget.prefixSpans != null) ...widget.prefixSpans!,
      ..._spans,
      if (widget.suffixSpans != null) ...widget.suffixSpans!,
    ];

    return Text.rich(
      TextSpan(children: allSpans),
      maxLines: widget.maxLines,
      overflow: widget.overflow ?? TextOverflow.clip,
      textDirection: widget.textDirection,
    );
  }
}
