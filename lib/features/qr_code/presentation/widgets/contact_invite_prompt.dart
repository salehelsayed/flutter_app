import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/qr_code/application/confirm_contact_invite_use_case.dart';
import 'package:flutter_app/features/qr_code/application/contact_invite_intake.dart';
import 'package:flutter_app/features/qr_code/application/parse_qr_payload_use_case.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

class ContactInvitePrompt extends StatefulWidget {
  const ContactInvitePrompt({
    required this.entry,
    required this.preview,
    required this.confirm,
    required this.isCurrent,
    super.key,
  });

  final ContactInviteEntry entry;
  final Future<(ParseQRResult, ContactModel?)> Function(String link) preview;
  final Future<ContactInviteConfirmation> Function(String link) confirm;
  final bool Function() isCurrent;

  @override
  State<ContactInvitePrompt> createState() => _ContactInvitePromptState();
}

enum _PromptStep { paste, checking, review, sending, invalid, expired, failed }

class _ContactInvitePromptState extends State<ContactInvitePrompt> {
  final _input = TextEditingController();
  var _step = _PromptStep.paste;
  ({String link, String name})? _verifiedInvite;
  ModalRoute<SavedContactInvite>? _route;
  SavedContactInvite? _saved;

  @override
  void initState() {
    super.initState();
    if (widget.entry case OpenContactInvite(:final rawUrl)) {
      _step = _PromptStep.checking;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_preview(rawUrl));
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of<SavedContactInvite>(context);
    _route = route;
    if (_saved != null && route != null && route.isCurrent) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _returnSaved(route));
    }
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  bool _owns(ModalRoute<SavedContactInvite> route) =>
      mounted &&
      identical(_route, route) &&
      route.isActive &&
      widget.isCurrent();

  ModalRoute<SavedContactInvite>? get _currentDialog {
    final route = _route;
    return route != null && route.isCurrent && _owns(route) ? route : null;
  }

  Future<void> _preview(String link) async {
    final route = _route;
    if (route == null || !_owns(route)) return;
    if (_step == _PromptStep.paste) {
      if (!route.isCurrent) return;
      FocusScope.of(context).unfocus();
      setState(() => _step = _PromptStep.checking);
    }

    (ParseQRResult, ContactModel?) preview;
    try {
      preview = await widget.preview(link);
    } catch (_) {
      preview = (ParseQRResult.invalidJson, null);
    }
    if (!_owns(route)) return;

    final (status, contact) = preview;
    setState(() {
      if (status == ParseQRResult.success && contact != null) {
        _verifiedInvite = (link: link, name: contact.username);
        _step = _PromptStep.review;
      } else {
        _step = status == ParseQRResult.expired
            ? _PromptStep.expired
            : _PromptStep.invalid;
      }
    });
  }

  Future<void> _confirm() async {
    if (_step != _PromptStep.review) return;
    final route = _currentDialog;
    if (route == null) return;
    final link = _verifiedInvite!.link;
    setState(() => _step = _PromptStep.sending);

    ContactInviteConfirmation result;
    try {
      result = await widget.confirm(link);
    } catch (_) {
      result = const RejectedContactInvite(ContactInviteRejection.saveFailed);
    }
    if (!_owns(route)) return;

    switch (result) {
      case final SavedContactInvite saved:
        _saved = saved;
        _returnSaved(route);
      case RejectedContactInvite(:final reason):
        setState(() {
          _verifiedInvite = null;
          _step = switch (reason) {
            ContactInviteRejection.expired => _PromptStep.expired,
            ContactInviteRejection.invalid ||
            ContactInviteRejection.self => _PromptStep.invalid,
            _ => _PromptStep.failed,
          };
        });
    }
  }

  void _returnSaved(ModalRoute<SavedContactInvite> route) {
    final saved = _saved;
    if (saved == null || !route.isCurrent || !_owns(route)) return;
    _saved = null;
    route.navigator?.pop<SavedContactInvite>(saved);
  }

  void _cancel() {
    final route = _route;
    if (route != null && route.isCurrent) {
      route.navigator?.pop<SavedContactInvite>();
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = AppLocalizations.of(context)!;
    final title = switch (_step) {
      _PromptStep.paste => copy.contact_invite_paste,
      _PromptStep.review ||
      _PromptStep.sending => copy.contact_invite_connect(_verifiedInvite!.name),
      _ => copy.contact_invite_title,
    };
    final content = switch (_step) {
      _PromptStep.paste => TextField(
        controller: _input,
        decoration: InputDecoration(labelText: copy.contact_invite_title),
        keyboardType: TextInputType.url,
        textDirection: TextDirection.ltr,
        autocorrect: false,
        enableSuggestions: false,
      ),
      _PromptStep.checking || _PromptStep.sending => const Align(
        alignment: AlignmentDirectional.centerStart,
        child: SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      _PromptStep.invalid => Text(copy.contact_invite_invalid),
      _PromptStep.expired => Text(copy.contact_invite_expired),
      _PromptStep.failed => Text(copy.contact_invite_send_failed),
      _PromptStep.review => null,
    };
    return AlertDialog(
      title: Text(title),
      content: content,
      scrollable: true,
      actions: [
        TextButton(onPressed: _cancel, child: Text(copy.btn_cancel)),
        if (_step == _PromptStep.paste)
          FilledButton(
            onPressed: () {
              if (_step == _PromptStep.paste) {
                unawaited(_preview(_input.text));
              }
            },
            child: Text(copy.contact_invite_continue),
          ),
        if (_step == _PromptStep.review)
          FilledButton(
            onPressed: _confirm,
            child: Text(copy.contact_invite_send),
          ),
      ],
    );
  }
}
