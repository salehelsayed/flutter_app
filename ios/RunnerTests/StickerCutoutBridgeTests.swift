import CoreGraphics
import Flutter
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers
import XCTest
import zlib

@testable import Runner

/// The fake replaces Vision only. Input decode/orientation, output bytes,
/// channel envelopes and filesystem ownership belong to the production bridge.
final class StickerCutoutBridgeTests: XCTestCase {
  private var roots: [URL] = []
  private var originals: [URL: Data] = [:]
  private var owners: [StickerCutoutPlugin] = []

  override func tearDownWithError() throws {
    onMain { owners.forEach { $0.close() } }
    owners.removeAll()
    for (url, data) in originals {
      XCTAssertEqual(try Data(contentsOf: url), data, "caller or foreign file changed")
    }
    for root in roots { try? FileManager.default.removeItem(at: root) }
    originals.removeAll()
    roots.removeAll()
    try super.tearDownWithError()
  }

  func testBelowIOS17IsUnsupportedWithoutCallingTheBackend() throws {
    let h = harness(majorVersion: 16)
    let job = try makeJob()
    assertReply(try call(h, "availability"), equals: "unsupported")
    assertError(try call(h, "extract", job.arguments), code: "unsupported")
    XCTAssertEqual(h.backend.count, 0)
    XCTAssertFalse(FileManager.default.fileExists(atPath: job.output.path))
  }

  func testIOS17ReadinessUsesBackendSupportWithoutStartingSegmentation() throws {
    let ready = harness()
    assertReply(try call(ready, "availability"), equals: "ready")
    XCTAssertEqual(ready.backend.count, 0)
    let unavailable = harness(available: false)
    assertReply(try call(unavailable, "availability"), equals: "unsupported")
    assertError(try call(unavailable, "extract", makeJob().arguments), code: "unsupported")
    XCTAssertEqual(unavailable.backend.count, 0)
  }

  func testAllEightImageIOOrientationsReachVisionUprightAndKeepPixels() throws {
    let colors: [[UInt8]] = [
      [255, 0, 0, 255], [0, 255, 0, 255], [0, 0, 255, 255],
      [255, 255, 0, 255], [0, 255, 255, 255], [255, 0, 255, 255],
    ]
    let expected = [
      [0, 1, 2, 3, 4, 5], [2, 1, 0, 5, 4, 3],
      [5, 4, 3, 2, 1, 0], [3, 4, 5, 0, 1, 2],
      [0, 3, 1, 4, 2, 5], [3, 0, 4, 1, 5, 2],
      [5, 2, 4, 1, 3, 0], [2, 5, 1, 4, 0, 3],
    ]
    let h = harness()
    for orientation in 1...8 {
      let source = try sourceImage(
        width: 3, height: 2, rgba: colors.flatMap { $0 }, orientation: orientation
      )
      let job = try makeJob(source: source)
      let (reply, request) = try start(h, job)
      let width = orientation <= 4 ? 3 : 2
      let height = orientation <= 4 ? 2 : 3
      XCTAssertEqual(request.image.width, width)
      XCTAssertEqual(request.image.height, height)
      XCTAssertFalse(request.wasMainThread, "Vision/decode work must not block the channel thread")
      XCTAssertEqual(try rgba(request.image), expected[orientation - 1].flatMap { colors[$0] })
      request.complete(.success(request.image))
      let result = try descriptor(reply)
      XCTAssertEqual(result["width"] as? Int, width)
      XCTAssertEqual(result["height"] as? Int, height)
      let png = try strictPNG(job.output)
      XCTAssertEqual(png.rgba, expected[orientation - 1].flatMap { colors[$0] })
    }
  }

  func testImageIOThumbnailCapsBothAxesAfterOrientationWithoutUpscalingSmallInput() throws {
    let h = harness()
    let source = try sourceImage(
      width: 4096, height: 2048,
      rgba: [UInt8](repeating: 255, count: 4096 * 2048 * 4),
      orientation: 6
    )
    let job = try makeJob(source: source)
    let (reply, request) = try start(h, job)
    XCTAssertEqual(request.image.width, 1024)
    XCTAssertEqual(request.image.height, 2048)
    request.complete(.success(nil))
    assertNilReply(reply)
    XCTAssertFalse(FileManager.default.fileExists(atPath: job.output.path))
  }

  func testFullCanvasPNGHasTightBoundsNoMetadataAndNoHiddenRGB() throws {
    let h = harness()
    let job = try makeJob()
    let (reply, request) = try start(h, job)
    var pixels = Array<[UInt8]>(repeating: [97, 83, 71, 0], count: 12).flatMap { $0 }
    pixels.replaceSubrange(4..<8, with: [220, 40, 20, 255])
    pixels.replaceSubrange(8..<12, with: [60, 90, 120, 128])
    request.complete(.success(try makeImage(width: 4, height: 3, rgba: pixels)))
    let result = try descriptor(reply)
    XCTAssertEqual(Set(result.keys), Set(["width", "height", "subjectBounds"]))
    XCTAssertEqual(result["width"] as? Int, 4)
    XCTAssertEqual(result["height"] as? Int, 3)
    assertBounds(result, left: 0.25, top: 0, right: 0.75, bottom: 1.0 / 3.0)
    let png = try strictPNG(job.output)
    XCTAssertEqual(png.width, 4)
    XCTAssertEqual(png.height, 3)
    XCTAssertEqual(png.rgba[7], 255)
    XCTAssertTrue((127...129).contains(Int(png.rgba[11])))
    for i in stride(from: 0, to: png.rgba.count, by: 4) where png.rgba[i + 3] == 0 {
      XCTAssertEqual(Array(png.rgba[i..<(i + 3)]), [0, 0, 0])
    }
    let bytes = try Data(contentsOf: job.output)
    XCTAssertLessThanOrEqual(bytes.count, 24 * 1024 * 1024)
    let imageSource = try XCTUnwrap(CGImageSourceCreateWithData(bytes as CFData, nil))
    XCTAssertEqual(CGImageSourceGetCount(imageSource), 1)
    let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any]
    for key in [kCGImagePropertyExifDictionary, kCGImagePropertyGPSDictionary,
                kCGImagePropertyTIFFDictionary, kCGImagePropertyOrientation] {
      XCTAssertNil(properties?[key as String])
    }
    let cancel = try call(h, "cancel", ["jobId": job.id])
    assertNilReply(cancel)
    XCTAssertEqual(h.backend.cancels, 0)
    XCTAssertEqual(try Data(contentsOf: job.output), bytes)
  }

  func testDifferentRemovedBackgroundAndPrivateMetadataProduceIdenticalPNG() throws {
    let h = harness()
    var outputs: [Data] = []
    for background: UInt8 in [30, 210] {
      var pixels = Array<[UInt8]>(repeating: [background, 40, 80, 255], count: 12).flatMap { $0 }
      pixels.replaceSubrange(20..<24, with: [100, 150, 200, 255])
      let source = try sourceImage(width: 4, height: 3, rgba: pixels, comment: "private-\(background)")
      let job = try makeJob(source: source)
      let (reply, request) = try start(h, job)
      var masked = try rgba(request.image)
      for index in 0..<12 where index != 5 { masked[index * 4 + 3] = 0 }
      request.complete(.success(try makeImage(width: 4, height: 3, rgba: masked)))
      _ = try descriptor(reply)
      _ = try strictPNG(job.output)
      outputs.append(try Data(contentsOf: job.output))
    }
    XCTAssertEqual(outputs[0], outputs[1])
  }

  func testNoSubjectAndAllTransparentResultReturnNullWithoutPublishing() throws {
    let h = harness()
    for transparentImage in [false, true] {
      let job = try makeJob()
      let (reply, request) = try start(h, job)
      let empty = transparentImage
        ? try makeImage(width: 4, height: 3, rgba: Array(repeating: 0, count: 48)) : nil
      request.complete(.success(empty))
      assertNilReply(reply)
      XCTAssertFalse(FileManager.default.fileExists(atPath: job.output.path))
      XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: job.output.deletingLastPathComponent().path), [])
    }
  }

  func testBackendCanvasMismatchFailsWithoutPublishing() throws {
    let h = harness()
    let job = try makeJob()
    let (reply, request) = try start(h, job)
    request.complete(.success(try makeImage(width: 1, height: 1, rgba: [1, 2, 3, 255])))
    assertError(reply, code: "failed")
    XCTAssertFalse(FileManager.default.fileExists(atPath: job.output.path))
  }

  func testMissingEmptyCorruptAndDirectorySourcesFailBeforeVision() throws {
    let h = harness()
    let root = try makeRoot(prefix: "cutout-invalid-source-")
    let corrupt = root.appendingPathComponent("corrupt.jpg")
    try preserve(Data("not an image private-content".utf8), at: corrupt)
    let empty = root.appendingPathComponent("empty.jpg")
    try preserve(Data(), at: empty)
    for source in [root.appendingPathComponent("missing.jpg"), empty, corrupt, root] {
      let job = try makeJob(source: source)
      assertError(try call(h, "extract", job.arguments), code: "invalidSource")
      XCTAssertFalse(FileManager.default.fileExists(atPath: job.output.path))
    }
    XCTAssertEqual(h.backend.count, 0)
  }

  func testBackendFailureIsRedactedAndReleasesAdmissionForRetry() throws {
    let h = harness()
    let failed = try makeJob()
    let (reply, request) = try start(h, failed)
    request.complete(.failure(NSError(
      domain: failed.source.path, code: 99,
      userInfo: [NSLocalizedDescriptionKey: "private-image-data \(failed.source.path)"]
    )))
    assertError(reply, code: "failed")
    XCTAssertFalse(FileManager.default.fileExists(atPath: failed.output.path))
    let next = try makeJob()
    let (success, pending) = try start(h, next)
    pending.complete(.success(pending.image))
    _ = try descriptor(success)
    _ = try strictPNG(next.output)
  }

  func testMismatchedJobDirectoryAndUnexpectedFilenameAreRejectedWithoutTouchingForeignFiles() throws {
    let h = harness()
    let job = try makeJob()
    let foreignRoot = try makeRoot(prefix: "foreign-cutout-")
    let foreign = foreignRoot.appendingPathComponent("result.png")
    try preserve(Data("foreign-owned".utf8), at: foreign)
    var wrongID = job.arguments
    wrongID["jobId"] = "mknoon-sticker-cutout-other"
    var wrongRoot = job.arguments
    wrongRoot["outputPath"] = foreign.path
    var wrongName = job.arguments
    wrongName["outputPath"] = job.output.deletingLastPathComponent().appendingPathComponent("other.png").path
    for arguments in [wrongID, wrongRoot, wrongName] {
      assertError(try call(h, "extract", arguments), code: "failed")
    }
    XCTAssertEqual(h.backend.count, 0)
    XCTAssertFalse(FileManager.default.fileExists(atPath: job.output.path))
  }

  func testExistingOutputAndSymlinksCannotTransferOwnershipOfCallerFiles() throws {
    let h = harness()
    let job = try makeJob()
    try preserve(Data("already-owned-output".utf8), at: job.output)
    assertError(try call(h, "extract", job.arguments), code: "failed")
    let linked = try makeJob()
    try FileManager.default.createSymbolicLink(at: linked.output, withDestinationURL: job.source)
    assertError(try call(h, "extract", linked.arguments), code: "failed")
    XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: linked.output.path), job.source.path)
    let alias = FileManager.default.temporaryDirectory
      .appendingPathComponent("mknoon-sticker-cutout-\(UUID().uuidString)")
    roots.append(alias)
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: linked.output.deletingLastPathComponent())
    var arguments = linked.arguments
    arguments["jobId"] = alias.lastPathComponent
    arguments["outputPath"] = alias.appendingPathComponent("result.png").path
    assertError(try call(h, "extract", arguments), code: "failed")
    XCTAssertEqual(h.backend.count, 0)
  }

  func testConcurrentExtractIsUnavailableAndDoesNotStartASecondVisionJob() throws {
    let h = harness()
    let first = try makeJob()
    let (reply, request) = try start(h, first)
    let second = try makeJob()
    assertError(try call(h, "extract", second.arguments), code: "unavailable")
    XCTAssertEqual(h.backend.count, 1)
    XCTAssertEqual(reply.count, 0)
    request.complete(.success(request.image))
    _ = try descriptor(reply)
    XCTAssertFalse(FileManager.default.fileExists(atPath: second.output.path))
  }

  func testWrongJobCancellationDoesNotCancelOrSettleTheActiveJob() throws {
    let h = harness()
    let job = try makeJob()
    let (reply, request) = try start(h, job)
    assertNilReply(try call(h, "cancel", ["jobId": "different-job"]))
    XCTAssertEqual(h.backend.cancels, 0)
    XCTAssertEqual(reply.count, 0)
    request.complete(.success(request.image))
    _ = try descriptor(reply)
  }

  func testCancelSettlesOnceAllowsRetryAndLateOldCompletionCannotAffectSuccessor() throws {
    let h = harness()
    let old = try makeJob()
    let (oldReply, oldRequest) = try start(h, old)
    assertNilReply(try call(h, "cancel", ["jobId": old.id]))
    assertNilReply(oldReply)
    assertNilReply(try call(h, "cancel", ["jobId": old.id]))
    XCTAssertEqual(h.backend.cancels, 1)
    let next = try makeJob()
    let (nextReply, nextRequest) = try start(h, next)
    oldRequest.complete(.success(oldRequest.image))
    drainMain()
    assertError(try call(h, "extract", makeJob().arguments), code: "unavailable")
    XCTAssertEqual(nextReply.count, 0)
    XCTAssertEqual(h.backend.count, 2)
    nextRequest.complete(.success(nextRequest.image))
    _ = try descriptor(nextReply)
    let published = try Data(contentsOf: next.output)
    oldRequest.complete(.failure(NSError(domain: "late-private", code: 1)))
    drainMain()
    XCTAssertEqual(oldReply.count, 1)
    XCTAssertEqual(nextReply.count, 1)
    XCTAssertFalse(FileManager.default.fileExists(atPath: old.output.path))
    XCTAssertEqual(try Data(contentsOf: next.output), published)
  }

  func testDuplicateBackendCompletionCannotReplyTwiceOrDeletePublishedOutput() throws {
    let h = harness()
    let job = try makeJob()
    let (reply, request) = try start(h, job)
    request.complete(.success(request.image))
    _ = try descriptor(reply)
    let before = try Data(contentsOf: job.output)
    request.complete(.failure(NSError(domain: "duplicate", code: 2)))
    request.complete(.success(nil))
    drainMain()
    XCTAssertEqual(reply.count, 1)
    XCTAssertEqual(try Data(contentsOf: job.output), before)
  }

  func testDetachSettlesPendingOnceAndSuppressesLatePublication() throws {
    let h = harness()
    let job = try makeJob()
    let (reply, request) = try start(h, job)
    let registrar = CutoutRegistrar(messenger: h.messenger)
    onMain {
      h.owner.detachFromEngine(for: registrar)
      h.owner.close()
    }
    assertNilReply(reply)
    XCTAssertNil(h.messenger.handler)
    XCTAssertEqual(h.messenger.removals, 1)
    XCTAssertEqual(h.backend.cancels, 1)
    request.complete(.success(request.image))
    drainMain()
    XCTAssertEqual(reply.count, 1)
    XCTAssertFalse(FileManager.default.fileExists(atPath: job.output.path))
  }

  func testOldOwnerDetachCannotRemoveReplacementChannelOrItsActiveJob() throws {
    let old = harness()
    onMain { old.owner.close() }
    let next = harness(messenger: old.messenger)
    let job = try makeJob()
    let (reply, request) = try start(next, job)
    onMain { old.owner.detachFromEngine(for: CutoutRegistrar(messenger: old.messenger)) }
    XCTAssertNotNil(next.messenger.handler)
    XCTAssertEqual(next.backend.cancels, 0)
    assertReply(try call(next, "availability"), equals: "ready")
    request.complete(.success(request.image))
    _ = try descriptor(reply)
    _ = try strictPNG(job.output)
  }

  func testRegisterPublishesDetachableOwnerAndDeinitClosesTheChannel() throws {
    try onMain {
      let messenger = CutoutMessenger()
      let registrar = CutoutRegistrar(messenger: messenger)
      StickerCutoutPlugin.register(with: registrar)
      let published = try XCTUnwrap(registrar.published as? StickerCutoutPlugin)
      XCTAssertNotNil(messenger.handler)
      published.detachFromEngine(for: registrar)
      XCTAssertNil(messenger.handler)
      XCTAssertEqual(messenger.removals, 1)
      let other = CutoutMessenger()
      weak var weakOwner: StickerCutoutPlugin?
      autoreleasepool {
        let owner = StickerCutoutPlugin(messenger: other, segmenter: CutoutBackend(), majorVersion: 17)
        weakOwner = owner
        withExtendedLifetime(owner) { XCTAssertNotNil(other.handler) }
      }
      XCTAssertNil(weakOwner)
      XCTAssertNil(other.handler)
      XCTAssertEqual(other.removals, 1)
    }
  }

  private struct Harness {
    let messenger: CutoutMessenger
    let backend: CutoutBackend
    let owner: StickerCutoutPlugin
  }

  private struct Job {
    let id: String
    let source: URL
    let output: URL
    var arguments: [String: Any] {
      ["jobId": id, "sourceImagePath": source.path, "outputPath": output.path]
    }
  }

  private func harness(
    majorVersion: Int = 17, available: Bool = true, messenger: CutoutMessenger? = nil
  ) -> Harness {
    onMain {
      let messenger = messenger ?? CutoutMessenger()
      let backend = CutoutBackend(available: available)
      let owner = StickerCutoutPlugin(messenger: messenger, segmenter: backend, majorVersion: majorVersion)
      owners.append(owner)
      return Harness(messenger: messenger, backend: backend, owner: owner)
    }
  }

  private func call(_ h: Harness, _ method: String, _ arguments: Any? = nil) throws -> CutoutReply {
    try onMain { try h.messenger.call(method, arguments: arguments) }
  }

  private func start(_ h: Harness, _ job: Job) throws -> (CutoutReply, CutoutRequest) {
    // Observe either real backend entry OR an immediate terminal reply. The RED
    // scaffold therefore fails an assertion immediately, rather than a timeout.
    let gate = expectation(description: "backend entered or bridge settled")
    let before = h.backend.count
    var signalled = false
    let signal = {
      XCTAssertTrue(Thread.isMainThread)
      if !signalled { signalled = true; gate.fulfill() }
    }
    h.backend.onStart = signal
    let reply = try onMain { try h.messenger.call("extract", arguments: job.arguments, onFirst: signal) }
    wait(for: [gate], timeout: 3)
    h.backend.onStart = nil
    let request = try XCTUnwrap(h.backend.request(at: before), "extract must reach the injected Vision boundary")
    return (reply, request)
  }

  private func awaitReply(_ reply: CutoutReply) {
    if reply.count == 0 { wait(for: [reply.done], timeout: 3) }
    XCTAssertEqual(reply.count, 1)
  }

  private func descriptor(_ reply: CutoutReply) throws -> [String: Any] {
    awaitReply(reply)
    return try XCTUnwrap(reply.value as? [String: Any], "expected a success descriptor")
  }

  private func assertNilReply(_ reply: CutoutReply) {
    awaitReply(reply)
    XCTAssertNil(reply.value)
  }

  private func assertReply(_ reply: CutoutReply, equals value: String) {
    awaitReply(reply)
    XCTAssertEqual(reply.value as? String, value)
  }

  private func assertError(_ reply: CutoutReply, code: String) {
    awaitReply(reply)
    guard let error = reply.value as? FlutterError else { return XCTFail("expected safe FlutterError \(code)") }
    XCTAssertEqual(error.code, code)
    XCTAssertNil(error.message)
    XCTAssertNil(error.details)
  }

  private func assertBounds(_ result: [String: Any], left: Double, top: Double, right: Double, bottom: Double) {
    guard let bounds = result["subjectBounds"] as? [String: Double] else { return XCTFail("missing bounds") }
    XCTAssertEqual(Set(bounds.keys), Set(["left", "top", "right", "bottom"]))
    for (key, expected) in ["left": left, "top": top, "right": right, "bottom": bottom] {
      XCTAssertEqual(bounds[key] ?? -1, expected, accuracy: 0.000001)
    }
  }

  private func drainMain() {
    let done = expectation(description: "delivered completion callbacks")
    DispatchQueue.main.async { DispatchQueue.main.async { done.fulfill() } }
    wait(for: [done], timeout: 3)
  }

  private func makeRoot(prefix: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(prefix + UUID().uuidString, isDirectory: true)
      .standardizedFileURL.resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    roots.append(root)
    return root
  }

  private func makeJob(source: URL? = nil) throws -> Job {
    let source = try source ?? sourceImage(
      width: 4, height: 3, rgba: Array(repeating: [UInt8(80), 120, 160, 255], count: 12).flatMap { $0 }
    )
    let directory = try makeRoot(prefix: "mknoon-sticker-cutout-")
    return Job(id: directory.lastPathComponent, source: source, output: directory.appendingPathComponent("result.png"))
  }

  private func preserve(_ data: Data, at url: URL) throws {
    try data.write(to: url)
    originals[url] = data
  }

  private func sourceImage(
    width: Int, height: Int, rgba: [UInt8], orientation: Int = 1, comment: String = "private-location-and-camera"
  ) throws -> URL {
    let root = try makeRoot(prefix: "cutout-source-")
    let url = root.appendingPathComponent("source.tiff")
    let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.tiff.identifier as CFString, 1, nil))
    let properties: [CFString: Any] = [
      kCGImagePropertyOrientation: orientation,
      kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: comment],
      kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 51.5, kCGImagePropertyGPSLatitudeRef: "N"],
    ]
    CGImageDestinationAddImage(destination, try makeImage(width: width, height: height, rgba: rgba), properties as CFDictionary)
    XCTAssertTrue(CGImageDestinationFinalize(destination), "fixture TIFF encoding")
    let data = try Data(contentsOf: url)
    let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
    let metadata = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
    XCTAssertEqual(metadata[kCGImagePropertyOrientation as String] as? Int, orientation, "fixture orientation")
    XCTAssertNotNil(metadata[kCGImagePropertyExifDictionary as String], "fixture private metadata")
    originals[url] = data
    return url
  }
}

private final class CutoutRequest {
  let image: CGImage
  let wasMainThread: Bool
  private let completion: (Result<CGImage?, Error>) -> Void
  init(image: CGImage, completion: @escaping (Result<CGImage?, Error>) -> Void) {
    self.image = image
    self.wasMainThread = Thread.isMainThread
    self.completion = completion
  }
  func complete(_ result: Result<CGImage?, Error>) { onMain { completion(result) } }
}

private final class CutoutBackend: StickerCutoutSegmenting {
  let isAvailable: Bool
  private let lock = NSLock()
  private var requests: [CutoutRequest] = []
  private var cancelCount = 0
  private var observer: (() -> Void)?
  init(available: Bool = true) { isAvailable = available }
  var count: Int { lock.lock(); defer { lock.unlock() }; return requests.count }
  var cancels: Int { lock.lock(); defer { lock.unlock() }; return cancelCount }
  var onStart: (() -> Void)? {
    get { lock.lock(); defer { lock.unlock() }; return observer }
    set { lock.lock(); observer = newValue; lock.unlock() }
  }
  func request(at index: Int) -> CutoutRequest? {
    lock.lock(); defer { lock.unlock() }
    return requests.indices.contains(index) ? requests[index] : nil
  }
  func segment(_ image: CGImage, completion: @escaping (Result<CGImage?, Error>) -> Void) {
    lock.lock()
    requests.append(CutoutRequest(image: image, completion: completion))
    let callback = observer
    lock.unlock()
    DispatchQueue.main.async { callback?() }
  }
  func cancel() { lock.lock(); cancelCount += 1; lock.unlock() }
}

private final class CutoutReply {
  let done = XCTestExpectation(description: "method-channel completion")
  private(set) var count = 0
  private(set) var value: Any?
  var onFirst: (() -> Void)?
  func receive(_ data: Data?) {
    XCTAssertTrue(Thread.isMainThread, "Flutter results must be delivered on the main thread")
    count += 1
    if let data { value = FlutterStandardMethodCodec.sharedInstance().decodeEnvelope(data) }
    else { XCTFail("unexpected not-implemented reply") }
    if count == 1 { done.fulfill(); onFirst?() }
  }
}

private final class CutoutMessenger: NSObject, FlutterBinaryMessenger {
  private(set) var handler: FlutterBinaryMessageHandler?
  private(set) var removals = 0
  private var nextConnection: FlutterBinaryMessengerConnection = 1
  private var connection: FlutterBinaryMessengerConnection?
  func send(onChannel channel: String, message: Data?) {}
  func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) {}
  func setMessageHandlerOnChannel(_ channel: String, binaryMessageHandler handler: FlutterBinaryMessageHandler?) -> FlutterBinaryMessengerConnection {
    XCTAssertEqual(channel, "mknoon/custom_sticker_cutout")
    let next = nextConnection
    nextConnection += 1
    connection = handler == nil ? nil : next
    self.handler = handler
    if handler == nil { removals += 1 }
    return next
  }
  func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {
    // Flutter also removes handlers through connection cleanup. Count the
    // semantic removal while retaining the guard against an old connection.
    guard self.connection == connection else { return }
    self.connection = nil
    handler = nil
    removals += 1
  }
  func call(_ method: String, arguments: Any? = nil, onFirst: (() -> Void)? = nil) throws -> CutoutReply {
    let callback = try XCTUnwrap(handler, "cutout channel must be registered")
    let reply = CutoutReply()
    reply.onFirst = onFirst
    let call = FlutterMethodCall(methodName: method, arguments: arguments)
    callback(FlutterStandardMethodCodec.sharedInstance().encode(call)) { reply.receive($0) }
    return reply
  }
}

private final class CutoutRegistrar: NSObject, FlutterPluginRegistrar {
  let recordingMessenger: CutoutMessenger
  var published: NSObject?
  init(messenger: CutoutMessenger) { recordingMessenger = messenger }
  func messenger() -> FlutterBinaryMessenger { recordingMessenger }
  var viewController: UIViewController? { nil }
  func publish(_ value: NSObject) { published = value }
  func valuePublished(byPlugin pluginKey: String) -> NSObject? { published }
  func textures() -> FlutterTextureRegistry { fatalError("cutout must not use textures") }
  func register(_ factory: FlutterPlatformViewFactory, withId factoryId: String) { XCTFail("unexpected platform view") }
  func register(_ factory: FlutterPlatformViewFactory, withId factoryId: String, gestureRecognizersBlockingPolicy: FlutterPlatformViewGestureRecognizersBlockingPolicy) { XCTFail("unexpected platform view") }
  func addMethodCallDelegate(_ delegate: FlutterPlugin, channel: FlutterMethodChannel) { XCTFail("bridge owns its handler") }
  func addApplicationDelegate(_ delegate: FlutterPlugin) { XCTFail("published owner supplies detach") }
  func addSceneDelegate(_ delegate: FlutterSceneLifeCycleDelegate) { XCTFail("unexpected scene delegate") }
  func lookupKey(forAsset asset: String) -> String { asset }
  func lookupKey(forAsset asset: String, fromPackage package: String) -> String { asset }
}

private func onMain<T>(_ body: () throws -> T) rethrows -> T {
  if Thread.isMainThread { return try body() }
  return try DispatchQueue.main.sync(execute: body)
}

private func makeImage(width: Int, height: Int, rgba: [UInt8]) throws -> CGImage {
  XCTAssertEqual(rgba.count, width * height * 4)
  let provider = try XCTUnwrap(CGDataProvider(data: Data(rgba) as CFData))
  return try XCTUnwrap(CGImage(
    width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.last.rawValue),
    provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
  ))
}

private func rgba(_ image: CGImage) throws -> [UInt8] {
  var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
  try bytes.withUnsafeMutableBytes { buffer in
    let context = try XCTUnwrap(CGContext(
      data: buffer.baseAddress, width: image.width, height: image.height,
      bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.interpolationQuality = .none
    context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height)))
  }
  return bytes
}

private struct CutoutPNG { let width: Int; let height: Int; let rgba: [UInt8] }

/// Independent inspection of the actual PNG samples: CGContext premultiplication
/// would erase hidden alpha-zero RGB and is therefore not a privacy oracle.
private func strictPNG(_ url: URL) throws -> CutoutPNG {
  let bytes = [UInt8](try Data(contentsOf: url))
  guard bytes.count >= 45, Array(bytes.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10] else {
    XCTFail("not a complete PNG"); throw CutoutFixtureError.invalidPNG
  }
  func uint32(_ index: Int) -> Int {
    Int(bytes[index]) << 24 | Int(bytes[index + 1]) << 16 | Int(bytes[index + 2]) << 8 | Int(bytes[index + 3])
  }
  var offset = 8
  var width = 0
  var height = 0
  var compressed: [UInt8] = []
  var types: [String] = []
  var ended = false
  while offset + 12 <= bytes.count {
    let length = uint32(offset)
    let end = offset + 8 + length
    guard end + 4 <= bytes.count else { throw CutoutFixtureError.invalidPNG }
    let type = String(bytes: bytes[(offset + 4)..<(offset + 8)], encoding: .ascii) ?? ""
    types.append(type)
    let crcBytes = Array(bytes[(offset + 4)..<end])
    let observed = crcBytes.withUnsafeBufferPointer { crc32(0, $0.baseAddress, uInt($0.count)) }
    XCTAssertEqual(UInt32(truncatingIfNeeded: observed), UInt32(uint32(end)), "PNG chunk CRC")
    switch type {
    case "IHDR":
      guard types.count == 1, length == 13 else { throw CutoutFixtureError.invalidPNG }
      width = uint32(offset + 8); height = uint32(offset + 12)
      // Our native output is deliberately one non-interlaced 8-bit RGBA canvas.
      XCTAssertEqual(Array(bytes[(offset + 16)..<(offset + 21)]), [8, 6, 0, 0, 0])
    case "IDAT":
      guard types.dropLast().allSatisfy({ $0 == "IHDR" || $0 == "IDAT" }) else { throw CutoutFixtureError.invalidPNG }
      compressed.append(contentsOf: bytes[(offset + 8)..<end])
    case "IEND":
      XCTAssertEqual(length, 0)
      XCTAssertEqual(end + 4, bytes.count, "no bytes after IEND")
      ended = true
    default:
      XCTFail("native PNG leaks disallowed chunk \(type)")
      throw CutoutFixtureError.invalidPNG
    }
    offset = end + 4
    if ended { break }
  }
  guard ended, width > 0, height > 0, width <= 2048, height <= 2048, !compressed.isEmpty else {
    throw CutoutFixtureError.invalidPNG
  }
  let stride = width * 4
  var raw = [UInt8](repeating: 0, count: (stride + 1) * height)
  var size = uLongf(raw.count)
  let status = raw.withUnsafeMutableBufferPointer { target in
    compressed.withUnsafeBufferPointer { source in
      uncompress(target.baseAddress, &size, source.baseAddress, uLong(source.count))
    }
  }
  guard status == Z_OK, Int(size) == raw.count else { throw CutoutFixtureError.invalidPNG }
  var pixels = [UInt8](repeating: 0, count: stride * height)
  for y in 0..<height {
    let filter = raw[y * (stride + 1)]
    guard filter <= 4 else { throw CutoutFixtureError.invalidPNG }
    for x in 0..<stride {
      let index = y * stride + x
      let a = x >= 4 ? Int(pixels[index - 4]) : 0
      let b = y > 0 ? Int(pixels[index - stride]) : 0
      let c = x >= 4 && y > 0 ? Int(pixels[index - stride - 4]) : 0
      let prediction: Int
      switch filter {
      case 0: prediction = 0
      case 1: prediction = a
      case 2: prediction = b
      case 3: prediction = (a + b) / 2
      default:
        let p = a + b - c
        let pa = abs(p - a), pb = abs(p - b), pc = abs(p - c)
        prediction = pa <= pb && pa <= pc ? a : (pb <= pc ? b : c)
      }
      pixels[index] = UInt8(truncatingIfNeeded: Int(raw[y * (stride + 1) + x + 1]) + prediction)
    }
  }
  return CutoutPNG(width: width, height: height, rgba: pixels)
}

private enum CutoutFixtureError: Error { case invalidPNG }
