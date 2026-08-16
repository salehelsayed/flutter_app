import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/bridge/bridge.dart'
    show Bridge, callSignPayload, callVerifyPayload;
import 'package:flutter_app/core/config/direct_linked_devices_flag.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/identity/application/linked_installation_authority.dart';
import 'package:flutter_app/features/identity/application/linked_secondary_setup_use_case.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/groups/application/linked_group_status_refresh.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/qr_code/application/direct_linked_device_qr.dart';
import 'package:flutter_app/features/qr_code/presentation/screens/qr_display_wired.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// The RESTRICTED linked-secondary setup and status route.
///
/// This is the only production surface that creates linked authority, and it is
/// deliberately minimal. It runs exactly the crash-safe setup use case and then
/// shows the dedicated dual-signed QR — it starts no messaging, event, group,
/// push, or retry owner, because a linked secondary must not reach generic
/// runtime startup until Plan 361 makes event fanout device-aware.
///
/// Reachable only when the direct selector is enabled; the composition root
/// omits its builder entirely otherwise, so a stock build has no entry point.
class LinkedDeviceSetupWired extends StatefulWidget {
  const LinkedDeviceSetupWired({
    super.key,
    required this.repository,
    required this.secureKeyStore,
    required this.bridge,
    required this.callIdentityRestore,
    required this.callMlKemKeygen,
    required this.callIdentityGenerateForTransport,
    this.selector = const DirectLinkedDeviceSelector(),
    this.backgroundPreference = BackgroundPreference.defaultBackground,
    this.groupRepository,
    this.linkedGroupConversationBuilder,
    this.isLinkedGroupAuthoritySettled,
    this.retireIosNseInboxTransport,
    this.onSetupSuccess,
  });

  final IdentityRepository repository;
  final SecureKeyStore secureKeyStore;
  final Bridge bridge;
  final Future<Map<String, dynamic>> Function(String mnemonic)
  callIdentityRestore;
  final Future<Map<String, dynamic>> Function() callMlKemKeygen;
  final Future<Map<String, dynamic>> Function()
  callIdentityGenerateForTransport;
  final DirectLinkedDeviceSelector selector;
  final BackgroundPreference backgroundPreference;
  final GroupRepository? groupRepository;
  final Widget Function(BuildContext context, GroupModel group)?
  linkedGroupConversationBuilder;
  final Future<bool> Function(String groupId)? isLinkedGroupAuthoritySettled;
  final Future<void> Function()? retireIosNseInboxTransport;
  final Future<void> Function()? onSetupSuccess;

  @override
  State<LinkedDeviceSetupWired> createState() => _LinkedDeviceSetupWiredState();
}

class _LinkedDeviceSetupWiredState extends State<LinkedDeviceSetupWired> {
  final TextEditingController _mnemonic = TextEditingController();
  bool _busy = false;
  bool _linked = false;
  String? _error;

  late final LinkedInstallationAuthority _authority =
      LinkedInstallationAuthority(
        secureKeyStore: widget.secureKeyStore,
        retireIosNseInboxTransport: widget.retireIosNseInboxTransport,
      );

  @override
  void initState() {
    super.initState();
    unawaitedLoad();
  }

  void unawaitedLoad() {
    _authority.load().then((snapshot) {
      if (!mounted) return;
      setState(() => _linked = snapshot.isActiveLinkedSecondary);
    });
  }

  @override
  void dispose() {
    _mnemonic.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await setUpLinkedSecondaryInstallation(
      mnemonic: _mnemonic.text,
      authority: _authority,
      identityRepo: widget.repository,
      callRestore: widget.callIdentityRestore,
      callMlKemKeygen: widget.callMlKemKeygen,
      callIdentityGenerate: widget.callIdentityGenerateForTransport,
      callSign: (data, privateKey) => callSignPayload(
        bridge: widget.bridge,
        dataToSign: data,
        privateKey: privateKey,
      ),
      callVerify:
          ({
            required String publicKey,
            required String data,
            required String signature,
          }) => callVerifyPayload(
            bridge: widget.bridge,
            publicKey: publicKey,
            data: data,
            signature: signature,
          ),
      selector: widget.selector,
    );
    emitFlowEvent(
      layer: 'FL',
      event: 'LINKED_DEVICE_SETUP_ROUTE_RESULT',
      details: {'result': result.name},
    );
    if (result == LinkedSecondarySetupResult.success) {
      try {
        await widget.onSetupSuccess?.call();
      } catch (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'LINKED_DEVICE_SETUP_RUNTIME_START_ERROR',
          details: {'errorType': error.runtimeType.toString()},
        );
      }
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _linked = result == LinkedSecondarySetupResult.success;
      _error = result == LinkedSecondarySetupResult.success
          ? null
          : 'Could not link this device (${result.name}).';
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (_linked) {
      // Status route: the dedicated dual-signed device QR, nothing else.
      return QRDisplayWired(
        repo: widget.repository,
        bridgeClient: widget.bridge,
        onClose: () => Navigator.of(context).maybePop(),
        backgroundPreference: widget.backgroundPreference,
        linkedDeviceQrSource: DirectLinkedDeviceQrSource(
          selector: widget.selector,
          loadAuthority: _authority.load,
        ),
        footer: LinkedGroupReadOnlyStatus(
          groupRepository: widget.groupRepository,
          linkedGroupConversationBuilder: widget.linkedGroupConversationBuilder,
          isLinkedGroupAuthoritySettled: widget.isLinkedGroupAuthoritySettled,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.linked_device_setup_title)),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.linked_device_setup_recovery_phrase_instruction),
            const SizedBox(height: 16),
            TextField(
              key: const Key('linked-device-setup-mnemonic'),
              controller: _mnemonic,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            if (_error case final error?) ...[
              const SizedBox(height: 12),
              Text(error, key: const Key('linked-device-setup-error')),
            ],
            const SizedBox(height: 20),
            FilledButton(
              key: const Key('linked-device-setup-submit'),
              onPressed: _busy ? null : _submit,
              child: Text(_busy ? 'Linking…' : 'Link this device'),
            ),
          ],
        ),
      ),
    );
  }
}

class LinkedGroupReadOnlyStatus extends StatefulWidget {
  const LinkedGroupReadOnlyStatus({
    super.key,
    required this.groupRepository,
    this.linkedGroupConversationBuilder,
    this.isLinkedGroupAuthoritySettled,
  });

  final GroupRepository? groupRepository;
  final Widget Function(BuildContext context, GroupModel group)?
  linkedGroupConversationBuilder;
  final Future<bool> Function(String groupId)? isLinkedGroupAuthoritySettled;

  @override
  State<LinkedGroupReadOnlyStatus> createState() =>
      _LinkedGroupReadOnlyStatusState();
}

class _LinkedGroupReadOnlyStatusState extends State<LinkedGroupReadOnlyStatus> {
  StreamSubscription<void>? _refreshSubscription;
  List<GroupModel> _groups = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refreshSubscription = linkedGroupStatusRefreshes.listen((_) => _load());
    unawaited(_load());
  }

  @override
  void dispose() {
    _refreshSubscription?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final repository = widget.groupRepository;
    final groups = repository == null
        ? const <GroupModel>[]
        : await repository.getAllGroups();
    if (!mounted) return;
    setState(() {
      _groups = groups;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Card(
      key: const Key('linked-group-status-list'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.linked_group_status_title,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  key: const Key('linked-group-status-refresh'),
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  tooltip: l10n.linked_group_status_refresh,
                ),
              ],
            ),
            if (_loading)
              const LinearProgressIndicator()
            else if (_groups.isEmpty)
              Text(
                l10n.linked_group_status_waiting,
                key: const Key('linked-group-status-waiting'),
              )
            else
              for (final group in _groups)
                ListTile(
                  key: Key('linked-group-open-${group.id}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    group.isDissolved ? Icons.lock_outline : Icons.group,
                  ),
                  title: Text(group.name),
                  subtitle: Text(
                    group.isDissolved
                        ? 'Dissolved · read only'
                        : '${group.myRole.name} · read only',
                  ),
                  onTap:
                      widget.linkedGroupConversationBuilder == null ||
                          widget.isLinkedGroupAuthoritySettled == null ||
                          group.isDissolved ||
                          group.selfRemovedAt != null ||
                          group.type == GroupType.qa
                      ? null
                      : () async {
                          final settled = await widget
                              .isLinkedGroupAuthoritySettled!(group.id);
                          if (!settled || !context.mounted) return;
                          await Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (context) =>
                                  widget.linkedGroupConversationBuilder!(
                                    context,
                                    group,
                                  ),
                            ),
                          );
                          await _load();
                        },
                ),
          ],
        ),
      ),
    );
  }
}
