import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

Future<bool> _openExternalUrl(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

Future<void> _copyText(String text) =>
    Clipboard.setData(ClipboardData(text: text));

/// An in-app reporting contact, available even without a mail application.
/// Only the user can send a report; no app or conversation data is attached.
class SafetySupportSheet extends StatefulWidget {
  static const contactEmail = 'saleh.m.elsayed@proton.me';
  static final standardsUri = Uri.https('mknoon.space', '/child-safety');
  static final reportUri = Uri(
    scheme: 'mailto',
    path: contactEmail,
    query: 'subject=${Uri.encodeComponent('mknoon safety report')}',
  );

  final Future<bool> Function(Uri) openUrl;
  final Future<void> Function(String) copyText;

  const SafetySupportSheet({
    super.key,
    this.openUrl = _openExternalUrl,
    this.copyText = _copyText,
  });

  @override
  State<SafetySupportSheet> createState() => _SafetySupportSheetState();
}

enum _SupportFeedback {
  emailUnavailable,
  browserUnavailable,
  copied,
  copyFailed,
}

class _SafetySupportSheetState extends State<SafetySupportSheet> {
  bool _working = false;
  _SupportFeedback? _feedback;

  Future<void> _open(Uri uri, _SupportFeedback failure) async {
    if (_working) return;
    setState(() {
      _working = true;
      _feedback = null;
    });
    var opened = false;
    try {
      opened = await widget.openUrl(uri);
    } catch (_) {
      // A missing handler or platform failure leaves the contact visible.
    }
    if (!mounted) return;
    setState(() {
      _working = false;
      _feedback = opened ? null : failure;
    });
  }

  Future<void> _copyEmail() async {
    if (_working) return;
    setState(() {
      _working = true;
      _feedback = null;
    });
    var feedback = _SupportFeedback.copied;
    try {
      await widget.copyText(SafetySupportSheet.contactEmail);
    } catch (_) {
      feedback = _SupportFeedback.copyFailed;
    }
    if (!mounted) return;
    setState(() {
      _working = false;
      _feedback = feedback;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.backgroundReadableColors;
    final feedbackText = switch (_feedback) {
      _SupportFeedback.emailUnavailable =>
        l10n.settings_safety_support_email_unavailable,
      _SupportFeedback.browserUnavailable =>
        l10n.settings_safety_support_browser_unavailable,
      _SupportFeedback.copied => l10n.settings_safety_support_copied,
      _SupportFeedback.copyFailed => l10n.settings_safety_support_copy_failed,
      null => null,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    l10n.settings_safety_support_title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: () => Navigator.of(context).pop(),
                color: colors.iconPrimary,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l10n.settings_safety_support_description,
            style: TextStyle(color: colors.textPrimary, height: 1.4),
          ),
          const SizedBox(height: 12),
          SelectableText(
            SafetySupportSheet.contactEmail,
            textDirection: TextDirection.ltr,
            style: TextStyle(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                key: const ValueKey('safety-support-email'),
                onPressed: _working
                    ? null
                    : () => _open(
                        SafetySupportSheet.reportUri,
                        _SupportFeedback.emailUnavailable,
                      ),
                style: FilledButton.styleFrom(
                  backgroundColor: colors.accent,
                  foregroundColor: colors.accentIcon,
                ),
                icon: const Icon(Icons.mail_outline),
                label: Text(l10n.settings_safety_support_email),
              ),
              OutlinedButton.icon(
                key: const ValueKey('safety-support-copy-email'),
                onPressed: _working ? null : _copyEmail,
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.textPrimary,
                  side: BorderSide(color: colors.border),
                ),
                icon: const Icon(Icons.copy_outlined),
                label: Text(l10n.settings_safety_support_copy_email),
              ),
            ],
          ),
          if (feedbackText != null) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                feedbackText,
                style: TextStyle(color: colors.textPrimary, height: 1.4),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            l10n.settings_safety_support_guidance,
            style: TextStyle(color: colors.textMuted, height: 1.4),
          ),
          const SizedBox(height: 8),
          TextButton(
            key: const ValueKey('safety-support-standards'),
            onPressed: _working
                ? null
                : () => _open(
                    SafetySupportSheet.standardsUri,
                    _SupportFeedback.browserUnavailable,
                  ),
            style: TextButton.styleFrom(foregroundColor: colors.textPrimary),
            child: Text(l10n.settings_safety_support_standards),
          ),
          SelectableText(
            SafetySupportSheet.standardsUri.toString(),
            textDirection: TextDirection.ltr,
            style: TextStyle(color: colors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
