import '../domain/call_engine.dart';

/// Privacy-safe network path classes that may be shown in local diagnostics.
enum CallRouteDiagnostic { direct, turnUdp, turnTcpTls, unknown }

/// Maps engine transport details to the fixed diagnostic vocabulary.
final class CallRouteDiagnostics {
  const CallRouteDiagnostics._(this.route);

  factory CallRouteDiagnostics.fromSnapshot(CallConnectionSnapshot snapshot) =>
      CallRouteDiagnostics.fromTransport(snapshot.transport);

  factory CallRouteDiagnostics.fromTransport(CallTransportClass transport) {
    final route = switch (transport) {
      CallTransportClass.direct => CallRouteDiagnostic.direct,
      CallTransportClass.turnUdp => CallRouteDiagnostic.turnUdp,
      CallTransportClass.turnTcpTls => CallRouteDiagnostic.turnTcpTls,
      CallTransportClass.unknown ||
      CallTransportClass.relay => CallRouteDiagnostic.unknown,
    };
    return CallRouteDiagnostics._(route);
  }

  final CallRouteDiagnostic route;

  Map<String, String> toDiagnosticMap() => <String, String>{
    'route': route.name,
  };

  @override
  String toString() => 'CallRouteDiagnostics(route: ${route.name})';
}
