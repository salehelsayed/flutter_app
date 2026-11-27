import 'package:flutter/widgets.dart';

/// Keeps a name visible on two lines at large text sizes and narrow widths.
class TwoLineLabel extends StatelessWidget {
  const TwoLineLabel({
    super.key,
    required this.text,
    required this.style,
    this.textAlign = TextAlign.start,
  });

  final TextSpan text;
  final TextStyle style;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final inheritedStyle = DefaultTextStyle.of(context).style.merge(style);
    final effectiveStyle = MediaQuery.boldTextOf(context)
        ? inheritedStyle.merge(const TextStyle(fontWeight: FontWeight.bold))
        : inheritedStyle;
    final scaler = MediaQuery.textScalerOf(context);
    final size = effectiveStyle.fontSize ?? 14;

    return LayoutBuilder(
      builder: (context, constraints) {
        var fittedScaler = scaler;
        int? lines = 2;
        if (constraints.hasBoundedWidth) {
          final painter = TextPainter(
            text: TextSpan(style: effectiveStyle, children: [text]),
            textDirection: Directionality.of(context),
            locale: Localizations.maybeLocaleOf(context),
            maxLines: lines,
          );
          bool fits(TextScaler candidate) {
            painter.textScaler = candidate;
            painter.layout(maxWidth: constraints.maxWidth);
            return !painter.didExceedMaxLines;
          }

          if (!fits(scaler)) {
            if (fits(scaler.clamp(maxScaleFactor: 1))) {
              var low = 1.0;
              var high = scaler.scale(size) / size;
              for (var step = 0; step < 6; step++) {
                final middle = (low + high) / 2;
                if (fits(scaler.clamp(maxScaleFactor: middle))) {
                  low = middle;
                } else {
                  high = middle;
                }
              }
              fittedScaler = scaler.clamp(maxScaleFactor: low);
            } else {
              lines = null;
            }
          }
          painter.dispose();
        }
        return Text.rich(
          text,
          style: style,
          textAlign: textAlign,
          maxLines: lines,
          overflow: TextOverflow.clip,
          textScaler: fittedScaler,
        );
      },
    );
  }
}
