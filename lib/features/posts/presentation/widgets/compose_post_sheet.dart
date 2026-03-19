import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/core/media/amplitude_buffer.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/core/media/downsample_waveform.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/application/attach_post_media_use_case.dart';
import 'package:flutter_app/features/posts/application/nearby_location_service.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/shared/widgets/media/recording_overlay.dart';

class ComposePostResult {
  final String text;
  final PostAudience audience;
  final List<PostMediaDraft> mediaDrafts;

  const ComposePostResult({
    required this.text,
    required this.audience,
    this.mediaDrafts = const <PostMediaDraft>[],
  });
}

enum ComposePostSubmitOutcome { closeSheet, keepSheetOpen }

class ComposePostSheet extends StatefulWidget {
  final List<ContactModel> eligibleContacts;
  final Future<void> Function(ComposePostResult result)? onSubmit;
  final Future<ComposePostSubmitOutcome> Function(ComposePostResult result)?
  onSubmitWithOutcome;
  final Future<List<PostMediaDraft>> Function()? onAttachMedia;
  final Future<PostMediaDraft?> Function()? onAttachVoice;
  final AudioRecorderService? audioRecorderService;
  final NearbyComposeAvailability? nearbyAvailability;
  final Future<NearbyComposeAvailability> Function()? onRefreshNearby;
  final Future<NearbyComposeAvailability> Function()? onOpenNearbySettings;
  final int activePinCount;
  final VoidCallback? onManagePins;

  const ComposePostSheet({
    super.key,
    required this.eligibleContacts,
    this.onSubmit,
    this.onSubmitWithOutcome,
    this.onAttachMedia,
    this.onAttachVoice,
    this.audioRecorderService,
    this.nearbyAvailability,
    this.onRefreshNearby,
    this.onOpenNearbySettings,
    this.activePinCount = 0,
    this.onManagePins,
  }) : assert(
         onSubmit != null || onSubmitWithOutcome != null,
         'Either onSubmit or onSubmitWithOutcome must be provided.',
       ),
       assert(
         onSubmit == null || onSubmitWithOutcome == null,
         'Only one submit callback may be provided.',
       );

  @override
  State<ComposePostSheet> createState() => _ComposePostSheetState();
}

class _ComposePostSheetState extends State<ComposePostSheet> {
  final TextEditingController _textController = TextEditingController();
  PostAudienceKind _audienceKind = PostAudienceKind.allFriends;
  int _nearbyRadiusM = 1000;
  final Set<String> _selectedPeerIds = <String>{};
  bool _isSubmitting = false;
  bool _isAttaching = false;
  bool _isRecording = false;
  Duration _recordingDuration = Duration.zero;
  List<double> _recordingAmplitudes = const <double>[];
  List<PostMediaDraft> _mediaDrafts = const <PostMediaDraft>[];
  final AmplitudeBuffer _amplitudeBuffer = AmplitudeBuffer(size: 24);
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<double>? _amplitudeSubscription;
  List<double> _waveformSamples = <double>[];
  NearbyComposeAvailability? _nearbyAvailability;
  bool _isRefreshingNearby = false;

  @override
  void initState() {
    super.initState();
    _nearbyAvailability = widget.nearbyAvailability;
  }

  @override
  void didUpdateWidget(covariant ComposePostSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nearbyAvailability != widget.nearbyAvailability) {
      _nearbyAvailability = widget.nearbyAvailability;
    }
  }

  bool get _canSubmit {
    if ((_textController.text.trim().isEmpty && _mediaDrafts.isEmpty) ||
        _isSubmitting ||
        _isAttaching ||
        _isRecording) {
      return false;
    }
    if (_audienceKind == PostAudienceKind.pickPeople &&
        _selectedPeerIds.isEmpty) {
      return false;
    }
    if (_audienceKind == PostAudienceKind.peopleNearby &&
        _nearbyAvailability?.state != NearbyComposeAvailabilityState.ready) {
      return false;
    }
    return true;
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _isSubmitting = true);
    try {
      final audience = switch (_audienceKind) {
        PostAudienceKind.peopleNearby => PostAudience.peopleNearby(
          radiusM: _nearbyRadiusM,
        ),
        PostAudienceKind.pickPeople => PostAudience.pickPeople(
          _selectedPeerIds.toList(),
        ),
        _ => PostAudience.allFriends(),
      };
      final outcome = await _submitPost(
        ComposePostResult(
          text: _textController.text.trim(),
          audience: audience,
          mediaDrafts: _mediaDrafts,
        ),
      );
      if (outcome == ComposePostSubmitOutcome.closeSheet && mounted) {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<ComposePostSubmitOutcome> _submitPost(ComposePostResult result) async {
    final onSubmitWithOutcome = widget.onSubmitWithOutcome;
    if (onSubmitWithOutcome != null) {
      return onSubmitWithOutcome(result);
    }

    await widget.onSubmit!(result);
    return ComposePostSubmitOutcome.closeSheet;
  }

  @override
  void dispose() {
    _cancelRecorderSubscriptions();
    if (_isRecording) {
      unawaited(widget.audioRecorderService?.cancel());
    }
    _textController.dispose();
    super.dispose();
  }

  Future<void> _attachMedia() async {
    if (widget.onAttachMedia == null || _isAttaching) {
      return;
    }
    setState(() => _isAttaching = true);
    try {
      final drafts = await widget.onAttachMedia!();
      if (!mounted || drafts.isEmpty) {
        return;
      }
      setState(() => _mediaDrafts = drafts);
    } finally {
      if (mounted) {
        setState(() => _isAttaching = false);
      }
    }
  }

  Future<void> _attachVoice() async {
    if (_isAttaching || _isRecording) {
      return;
    }
    if (widget.audioRecorderService != null) {
      await _startVoiceRecording();
      return;
    }
    if (widget.onAttachVoice == null) {
      return;
    }
    setState(() => _isAttaching = true);
    try {
      final draft = await widget.onAttachVoice!();
      if (!mounted || draft == null) {
        return;
      }
      setState(() => _mediaDrafts = <PostMediaDraft>[draft]);
    } finally {
      if (mounted) {
        setState(() => _isAttaching = false);
      }
    }
  }

  Future<void> _startVoiceRecording() async {
    final recorder = widget.audioRecorderService;
    if (recorder == null) {
      return;
    }

    final hasPermission = await recorder.requestPermission();
    if (!hasPermission || !mounted) {
      return;
    }

    await recorder.start(outputPath: '');
    if (!mounted) {
      await recorder.cancel();
      return;
    }

    _cancelRecorderSubscriptions();
    _amplitudeBuffer.reset();
    _waveformSamples = <double>[];
    _durationSubscription = recorder.durationStream.listen((duration) {
      if (!mounted) {
        return;
      }
      setState(() => _recordingDuration = duration);
    });
    _amplitudeSubscription = recorder.amplitudeStream.listen((value) {
      if (!mounted) {
        return;
      }
      _amplitudeBuffer.push(value);
      _waveformSamples.add(value);
      setState(() => _recordingAmplitudes = _amplitudeBuffer.values);
    });

    setState(() {
      _isRecording = true;
      _recordingDuration = Duration.zero;
      _recordingAmplitudes = _amplitudeBuffer.values;
      _mediaDrafts = const <PostMediaDraft>[];
    });
  }

  Future<void> _stopVoiceRecording() async {
    final recorder = widget.audioRecorderService;
    if (recorder == null || !_isRecording) {
      return;
    }

    final waveform = downsampleWaveform(_waveformSamples, 50);
    final recording = await recorder.stop();
    _cancelRecorderSubscriptions();
    if (!mounted) {
      return;
    }

    if (recording == null) {
      setState(_resetRecordingState);
      return;
    }

    setState(() {
      _resetRecordingState();
      _mediaDrafts = <PostMediaDraft>[
        PostMediaDraft(
          localFilePath: recording.filePath,
          mime: recording.mime,
          durationMs: recording.durationMs,
          waveform: waveform,
        ),
      ];
    });
  }

  Future<void> _cancelVoiceRecording() async {
    final recorder = widget.audioRecorderService;
    if (recorder == null || !_isRecording) {
      return;
    }
    _cancelRecorderSubscriptions();
    await recorder.cancel();
    if (!mounted) {
      return;
    }
    setState(_resetRecordingState);
  }

  void _cancelRecorderSubscriptions() {
    final durationSubscription = _durationSubscription;
    final amplitudeSubscription = _amplitudeSubscription;
    _durationSubscription = null;
    _amplitudeSubscription = null;
    if (durationSubscription != null) {
      unawaited(durationSubscription.cancel());
    }
    if (amplitudeSubscription != null) {
      unawaited(amplitudeSubscription.cancel());
    }
  }

  void _resetRecordingState() {
    _isRecording = false;
    _recordingDuration = Duration.zero;
    _recordingAmplitudes = const <double>[];
    _waveformSamples = <double>[];
    _amplitudeBuffer.reset();
  }

  void _clearDrafts() {
    setState(() => _mediaDrafts = const <PostMediaDraft>[]);
  }

  Future<void> _refreshNearby() async {
    if (widget.onRefreshNearby == null || _isRefreshingNearby) {
      return;
    }
    setState(() => _isRefreshingNearby = true);
    try {
      final availability = await widget.onRefreshNearby!();
      if (!mounted) {
        return;
      }
      setState(() => _nearbyAvailability = availability);
    } finally {
      if (mounted) {
        setState(() => _isRefreshingNearby = false);
      }
    }
  }

  Future<void> _openNearbySettings() async {
    if (widget.onOpenNearbySettings == null) {
      return;
    }
    final availability = await widget.onOpenNearbySettings!();
    if (!mounted) {
      return;
    }
    setState(() => _nearbyAvailability = availability);
  }

  @override
  Widget build(BuildContext context) {
    final contacts = widget.eligibleContacts
        .where((contact) => !contact.isArchived && !contact.isBlocked)
        .toList(growable: false);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: 20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Material(
          color: const Color(0xFF111318),
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context)!.compose_title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (widget.activePinCount > 0) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1E26),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: const Color.fromRGBO(143, 214, 181, 0.25),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.bookmark_border,
                            color: Color(0xFF8FD6B5),
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              widget.activePinCount == 1
                                  ? AppLocalizations.of(context)!.compose_pinned_1
                                  : AppLocalizations.of(context)!.compose_pinned_n(widget.activePinCount),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (widget.onManagePins != null)
                            TextButton(
                              onPressed: widget.onManagePins,
                              child: Text(AppLocalizations.of(context)!.compose_manage),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextField(
                    controller: _textController,
                    maxLines: 5,
                    minLines: 4,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: AppLocalizations.of(context)!.compose_hint,
                      hintStyle: const TextStyle(
                        color: Color.fromRGBO(255, 255, 255, 0.35),
                      ),
                      filled: true,
                      fillColor: const Color(0xFF1A1E26),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    children: [
                      ChoiceChip(
                        label: Text(AppLocalizations.of(context)!.compose_audience_all),
                        selected: _audienceKind == PostAudienceKind.allFriends,
                        onSelected: (_) {
                          setState(() {
                            _audienceKind = PostAudienceKind.allFriends;
                            _selectedPeerIds.clear();
                          });
                        },
                      ),
                      ChoiceChip(
                        label: Text(AppLocalizations.of(context)!.compose_audience_nearby),
                        selected:
                            _audienceKind == PostAudienceKind.peopleNearby,
                        onSelected: (_) {
                          setState(() {
                            _audienceKind = PostAudienceKind.peopleNearby;
                            _selectedPeerIds.clear();
                          });
                        },
                      ),
                      ChoiceChip(
                        label: Text(AppLocalizations.of(context)!.compose_audience_pick),
                        selected: _audienceKind == PostAudienceKind.pickPeople,
                        onSelected: (_) {
                          setState(() {
                            _audienceKind = PostAudienceKind.pickPeople;
                          });
                        },
                      ),
                    ],
                  ),
                  if (_audienceKind == PostAudienceKind.peopleNearby) ...[
                    const SizedBox(height: 16),
                    Text(
                      AppLocalizations.of(context)!.compose_radius,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      children: <int>[500, 1000, 2000]
                          .map((radiusM) {
                            final l10n = AppLocalizations.of(context)!;
                            final label = switch (radiusM) {
                              500 => l10n.compose_radius_500,
                              1000 => l10n.compose_radius_1k,
                              _ => l10n.compose_radius_2k,
                            };
                            return ChoiceChip(
                              label: Text(label),
                              selected: _nearbyRadiusM == radiusM,
                              onSelected: (_) {
                                setState(() => _nearbyRadiusM = radiusM);
                              },
                            );
                          })
                          .toList(growable: false),
                    ),
                  ],
                  if (_nearbyAvailability != null) ...[
                    const SizedBox(height: 16),
                    _NearbyComposeAvailabilityCard(
                      availability: _nearbyAvailability!,
                      isRefreshing: _isRefreshingNearby,
                      onRefresh: widget.onRefreshNearby == null
                          ? null
                          : _refreshNearby,
                      onOpenSettings: widget.onOpenNearbySettings == null
                          ? null
                          : _openNearbySettings,
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: widget.onAttachMedia == null || _isRecording
                            ? null
                            : _attachMedia,
                        icon: const Icon(
                          Icons.photo_library_outlined,
                          size: 18,
                        ),
                        label: Text(_isAttaching ? AppLocalizations.of(context)!.compose_media_adding : AppLocalizations.of(context)!.compose_media),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed:
                            (widget.onAttachVoice == null &&
                                widget.audioRecorderService == null)
                            ? null
                            : _attachVoice,
                        icon: const Icon(Icons.mic_none_rounded, size: 18),
                        label: Text(AppLocalizations.of(context)!.compose_voice),
                      ),
                    ],
                  ),
                  if (_isRecording) ...[
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: RecordingOverlay(
                            elapsed: _recordingDuration,
                            amplitudeValues: _recordingAmplitudes,
                            onCancel: () {
                              unawaited(_cancelVoiceRecording());
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton.icon(
                          onPressed: _stopVoiceRecording,
                          icon: const Icon(
                            Icons.stop_circle_outlined,
                            size: 18,
                          ),
                          label: Text(AppLocalizations.of(context)!.compose_voice_stop),
                        ),
                      ],
                    ),
                  ],
                  if (_mediaDrafts.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1E26),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _mediaDrafts.first.kind == 'voice'
                                  ? AppLocalizations.of(context)!.compose_voice_attached
                                  : AppLocalizations.of(context)!.compose_attachments(_mediaDrafts.length),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: _clearDrafts,
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_audienceKind == PostAudienceKind.pickPeople) ...[
                    const SizedBox(height: 16),
                    Text(
                      AppLocalizations.of(context)!.compose_pick_people,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: contacts.length,
                        separatorBuilder: (_, _) => const Divider(
                          color: Color.fromRGBO(255, 255, 255, 0.06),
                          height: 1,
                        ),
                        itemBuilder: (context, index) {
                          final contact = contacts[index];
                          final isSelected = _selectedPeerIds.contains(
                            contact.peerId,
                          );
                          return CheckboxListTile(
                            value: isSelected,
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.trailing,
                            title: Text(
                              contact.username,
                              style: const TextStyle(color: Colors.white),
                            ),
                            subtitle: Text(
                              contact.peerId,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color.fromRGBO(255, 255, 255, 0.45),
                                fontSize: 12,
                              ),
                            ),
                            onChanged: (_) {
                              setState(() {
                                if (isSelected) {
                                  _selectedPeerIds.remove(contact.peerId);
                                } else {
                                  _selectedPeerIds.add(contact.peerId);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _canSubmit ? _submit : null,
                      child: Text(_isSubmitting ? AppLocalizations.of(context)!.compose_posting : AppLocalizations.of(context)!.compose_post),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NearbyComposeAvailabilityCard extends StatelessWidget {
  final NearbyComposeAvailability availability;
  final bool isRefreshing;
  final VoidCallback? onRefresh;
  final VoidCallback? onOpenSettings;

  const _NearbyComposeAvailabilityCard({
    required this.availability,
    required this.isRefreshing,
    this.onRefresh,
    this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final title = switch (availability.state) {
      NearbyComposeAvailabilityState.sharingOff => l10n.compose_nearby_off,
      NearbyComposeAvailabilityState.ready => l10n.compose_nearby_ready,
      NearbyComposeAvailabilityState.stale => l10n.compose_nearby_refresh,
      NearbyComposeAvailabilityState.permissionRequired =>
        l10n.compose_nearby_allow,
      NearbyComposeAvailabilityState.permissionDeniedForever =>
        l10n.compose_nearby_perm_off,
      NearbyComposeAvailabilityState.servicesOff =>
        l10n.compose_nearby_services,
    };

    final subtitle = switch (availability.state) {
      NearbyComposeAvailabilityState.sharingOff =>
        l10n.compose_nearby_off_desc,
      NearbyComposeAvailabilityState.ready =>
        l10n.compose_nearby_ready_desc,
      NearbyComposeAvailabilityState.stale =>
        l10n.compose_nearby_refresh_desc,
      NearbyComposeAvailabilityState.permissionRequired =>
        l10n.compose_nearby_allow_desc,
      NearbyComposeAvailabilityState.permissionDeniedForever =>
        l10n.compose_nearby_perm_desc,
      NearbyComposeAvailabilityState.servicesOff =>
        l10n.compose_nearby_services_desc,
    };

    final canOpenSettingsShortcut =
        (availability.state == NearbyComposeAvailabilityState.sharingOff ||
            availability.canOpenSettings) &&
        onOpenSettings != null;

    final action = canOpenSettingsShortcut
        ? TextButton.icon(
            onPressed: onOpenSettings,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: const Color.fromRGBO(255, 255, 255, 0.08),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(
                  color: Color.fromRGBO(255, 255, 255, 0.10),
                ),
              ),
            ),
            icon: const Icon(Icons.settings_outlined, size: 16),
            label: Text(l10n.compose_open_settings),
          )
        : availability.canRefresh && onRefresh != null
        ? TextButton.icon(
            onPressed: isRefreshing ? null : onRefresh,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: const Color.fromRGBO(255, 255, 255, 0.08),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(
                  color: Color.fromRGBO(255, 255, 255, 0.10),
                ),
              ),
            ),
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: Text(isRefreshing ? l10n.compose_refreshing : l10n.compose_refresh_nearby),
          )
        : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1E26),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              color: Color.fromRGBO(255, 255, 255, 0.55),
              fontSize: 12,
              height: 1.35,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 12), action],
        ],
      ),
    );
  }
}
