import 'package:flutter_app/app/bootstrap/application_bootstrap.dart';
import 'package:flutter_app/app/bootstrap/production_application_bootstrap.dart';

export 'package:flutter_app/app/application_root.dart'
    show MyApp, openIntroNotificationOrbitRoute;
export 'package:flutter_app/app/bootstrap/production_application_bootstrap.dart'
    show keychainMirrorBackfill;

void main() async {
  await runApplicationBootstrap(
    bootstrapFactory: ProductionApplicationBootstrap.new,
    host: const FlutterApplicationHost(),
  );
}
