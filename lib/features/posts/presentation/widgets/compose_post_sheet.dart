import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/amplitude_buffer.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/core/media/downsample_waveform.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/application/attach_post_media_use_case.dart';
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

class ComposePostSheet extends StatefulWidget {
  final List<ContactModel> eligibleContacts;
  final Future<void> Function(ComposePostResult result) onSubmit;
  final Future<List<PostMediaDraft>> Function()? onAttachMedia;
  final Future<PostMediaDraft?> Function()? onAttachVoice;
  final AudioRecorderService? audioRecorderService;

  const ComposePostSheet({
    super.key,
    required this.eligibleContacts,
    required this.onSubmit,
    this.onAttachMedia,
    this.onAttachVoice,
    this.audioRecorderService,
  });

  @override
  State<ComposePostSheet> createState() => _ComposePostSheetState();
}

class _ComposePostSheetState extends State<ComposePostSheet> {
  final TextEditingController _textController = TextEditingController();
  PostAudienceKind _audienceKind = PostAudienceKind.allFriends;
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
    return true;
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _isSubmitting = true);
    try {
      final audience = switch (_audienceKind) {
        PostAudienceKind.pickPeople => PostAudience.pickPeople(
          _selectedPeerIds.toList(),
        ),
        _ => PostAudience.allFriends(),
      };
      await widget.onSubmit(
        ComposePostResult(
          text: _textController.text.trim(),
          audience: audience,
          mediaDrafts: _mediaDrafts,
        ),
      );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
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
                const Text(
                  'Create Post',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _textController,
                  maxLines: 5,
                  minLines: 4,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'What do you want to share?',
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
                      label: const Text('All Friends'),
                      selected: _audienceKind == PostAudienceKind.allFriends,
                      onSelected: (_) {
                        setState(() {
                          _audienceKind = PostAudienceKind.allFriends;
                          _selectedPeerIds.clear();
                        });
                      },
                    ),
                    ChoiceChip(
                      label: const Text('Pick People'),
                      selected: _audienceKind == PostAudienceKind.pickPeople,
                      onSelected: (_) {
                        setState(() {
                          _audienceKind = PostAudienceKind.pickPeople;
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: widget.onAttachMedia == null || _isRecording
                          ? null
                          : _attachMedia,
                      icon: const Icon(Icons.photo_library_outlined, size: 18),
                      label: Text(_isAttaching ? 'Adding...' : 'Media'),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed:
                          (widget.onAttachVoice == null &&
                              widget.audioRecorderService == null)
                          ? null
                          : _attachVoice,
                      icon: const Icon(Icons.mic_none_rounded, size: 18),
                      label: const Text('Voice'),
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
                        icon: const Icon(Icons.stop_circle_outlined, size: 18),
                        label: const Text('Stop'),
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
                                ? 'Voice attached'
                                : '${_mediaDrafts.length} attachments',
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
                  const Text(
                    'Pick People',
                    style: TextStyle(
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
                    child: Text(_isSubmitting ? 'Posting...' : 'Post'),
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
