import Flutter
import Photos
import UIKit

enum ReceivedMediaEgressPhotosAuthorizationMode { case addAttempt, addOnly }
enum ReceivedMediaEgressFilesExportMode { case legacyExportToService, copy }
enum ReceivedMediaEgressAuthorizationStatus { case notDetermined, authorized, limited, denied, restricted }
enum ReceivedMediaEgressAuthorizationDecision { case proceed, permissionDenied }

protocol ReceivedMediaEgressPhotoAuthorizationClient {
  var currentStatus: ReceivedMediaEgressAuthorizationStatus { get }
  func requestLegacy(_ completion: @escaping (ReceivedMediaEgressAuthorizationStatus) -> Void)
  func requestAddOnly(_ completion: @escaping (ReceivedMediaEgressAuthorizationStatus) -> Void)
}

protocol ReceivedMediaEgressPhotoLibraryClient {
  func performChanges(
    items: [ReceivedMediaEgressItem],
    completion: @escaping (Bool, Error?) -> Void
  )
}

final class ReceivedMediaEgressSystemPhotoAuthorizationClient: ReceivedMediaEgressPhotoAuthorizationClient {
  var currentStatus: ReceivedMediaEgressAuthorizationStatus {
    if #available(iOS 14, *) {
      return Self.map(PHPhotoLibrary.authorizationStatus(for: .addOnly))
    }
    return Self.map(PHPhotoLibrary.authorizationStatus())
  }

  func requestLegacy(_ completion: @escaping (ReceivedMediaEgressAuthorizationStatus) -> Void) {
    PHPhotoLibrary.requestAuthorization { completion(Self.map($0)) }
  }

  func requestAddOnly(_ completion: @escaping (ReceivedMediaEgressAuthorizationStatus) -> Void) {
    if #available(iOS 14, *) {
      PHPhotoLibrary.requestAuthorization(for: .addOnly) { completion(Self.map($0)) }
    } else {
      completion(.notDetermined)
    }
  }

  private static func map(_ status: PHAuthorizationStatus) -> ReceivedMediaEgressAuthorizationStatus {
    switch status {
    case .notDetermined: return .notDetermined
    case .authorized: return .authorized
    case .denied: return .denied
    case .restricted: return .restricted
    case .limited: return .limited
    @unknown default: return .denied
    }
  }
}

enum ReceivedMediaEgressPhotosAuthorizer {
  static func authorize(
    majorVersion: Int,
    client: ReceivedMediaEgressPhotoAuthorizationClient,
    completion: @escaping (ReceivedMediaEgressAuthorizationDecision) -> Void
  ) {
    // iOS 13 has no add-only authorization query/request API. Requesting the
    // legacy status here would expand an egress-only feature into read/write
    // library access. Attempt the add under NSPhotoLibraryAddUsageDescription
    // and classify the performChanges error instead.
    if majorVersion < 14 {
      completion(.proceed)
      return
    }
    func decide(_ status: ReceivedMediaEgressAuthorizationStatus) {
      completion(status == .authorized || status == .limited ? .proceed : .permissionDenied)
    }
    if client.currentStatus != .notDetermined {
      decide(client.currentStatus)
    } else {
      client.requestAddOnly(decide)
    }
  }
}

final class ReceivedMediaEgressSystemPhotoLibraryClient: ReceivedMediaEgressPhotoLibraryClient {
  func performChanges(
    items: [ReceivedMediaEgressItem],
    completion: @escaping (Bool, Error?) -> Void
  ) {
    PHPhotoLibrary.shared().performChanges({
      for media in items {
        let creation = PHAssetCreationRequest.forAsset()
        let type: PHAssetResourceType = media.mime.hasPrefix("video/") ? .video : .photo
        creation.addResource(with: type, fileURL: media.url, options: nil)
      }
    }, completionHandler: completion)
  }
}

protocol ReceivedMediaEgressControllerFactory {
  func makeFiles(urls: [URL], mode: ReceivedMediaEgressFilesExportMode) -> UIDocumentPickerViewController
  func makeShare(urls: [URL]) -> UIActivityViewController
}

final class ReceivedMediaEgressSystemControllerFactory: ReceivedMediaEgressControllerFactory {
  func makeFiles(urls: [URL], mode: ReceivedMediaEgressFilesExportMode) -> UIDocumentPickerViewController {
    switch mode {
    case .copy:
      if #available(iOS 14, *) {
        return UIDocumentPickerViewController(forExporting: urls, asCopy: true)
      }
      return UIDocumentPickerViewController(urls: urls, in: .exportToService)
    case .legacyExportToService:
      return UIDocumentPickerViewController(urls: urls, in: .exportToService)
    }
  }

  func makeShare(urls: [URL]) -> UIActivityViewController {
    UIActivityViewController(activityItems: urls, applicationActivities: nil)
  }
}

enum ReceivedMediaEgressPresenterResolver {
  static func top(from root: UIViewController?) -> UIViewController? {
    var controller = root
    while true {
      if let presented = controller?.presentedViewController { controller = presented; continue }
      if let navigation = controller as? UINavigationController { controller = navigation.visibleViewController; continue }
      if let tabs = controller as? UITabBarController { controller = tabs.selectedViewController; continue }
      return controller
    }
  }
}

enum ReceivedMediaEgressPolicy {
  static func photosAuthorizationMode(majorVersion: Int) -> ReceivedMediaEgressPhotosAuthorizationMode {
    majorVersion >= 14 ? .addOnly : .addAttempt
  }

  static func filesExportMode(majorVersion: Int) -> ReceivedMediaEgressFilesExportMode {
    majorVersion >= 14 ? .copy : .legacyExportToService
  }

  static func atomicPhotoOutcomes(ids: [String], succeeded: Bool) -> [[String: Any]] {
    ids.map { ["attachmentId": $0, "outcome": succeeded ? "saved" : "platformFailure"] }
  }

  static func photoFailureOutcome(error: Error?) -> String {
    guard let error = error as NSError? else { return "platformFailure" }
    // These PhotoKit cases were introduced in iOS 15. Keep the raw values so
    // denial returned while this iOS 13-targeted binary runs on older systems
    // is still classified, and use the SDK cases whenever they are available.
    var photoAuthorizationCodes: Set<Int> = [3310, 3311]
    if #available(iOS 15, *) {
      photoAuthorizationCodes.insert(PHPhotosError.accessRestricted.rawValue)
      photoAuthorizationCodes.insert(PHPhotosError.accessUserDenied.rawValue)
    }
    let cocoaAuthorizationCodes: Set<Int> = [NSFileReadNoPermissionError, NSFileWriteNoPermissionError]
    if (error.domain == PHPhotosErrorDomain && photoAuthorizationCodes.contains(error.code)) ||
       (error.domain == NSCocoaErrorDomain && cocoaAuthorizationCodes.contains(error.code)) {
      return "permissionDenied"
    }
    return "platformFailure"
  }

  static func saveEnvelope(_ request: ReceivedMediaEgressRequest, outcome: String) -> [String: Any] {
    [
      "requestId": request.requestId,
      "outcome": outcome,
      "items": request.items.map { ["attachmentId": $0.attachmentId, "outcome": outcome] },
    ]
  }

  static func busyEnvelope(_ request: ReceivedMediaEgressRequest) -> [String: Any] {
    request.destination == "share"
      ? ["requestId": request.requestId, "outcome": "busy", "items": []]
      : saveEnvelope(request, outcome: "busy")
  }
}

final class ReceivedMediaEgressCompletionLatch {
  private let lock = NSLock()
  private var completed = false

  func claim() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard !completed else { return false }
    completed = true
    return true
  }
}

struct ReceivedMediaEgressItem {
  let attachmentId: String
  let sourcePath: String
  let mime: String
  let displayName: String
  var url: URL { URL(fileURLWithPath: sourcePath) }
}

struct ReceivedMediaEgressRequest {
  let requestId: String
  let destination: String
  let items: [ReceivedMediaEgressItem]
}

final class ReceivedMediaEgressCoordinator: NSObject, UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate {
  private static let channelName = "mknoon/received_media_egress"
  private static let requestPattern = try! NSRegularExpression(pattern: "^[A-Za-z0-9_-]{1,64}$")
  private static let allowedMimes: Set<String> = [
    "image/jpeg", "image/png", "image/gif", "image/webp", "image/heic",
    "video/mp4", "video/quicktime", "video/webm",
  ]

  private struct Pending {
    let request: ReceivedMediaEgressRequest
    let result: FlutterResult
    let latch: ReceivedMediaEgressCompletionLatch
  }

  private let channel: FlutterMethodChannel
  private let photoAuthorizationClient: ReceivedMediaEgressPhotoAuthorizationClient
  private let photoLibraryClient: ReceivedMediaEgressPhotoLibraryClient
  private let majorVersion: Int
  private let presenterProvider: () -> UIViewController?
  private let controllerFactory: ReceivedMediaEgressControllerFactory
  private let presentController: (UIViewController, UIViewController, (() -> Void)?) -> Void
  private var pending: Pending?
  private var retainedController: UIViewController?

  init(
    messenger: FlutterBinaryMessenger,
    photoAuthorizationClient: ReceivedMediaEgressPhotoAuthorizationClient = ReceivedMediaEgressSystemPhotoAuthorizationClient(),
    photoLibraryClient: ReceivedMediaEgressPhotoLibraryClient = ReceivedMediaEgressSystemPhotoLibraryClient(),
    majorVersion: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
    presenterProvider: (() -> UIViewController?)? = nil,
    controllerFactory: ReceivedMediaEgressControllerFactory = ReceivedMediaEgressSystemControllerFactory(),
    presentController: @escaping (UIViewController, UIViewController, (() -> Void)?) -> Void = {
      presenter, controller, completion in presenter.present(controller, animated: true, completion: completion)
    }
  ) {
    channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    self.photoAuthorizationClient = photoAuthorizationClient
    self.photoLibraryClient = photoLibraryClient
    self.majorVersion = majorVersion
    self.presenterProvider = presenterProvider ?? Self.activePresenter
    self.controllerFactory = controllerFactory
    self.presentController = presentController
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in self?.handle(call, result: result) }
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "perform" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let request = Self.parse(call.arguments) else {
      result(FlutterError(code: "invalid_arguments", message: "invalid request", details: nil))
      return
    }
    guard pending == nil else {
      result(ReceivedMediaEgressPolicy.busyEnvelope(request))
      return
    }
    let value = Pending(request: request, result: result, latch: ReceivedMediaEgressCompletionLatch())
    pending = value
    DispatchQueue.main.async { [weak self] in self?.begin(value) }
  }

  private func begin(_ value: Pending) {
    guard let presenter = presenterProvider() else {
      finish(value, outcome: "platformFailure", items: failureItems(value.request))
      return
    }
    switch value.request.destination {
    case "photos": savePhotos(value)
    case "files": presentFiles(value, from: presenter)
    case "share": presentShare(value, from: presenter)
    default: finish(value, outcome: "platformFailure", items: failureItems(value.request))
    }
  }

  private func savePhotos(_ value: Pending) {
    ReceivedMediaEgressPhotosAuthorizer.authorize(
      majorVersion: majorVersion,
      client: photoAuthorizationClient
    ) { [weak self] decision in
      guard let self else { return }
      guard decision == .proceed else {
        let items = value.request.items.map { self.item($0.attachmentId, "permissionDenied") }
        self.finish(value, outcome: "permissionDenied", items: items)
        return
      }
      self.performPhotoChanges(value)
    }
  }

  private func performPhotoChanges(_ value: Pending) {
    photoLibraryClient.performChanges(items: value.request.items) { [weak self] succeeded, error in
      let outcome = succeeded ? "saved" : ReceivedMediaEgressPolicy.photoFailureOutcome(error: error)
      let items = value.request.items.map { ["attachmentId": $0.attachmentId, "outcome": outcome] }
      self?.finish(value, outcome: outcome, items: items)
    }
  }

  private func presentFiles(_ value: Pending, from presenter: UIViewController) {
    let urls = value.request.items.map(\.url)
    let mode = ReceivedMediaEgressPolicy.filesExportMode(majorVersion: majorVersion)
    let picker = controllerFactory.makeFiles(urls: urls, mode: mode)
    picker.delegate = self
    picker.presentationController?.delegate = self
    retainedController = picker
    presentController(presenter, picker, nil)
  }

  private func presentShare(_ value: Pending, from presenter: UIViewController) {
    let controller = controllerFactory.makeShare(urls: value.request.items.map(\.url))
    if let popover = controller.popoverPresentationController {
      popover.sourceView = presenter.view
      popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
    }
    controller.completionWithItemsHandler = { [weak self] _, _, _, _ in
      self?.retainedController = nil
      self?.pending = nil
    }
    retainedController = controller
    presentController(presenter, controller) { [weak self] in
      self?.returnPresented(value)
    }
  }

  private func returnPresented(_ value: Pending) {
    guard value.latch.claim() else { return }
    value.result(envelope(value.request.requestId, "presented", []))
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    guard let value = pending else { return }
    let envelope = ReceivedMediaEgressPolicy.saveEnvelope(value.request, outcome: "cancelled")
    finish(value, outcome: "cancelled", items: envelope["items"] as! [[String: Any]])
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let value = pending else { return }
    let envelope = ReceivedMediaEgressPolicy.saveEnvelope(value.request, outcome: "saved")
    finish(value, outcome: "saved", items: envelope["items"] as! [[String: Any]])
  }

  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    if let picker = retainedController as? UIDocumentPickerViewController { documentPickerWasCancelled(picker) }
    else { retainedController = nil; pending = nil }
  }

  private func finish(_ value: Pending, outcome: String, items: [[String: Any]]) {
    DispatchQueue.main.async { [weak self] in
      guard value.latch.claim() else { return }
      value.result(self?.envelope(value.request.requestId, outcome, items))
      self?.retainedController = nil
      self?.pending = nil
    }
  }

  private func failureItems(_ request: ReceivedMediaEgressRequest) -> [[String: Any]] {
    request.destination == "share" ? [] : request.items.map { item($0.attachmentId, "platformFailure") }
  }

  static func parse(_ arguments: Any?) -> ReceivedMediaEgressRequest? {
    guard let map = arguments as? [String: Any], Set(map.keys) == ["requestId", "destination", "items"],
          let requestId = map["requestId"] as? String, validRequestId(requestId),
          let destination = map["destination"] as? String, ["photos", "files", "share"].contains(destination),
          let rawItems = map["items"] as? [[String: Any]], !rawItems.isEmpty, rawItems.count <= 10 else { return nil }
    var ids = Set<String>()
    var items: [ReceivedMediaEgressItem] = []
    for raw in rawItems {
      guard Set(raw.keys) == ["attachmentId", "sourcePath", "mime", "displayName"],
            let id = raw["attachmentId"] as? String, !id.isEmpty, ids.insert(id).inserted,
            let source = raw["sourcePath"] as? String, !source.isEmpty,
            let mime = raw["mime"] as? String, Self.allowedMimes.contains(mime),
            let display = raw["displayName"] as? String, !display.isEmpty,
            !display.contains("/"), !display.contains("\\") else { return nil }
      items.append(ReceivedMediaEgressItem(attachmentId: id, sourcePath: source, mime: mime, displayName: display))
    }
    return ReceivedMediaEgressRequest(requestId: requestId, destination: destination, items: items)
  }

  private static func validRequestId(_ value: String) -> Bool {
    Self.requestPattern.firstMatch(in: value, range: NSRange(location: 0, length: value.utf16.count)) != nil
  }

  private static func activePresenter() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
    let root = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
    return ReceivedMediaEgressPresenterResolver.top(from: root)
  }

  private func item(_ attachmentId: String, _ outcome: String) -> [String: Any] {
    ["attachmentId": attachmentId, "outcome": outcome]
  }

  private func envelope(_ requestId: String, _ outcome: String, _ items: [[String: Any]]) -> [String: Any] {
    ["requestId": requestId, "outcome": outcome, "items": items]
  }
}
