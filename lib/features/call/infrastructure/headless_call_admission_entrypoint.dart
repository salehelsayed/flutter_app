import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

enum HeadlessCallAdmissionDisposition {
  admitted('admitted'),
  terminal('terminal'),
  permanentReject('permanent_reject'),
  emptyOrAlreadyAcked('empty_or_already_acked'),
  deferred('deferred');

  const HeadlessCallAdmissionDisposition(this.wireName);

  final String wireName;
}

/// What one headless run is asked to do. Admission presents an authenticated
/// invite natively. The decline reply (plan 404) answers a call that was
/// declined natively while the process had no Dart owner: it sends the
/// caller its `reject` and acknowledges the ended call's rows.
enum HeadlessCallAdmissionMode {
  admission('admission'),
  declineReply('decline_reply');

  const HeadlessCallAdmissionMode(this.wireName);

  final String wireName;
}

final class HeadlessCallAdmissionInvocation {
  const HeadlessCallAdmissionInvocation({
    required this.nonce,
    required this.callId,
    required this.wakeHandle,
    required this.expiresAtMs,
    this.mode = HeadlessCallAdmissionMode.admission,
  });

  static final RegExp _nonce = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );
  static final RegExp _canonicalCallId = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );
  static final RegExp _wakeHandle = RegExp(
    r'^(?:[0-9a-f]{32}|[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})$',
  );
  static final RegExp _positiveMilliseconds = RegExp(r'^[1-9][0-9]{0,18}$');

  final String nonce;
  final String callId;
  final String wakeHandle;
  final int expiresAtMs;
  final HeadlessCallAdmissionMode mode;

  factory HeadlessCallAdmissionInvocation.parse(List<String> arguments) {
    if (arguments.length != 4 && arguments.length != 5) {
      throw const FormatException(
        'headless call admission requires four or five opaque arguments',
      );
    }
    final nonce = arguments[0];
    final callId = arguments[1];
    final wakeHandle = arguments[2];
    final rawExpiry = arguments[3];
    if (!_nonce.hasMatch(nonce) ||
        !_canonicalCallId.hasMatch(callId) ||
        !_wakeHandle.hasMatch(wakeHandle) ||
        !_positiveMilliseconds.hasMatch(rawExpiry)) {
      throw const FormatException('invalid headless call admission arguments');
    }
    final expiresAtMs = int.tryParse(rawExpiry);
    if (expiresAtMs == null || expiresAtMs <= 0) {
      throw const FormatException('invalid headless call admission expiry');
    }
    var mode = HeadlessCallAdmissionMode.admission;
    if (arguments.length == 5) {
      if (arguments[4] != HeadlessCallAdmissionMode.declineReply.wireName) {
        throw const FormatException('invalid headless call admission mode');
      }
      mode = HeadlessCallAdmissionMode.declineReply;
    }
    return HeadlessCallAdmissionInvocation(
      nonce: nonce,
      callId: callId,
      wakeHandle: wakeHandle,
      expiresAtMs: expiresAtMs,
      mode: mode,
    );
  }

  Map<String, Object?> identityPayload() => <String, Object?>{
    'nonce': nonce,
    'callId': callId,
    'wakeHandle': wakeHandle,
    'expiresAtMs': expiresAtMs,
  };

  @override
  String toString() => 'HeadlessCallAdmissionInvocation(redacted)';
}

final class HeadlessCallAdmissionCleanup {
  const HeadlessCallAdmissionCleanup({
    required this.databaseClosed,
    required this.leaseReleased,
  });

  final bool databaseClosed;
  final bool leaseReleased;
}

final class HeadlessCallAdmissionRunReport {
  const HeadlessCallAdmissionRunReport({
    required this.disposition,
    required this.requiredPersistenceComplete,
    required this.databaseClosed,
    required this.leaseReleased,
  });

  final HeadlessCallAdmissionDisposition disposition;
  final bool requiredPersistenceComplete;
  final bool databaseClosed;
  final bool leaseReleased;
}

typedef RunHeadlessCallAdmission =
    Future<HeadlessCallAdmissionRunReport> Function({
      required HeadlessCallAdmissionInvocation invocation,
      required bool Function() isStopRequested,
    });

abstract interface class HeadlessCallAdmissionResultChannel {
  void registerCancelHandler(void Function() onCancel);

  Future<void> send({
    required String method,
    required Map<String, Object?> payload,
  });

  void dispose();
}

final class MethodChannelHeadlessCallAdmissionResultChannel
    implements HeadlessCallAdmissionResultChannel {
  MethodChannelHeadlessCallAdmissionResultChannel({
    MethodChannel channel = const MethodChannel(
      'mknoon/headless_call_admission',
    ),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  void registerCancelHandler(void Function() onCancel) {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'cancel') {
        throw MissingPluginException(
          'Unsupported headless call admission method',
        );
      }
      onCancel();
      return true;
    });
  }

  @override
  Future<void> send({
    required String method,
    required Map<String, Object?> payload,
  }) => _channel.invokeMethod<void>(method, payload);

  @override
  void dispose() => _channel.setMethodCallHandler(null);
}

Future<void> runAndroidHeadlessCallAdmission(
  List<String> arguments, {
  required RunHeadlessCallAdmission runAdmission,
  required Future<HeadlessCallAdmissionCleanup> Function() emergencyShutdown,
  HeadlessCallAdmissionResultChannel? resultChannel,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  final invocation = HeadlessCallAdmissionInvocation.parse(arguments);
  final channel =
      resultChannel ?? MethodChannelHeadlessCallAdmissionResultChannel();
  var stopRequested = false;
  channel.registerCancelHandler(() => stopRequested = true);
  late HeadlessCallAdmissionRunReport report;
  try {
    report = await runAdmission(
      invocation: invocation,
      isStopRequested: () => stopRequested,
    );
  } catch (_) {
    HeadlessCallAdmissionCleanup cleanup;
    try {
      cleanup = await emergencyShutdown();
    } catch (_) {
      cleanup = const HeadlessCallAdmissionCleanup(
        databaseClosed: false,
        leaseReleased: false,
      );
    }
    report = HeadlessCallAdmissionRunReport(
      disposition: HeadlessCallAdmissionDisposition.deferred,
      requiredPersistenceComplete: false,
      databaseClosed: cleanup.databaseClosed,
      leaseReleased: cleanup.leaseReleased,
    );
  }

  try {
    await channel.send(
      method: 'complete',
      payload: <String, Object?>{
        ...invocation.identityPayload(),
        'disposition': report.disposition.wireName,
        'requiredPersistenceComplete': report.requiredPersistenceComplete,
        'databaseClosed': report.databaseClosed,
        'leaseReleased': report.leaseReleased,
      },
    );
  } finally {
    channel.dispose();
  }
}
