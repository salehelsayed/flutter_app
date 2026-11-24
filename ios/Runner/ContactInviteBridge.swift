import Flutter
import UIKit
import receive_sharing_intent

/// Retained by AppDelegate. Scene callbacks and the default channel run on the main thread.
@MainActor
final class ContactInviteBridge: NSObject, @preconcurrency FlutterSceneLifeCycleDelegate {
  private enum Entry {
    case paste
    case link(String)

    var envelope: [String: String] {
      switch self {
      case .paste: return ["kind": "paste"]
      case .link(let raw): return ["kind": "link", "url": raw]
      }
    }
  }

  private static let invitePrefix = "https://invite.mknoon.xyz/i/v1#".utf8
  private static let pasteURL = "mknoon://invite".utf8
  private static let maxFragmentLength = 2048

  private let channel: FlutterMethodChannel
  private var pending: Entry?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "mknoon/contact_invites", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "takePending" where call.arguments == nil:
        let entry = self?.pending
        self?.pending = nil
        result(entry?.envelope)
      case "shareLink":
        result(self?.shareLink(call.arguments as? String) ?? false)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func detach() {
    channel.setMethodCallHandler(nil)
    pending = nil
  }

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions?
  ) -> Bool {
    guard let options = connectionOptions else { return false }
    let urls = options.urlContexts.map(\.url)
    let hasPaste = urls.contains(where: Self.isPaste)
    if let link = options.userActivities.lazy.compactMap(Self.inviteLink).first {
      offer(.link(link))
    } else if hasPaste {
      offer(.paste)
    } else {
      return false
    }

    let hasOnlyInviteActivities =
      options.notificationResponse == nil && options.shortcutItem == nil &&
      options.cloudKitShareMetadata == nil && options.handoffUserActivityType == nil &&
      options.userActivities.allSatisfy { Self.inviteLink($0) != nil }
    let ownsURLs = urls.allSatisfy(Self.isPaste)

    // Cold Flutter fallback inspects only one URL context. When this event has
    // both schemes, prepare the existing share plugin with the actual ShareMedia URL.
    if hasPaste, let shareURL = urls.first(where: Self.isShareMedia) {
      let forwarded = SwiftReceiveSharingIntentPlugin.instance.application(
        UIApplication.shared,
        didFinishLaunchingWithOptions: [UIApplication.LaunchOptionsKey.url: shareURL]
      )
      return forwarded && hasOnlyInviteActivities &&
        urls.allSatisfy { Self.isPaste($0) || Self.isShareMedia($0) }
    }
    return hasOnlyInviteActivities && ownsURLs
  }

  func scene(_ scene: UIScene, continue userActivity: NSUserActivity) -> Bool {
    guard let link = Self.inviteLink(userActivity) else { return false }
    offer(.link(link))
    return true
  }

  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) -> Bool {
    guard URLContexts.contains(where: { Self.isPaste($0.url) }) else { return false }
    offer(.paste)
    // The warm legacy fallback examines every context. Leave it available to ShareMedia.
    return URLContexts.allSatisfy { Self.isPaste($0.url) }
  }

  private func offer(_ entry: Entry) {
    pending = entry
    channel.invokeMethod("inviteAvailable", arguments: nil)
  }

  private func shareLink(_ raw: String?) -> Bool {
    guard let raw, Self.isInviteLink(raw) else { return false }
    let window = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .filter { $0.activationState == .foregroundActive }
      .flatMap(\.windows)
      .first(where: \.isKeyWindow)
    guard let presenter = window?.rootViewController,
      let view = presenter.viewIfLoaded,
      view.window != nil,
      presenter.presentedViewController == nil
    else { return false }

    let share = UIActivityViewController(activityItems: [raw], applicationActivities: nil)
    if let popover = share.popoverPresentationController {
      popover.sourceView = view
      popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
    }
    presenter.present(share, animated: true)
    return true
  }

  private static func isPaste(_ url: URL) -> Bool {
    url.absoluteString.utf8.elementsEqual(pasteURL)
  }

  private static func isShareMedia(_ url: URL) -> Bool {
    guard let bundle = Bundle.main.bundleIdentifier else { return false }
    return url.absoluteString.utf8.starts(with: "ShareMedia-\(bundle):".utf8)
  }

  private static func inviteLink(_ activity: NSUserActivity) -> String? {
    guard activity.activityType == NSUserActivityTypeBrowsingWeb,
      let raw = activity.webpageURL?.absoluteString,
      isInviteLink(raw)
    else { return nil }
    return raw
  }

  private static func isInviteLink(_ raw: String) -> Bool {
    let bytes = raw.utf8
    guard bytes.starts(with: invitePrefix) else { return false }
    let fragment = bytes.dropFirst(invitePrefix.count)
    return (1...maxFragmentLength).contains(fragment.count) &&
      fragment.allSatisfy { byte in
        (65...90).contains(byte) || (97...122).contains(byte) ||
          (48...57).contains(byte) || byte == 45 || byte == 95
      }
  }
}
