import 'package:flutter/widgets.dart';

typedef ApplicationBootstrapFactory = ApplicationBootstrap Function();

abstract interface class ApplicationBootstrap {
  Future<PreparedApplication> prepare();
}

abstract interface class PreparedApplication {
  Future<Widget> buildRootWidget();

  void afterRunApp();
}

abstract interface class ApplicationHost {
  void initializeBinding();

  void launch(Widget rootWidget);
}

final class FlutterApplicationHost implements ApplicationHost {
  const FlutterApplicationHost();

  @override
  void initializeBinding() {
    WidgetsFlutterBinding.ensureInitialized();
  }

  @override
  void launch(Widget rootWidget) {
    runApp(rootWidget);
  }
}

Future<void> runApplicationBootstrap({
  required ApplicationBootstrapFactory bootstrapFactory,
  required ApplicationHost host,
}) async {
  host.initializeBinding();
  final bootstrap = bootstrapFactory();
  final preparedApplication = await bootstrap.prepare();
  final rootWidget = await preparedApplication.buildRootWidget();
  host.launch(rootWidget);
  preparedApplication.afterRunApp();
}
