import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

/// Why an upload attempt owns a media attachment lease.
///
/// The value is consumed only by claim telemetry. Production behavior never
/// branches on it.
enum MediaUploadTriggerSource {
  foreground,
  networkRestored,
  full,
  periodic,
  resume,
  manual;

  String get wireValue => switch (this) {
    MediaUploadTriggerSource.foreground => 'foreground',
    MediaUploadTriggerSource.networkRestored => 'network_restored',
    MediaUploadTriggerSource.full => 'full',
    MediaUploadTriggerSource.periodic => 'periodic',
    MediaUploadTriggerSource.resume => 'resume',
    MediaUploadTriggerSource.manual => 'manual',
  };
}

/// Opaque ownership token returned by [MediaUploadInFlightTracker.tryClaimAll].
///
/// A lease can only release the exact all-or-none claim that created it. Its
/// attachment identifiers are deliberately private so telemetry and callers
/// cannot accidentally expose raw blob IDs.
class MediaUploadLease {
  const MediaUploadLease._({
    required Object trackerToken,
    required Object ownerToken,
    required Set<String> attachmentIds,
  }) : _trackerToken = trackerToken,
       _ownerToken = ownerToken,
       _attachmentIds = attachmentIds;

  final Object _trackerToken;
  final Object _ownerToken;
  final Set<String> _attachmentIds;

  int get attachmentCount => _attachmentIds.length;
}

typedef TryClaimMediaUploadLease =
    MediaUploadLease? Function(
      Iterable<String> attachmentIds, {
      required MediaUploadTriggerSource source,
    });

/// A claim callback whose trigger source was bound by its production caller.
///
/// Retry entry points accept this shape so trigger source remains claim-only
/// metadata rather than becoming a behavior-bearing use-case parameter.
typedef TryClaimMediaUploadLeaseForSource =
    MediaUploadLease? Function(Iterable<String> attachmentIds);
typedef ReleaseMediaUploadLease = bool Function(MediaUploadLease lease);

/// Process-wide, token-owned registry for conversation media uploads.
///
/// Claims are synchronous and therefore atomic within the owning Dart
/// isolate. Multi-attachment claims are all-or-none: if any requested ID is
/// already owned, no ID is mutated. Release requires the opaque owner token;
/// a stale lease or a lease created by another tracker cannot clear a winner.
class MediaUploadInFlightTracker {
  final Object _trackerToken = Object();
  final Map<String, Object> _owners = <String, Object>{};

  MediaUploadLease? tryClaimAll(
    Iterable<String> attachmentIds, {
    required MediaUploadTriggerSource source,
  }) {
    final ids = attachmentIds.toSet();
    if (ids.isEmpty || ids.any((id) => id.isEmpty)) return null;
    if (ids.any(_owners.containsKey)) return null;

    final ownerToken = Object();
    for (final id in ids) {
      _owners[id] = ownerToken;
    }
    final lease = MediaUploadLease._(
      trackerToken: _trackerToken,
      ownerToken: ownerToken,
      attachmentIds: Set<String>.unmodifiable(ids),
    );

    // One receipt per attachment lets the E2E endpoint correlate its selected
    // row without exposing raw/truncated identifiers. Keep these details exact.
    for (final id in ids) {
      emitFlowEvent(
        layer: 'FL',
        event: 'MEDIA_UPLOAD_LEASE_CLAIMED',
        details: {
          'source': source.wireValue,
          'attachmentSha256': sha256.convert(utf8.encode(id)).toString(),
        },
      );
    }
    return lease;
  }

  /// Releases [lease] only when every attachment is still owned by its token.
  bool release(MediaUploadLease lease) {
    if (!identical(lease._trackerToken, _trackerToken)) return false;
    if (lease._attachmentIds.any(
      (id) => !identical(_owners[id], lease._ownerToken),
    )) {
      return false;
    }
    for (final id in lease._attachmentIds) {
      _owners.remove(id);
    }
    return true;
  }

  bool isInFlight(String attachmentId) => _owners.containsKey(attachmentId);

  @visibleForTesting
  int get inFlightCount => _owners.length;

  @visibleForTesting
  void clearAll() => _owners.clear();
}

/// The single process-wide instance shared by every conversation upload lane.
final MediaUploadInFlightTracker mediaUploadInFlightTracker =
    MediaUploadInFlightTracker();
