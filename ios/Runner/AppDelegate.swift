import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
#if canImport(GoMknoon)
  private var goBridge: GoBridge?
#endif

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

#if canImport(GoMknoon)
    if let flutterVC = self.window?.rootViewController as? FlutterViewController {
      goBridge = GoBridge(messenger: flutterVC.binaryMessenger)
    }
#endif

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
