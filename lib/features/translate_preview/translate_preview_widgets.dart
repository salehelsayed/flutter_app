import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/utils/text_direction_utils.dart';
import 'package:flutter_app/features/translate_preview/language_heuristic.dart';
import 'package:flutter_app/features/translate_preview/model_delivery_contract.dart';
import 'package:flutter_app/features/translate_preview/on_device_ai.dart';
import 'package:flutter_app/features/translate_preview/private_translator_sheet.dart';
import 'package:flutter_app/features/translate_preview/translate_preview_persistence.dart';
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
    this.owner,
    this.persistence,
  });

  final String text;
  final OnDeviceAi ai;

  /// Null means the model is already on the phone.
  final ModelDeliveryController? delivery;
  final VoidCallback? onFreeUpSpace;
  final Color? color;
  final PreviewOwner? owner;
  final TranslatePreviewPersistence? persistence;

  @override
  Widget build(BuildContext context) {
    final target = Localizations.localeOf(context).languageCode;
    final languageName = translateLanguageName(target);
    final store = persistence ?? translatePreviewPersistence;
    final offered = languageName != null && shouldOfferTranslate(text, target);
    if (!offered && store == null) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context)!;
    final item = owner;
    Future<String?> restore() => store != null && item != null
        ? store.loadTranslation(item, text, target)
        : Future<String?>.value();
    return _AiAction(
      key: ValueKey(('translate-preview', item ?? text)),
      identity: (item, text),
      targetLanguage: target,
      visible: offered,
      labels: _Labels(
        action: l10n.translator_see_translation,
        busy: l10n.translator_translating,
        failure: l10n.translator_translate_failed,
      ),
      restore: store != null && item != null ? restore : null,
      run: () async =>
          await restore() ??
          await ai.translate(text, languageName: languageName!),
      save: store != null && item != null
          ? (result) => store.saveTranslation(item, text, target, result)
          : null,
      color: color,
      gate: (child, restore) => _DeliveryGate(
        beforeOpen: restore,
        delivery: delivery,
        onFreeUpSpace: onFreeUpSpace,
        action: l10n.translator_see_translation,
        words: (
          downloading: l10n.translator_link_downloading,
          paused: l10n.translator_link_paused,
          failed: l10n.translator_link_failed,
        ),
        color: color,
        ready: () => child,
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
    this.owner,
    this.persistence,
  });

  final String audioPath;
  final OnDeviceAi ai;
  final ModelDeliveryController? delivery;
  final VoidCallback? onFreeUpSpace;
  final Color? color;
  final PreviewOwner? owner;
  final TranslatePreviewPersistence? persistence;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final store = persistence ?? translatePreviewPersistence;
    final item = owner;
    Future<String?> restore() => store != null && item != null
        ? store.loadTranscript(item)
        : Future<String?>.value();
    return _AiAction(
      identity: item ?? audioPath,
      labels: _Labels(
        action: l10n.translator_transcribe,
        busy: l10n.translator_transcribing,
        failure: l10n.translator_transcribe_failed,
      ),
      restore: store != null && item != null ? restore : null,
      run: () async => await restore() ?? await ai.transcribe(audioPath),
      save: store != null && item != null
          ? (result) => store.saveTranscript(item, result)
          : null,
      color: color,
      below: (transcript) => TranslatePreview(
        text: transcript,
        ai: ai,
        delivery: delivery,
        onFreeUpSpace: onFreeUpSpace,
        color: color,
        owner: item,
        persistence: store,
      ),
      gate: (child, restore) => _DeliveryGate(
        beforeOpen: restore,
        delivery: delivery,
        onFreeUpSpace: onFreeUpSpace,
        action: l10n.translator_transcribe,
        words: (
          downloading: l10n.translator_link_transcribe_downloading,
          paused: l10n.translator_link_transcribe_paused,
          failed: l10n.translator_link_transcribe_failed,
        ),
        color: color,
        ready: () => child,
      ),
    );
  }
}

/// What a link says while the one download runs, waits or failed: a voice
/// message offers its transcript first, so it never promises a translation.
typedef _GateWords = ({
  String Function(String percent) downloading,
  String Function(String percent) paused,
  String failed,
});

/// Until the translator is on the phone, every link shows where the one
/// download stands and opens the download sheet.
class _DeliveryGate extends StatelessWidget {
  const _DeliveryGate({
    required this.delivery,
    required this.action,
    required this.words,
    required this.ready,
    this.onFreeUpSpace,
    this.color,
    this.beforeOpen,
  });

  final ModelDeliveryController? delivery;
  final VoidCallback? onFreeUpSpace;
  final String action;
  final _GateWords words;
  final Widget Function() ready;
  final Color? color;
  final Future<bool> Function()? beforeOpen;

  @override
  Widget build(BuildContext context) {
    final controller = delivery;
    if (controller == null) return ready();
    return ValueListenableBuilder<ModelDeliveryState>(
      valueListenable: controller.state,
      builder: (context, state, _) {
        final l10n = AppLocalizations.of(context)!;
        void openSheet() => unawaited(() async {
          if (await beforeOpen?.call() == true || !context.mounted) return;
          await showPrivateTranslatorSheet(
            context,
            controller: controller,
            onFreeUpSpace: onFreeUpSpace,
          );
        }());
        final base = color ?? DefaultTextStyle.of(context).style.color;
        final link = switch (state) {
          ModelUnsupported() => null,
          ModelReady() => null,
          ModelNotDownloaded() ||
          ModelNotEnoughSpace() => _Link(action, base, onTap: openSheet),
          ModelDownloading(:final percent) => _Link(
            words.downloading('$percent'),
            base,
            onTap: openSheet,
            quiet: true,
          ),
          ModelWaitingForWifi(:final percent) ||
          ModelPaused(:final percent) => _Link(
            words.paused('$percent'),
            base,
            onTap: openSheet,
            quiet: true,
          ),
          ModelFailed() => Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(words.failed, style: _quiet(base)),
              _Link(
                l10n.translator_try_again,
                base,
                onTap: () => unawaited(() async {
                  if (await beforeOpen?.call() == true || !context.mounted) {
                    return;
                  }
                  await controller.retry();
                }()),
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

class _Labels {
  const _Labels({
    required this.action,
    required this.busy,
    required this.failure,
  });

  final String action;
  final String busy;
  final String failure;
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

final class _Restoring extends _Phase {
  const _Restoring();
}

final class _Failed extends _Phase {
  const _Failed();
}

final class _Done extends _Phase {
  const _Done(this.text);
  final String text;
}

class _AiAction extends StatefulWidget {
  const _AiAction({
    super.key,
    required this.labels,
    required this.run,
    this.color,
    this.below,
    this.restore,
    this.save,
    this.gate,
    this.identity,
    this.targetLanguage,
    this.visible = true,
  });

  final _Labels labels;
  final Future<String> Function() run;
  final Color? color;
  final Widget Function(String result)? below;
  final Future<String?> Function()? restore;
  final Future<bool> Function(String result)? save;
  final Widget Function(Widget child, Future<bool> Function() restore)? gate;
  final Object? identity;
  final String? targetLanguage;
  final bool visible;

  @override
  State<_AiAction> createState() => _AiActionState();
}

class _AiActionState extends State<_AiAction> {
  _Phase _phase = const _Idle();
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_restore());
  }

  Future<bool> _restore() async {
    final restore = widget.restore;
    if (restore == null || !widget.visible) return false;
    final generation = ++_generation;
    _phase = const _Restoring();
    try {
      final result = await restore();
      if (!mounted || generation != _generation) return true;
      setState(() => _phase = result == null ? const _Idle() : _Done(result));
      return result != null;
    } on Object {
      if (mounted && generation == _generation) {
        setState(() => _phase = const _Failed());
      }
      return true;
    }
  }

  @override
  void didUpdateWidget(covariant _AiAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity ||
        oldWidget.targetLanguage != widget.targetLanguage) {
      ++_generation;
      _phase = const _Idle();
      // A live language change waits for the user's request, then reuses cache.
      if (oldWidget.targetLanguage == widget.targetLanguage) {
        unawaited(_restore());
      }
    }
  }

  Future<void> _start() async {
    if (_phase is _Done || _phase is _Running || _phase is _Restoring) return;
    final generation = ++_generation;
    final run = widget.run;
    final save = widget.save;
    setState(() => _phase = const _Running());
    try {
      final result = await run();
      // Completion remains durable even if the user has left this widget.
      if (save != null && !await save(result)) {
        throw StateError('Preview owner is no longer available');
      }
      if (mounted && generation == _generation) {
        setState(() => _phase = _Done(result));
      }
    } on Object {
      if (mounted && generation == _generation) {
        setState(() => _phase = const _Failed());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) return const SizedBox.shrink();
    final base = widget.color ?? DefaultTextStyle.of(context).style.color;
    final quiet = TextStyle(color: base?.withValues(alpha: 0.75), fontSize: 12);
    final labels = widget.labels;
    final body = switch (_phase) {
      _Restoring() => const SizedBox.shrink(),
      _Idle() => _link(labels.action, base),
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
          if (widget.below case final below?) below(text),
        ],
      ),
    };
    final result = Padding(
      padding: const EdgeInsetsDirectional.only(top: 6),
      child: body,
    );
    return _phase is _Done
        ? result
        : widget.gate?.call(result, _restore) ?? result;
  }

  Widget _link(String label, Color? color) =>
      _Link(label, color, onTap: () => unawaited(_start()));
}
