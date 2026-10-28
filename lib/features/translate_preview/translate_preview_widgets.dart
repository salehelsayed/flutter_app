import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/utils/text_direction_utils.dart';
import 'package:flutter_app/features/translate_preview/language_heuristic.dart';
import 'package:flutter_app/features/translate_preview/on_device_ai.dart';

String _systemLanguageCode() =>
    WidgetsBinding.instance.platformDispatcher.locale.languageCode;

/// A small "Translate" link under [text]. Shows nothing when [text] is already
/// in the phone's language, is Arabizi, or the language has no prompt name.
/// The original stays where it is; the translation appears below it.
class TranslatePreview extends StatelessWidget {
  const TranslatePreview({
    super.key,
    required this.text,
    required this.ai,
    this.color,
  });

  final String text;
  final OnDeviceAi ai;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final target = _systemLanguageCode();
    final languageName = translateLanguageName(target);
    if (languageName == null || !shouldOfferTranslate(text, target)) {
      return const SizedBox.shrink();
    }
    return _AiAction(
      key: ValueKey('translate-preview:$target:$text'),
      labels: const _Labels(
        action: 'Translate',
        busy: 'Translating…',
        failure: "Couldn't translate",
        result: 'Auto-translated, may be wrong',
        hide: 'Show original',
      ),
      run: () => ai.translate(text, languageName: languageName),
      color: color,
    );
  }
}

/// A small "Transcribe" link under a received voice message, then the
/// transcript with Translate offered on it.
class TranscribePreview extends StatelessWidget {
  const TranscribePreview({
    super.key,
    required this.audioPath,
    required this.ai,
    this.color,
  });

  final String audioPath;
  final OnDeviceAi ai;
  final Color? color;

  @override
  Widget build(BuildContext context) => _AiAction(
    labels: const _Labels(
      action: 'Transcribe',
      busy: 'Transcribing…',
      failure: "Couldn't transcribe",
      result: 'Auto-transcribed, may be wrong',
    ),
    run: () => ai.transcribe(audioPath),
    color: color,
    below: (transcript) =>
        TranslatePreview(text: transcript, ai: ai, color: color),
  );
}

class _Labels {
  const _Labels({
    required this.action,
    required this.busy,
    required this.failure,
    required this.result,
    this.hide,
  });

  final String action;
  final String busy;
  final String failure;
  final String result;

  /// Hides the result again. Null keeps it once shown.
  final String? hide;
}

sealed class _Phase {
  const _Phase();
}

final class _Idle extends _Phase {
  const _Idle();
}

final class _Running extends _Phase {
  const _Running();
}

final class _Failed extends _Phase {
  const _Failed();
}

final class _Done extends _Phase {
  const _Done(this.text, {required this.shown});
  final String text;
  final bool shown;
}

class _AiAction extends StatefulWidget {
  const _AiAction({
    super.key,
    required this.labels,
    required this.run,
    this.color,
    this.below,
  });

  final _Labels labels;
  final Future<String> Function() run;
  final Color? color;
  final Widget Function(String result)? below;

  @override
  State<_AiAction> createState() => _AiActionState();
}

class _AiActionState extends State<_AiAction> {
  _Phase _phase = const _Idle();

  Future<void> _start() async {
    if (_phase case _Done(:final text)) {
      setState(() => _phase = _Done(text, shown: true));
      return;
    }
    setState(() => _phase = const _Running());
    try {
      final result = await widget.run();
      if (mounted) setState(() => _phase = _Done(result, shown: true));
    } on Object {
      if (mounted) setState(() => _phase = const _Failed());
    }
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.color ?? DefaultTextStyle.of(context).style.color;
    final quiet = TextStyle(color: base?.withValues(alpha: 0.75), fontSize: 12);
    final labels = widget.labels;
    final body = switch (_phase) {
      _Idle() || _Done(shown: false) => _link(labels.action, base),
      _Running() => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 12,
            child: CircularProgressIndicator(strokeWidth: 1.5, color: base),
          ),
          const SizedBox(width: 8),
          Text(labels.busy, style: quiet),
        ],
      ),
      _Failed() => Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          Text(labels.failure, style: quiet),
          _link('Try again', base),
        ],
      ),
      _Done(:final text) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            textDirection: detectTextDirection(text),
            style: TextStyle(color: base, fontSize: 15, height: 1.3),
          ),
          const SizedBox(height: 4),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(labels.result, style: quiet),
              if (labels.hide case final hide?)
                _link(
                  hide,
                  base,
                  onTap: () =>
                      setState(() => _phase = _Done(text, shown: false)),
                ),
            ],
          ),
          if (widget.below case final below?) below(text),
        ],
      ),
    };
    return Padding(padding: const EdgeInsets.only(top: 6), child: body);
  }

  Widget _link(String label, Color? color, {VoidCallback? onTap}) => InkWell(
    onTap: onTap ?? () => unawaited(_start()),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.underline,
          decorationColor: color,
        ),
      ),
    ),
  );
}
