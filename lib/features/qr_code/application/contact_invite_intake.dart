import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

sealed class ContactInviteEntry {
  const ContactInviteEntry();
}

final class OpenContactInvite extends ContactInviteEntry {
  const OpenContactInvite(this.rawUrl);

  final String rawUrl;
}

final class PasteContactInvite extends ContactInviteEntry {
  const PasteContactInvite();
}

final class ContactInviteIntake extends ChangeNotifier {
  ContactInviteIntake({
    MethodChannel channel = const MethodChannel('mknoon/contact_invites'),
  }) : _channel = channel;

  static final _inviteFrame = RegExp(
    r'https://invite\.mknoon\.xyz/i/v1#[A-Za-z0-9_-]{1,2048}',
  );

  final MethodChannel _channel;
  ContactInviteEntry? _pending;
  bool _started = false;
  bool _reading = false;
  bool _readAgain = false;
  bool _disposed = false;
  int _generation = 0;

  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'inviteAvailable' && call.arguments == null) {
        unawaited(_drain());
      }
    });
    await _drain();
  }

  ContactInviteEntry? takePending() {
    final pending = _pending;
    _pending = null;
    return pending;
  }

  ContactInviteEntry? get pending => _pending;

  void requestPaste() {
    if (_disposed) return;
    _pending = const PasteContactInvite();
    notifyListeners();
  }

  void discardPending() {
    _generation++;
    _pending = null;
  }

  Future<bool> presentShare(String link) async {
    if (_disposed) return false;
    return await _channel.invokeMethod<bool>('shareLink', link) ?? false;
  }

  Future<void> _drain() async {
    if (_disposed) return;
    if (_reading) {
      _readAgain = true;
      return;
    }
    _reading = true;
    try {
      do {
        _readAgain = false;
        final generation = _generation;
        final Object? reply;
        try {
          reply = await _channel.invokeMethod<Object?>('takePending');
        } on MissingPluginException {
          continue;
        } on PlatformException {
          continue;
        }
        if (_disposed) return;
        if (generation != _generation) continue;
        final entry = _decodeEntry(reply);
        if (entry != null) {
          _pending = entry;
          notifyListeners();
        }
      } while (_readAgain && !_disposed);
    } finally {
      _reading = false;
    }
  }

  static ContactInviteEntry? _decodeEntry(Object? reply) {
    if (reply is! Map<Object?, Object?>) return null;
    return switch (reply) {
      {'kind': 'paste'} when reply.length == 1 => const PasteContactInvite(),
      {'kind': 'link', 'url': final String rawUrl}
          when reply.length == 2 &&
              _inviteFrame.matchAsPrefix(rawUrl)?.end == rawUrl.length =>
        OpenContactInvite(rawUrl),
      _ => null,
    };
  }

  @override
  void dispose() {
    _disposed = true;
    _pending = null;
    if (_started) _channel.setMethodCallHandler(null);
    super.dispose();
  }
}
