import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/utils/text_direction_utils.dart';
import 'package:flutter_app/features/translate_preview/language_heuristic.dart';
import 'package:flutter_app/features/translate_preview/model_delivery_contract.dart';
import 'package:flutter_app/features/translate_preview/on_device_ai.dart';
import 'package:flutter_app/features/translate_preview/private_translator_sheet.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// Opens the existing Storage section from a link's download sheet. The
/// Orbit screen registers it because it owns the storage manager and scopes.
VoidCallback? translatePreviewOpenStorage;

/// A small "See translation" link under [text]. Shows nothing when [text] is
/// already in the user's Mknoon language, is Arabizi, or the language has no
/// prompt name. The original stays where it is; the translation appears below
/// it.
class TranslatePreview extends StatelessWidget {
  const TranslatePreview({
    super.key,
    required this.text,
    required this.ai,
    this.delivery,
    this.onFreeUpSpace,
    this.color,
  });

  final String text;
  final OnDeviceAi ai;

  /// Null means the model is already on the phone.
  final ModelDeliveryController? delivery;
  final VoidCallback? onFreeUpSpace;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final target = Localizations.localeOf(context).languageCode;
    final languageName = translateLanguageName(target);
    if (languageName == null || !shouldOfferTranslate(text, target)) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context)!;
    return _DeliveryGate(
      delivery: delivery,
      onFreeUpSpace: onFreeUpSpace,
      action: l10n.translator_see_translation,
      color: color,
      ready: () => _AiAction(
        key: ValueKey('translate-preview:$target:$text'),
        labels: _Labels(
          action: l10n.translator_see_translation,
          busy: 'Translating…',
          failure: "Couldn't translate",
          hide: l10n.translator_hide,
        ),
        run: () => ai.translate(text, languageName: languageName),
        color: color,
      ),
    );
  }
}

/// A small "Transcribe" link under a received voice message, then the
/// transcript with "See translation" offered on it.
class TranscribePreview extends StatelessWidget {
  const TranscribePreview({
    super.key,
    required this.audioPath,
    required this.ai,
    this.delivery,
    this.onFreeUpSpace,
    this.color,
  });

  final String audioPath;
  final OnDeviceAi ai;
  final ModelDeliveryController? delivery;
  final VoidCallback? onFreeUpSpace;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _DeliveryGate(
      delivery: delivery,
      onFreeUpSpace: onFreeUpSpace,
      action: l10n.translator_transcribe,
      color: color,
      ready: () => _AiAction(
        labels: _Labels(
          action: l10n.translator_transcribe,
          busy: 'Transcribing…',
          failure: "Couldn't transcribe",
        ),
        run: () => ai.transcribe(audioPath),
        color: color,
        below: (transcript) => TranslatePreview(
          text: transcript,
          ai: ai,
          delivery: delivery,
          onFreeUpSpace: onFreeUpSpace,
          color: color,
        ),
      ),
    );
  }
}

/// Until the translator is on the phone, every link shows where the one
/// download stands and opens the download sheet.
class _DeliveryGate extends StatelessWidget {
  const _DeliveryGate({
    required this.delivery,
    required this.action,
    required this.ready,
    this.onFreeUpSpace,
    this.color,
  });

  final ModelDeliveryController? delivery;
  final VoidCallback? onFreeUpSpace;
  final String action;
  final Widget Function() ready;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final controller = delivery;
    if (controller == null) return ready();
    return ValueListenableBuilder<ModelDeliveryState>(
      valueListenable: controller.state,
      builder: (context, state, _) {
        final l10n = AppLocalizations.of(context)!;
        void openSheet() => unawaited(
          showPrivateTranslatorSheet(
            context,
            controller: controller,
            onFreeUpSpace: onFreeUpSpace,
          ),
        );
        final base = color ?? DefaultTextStyle.of(context).style.color;
        final link = switch (state) {
          ModelUnsupported() => null,
          ModelReady() => null,
          ModelNotDownloaded() ||
          ModelNotEnoughSpace() => _Link(action, base, onTap: openSheet),
          ModelDownloading(:final percent) => _Link(
            l10n.translator_link_downloading('$percent'),
            base,
            onTap: openSheet,
            quiet: true,
          ),
          ModelWaitingForWifi(:final percent) ||
          ModelPaused(:final percent) => _Link(
            l10n.translator_link_paused('$percent'),
            base,
            onTap: openSheet,
            quiet: true,
          ),
          ModelFailed() => Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(l10n.translator_link_failed, style: _quiet(base)),
              _Link(
                l10n.translator_try_again,
                base,
                onTap: () => unawaited(controller.retry()),
              ),
            ],
          ),
        };
        return switch (state) {
          ModelReady() => ready(),
          ModelUnsupported() => const SizedBox.shrink(),
          _ => Padding(
            padding: const EdgeInsetsDirectional.only(top: 6),
            child: link,
          ),
        };
      },
    );
  }
}

TextStyle _quiet(Color? base) =>
    TextStyle(color: base?.withValues(alpha: 0.75), fontSize: 12);

class _Link extends StatelessWidget {
  const _Link(
    this.label,
    this.color, {
    required this.onTap,
    this.quiet = false,
  });

  final String label;
  final Color? color;
  final VoidCallback onTap;

  /// A status the user can tap, not an action, so it is not underlined.
  final bool quiet;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        label,
        style: quiet
            ? _quiet(color).copyWith(fontSize: 13)
            : TextStyle(
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

/// "BETA · Only on your phone", under every translation and transcript.
class _BetaTag extends StatelessWidget {
  const _BetaTag(this.color);

  final Color? color;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: 5,
            vertical: 1,
          ),
          decoration: BoxDecoration(
            border: Border.all(
              color: color?.withValues(alpha: 0.6) ?? Colors.grey,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            l10n.translator_result_beta,
            style: _quiet(
              color,
            ).copyWith(fontSize: 10, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 6),
        Text(l10n.translator_result_only_phone, style: _quiet(color)),
      ],
    );
  }
}

class _Labels {
  const _Labels({
    required this.action,
    required this.busy,
    required this.failure,
    this.hide,
  });

  final String action;
  final String busy;
  final String failure;

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
          _link(AppLocalizations.of(context)!.translator_try_again, base),
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
              _BetaTag(base),
              if (labels.hide case final hide?) ...[
                Text('·', style: quiet),
                _Link(
                  hide,
                  base,
                  onTap: () =>
                      setState(() => _phase = _Done(text, shown: false)),
                ),
              ],
            ],
          ),
          if (widget.below case final below?) below(text),
        ],
      ),
    };
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 6),
      child: body,
    );
  }

  Widget _link(String label, Color? color) =>
      _Link(label, color, onTap: () => unawaited(_start()));
}
