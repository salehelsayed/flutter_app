import 'dart:async';

import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

import 'in_memory_media_attachment_repository.dart';

/// Pauses one exact attachment-ID hydration before reading its current row.
///
/// Forward race tests use this at the final exact-row boundary so a concurrent
/// parent-authority change is guaranteed to happen before the subsequent
/// group/tombstone/parent decision.
class NthExactMediaReadGatedRepository
    extends InMemoryMediaAttachmentRepository {
  NthExactMediaReadGatedRepository({required this.gateAtCall});

  final int gateAtCall;
  final Completer<void> captured = Completer<void>();
  final Completer<void> release = Completer<void>();
  int _calls = 0;

  int get exactReadCount => _calls;

  @override
  Future<MediaAttachment?> getAttachmentById(String id) async {
    _calls++;
    if (_calls == gateAtCall) {
      captured.complete();
      await release.future;
    }
    return super.getAttachmentById(id);
  }
}
