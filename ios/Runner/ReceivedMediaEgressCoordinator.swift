import Flutter
import Photos
import QuickLook
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

// 414: Quick Look for the `open` destination. A default keeps existing
// factories (and test fakes) source compatible.
extension ReceivedMediaEgressControllerFactory {
  func makePreview() -> QLPreviewController { QLPreviewController() }
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

  static func isPresentation(_ destination: String) -> Bool {
    destination == "share" || destination == "open"
  }

  static func busyEnvelope(_ request: ReceivedMediaEgressRequest) -> [String: Any] {
    isPresentation(request.destination)
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

final class ReceivedMediaEgressCoordinator: NSObject, UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate,
  QLPreviewControllerDataSource, QLPreviewControllerDelegate {
  private static let channelName = "mknoon/received_media_egress"
  private static let requestPattern = try! NSRegularExpression(pattern: "^[A-Za-z0-9_-]{1,64}$")
  private static let allowedMimes: Set<String> = [
    "image/jpeg", "image/png", "image/gif", "image/webp", "image/heic",
    "video/mp4", "video/quicktime", "video/webm",
    "application/pdf",
  ]
  private static let pdfMime = "application/pdf"

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
  // 414: the named temporary copy Quick Look shows; removed on dismiss.
  private var previewURL: URL?
  // 414: named copies handed to Files export and Share; removed when done.
  private var exportDirectory: URL?

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
    case "open": presentPreview(value, from: presenter)
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

  /// 414: exported files carry the document's display name (for example
  /// "Invoice.pdf") instead of the stored blob id. Items whose stored name
  /// already matches are passed as is; on any copy failure the stored files
  /// are used, so export never fails because of naming.
  private func exportURLs(_ request: ReceivedMediaEgressRequest) -> [URL] {
    let renamed = request.items.contains { $0.url.lastPathComponent != $0.displayName }
    guard renamed else { return request.items.map(\.url) }
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("mknoon-export-\(request.requestId)", isDirectory: true)
    do {
      try? FileManager.default.removeItem(at: directory)
      var urls: [URL] = []
      for (index, item) in request.items.enumerated() {
        // One folder per item keeps two equal display names apart.
        let folder = directory.appendingPathComponent("\(index)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let copy = folder.appendingPathComponent(item.displayName)
        try FileManager.default.copyItem(at: item.url, to: copy)
        urls.append(copy)
      }
      exportDirectory = directory
      return urls
    } catch {
      try? FileManager.default.removeItem(at: directory)
      return request.items.map(\.url)
    }
  }

  private func removeExportCopies() {
    if let directory = exportDirectory {
      try? FileManager.default.removeItem(at: directory)
    }
    exportDirectory = nil
  }

  private func presentFiles(_ value: Pending, from presenter: UIViewController) {
    let urls = exportURLs(value.request)
    let mode = ReceivedMediaEgressPolicy.filesExportMode(majorVersion: majorVersion)
    let picker = controllerFactory.makeFiles(urls: urls, mode: mode)
    picker.delegate = self
    picker.presentationController?.delegate = self
    retainedController = picker
    presentController(presenter, picker, nil)
  }

  private func presentShare(_ value: Pending, from presenter: UIViewController) {
    let controller = controllerFactory.makeShare(urls: exportURLs(value.request))
    if let popover = controller.popoverPresentationController {
      popover.sourceView = presenter.view
      popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
    }
    controller.completionWithItemsHandler = { [weak self] _, _, _, _ in
      self?.removeExportCopies()
      self?.retainedController = nil
      self?.pending = nil
    }
    retainedController = controller
    presentController(presenter, controller) { [weak self] in
      self?.returnPresented(value)
    }
  }

  /// 414: Quick Look shows the PDF inside its own out-of-process view
  /// service. The copy carries the document's display name for the title bar.
  private func presentPreview(_ value: Pending, from presenter: UIViewController) {
    guard let item = value.request.items.first else {
      finish(value, outcome: "platformFailure", items: [])
      return
    }
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("mknoon-preview-\(value.request.requestId)", isDirectory: true)
    let copy = directory.appendingPathComponent(item.displayName)
    do {
      try? FileManager.default.removeItem(at: directory)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try FileManager.default.copyItem(at: item.url, to: copy)
    } catch {
      try? FileManager.default.removeItem(at: directory)
      finish(value, outcome: "platformFailure", items: [])
      return
    }
    previewURL = copy
    let controller = controllerFactory.makePreview()
    controller.dataSource = self
    controller.delegate = self
    retainedController = controller
    presentController(presenter, controller) { [weak self] in
      self?.returnPresented(value)
    }
  }

  func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
    previewURL == nil ? 0 : 1
  }

  func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
    (previewURL ?? URL(fileURLWithPath: "/dev/null")) as NSURL
  }

  func previewControllerDidDismiss(_ controller: QLPreviewController) {
    if let url = previewURL {
      try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
    previewURL = nil
    retainedController = nil
    pending = nil
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
      // Files export has copied (or been cancelled) by now.
      if value.request.destination == "files" { self?.removeExportCopies() }
      self?.retainedController = nil
      self?.pending = nil
    }
  }

  private func failureItems(_ request: ReceivedMediaEgressRequest) -> [[String: Any]] {
    ReceivedMediaEgressPolicy.isPresentation(request.destination) ? [] : request.items.map { item($0.attachmentId, "platformFailure") }
  }

  static func parse(_ arguments: Any?) -> ReceivedMediaEgressRequest? {
    guard let map = arguments as? [String: Any], Set(map.keys) == ["requestId", "destination", "items"],
          let requestId = map["requestId"] as? String, validRequestId(requestId),
          let destination = map["destination"] as? String, ["photos", "files", "share", "open"].contains(destination),
          let rawItems = map["items"] as? [[String: Any]], !rawItems.isEmpty, rawItems.count <= 10,
          destination != "open" || rawItems.count == 1 else { return nil }
    var ids = Set<String>()
    var items: [ReceivedMediaEgressItem] = []
    for raw in rawItems {
      guard Set(raw.keys) == ["attachmentId", "sourcePath", "mime", "displayName"],
            let id = raw["attachmentId"] as? String, !id.isEmpty, ids.insert(id).inserted,
            let source = raw["sourcePath"] as? String, !source.isEmpty,
            let mime = raw["mime"] as? String, Self.allowedMimes.contains(mime),
            let display = raw["displayName"] as? String, !display.isEmpty,
            !display.contains("/"), !display.contains("\\"),
            // 414: a PDF never goes to Photos; `open` takes PDFs only.
            !(destination == "photos" && mime == Self.pdfMime),
            destination != "open" || mime == Self.pdfMime else { return nil }
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
