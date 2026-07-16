import 'dart:convert';

const String iosReceiverBootstrapBuildProfile = 'ios.device.production';

bool isIosReceiverBootstrapBuildProfile(String value) =>
    value == iosReceiverBootstrapBuildProfile;

bool isIosReceiverBootstrapTransportPeerId(String value) {
  const base58 = r'[1-9A-HJ-NP-Za-km-z]';
  return RegExp('^(?:12D3KooW$base58{44}|Qm$base58{44})\$').hasMatch(value);
}

bool isIosReceiverBootstrapMlKemPublicKey(String value) {
  if (!RegExp(r'^[A-Za-z0-9_+/=-]{100,4096}$').hasMatch(value)) return false;
  try {
    final normalized = base64.normalize(
      value.replaceAll('-', '+').replaceAll('_', '/'),
    );
    return base64.decode(normalized).length == 1184;
  } on FormatException {
    return false;
  }
}

bool isIosReceiverBootstrapNotificationAuthorization(String value) =>
    value == 'authorized' || value == 'provisional' || value == 'ephemeral';

bool isIosReceiverBootstrapNotificationAlertSetting(String value) =>
    value == 'enabled';
