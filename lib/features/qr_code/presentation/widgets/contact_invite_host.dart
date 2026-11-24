import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/features/contact_request/application/send_contact_request_use_case.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/qr_code/application/confirm_contact_invite_use_case.dart';
import 'package:flutter_app/features/qr_code/application/contact_invite_intake.dart';
import 'package:flutter_app/features/qr_code/application/parse_qr_payload_use_case.dart';
import 'package:flutter_app/features/qr_code/application/share_contact_invite.dart';
import 'package:flutter_app/features/qr_code/presentation/widgets/contact_invite_prompt.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

typedef PreviewContactInviteForAccount =
    Future<(ParseQRResult, ContactModel?)> Function(
      String link,
      String ownPeerId,
    );
typedef ConfirmContactInviteForAccount =
    Future<ContactInviteConfirmation> Function(
      String link,
      String ownPeerId,
      bool Function() isCurrent,
    );
typedef ShareContactInviteForAccount =
    Future<ContactInviteShareResult> Function(
      String ownPeerId,
      bool Function() isCurrent,
    );

class ContactInviteHost extends StatefulWidget {
  const ContactInviteHost({
    required this.intake,
    required this.accountPeerId,
    required this.navigatorKey,
    required this.preview,
    required this.confirm,
    required this.child,
    this.share,
    super.key,
  });

  final ContactInviteIntake intake;
  final ValueListenable<String?> accountPeerId;
  final GlobalKey<NavigatorState> navigatorKey;
  final PreviewContactInviteForAccount preview;
  final ConfirmContactInviteForAccount confirm;
  final ShareContactInviteForAccount? share;
  final Widget child;

  @override
  State<ContactInviteHost> createState() => _ContactInviteHostState();

  static VoidCallback? pasteActionOf(BuildContext context) =>
      _ContactInviteScope.maybeOf(context)?.host.widget.intake.requestPaste;

  static VoidCallback? shareActionOf(BuildContext context) {
    if (!contactInviteSharingEnabled) return null;
    final host = _ContactInviteScope.maybeOf(context)?.host;
    if (host?.widget.share == null) return null;
    return () => unawaited(host!._share(context));
  }
}

typedef _PresentedInvite = ({
  ContactInviteEntry entry,
  _ContactInviteHomeState home,
  String peerId,
  int generation,
  DialogRoute<SavedContactInvite> route,
});

class _ContactInviteHostState extends State<ContactInviteHost>
    with WidgetsBindingObserver {
  final _homes = <_ContactInviteHomeState>{};
  String? _peerId;
  var _generation = 0;
  var _scheduled = false;
  var _foreground = false;
  var _sharing = false;
  _PresentedInvite? _presented;

  @override
  void initState() {
    super.initState();
    final binding = WidgetsBinding.instance;
    binding.addObserver(this);
    final lifecycle = binding.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _peerId = widget.accountPeerId.value;
    widget.accountPeerId.addListener(_accountChanged);
    widget.intake.addListener(_intakeChanged);
    _schedule();
  }

  @override
  void didUpdateWidget(ContactInviteHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accountPeerId != widget.accountPeerId) {
      oldWidget.accountPeerId.removeListener(_accountChanged);
      widget.accountPeerId.addListener(_accountChanged);
      _accountChanged();
    }
    if (oldWidget.intake != widget.intake) {
      oldWidget.intake.removeListener(_intakeChanged);
      widget.intake.addListener(_intakeChanged);
      _intakeChanged();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _schedule();
  }

  void _accountChanged() {
    final next = widget.accountPeerId.value;
    if (_peerId == next) return;
    if (_peerId != null) {
      _generation++;
      widget.intake.discardPending();
    }
    _peerId = next;
    _schedule();
  }

  void _intakeChanged() {
    final presented = _presented?.entry;
    final pending = widget.intake.pending;
    final duplicate = switch ((presented, pending)) {
      (
        OpenContactInvite(rawUrl: final active),
        OpenContactInvite(:final rawUrl),
      )
          when active == rawUrl =>
        true,
      (PasteContactInvite(), PasteContactInvite()) => true,
      _ => false,
    };
    if (duplicate) widget.intake.takePending();
    _schedule();
  }

  void _schedule() {
    if (_scheduled || !mounted) return;
    _scheduled = true;
    final binding = WidgetsBinding.instance;
    binding.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) _flush();
    });
    binding.ensureVisualUpdate();
  }

  bool _ownsHome(_ContactInviteHomeState home, String peerId, int generation) =>
      _generation == generation &&
      _peerId == peerId &&
      _homes.contains(home) &&
      home.widget.ownPeerId == peerId &&
      home.route?.isActive == true;

  void _flush() {
    final presented = _presented;
    if (presented != null) {
      if (_ownsHome(presented.home, presented.peerId, presented.generation)) {
        return;
      }
      _presented = null;
      final route = presented.route;
      if (route.isActive) route.navigator?.removeRoute(route);
    }

    final peerId = _peerId;
    final navigator = widget.navigatorKey.currentState;
    if (!_foreground || peerId == null || navigator == null) return;
    final home = _homes.where((home) {
      return home.route?.navigator == navigator &&
          _ownsHome(home, peerId, _generation);
    }).lastOrNull;
    if (home == null) return;
    final entry = widget.intake.takePending();
    if (entry == null) return;

    final generation = _generation;
    late final DialogRoute<SavedContactInvite> route;
    bool isCurrent() =>
        mounted &&
        identical(_presented?.route, route) &&
        route.isActive &&
        _ownsHome(home, peerId, generation);

    route = DialogRoute<SavedContactInvite>(
      context: home.context,
      barrierDismissible: false,
      builder: (_) => ContactInvitePrompt(
        entry: entry,
        preview: (link) => widget.preview(link, peerId),
        confirm: (link) => widget.confirm(link, peerId, isCurrent),
        isCurrent: isCurrent,
      ),
    );
    final invite = (
      entry: entry,
      home: home,
      peerId: peerId,
      generation: generation,
      route: route,
    );
    _presented = invite;
    unawaited(navigator.push(route).then((saved) => _finish(invite, saved)));
  }

  void _finish(_PresentedInvite invite, SavedContactInvite? saved) {
    if (!mounted || !identical(_presented?.route, invite.route)) return;
    _presented = null;
    final home = invite.home;
    if (saved != null && _ownsHome(home, invite.peerId, invite.generation)) {
      final localizations = AppLocalizations.of(home.context)!;
      final delivery = saved.delivery;
      final notice = delivery.sendResult == SendContactRequestResult.success
          ? localizations.contact_invite_sent
          : delivery.retryRetained
          ? null
          : localizations.contact_invite_send_failed;
      if (notice != null) {
        ScaffoldMessenger.maybeOf(home.context)?.showSnackBar(
          SnackBar(content: Text(notice), behavior: SnackBarBehavior.floating),
        );
      }
      home.widget.onSaved?.call(saved);
    }
    _schedule();
  }

  Future<void> _share(BuildContext context) async {
    final share = widget.share;
    final peerId = _peerId;
    final generation = _generation;
    final route = ModalRoute.of(context);
    if (_sharing || share == null || peerId == null || route == null) return;
    bool isCurrent() =>
        mounted &&
        context.mounted &&
        _foreground &&
        _peerId == peerId &&
        _generation == generation &&
        route.isCurrent;
    _sharing = true;
    try {
      final result = await share(peerId, isCurrent);
      if (!context.mounted ||
          !isCurrent() ||
          result != ContactInviteShareResult.failed) {
        return;
      }
      final copy = AppLocalizations.of(context)!;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(copy.contact_invite_create_failed),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      _sharing = false;
    }
  }

  @override
  Widget build(BuildContext context) =>
      _ContactInviteScope(host: this, child: widget.child);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.accountPeerId.removeListener(_accountChanged);
    widget.intake.removeListener(_intakeChanged);
    super.dispose();
  }
}

class _ContactInviteScope extends InheritedWidget {
  const _ContactInviteScope({required this.host, required super.child});

  final _ContactInviteHostState host;

  static _ContactInviteScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ContactInviteScope>();

  @override
  bool updateShouldNotify(_ContactInviteScope oldWidget) =>
      oldWidget.host != host;
}

class ContactInviteHome extends StatefulWidget {
  const ContactInviteHome({
    required this.ownPeerId,
    required this.child,
    this.onSaved,
    super.key,
  });

  final String? ownPeerId;
  final Widget child;
  final void Function(SavedContactInvite result)? onSaved;

  @override
  State<ContactInviteHome> createState() => _ContactInviteHomeState();
}

class _ContactInviteHomeState extends State<ContactInviteHome> {
  _ContactInviteHostState? _host;
  ModalRoute<dynamic>? route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    route = ModalRoute.of(context);
    final host = _ContactInviteScope.maybeOf(context)?.host;
    if (_host != host) {
      _detach();
      _host = host;
      host?._homes.add(this);
    }
    host?._schedule();
  }

  @override
  void didUpdateWidget(ContactInviteHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ownPeerId != widget.ownPeerId) _host?._schedule();
  }

  void _detach() {
    _host?._homes.remove(this);
    _host?._schedule();
  }

  @override
  Widget build(BuildContext context) => widget.child;

  @override
  void dispose() {
    _detach();
    super.dispose();
  }
}
