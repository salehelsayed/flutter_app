import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/utils/text_direction_utils.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/core/media/amplitude_buffer.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/core/media/downsample_waveform.dart';
import 'package:flutter_app/features/conversation/domain/models/audio_recording.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/application/attach_post_media_use_case.dart';
import 'package:flutter_app/features/posts/application/nearby_location_service.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/presentation/pick_post_media_drafts.dart';
import 'package:flutter_app/features/posts/presentation/thought_photo_framing.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/attachment_preview_strip.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/compose_area.dart';
import 'package:flutter_app/shared/widgets/media/recording_overlay.dart';

import 'thought_audience.dart';
import 'thought_voice.dart';
import 'thought_photo_draft_preview.dart';

class ComposePostResult {
  final String text;
  final PostAudience audience;
  final List<PostMediaDraft> mediaDrafts;

  /// An unsent Thought's photo framings by path, so a reopened draft shows
  /// each photo as it was framed.
  final Map<String, PhotoFraming> photoFramings;

  const ComposePostResult({
    required this.text,
    required this.audience,
    this.mediaDrafts = const <PostMediaDraft>[],
    this.photoFramings = const {},
  });
}

enum ComposePostSubmitOutcome {
  closeSheet,
  keepSheetOpen,
  nobodyToShareWith,
  shareFailed,
}

/// Thoughts are short by design; chat allows 10,000.
const int _thoughtMaxLength = 500;
const int _thoughtCounterFrom = 450;

/// A Thought's voice note stops itself here; chat keeps the recorder's 5 min.
const Duration _thoughtVoiceLimit = Duration(minutes: 3);

enum _ComposeNotice {
  nobodyToShareWith,
  shareFailed,
  mediaLeftOut,
  mediaFailed,
  micOff,
  micBusy,
}

class ComposePostSheet extends StatefulWidget {
  /// The live Orbit composer shares only with friends. Dormant Posts callers
  /// retain their existing controls until that UI is retired.
  final bool thoughtsOnly;
  final List<ContactModel> eligibleContacts;
  final Future<void> Function(ComposePostResult result)? onSubmit;
  final Future<ComposePostSubmitOutcome> Function(ComposePostResult result)?
  onSubmitWithOutcome;
  final Future<List<PostMediaDraft>> Function()? onAttachMedia;
  final Future<PostMediaPick> Function()? onPickMedia;
  final Future<PostMediaDraft?> Function()? onAttachVoice;
  final AudioRecorderService? audioRecorderService;
  final NearbyComposeAvailability? nearbyAvailability;
  final Future<NearbyComposeAvailability> Function()? onRefreshNearby;
  final Future<NearbyComposeAvailability> Function()? onOpenNearbySettings;
  final int activePinCount;
  final VoidCallback? onManagePins;

  /// What a previous visit left unshared; the sheet starts from it.
  final ComposePostResult? initialDraft;

  /// The user has a thought up now, which sharing this one replaces.
  final bool replacesCurrentThought;

  /// Where a Thought's "select people…" remembers its last picks.
  final ThoughtRecentPicks? recentPicks;

  /// Runs once as the sheet goes away: the unshared draft, or null after a
  /// share or when nothing was left to keep.
  final ValueChanged<ComposePostResult?>? onClosed;

  const ComposePostSheet({
    super.key,
    this.thoughtsOnly = false,
    this.replacesCurrentThought = false,
    this.recentPicks,
    required this.eligibleContacts,
    this.onSubmit,
    this.onSubmitWithOutcome,
    this.onAttachMedia,
    this.onPickMedia,
    this.onAttachVoice,
    this.audioRecorderService,
    this.nearbyAvailability,
    this.onRefreshNearby,
    this.onOpenNearbySettings,
    this.activePinCount = 0,
    this.onManagePins,
    this.initialDraft,
    this.onClosed,
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

  /// The grey line above a Thought's voice card.
  final TextEditingController _voiceCaption = TextEditingController();
  TextDirection _inputDirection = TextDirection.ltr;
  PostAudienceKind _audienceKind = PostAudienceKind.allFriends;
  int _nearbyRadiusM = 1000;
  final Set<String> _selectedPeerIds = <String>{};
  bool _isSubmitting = false;
  bool _shared = false;
  bool _isAttaching = false;
  VoiceRecordingState _recordingState = VoiceRecordingState.idle;
  bool _pendingRecordingAbort = false;
  bool _recorderStartInFlight = false;
  bool _recordingPaused = false;
  MicrophoneCaptureLease? _microphoneCaptureLease;
  Duration _recordingDuration = Duration.zero;
  List<double> _recordingAmplitudes = const <double>[];
  List<PostMediaDraft> _mediaDrafts = const <PostMediaDraft>[];

  /// A Thought photo's framing by path, once the user has framed it.
  Map<String, PhotoFraming> _framings = const {};

  /// Every Thought photo's framing by path, centred cover until framed.
  Map<String, PhotoFraming> get _photoFramings => {
    if (widget.thoughtsOnly)
      for (final draft in _mediaDrafts)
        if (draft.kind == 'image')
          draft.localFilePath:
              _framings[draft.localFilePath] ?? PhotoFraming.cover,
  };
  _ComposeNotice? _notice;
  final AmplitudeBuffer _amplitudeBuffer = AmplitudeBuffer(size: 24);
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<double>? _amplitudeSubscription;
  List<double> _waveformSamples = <double>[];
  NearbyComposeAvailability? _nearbyAvailability;
  bool _isRefreshingNearby = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialDraft case final draft?) {
      _textController.text = draft.text;
      _inputDirection = detectTextDirection(draft.text);
      _mediaDrafts = draft.mediaDrafts;
      _voiceCaption.text =
          [
            for (final media in draft.mediaDrafts)
              if (media.kind == 'voice') ?media.caption,
          ].firstOrNull ??
          '';
      _framings = draft.photoFramings;
      if (draft.audience.kind == PostAudienceKind.pickPeople) {
        _audienceKind = PostAudienceKind.pickPeople;
        _selectedPeerIds.addAll(draft.audience.selectedPeerIds);
      }
    }
    _textController.addListener(_updateInputDirection);
    _nearbyAvailability = widget.nearbyAvailability;
  }

  @override
  void didUpdateWidget(covariant ComposePostSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nearbyAvailability != widget.nearbyAvailability) {
      _nearbyAvailability = widget.nearbyAvailability;
    }
  }

  /// The drafts as shared: a Thought's voice note carries its caption line.
  List<PostMediaDraft> get _captionedDrafts {
    final typed = _voiceCaption.text.trim();
    final caption = typed.isEmpty ? null : typed;
    return [
      for (final draft in _mediaDrafts)
        if (!widget.thoughtsOnly ||
            draft.kind != 'voice' ||
            draft.caption == caption)
          draft
        else
          PostMediaDraft(
            localFilePath: draft.localFilePath,
            mime: draft.mime,
            width: draft.width,
            height: draft.height,
            durationMs: draft.durationMs,
            waveform: draft.waveform,
            caption: caption,
          ),
    ];
  }

  List<ContactModel> get _eligible => widget.eligibleContacts
      .where((contact) => !contact.isArchived && !contact.isBlocked)
      .toList(growable: false);

  /// A Thought's picked people still in the user's orbit; empty means
  /// friends.
  List<ContactModel> get _picked => [
    if (_audienceKind == PostAudienceKind.pickPeople)
      for (final contact in _eligible)
        if (_selectedPeerIds.contains(contact.peerId)) contact,
  ];

  /// A pick stays a pick even when everyone in it has left the orbit: it
  /// never widens to all friends on its own.
  PostAudience get _thoughtAudience =>
      _audienceKind == PostAudienceKind.pickPeople
      ? PostAudience.pickPeople([for (final contact in _picked) contact.peerId])
      : PostAudience.allFriends();

  Future<void> _chooseAudience(BuildContext chipContext) async {
    final choice = await showThoughtAudienceMenu(
      chipContext,
      friendCount: _eligible.length,
      picking: _audienceKind == PostAudienceKind.pickPeople,
    );
    if (!mounted || choice == null) return;
    if (choice == ThoughtAudienceChoice.friends) {
      setState(() {
        _audienceKind = PostAudienceKind.allFriends;
        _selectedPeerIds.clear();
      });
      return;
    }
    final recentPicks = await widget.recentPicks?.load() ?? const [];
    if (!mounted) return;
    final chosen = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ThoughtPeoplePickerSheet(
        contacts: _eligible,
        initial: {for (final contact in _picked) contact.peerId},
        recentPicks: recentPicks,
      ),
    );
    if (!mounted || chosen == null || chosen.isEmpty) return;
    setState(() {
      _audienceKind = PostAudienceKind.pickPeople;
      _selectedPeerIds
        ..clear()
        ..addAll(chosen);
    });
  }

  bool get _canSubmit {
    if ((_textController.text.trim().isEmpty && _mediaDrafts.isEmpty) ||
        _isSubmitting ||
        _isAttaching ||
        _recordingState.isActive) {
      return false;
    }
    if (widget.thoughtsOnly &&
        _textController.text.characters.length > _thoughtMaxLength) {
      return false;
    }
    if (widget.thoughtsOnly &&
        _audienceKind == PostAudienceKind.pickPeople &&
        _picked.isEmpty) {
      return false;
    }
    if (!widget.thoughtsOnly &&
        _audienceKind == PostAudienceKind.pickPeople &&
        _selectedPeerIds.isEmpty) {
      return false;
    }
    if (!widget.thoughtsOnly &&
        _audienceKind == PostAudienceKind.peopleNearby &&
        _nearbyAvailability?.state != NearbyComposeAvailabilityState.ready) {
      return false;
    }
    return true;
  }

  bool get _isRecording => _recordingState.isActive;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _isSubmitting = true;
      _notice = null;
    });
    try {
      final audience = widget.thoughtsOnly
          ? _thoughtAudience
          : switch (_audienceKind) {
              PostAudienceKind.peopleNearby => PostAudience.peopleNearby(
                radiusM: _nearbyRadiusM,
              ),
              PostAudienceKind.pickPeople => PostAudience.pickPeople(
                _selectedPeerIds.toList(),
              ),
              _ => PostAudience.allFriends(),
            };
      final framings = _photoFramings;
      final List<PostMediaDraft> media;
      try {
        media = [
          for (final draft in _captionedDrafts)
            if (framings[draft.localFilePath] case final framing?)
              await bakeFramedPhoto(draft, framing)
            else
              draft,
        ];
      } on Object catch (error) {
        // Friends never get more than the author framed: nothing is shared
        // and the draft stays for another try.
        emitFlowEvent(
          layer: 'FL',
          event: 'POST_COMPOSE_FL_PHOTO_FRAME_FAILED',
          details: {'error': error.runtimeType.toString()},
        );
        if (mounted) setState(() => _notice = _ComposeNotice.shareFailed);
        return;
      }
      final outcome = await _submitPost(
        ComposePostResult(
          text: _textController.text.trim(),
          audience: audience,
          mediaDrafts: media,
        ),
      );
      if (!mounted) return;
      if (widget.thoughtsOnly &&
          audience.kind == PostAudienceKind.pickPeople &&
          (outcome == ComposePostSubmitOutcome.closeSheet ||
              outcome == ComposePostSubmitOutcome.keepSheetOpen)) {
        unawaited(widget.recentPicks?.remember(audience.selectedPeerIds));
      }
      switch (outcome) {
        case ComposePostSubmitOutcome.closeSheet:
          _shared = true;
          Navigator.of(context).pop();
        case ComposePostSubmitOutcome.nobodyToShareWith:
          setState(() => _notice = _ComposeNotice.nobodyToShareWith);
        case ComposePostSubmitOutcome.shareFailed:
          setState(() => _notice = _ComposeNotice.shareFailed);
        case ComposePostSubmitOutcome.keepSheetOpen:
          break;
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
    final text = _textController.text;
    final keep =
        !_shared && (text.trim().isNotEmpty || _mediaDrafts.isNotEmpty);
    widget.onClosed?.call(
      keep
          ? ComposePostResult(
              text: text,
              audience: widget.thoughtsOnly
                  ? _thoughtAudience
                  : PostAudience.allFriends(),
              mediaDrafts: _captionedDrafts,
              photoFramings: _framings,
            )
          : null,
    );
    _textController.removeListener(_updateInputDirection);
    _cancelRecorderSubscriptions();
    if (_recordingState.isActive) {
      _pendingRecordingAbort = true;
      final recorder = widget.audioRecorderService;
      // Only cancel a session this sheet still owns — the recording state
      // can be stale after another surface displaced the shared recorder.
      if (recorder != null &&
          recorder.onAutoStopped == _onRecorderAutoStopped) {
        recorder.onAutoStopped = null;
        unawaited(_cancelRecorderAfterDispose(recorder));
      } else if (!_recorderStartInFlight) {
        _releaseMicrophoneCaptureLease();
      }
    }
    _textController.dispose();
    _voiceCaption.dispose();
    super.dispose();
  }

  Future<void> _attachMedia() async {
    if ((widget.onAttachMedia == null && widget.onPickMedia == null) ||
        _isAttaching) {
      return;
    }
    setState(() {
      _isAttaching = true;
      _notice = null;
    });
    try {
      final PostMediaPick pick;
      try {
        pick = widget.onPickMedia != null
            ? await widget.onPickMedia!()
            : (drafts: await widget.onAttachMedia!(), leftOut: false);
      } on Object {
        if (mounted) setState(() => _notice = _ComposeNotice.mediaFailed);
        return;
      }
      if (!mounted) return;
      final combined = combinePostMedia(_mediaDrafts, pick.drafts);
      setState(() {
        _mediaDrafts = combined.drafts;
        if (pick.leftOut || combined.leftOut) {
          _notice = _ComposeNotice.mediaLeftOut;
        }
      });
    } finally {
      if (mounted) {
        setState(() => _isAttaching = false);
      }
    }
  }

  Future<void> _attachVoice() async {
    if (_isAttaching || _recordingState.isActive) {
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
    try {
      _microphoneCaptureLease = microphoneCaptureLeasesFor(recorder).acquire();
    } on MicrophoneCaptureLeaseRefused {
      setState(() => _notice = _ComposeNotice.micBusy);
      return;
    }

    _pendingRecordingAbort = false;
    setState(() {
      _notice = null;
      _recordingState = VoiceRecordingState.arming;
      _recordingDuration = Duration.zero;
      _recordingAmplitudes = const <double>[];
    });

    bool hasPermission;
    try {
      hasPermission = await recorder.requestPermission();
    } on Object {
      if (mounted) setState(() => _resetRecordingState(_ComposeNotice.micBusy));
      _releaseMicrophoneCaptureLease();
      return;
    }
    if (!mounted || _pendingRecordingAbort) {
      if (mounted) {
        setState(_resetRecordingState);
      }
      _releaseMicrophoneCaptureLease();
      return;
    }

    if (!hasPermission) {
      if (mounted) {
        setState(() => _resetRecordingState(_ComposeNotice.micOff));
      }
      _releaseMicrophoneCaptureLease();
      return;
    }

    _recorderStartInFlight = true;
    try {
      await recorder.start(outputPath: '');
    } catch (_) {
      if (mounted) {
        setState(() => _resetRecordingState(_ComposeNotice.micBusy));
      }
      _releaseMicrophoneCaptureLease();
      return;
    } finally {
      _recorderStartInFlight = false;
    }
    if (!mounted ||
        _pendingRecordingAbort ||
        _recordingState == VoiceRecordingState.stopping) {
      try {
        await recorder.cancel();
      } finally {
        _releaseMicrophoneCaptureLease();
      }
      if (mounted) {
        setState(_resetRecordingState);
      }
      return;
    }

    _cancelRecorderSubscriptions();
    _amplitudeBuffer.reset();
    _waveformSamples = <double>[];
    recorder.onAutoStopped = _onRecorderAutoStopped;
    _durationSubscription = recorder.durationStream.listen((duration) {
      if (!mounted) {
        return;
      }
      setState(() => _recordingDuration = duration);
      if (widget.thoughtsOnly &&
          duration >= _thoughtVoiceLimit &&
          _recordingState == VoiceRecordingState.recording) {
        unawaited(_stopVoiceRecording());
      }
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
      _recordingState = VoiceRecordingState.recording;
      _recordingDuration = Duration.zero;
      _recordingAmplitudes = _amplitudeBuffer.values;
      _mediaDrafts = const <PostMediaDraft>[];
    });
  }

  Future<void> _stopVoiceRecording() async {
    final recorder = widget.audioRecorderService;
    if (recorder == null || !_recordingState.isActive) {
      return;
    }

    if (_recordingState == VoiceRecordingState.arming) {
      _pendingRecordingAbort = true;
      setState(() => _recordingState = VoiceRecordingState.stopping);
      if (!_recorderStartInFlight) _releaseMicrophoneCaptureLease();
      return;
    }

    recorder.onAutoStopped = null;
    setState(() => _recordingState = VoiceRecordingState.stopping);
    final waveform = downsampleWaveform(_waveformSamples, 50);
    AudioRecording? recording;
    try {
      recording = await recorder.stop();
    } finally {
      _releaseMicrophoneCaptureLease();
    }
    _cancelRecorderSubscriptions();
    if (!mounted) {
      return;
    }

    _finishRecording(recording, waveform);
  }

  void _finishRecording(AudioRecording? recording, List<double> waveform) {
    setState(() {
      _resetRecordingState();
      if (recording == null) return;
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

  Future<void> _togglePause() async {
    final recorder = widget.audioRecorderService;
    if (recorder is! PausableAudioRecorder ||
        _recordingState != VoiceRecordingState.recording) {
      return;
    }
    final pausable = recorder as PausableAudioRecorder;
    final pause = !_recordingPaused;
    try {
      pause ? await pausable.pause() : await pausable.resume();
    } on Object {
      return;
    }
    if (mounted) setState(() => _recordingPaused = pause);
  }

  Future<void> _cancelVoiceRecording() async {
    final recorder = widget.audioRecorderService;
    if (recorder == null || !_recordingState.isActive) {
      return;
    }
    if (_recordingState == VoiceRecordingState.arming) {
      _pendingRecordingAbort = true;
      setState(() => _recordingState = VoiceRecordingState.stopping);
      if (!_recorderStartInFlight) _releaseMicrophoneCaptureLease();
      return;
    }
    recorder.onAutoStopped = null;
    setState(() => _recordingState = VoiceRecordingState.stopping);
    _cancelRecorderSubscriptions();
    try {
      await recorder.cancel();
    } finally {
      _releaseMicrophoneCaptureLease();
    }
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

  void _resetRecordingState([_ComposeNotice? notice]) {
    if (notice != null) _notice = notice;
    _pendingRecordingAbort = false;
    _recordingPaused = false;
    _recordingState = VoiceRecordingState.idle;
    _recordingDuration = Duration.zero;
    _recordingAmplitudes = const <double>[];
    _waveformSamples = <double>[];
    _amplitudeBuffer.reset();
  }

  void _onRecorderAutoStopped(AudioRecording? recording) {
    // The recorder stopped itself at the max recording duration; keep what
    // was recorded as the voice draft, as chat does.
    widget.audioRecorderService?.onAutoStopped = null;
    _releaseMicrophoneCaptureLease();
    _cancelRecorderSubscriptions();
    if (mounted) {
      _finishRecording(recording, downsampleWaveform(_waveformSamples, 50));
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'POST_COMPOSE_FL_RECORD_AUTO_STOPPED',
      details: {'tooShort': recording == null},
    );
  }

  Future<void> _cancelRecorderAfterDispose(
    AudioRecorderService recorder,
  ) async {
    try {
      await recorder.cancel();
    } on Object {
      // Disposal remains best effort.
    } finally {
      _releaseMicrophoneCaptureLease();
    }
  }

  void _releaseMicrophoneCaptureLease() {
    final lease = _microphoneCaptureLease;
    _microphoneCaptureLease = null;
    lease?.release();
  }

  void _clearDrafts() {
    _voiceCaption.clear();
    setState(() => _mediaDrafts = const <PostMediaDraft>[]);
  }

  void _updateInputDirection() {
    final nextDirection = detectTextDirection(_textController.text);
    if (nextDirection != _inputDirection) {
      setState(() => _inputDirection = nextDirection);
    }
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
    final contacts = _eligible;

    final rc = context.backgroundReadableColors;
    final thought = widget.thoughtsOnly;
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.thoughtsOnly)
          Text(
            AppLocalizations.of(context)!.compose_title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
        if (!widget.thoughtsOnly && widget.activePinCount > 0) ...[
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
                        : AppLocalizations.of(
                            context,
                          )!.compose_pinned_n(widget.activePinCount),
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
        if (thought)
          // One row when it fits; the 24 h line wraps under the chip if not.
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Builder(
                builder: (chipContext) => ThoughtAudienceChip(
                  picking: _audienceKind == PostAudienceKind.pickPeople,
                  picked: _picked,
                  onTap: () => unawaited(_chooseAudience(chipContext)),
                ),
              ),
              if (_audienceKind != PostAudienceKind.pickPeople ||
                  _picked.isNotEmpty)
                Text(
                  AppLocalizations.of(context)!.thought_compose_lifetime_short,
                  key: const ValueKey('thought-composer-lifetime'),
                  semanticsLabel: thoughtPickedLifetime(
                    AppLocalizations.of(context)!,
                    [for (final contact in _picked) contact.username],
                  ),
                  style: TextStyle(color: rc.textSecondary, fontSize: 13),
                ),
            ],
          ),
        SizedBox(height: thought ? 6 : 16),
        TextField(
          controller: _textController,
          textDirection: _inputDirection,
          maxLines: widget.thoughtsOnly ? 6 : 5,
          minLines: widget.thoughtsOnly ? 2 : 4,
          maxLength: widget.thoughtsOnly ? _thoughtMaxLength : null,
          // A Thought shows its count on the toolbar instead.
          buildCounter: widget.thoughtsOnly ? _noCounter : null,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: thought
                ? AppLocalizations.of(context)!.thought_compose_hint
                : AppLocalizations.of(context)!.compose_hint,
            hintStyle: TextStyle(
              color: thought
                  ? rc.placeholderText
                  : const Color.fromRGBO(255, 255, 255, 0.35),
            ),
            filled: !widget.thoughtsOnly,
            fillColor: const Color(0xFF1A1E26),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide.none,
            ),
          ),
          style: thought
              ? TextStyle(color: rc.textPrimary, fontSize: 19, height: 1.4)
              : const TextStyle(color: Colors.white),
        ),
        const SizedBox(height: 16),
        if (!widget.thoughtsOnly)
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
                label: Text(
                  AppLocalizations.of(context)!.compose_audience_nearby,
                ),
                selected: _audienceKind == PostAudienceKind.peopleNearby,
                onSelected: (_) {
                  setState(() {
                    _audienceKind = PostAudienceKind.peopleNearby;
                    _selectedPeerIds.clear();
                  });
                },
              ),
              ChoiceChip(
                label: Text(
                  AppLocalizations.of(context)!.compose_audience_pick,
                ),
                selected: _audienceKind == PostAudienceKind.pickPeople,
                onSelected: (_) {
                  setState(() {
                    _audienceKind = PostAudienceKind.pickPeople;
                  });
                },
              ),
            ],
          ),
        if (!widget.thoughtsOnly &&
            _audienceKind == PostAudienceKind.peopleNearby) ...[
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
        if (!widget.thoughtsOnly && _nearbyAvailability != null) ...[
          const SizedBox(height: 16),
          _NearbyComposeAvailabilityCard(
            availability: _nearbyAvailability!,
            isRefreshing: _isRefreshingNearby,
            onRefresh: widget.onRefreshNearby == null ? null : _refreshNearby,
            onOpenSettings: widget.onOpenNearbySettings == null
                ? null
                : _openNearbySettings,
          ),
        ],
        if (!widget.thoughtsOnly) ...[
          const SizedBox(height: 16),
          // Media and voice belong to the field: tapping them keeps
          // the keyboard.
          TextFieldTapRegion(
            child: Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed:
                      (widget.onAttachMedia == null &&
                              widget.onPickMedia == null) ||
                          _isRecording
                      ? null
                      : _attachMedia,
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: Text(
                    _isAttaching
                        ? AppLocalizations.of(context)!.compose_media_adding
                        : AppLocalizations.of(context)!.compose_media,
                  ),
                ),
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
          ),
        ],
        // A Thought records on its toolbar instead.
        if (_isRecording && !thought) ...[
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
                icon: const Icon(Icons.stop_circle_outlined, size: 18),
                label: Text(AppLocalizations.of(context)!.compose_voice_stop),
              ),
            ],
          ),
        ],
        if (widget.thoughtsOnly &&
            _mediaDrafts.isNotEmpty &&
            _mediaDrafts.every((draft) => draft.kind == 'image')) ...[
          const SizedBox(height: 12),
          ThoughtPhotoDraftPreview(
            paths: [for (final draft in _mediaDrafts) draft.localFilePath],
            framings: _photoFramings,
            onFramed: (path, framing) =>
                setState(() => _framings = {..._framings, path: framing}),
            onRemove: (index) => setState(() {
              final removed = _mediaDrafts[index].localFilePath;
              _mediaDrafts = [..._mediaDrafts]..removeAt(index);
              _framings = {..._framings}..remove(removed);
            }),
          ),
        ] else if (_mediaDrafts.isNotEmpty &&
            _mediaDrafts.first.kind != 'voice') ...[
          const SizedBox(height: 12),
          AttachmentPreviewStrip(
            attachments: [
              for (final draft in _mediaDrafts) File(draft.localFilePath),
            ],
            onRemove: (index) => setState(
              () => _mediaDrafts = [..._mediaDrafts]..removeAt(index),
            ),
          ),
        ],
        if (thought && _isRecording) ...[
          const SizedBox(height: 12),
          ThoughtRecordingCard(
            elapsed: _recordingDuration,
            amplitudes: _recordingAmplitudes,
            paused: _recordingPaused,
            onPauseToggle: widget.audioRecorderService is PausableAudioRecorder
                ? () => unawaited(_togglePause())
                : null,
            onCancel: () => unawaited(_cancelVoiceRecording()),
            onStop: () => unawaited(_stopVoiceRecording()),
          ),
        ],
        if (thought &&
            _mediaDrafts.isNotEmpty &&
            _mediaDrafts.first.kind == 'voice') ...[
          const SizedBox(height: 12),
          ThoughtVoiceCard(
            draft: _mediaDrafts.first,
            caption: _voiceCaption,
            onRemove: _clearDrafts,
          ),
        ] else if (_mediaDrafts.isNotEmpty &&
            _mediaDrafts.first.kind == 'voice') ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: thought ? rc.composerInputFill : const Color(0xFF1A1E26),
              border: thought ? Border.all(color: rc.divider) : null,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                if (thought) ...[
                  Icon(Icons.graphic_eq_rounded, color: rc.accent),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    _mediaDrafts.first.kind == 'voice'
                        ? AppLocalizations.of(context)!.compose_voice_attached
                        : AppLocalizations.of(
                            context,
                          )!.compose_attachments(_mediaDrafts.length),
                    style: TextStyle(
                      color: thought ? rc.textPrimary : Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _clearDrafts,
                  icon: Icon(
                    Icons.close_rounded,
                    color: thought ? rc.iconSecondary : Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (!widget.thoughtsOnly &&
            _audienceKind == PostAudienceKind.pickPeople) ...[
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
                final isSelected = _selectedPeerIds.contains(contact.peerId);
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
        SizedBox(height: thought ? 12 : 20),
        if (_notice case final notice?) ...[
          Text(
            _noticeText(AppLocalizations.of(context)!, notice),
            style: TextStyle(
              color: thought
                  ? Theme.of(context).colorScheme.error
                  : const Color(0xFFFFB4A9),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (!widget.thoughtsOnly)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _canSubmit ? _submit : null,
              child: Text(
                _isSubmitting
                    ? AppLocalizations.of(context)!.compose_posting
                    : AppLocalizations.of(context)!.compose_post,
              ),
            ),
          ),
      ],
    );
    if (widget.thoughtsOnly) return _thoughtSheet(context, body);
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
            child: SingleChildScrollView(child: body),
          ),
        ),
      ),
    );
  }

  /// A Thought keeps Share in the header and its photo and mic on a toolbar
  /// that rides just above the keyboard, so neither scrolls out of reach. Its
  /// colours come from the app theme.
  Widget _thoughtSheet(BuildContext context, Widget body) {
    final l10n = AppLocalizations.of(context)!;
    final rc = context.backgroundReadableColors;
    final length = _textController.text.characters.length;
    final over = length > _thoughtMaxLength;
    final error = Theme.of(context).colorScheme.error;
    final onAccent = _onAccent(rc.accent);
    return Padding(
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top + 12,
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Material(
        color: rc.surfaceRaised.withValues(alpha: 1),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 5,
                margin: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(
                  color: rc.divider,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 2, 16, 2),
                child: Row(
                  children: [
                    TextButton(
                      key: const ValueKey('thought-composer-cancel'),
                      onPressed: () => Navigator.of(context).maybePop(),
                      style: TextButton.styleFrom(
                        foregroundColor: rc.textSecondary,
                        textStyle: const TextStyle(fontSize: 16),
                      ),
                      child: Text(l10n.btn_cancel),
                    ),
                    Expanded(
                      child: Text(
                        l10n.thought_compose_header,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: rc.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    ElevatedButton(
                      key: const ValueKey('thought-composer-share'),
                      onPressed: _canSubmit ? _submit : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: rc.accent,
                        foregroundColor: onAccent,
                        disabledBackgroundColor: rc.disabledSurface,
                        disabledForegroundColor: rc.disabledForeground,
                        elevation: 0,
                        shape: const StadiumBorder(),
                        minimumSize: const Size(72, 36),
                        textStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: Text(l10n.thought_compose_share),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: body,
                ),
              ),
              // Pinned above the toolbar: a tall body would scroll it under.
              // On a short screen with large text it scrolls in a fifth of
              // the visible height instead of pushing the toolbar down.
              if (widget.replacesCurrentThought)
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight:
                        (MediaQuery.sizeOf(context).height -
                            MediaQuery.viewInsetsOf(context).bottom -
                            MediaQuery.paddingOf(context).top) /
                        5,
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 16,
                          color: rc.textMuted,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            l10n.thought_compose_replaces,
                            key: const ValueKey('thought-composer-replaces'),
                            style: TextStyle(color: rc.textMuted, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              // Photo and mic belong to the field: tapping them keeps the
              // keyboard.
              TextFieldTapRegion(
                child: Container(
                  key: const ValueKey('thought-composer-toolbar'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: rc.composerBarColor,
                    border: Border(top: BorderSide(color: rc.divider)),
                  ),
                  child: Row(
                    children: [
                      _ToolButton(
                        key: const ValueKey('thought-composer-media'),
                        icon: Icons.photo_outlined,
                        label: _isAttaching
                            ? l10n.compose_media_adding
                            : l10n.compose_media,
                        onPressed:
                            (widget.onAttachMedia == null &&
                                    widget.onPickMedia == null) ||
                                _isRecording
                            ? null
                            : _attachMedia,
                      ),
                      const SizedBox(width: 12),
                      // The mic sits at the end; a recording shows in the
                      // sheet above.
                      Expanded(
                        child: Row(
                          key: const ValueKey('thought-composer-idle'),
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (length >= _thoughtCounterFrom) ...[
                              Text(
                                '$length/$_thoughtMaxLength',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: over ? error : rc.textMuted,
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            if (length > 0) ...[
                              SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  key: const ValueKey(
                                    'thought-composer-count-ring',
                                  ),
                                  value: (length / _thoughtMaxLength).clamp(
                                    0.0,
                                    1.0,
                                  ),
                                  strokeWidth: 2.5,
                                  backgroundColor: rc.divider,
                                  color: over ? error : rc.accent,
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],
                            _ToolButton(
                              key: const ValueKey('thought-composer-voice'),
                              icon: Icons.mic_none_rounded,
                              label: l10n.compose_voice,
                              onPressed:
                                  _isRecording ||
                                      (widget.onAttachVoice == null &&
                                          widget.audioRecorderService == null)
                                  ? null
                                  : _attachVoice,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A round photo or mic button on the Thought toolbar, in the chat
/// composer's style. Icon only; its label is the tooltip.
class _ToolButton extends StatelessWidget {
  const _ToolButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final rc = context.backgroundReadableColors;
    return IconButton(
      tooltip: label,
      onPressed: onPressed,
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      style: IconButton.styleFrom(
        backgroundColor: rc.composerInputFill,
        foregroundColor: rc.accent,
        disabledBackgroundColor: rc.composerInputFill,
        disabledForegroundColor: rc.disabledForeground,
        side: BorderSide(color: rc.divider),
      ),
      icon: Icon(icon, size: 22),
    );
  }
}

/// Text or an icon on the accent: white fails on the bright dark-theme green.
Color _onAccent(Color accent) =>
    accent.computeLuminance() > .3 ? const Color(0xFF0A0A0F) : Colors.white;

Widget? _noCounter(
  BuildContext context, {
  required int currentLength,
  required bool isFocused,
  required int? maxLength,
}) => null;

String _noticeText(AppLocalizations l10n, _ComposeNotice notice) =>
    switch (notice) {
      _ComposeNotice.nobodyToShareWith =>
        l10n.thought_compose_nobody_to_share_with,
      _ComposeNotice.shareFailed => l10n.thought_compose_share_failed,
      _ComposeNotice.mediaLeftOut => l10n.thought_compose_media_left_out,
      _ComposeNotice.mediaFailed => l10n.thought_compose_media_failed,
      _ComposeNotice.micOff => l10n.mic_perm_dialog_body,
      _ComposeNotice.micBusy => l10n.thought_compose_mic_busy,
    };

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
      NearbyComposeAvailabilityState.sharingOff => l10n.compose_nearby_off_desc,
      NearbyComposeAvailabilityState.ready => l10n.compose_nearby_ready_desc,
      NearbyComposeAvailabilityState.stale => l10n.compose_nearby_refresh_desc,
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
            label: Text(
              isRefreshing
                  ? l10n.compose_refreshing
                  : l10n.compose_refresh_nearby,
            ),
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
