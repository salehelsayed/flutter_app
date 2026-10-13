import 'dart:convert';

const missedCallPayloadPrefix = 'mknoon.missed_call.v1:';
const callBackPayloadPrefix = 'mknoon.call_back.v1:';
const missedCallBackActionId = 'mknoon_call_back';
const missedCallActionCategoryId = 'mknoon_missed_call';
final _callIdGrammar = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

/// Local routing only. Neither field authorizes a contact or an old call.
class MissedCallActionPayload {
  const MissedCallActionPayload(this.contactPeerId, this.callId);
  final String contactPeerId;
  final String callId;
  String encode() =>
      '$missedCallPayloadPrefix${jsonEncode({'contact': contactPeerId, 'call': callId})}';
  String get callBackPayload => '$callBackPayloadPrefix$callId';
  static MissedCallActionPayload? parse(String? value) {
    if (value == null ||
        !value.startsWith(missedCallPayloadPrefix) ||
        value.length > 1024) {
      return null;
    }
    try {
      final map = jsonDecode(value.substring(missedCallPayloadPrefix.length));
      if (map is! Map ||
          map.length != 2 ||
          map['contact'] is! String ||
          map['call'] is! String ||
          (map['contact'] as String).trim().isEmpty ||
          !_callIdGrammar.hasMatch(map['call'] as String)) {
        return null;
      }
      return MissedCallActionPayload(
        map['contact'] as String,
        map['call'] as String,
      );
    } catch (_) {
      return null;
    }
  }

  static String? parseCallBack(String value) {
    if (!value.startsWith(callBackPayloadPrefix)) return null;
    final id = value.substring(callBackPayloadPrefix.length);
    return _callIdGrammar.hasMatch(id) ? id : null;
  }
}
