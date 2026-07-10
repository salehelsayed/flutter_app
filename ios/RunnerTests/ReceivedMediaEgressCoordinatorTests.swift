import Flutter
import Photos
import UIKit
import XCTest

@testable import Runner

final class ReceivedMediaEgressCoordinatorTests: XCTestCase {
  func testIOS13AttemptsPhotoKitWithoutLegacyAuthorizationAndMapsDenial() {
    let authorization = FakePhotoAuthorization(status: .denied)
    let userDeniedCode: Int
    if #available(iOS 15, *) {
      userDeniedCode = PHPhotosError.accessUserDenied.rawValue
      XCTAssertEqual(userDeniedCode, 3311)
    } else {
      userDeniedCode = 3311
    }
    let photos = FakePhotoLibrary(
      succeeded: false,
      error: NSError(domain: PHPhotosErrorDomain, code: userDeniedCode)
    )
    let completed = expectation(description: "iOS 13 denial")
    let coordinator = makeCoordinator(
      majorVersion: 13,
      authorization: authorization,
      photos: photos
    )

    coordinator.handle(call(destination: "photos")) { raw in
      let result = raw as! [String: Any]
      XCTAssertEqual(result["outcome"] as? String, "permissionDenied")
      XCTAssertEqual(
        (result["items"] as! [[String: Any]]).map { $0["outcome"] as? String },
        ["permissionDenied", "permissionDenied"]
      )
      completed.fulfill()
    }

    wait(for: [completed], timeout: 2)
    XCTAssertEqual(authorization.currentStatusReads, 0)
    XCTAssertEqual(authorization.legacyRequests, 0)
    XCTAssertEqual(authorization.addOnlyRequests, 0)
    XCTAssertEqual(photos.calls, 1)
  }

  func testPhotoPermissionMappingUsesActualPhotoKitAndCocoaPermissionErrors() {
    if #available(iOS 15, *) {
      let photoCodes = [
        PHPhotosError.accessRestricted.rawValue,
        PHPhotosError.accessUserDenied.rawValue,
      ]
      XCTAssertEqual(photoCodes, [3310, 3311])
      for code in photoCodes {
        XCTAssertEqual(
          ReceivedMediaEgressPolicy.photoFailureOutcome(
            error: NSError(domain: PHPhotosErrorDomain, code: code)
          ),
          "permissionDenied"
        )
      }
    }

    for code in [NSFileReadNoPermissionError, NSFileWriteNoPermissionError] {
      XCTAssertEqual(
        ReceivedMediaEgressPolicy.photoFailureOutcome(
          error: NSError(domain: NSCocoaErrorDomain, code: code)
        ),
        "permissionDenied"
      )
    }
    XCTAssertEqual(
      ReceivedMediaEgressPolicy.photoFailureOutcome(
        error: NSError(domain: PHPhotosErrorDomain, code: 3073)
      ),
      "platformFailure"
    )
  }

  func testIOS14RequestsOnlyAddAuthorizationAndDoesNotAttemptPhotosWhenDenied() {
    let authorization = FakePhotoAuthorization(status: .notDetermined, addOnlyResponse: .restricted)
    let photos = FakePhotoLibrary(succeeded: true)
    let completed = expectation(description: "iOS 14 denial")
    let coordinator = makeCoordinator(
      majorVersion: 14,
      authorization: authorization,
      photos: photos
    )

    coordinator.handle(call(destination: "photos")) { raw in
      XCTAssertEqual((raw as! [String: Any])["outcome"] as? String, "permissionDenied")
      completed.fulfill()
    }

    wait(for: [completed], timeout: 2)
    XCTAssertEqual(authorization.legacyRequests, 0)
    XCTAssertEqual(authorization.addOnlyRequests, 1)
    XCTAssertEqual(photos.calls, 0)
  }

  func testPhotoKitNonAuthorizationFailureIsAtomicAndPreservesSources() throws {
    let first = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("egress-a.jpg")
    let second = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("egress-b.mp4")
    try Data([1, 3, 3, 7]).write(to: first)
    try Data([2, 4, 6, 8]).write(to: second)
    defer { try? FileManager.default.removeItem(at: first); try? FileManager.default.removeItem(at: second) }
    let before = [try Data(contentsOf: first), try Data(contentsOf: second)]
    let photos = FakePhotoLibrary(succeeded: false, error: NSError(domain: "proof", code: 1))
    let completed = expectation(description: "atomic failure")
    let coordinator = makeCoordinator(majorVersion: 13, photos: photos)

    coordinator.handle(call(destination: "photos", paths: [first.path, second.path])) { raw in
      let result = raw as! [String: Any]
      XCTAssertEqual(result["outcome"] as? String, "platformFailure")
      XCTAssertEqual(
        (result["items"] as! [[String: Any]]).map { $0["outcome"] as? String },
        ["platformFailure", "platformFailure"]
      )
      completed.fulfill()
    }

    wait(for: [completed], timeout: 2)
    XCTAssertEqual(photos.receivedItems.map(\.attachmentId), ["a", "b"])
    XCTAssertEqual(try Data(contentsOf: first), before[0])
    XCTAssertEqual(try Data(contentsOf: second), before[1])
  }

  func testActualCoordinatorFailsWithoutPresenterAndResolverSelectsVisibleChild() {
    let failed = expectation(description: "missing presenter")
    let coordinator = makeCoordinator(majorVersion: 14, presenter: { nil })
    coordinator.handle(call(destination: "files")) { raw in
      XCTAssertEqual((raw as! [String: Any])["outcome"] as? String, "platformFailure")
      failed.fulfill()
    }
    wait(for: [failed], timeout: 2)

    let first = UIViewController()
    let visible = UIViewController()
    let navigation = UINavigationController(rootViewController: first)
    navigation.pushViewController(visible, animated: false)
    let tabs = UITabBarController()
    tabs.viewControllers = [UIViewController(), navigation]
    tabs.selectedIndex = 1
    XCTAssertTrue(ReceivedMediaEgressPresenterResolver.top(from: tabs) === visible)
  }

  func testActualCoordinatorConstructsLegacyAndCopyPickersAndFilesCancellationIsTruthful() {
    let legacyFactory = FakeControllerFactory()
    let legacyPresentation = FakePresentation()
    let cancelled = expectation(description: "legacy cancelled")
    let legacy = makeCoordinator(
      majorVersion: 13,
      factory: legacyFactory,
      presentation: legacyPresentation
    )
    legacy.handle(call(destination: "files")) { raw in
      XCTAssertEqual((raw as! [String: Any])["outcome"] as? String, "cancelled")
      cancelled.fulfill()
    }
    drainMainQueue()
    XCTAssertEqual(legacyFactory.fileModes, [.legacyExportToService])
    XCTAssertEqual(legacyFactory.fileURLs.map(\.count), [2])
    XCTAssertTrue(legacyPresentation.controllers.last === legacyFactory.lastPicker)
    legacy.documentPickerWasCancelled(legacyFactory.lastPicker!)
    wait(for: [cancelled], timeout: 2)

    let copyFactory = FakeControllerFactory()
    let copyPresentation = FakePresentation()
    let saved = expectation(description: "copy saved")
    let modern = makeCoordinator(
      majorVersion: 14,
      factory: copyFactory,
      presentation: copyPresentation
    )
    modern.handle(call(destination: "files")) { raw in
      XCTAssertEqual((raw as! [String: Any])["outcome"] as? String, "saved")
      saved.fulfill()
    }
    drainMainQueue()
    XCTAssertEqual(copyFactory.fileModes, [.copy])
    modern.documentPicker(copyFactory.lastPicker!, didPickDocumentsAt: copyFactory.fileURLs[0])
    wait(for: [saved], timeout: 2)
  }

  func testActualCoordinatorBusyReentryDismissalAndLateCallbackSettleOnce() {
    let factory = FakeControllerFactory()
    let presentation = FakePresentation()
    let firstCompleted = expectation(description: "first completion")
    var firstSettlements = 0
    let coordinator = makeCoordinator(
      majorVersion: 14,
      factory: factory,
      presentation: presentation
    )
    coordinator.handle(call(requestId: "first", destination: "files")) { _ in
      firstSettlements += 1
      firstCompleted.fulfill()
    }
    drainMainQueue()

    var busy: [String: Any]?
    coordinator.handle(call(requestId: "second", destination: "files")) { busy = $0 as? [String: Any] }
    XCTAssertEqual(busy?["outcome"] as? String, "busy")
    XCTAssertEqual(factory.fileModes.count, 1)

    let picker = factory.lastPicker!
    coordinator.documentPickerWasCancelled(picker)
    coordinator.documentPicker(picker, didPickDocumentsAt: factory.fileURLs[0])
    wait(for: [firstCompleted], timeout: 2)
    drainMainQueue()
    XCTAssertEqual(firstSettlements, 1)

    let thirdCompleted = expectation(description: "third completion")
    coordinator.handle(call(requestId: "third", destination: "files")) { _ in thirdCompleted.fulfill() }
    drainMainQueue()
    XCTAssertEqual(factory.fileModes.count, 2)
    coordinator.documentPickerWasCancelled(factory.lastPicker!)
    wait(for: [thirdCompleted], timeout: 2)
  }

  func testSharePresentationIsOrderedAnchoredAndBusyUntilControllerCompletion() {
    let factory = FakeControllerFactory()
    let presentation = FakePresentation(invokeCompletion: true)
    let presented = expectation(description: "share presented")
    let coordinator = makeCoordinator(
      majorVersion: 14,
      factory: factory,
      presentation: presentation
    )
    coordinator.handle(call(requestId: "share_one", destination: "share")) { raw in
      let result = raw as! [String: Any]
      XCTAssertEqual(result["outcome"] as? String, "presented")
      XCTAssertTrue((result["items"] as! [Any]).isEmpty)
      presented.fulfill()
    }
    wait(for: [presented], timeout: 2)
    XCTAssertEqual(factory.shareURLs.first?.map(\.lastPathComponent), ["a.jpg", "b.mp4"])
    XCTAssertNotNil(factory.lastShare?.popoverPresentationController?.sourceView)

    var busy: [String: Any]?
    coordinator.handle(call(requestId: "share_two", destination: "share")) { busy = $0 as? [String: Any] }
    XCTAssertEqual(busy?["outcome"] as? String, "busy")
    factory.lastShare?.completionWithItemsHandler?(nil, false, nil, nil)

    let presentedAgain = expectation(description: "share presented again")
    coordinator.handle(call(requestId: "share_three", destination: "share")) { _ in presentedAgain.fulfill() }
    wait(for: [presentedAgain], timeout: 2)
    XCTAssertEqual(factory.shareURLs.count, 2)
  }

  func testParserAndBusyEnvelopesPreserveOrderAndRedaction() {
    let arguments = call(destination: "files").arguments as! [String: Any]
    let request = ReceivedMediaEgressCoordinator.parse(arguments)
    XCTAssertNotNil(request)
    let busy = ReceivedMediaEgressPolicy.busyEnvelope(request!)
    XCTAssertEqual(busy["requestId"] as? String, "request_1")
    XCTAssertEqual(
      (busy["items"] as! [[String: Any]]).map { $0["attachmentId"] as? String },
      ["a", "b"]
    )
    XCTAssertNil(busy["sourcePath"])
    XCTAssertNil(ReceivedMediaEgressCoordinator.parse(arguments.merging(["unexpected": true]) { _, new in new }))
    XCTAssertNil(ReceivedMediaEgressCoordinator.parse(arguments.merging(["requestId": "../bad"]) { _, new in new }))
  }

  private func makeCoordinator(
    majorVersion: Int,
    authorization: ReceivedMediaEgressPhotoAuthorizationClient = FakePhotoAuthorization(status: .authorized),
    photos: ReceivedMediaEgressPhotoLibraryClient = FakePhotoLibrary(succeeded: true),
    presenter: @escaping () -> UIViewController? = { UIViewController() },
    factory: ReceivedMediaEgressControllerFactory = FakeControllerFactory(),
    presentation: FakePresentation = FakePresentation()
  ) -> ReceivedMediaEgressCoordinator {
    ReceivedMediaEgressCoordinator(
      messenger: EgressMockMessenger(),
      photoAuthorizationClient: authorization,
      photoLibraryClient: photos,
      majorVersion: majorVersion,
      presenterProvider: presenter,
      controllerFactory: factory,
      presentController: presentation.present
    )
  }

  private func call(
    requestId: String = "request_1",
    destination: String,
    paths: [String] = ["/tmp/a.jpg", "/tmp/b.mp4"]
  ) -> FlutterMethodCall {
    FlutterMethodCall(methodName: "perform", arguments: [
      "requestId": requestId,
      "destination": destination,
      "items": [
        ["attachmentId": "a", "sourcePath": paths[0], "mime": "image/jpeg", "displayName": "a.jpg"],
        ["attachmentId": "b", "sourcePath": paths[1], "mime": "video/mp4", "displayName": "b.mp4"],
      ],
    ])
  }

  private func drainMainQueue() {
    let drained = expectation(description: "main queue drained")
    DispatchQueue.main.async { drained.fulfill() }
    wait(for: [drained], timeout: 2)
  }
}

private final class FakePhotoAuthorization: ReceivedMediaEgressPhotoAuthorizationClient {
  private let status: ReceivedMediaEgressAuthorizationStatus
  var currentStatusReads = 0
  var currentStatus: ReceivedMediaEgressAuthorizationStatus {
    currentStatusReads += 1
    return status
  }
  let legacyResponse: ReceivedMediaEgressAuthorizationStatus
  let addOnlyResponse: ReceivedMediaEgressAuthorizationStatus
  var legacyRequests = 0
  var addOnlyRequests = 0

  init(
    status: ReceivedMediaEgressAuthorizationStatus,
    legacyResponse: ReceivedMediaEgressAuthorizationStatus = .authorized,
    addOnlyResponse: ReceivedMediaEgressAuthorizationStatus = .authorized
  ) {
    self.status = status
    self.legacyResponse = legacyResponse
    self.addOnlyResponse = addOnlyResponse
  }

  func requestLegacy(_ completion: @escaping (ReceivedMediaEgressAuthorizationStatus) -> Void) {
    legacyRequests += 1
    completion(legacyResponse)
  }

  func requestAddOnly(_ completion: @escaping (ReceivedMediaEgressAuthorizationStatus) -> Void) {
    addOnlyRequests += 1
    completion(addOnlyResponse)
  }
}

private final class FakePhotoLibrary: ReceivedMediaEgressPhotoLibraryClient {
  let succeeded: Bool
  let error: Error?
  var calls = 0
  var receivedItems: [ReceivedMediaEgressItem] = []

  init(succeeded: Bool, error: Error? = nil) {
    self.succeeded = succeeded
    self.error = error
  }

  func performChanges(
    items: [ReceivedMediaEgressItem],
    completion: @escaping (Bool, Error?) -> Void
  ) {
    calls += 1
    receivedItems = items
    completion(succeeded, error)
  }
}

private final class FakeControllerFactory: ReceivedMediaEgressControllerFactory {
  var fileModes: [ReceivedMediaEgressFilesExportMode] = []
  var fileURLs: [[URL]] = []
  var shareURLs: [[URL]] = []
  var lastPicker: UIDocumentPickerViewController?
  var lastShare: UIActivityViewController?

  func makeFiles(urls: [URL], mode: ReceivedMediaEgressFilesExportMode) -> UIDocumentPickerViewController {
    fileModes.append(mode)
    fileURLs.append(urls)
    for url in urls where !FileManager.default.fileExists(atPath: url.path) {
      FileManager.default.createFile(atPath: url.path, contents: Data([1]))
    }
    let picker = UIDocumentPickerViewController(urls: urls, in: .exportToService)
    lastPicker = picker
    return picker
  }

  func makeShare(urls: [URL]) -> UIActivityViewController {
    shareURLs.append(urls)
    let controller = UIActivityViewController(activityItems: urls, applicationActivities: nil)
    lastShare = controller
    return controller
  }
}

private final class FakePresentation {
  let invokeCompletion: Bool
  var controllers: [UIViewController] = []

  init(invokeCompletion: Bool = false) {
    self.invokeCompletion = invokeCompletion
  }

  func present(
    presenter: UIViewController,
    controller: UIViewController,
    completion: (() -> Void)?
  ) {
    controllers.append(controller)
    if invokeCompletion { completion?() }
  }
}

private final class EgressMockMessenger: NSObject, FlutterBinaryMessenger {
  func send(onChannel channel: String, message: Data?) {}
  func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) {}
  func setMessageHandlerOnChannel(
    _ channel: String,
    binaryMessageHandler handler: FlutterBinaryMessageHandler?
  ) -> FlutterBinaryMessengerConnection { 0 }
  func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}
}
