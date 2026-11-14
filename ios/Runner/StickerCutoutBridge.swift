import CoreGraphics
import CoreImage
import Darwin
import Flutter
import Foundation
import ImageIO
import Vision
import zlib

/// A full-canvas, already oriented foreground result, or nil for no subject.
/// Implementations enqueue segmentation and return promptly; cancel is best effort.
protocol StickerCutoutSegmenting: AnyObject {
  var isAvailable: Bool { get }
  func segment(
    _ image: CGImage,
    completion: @escaping (Result<CGImage?, Error>) -> Void
  )
  func cancel()
}

final class StickerCutoutBridge: @unchecked Sendable {
  private final class Owner {
    weak var bridge: StickerCutoutBridge?
    init(_ bridge: StickerCutoutBridge) { self.bridge = bridge }
  }

  // Channel ownership, admission and Flutter replies are confined to main.
  private static var owners: [ObjectIdentifier: Owner] = [:]
  private let messengerID: ObjectIdentifier
  private let channel: FlutterMethodChannel
  private let segmenter: StickerCutoutSegmenting?
  private let supportedVersion: Bool
  private let queue = DispatchQueue(label: "mknoon.sticker-cutout", qos: .userInitiated)
  private var active: CutoutJob?
  private var closed = false

  init(
    messenger: FlutterBinaryMessenger,
    segmenter: StickerCutoutSegmenting? = nil,
    majorVersion: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
  ) {
    messengerID = ObjectIdentifier(messenger as AnyObject)
    channel = FlutterMethodChannel(
      name: "mknoon/custom_sticker_cutout", binaryMessenger: messenger
    )
    supportedVersion = majorVersion >= 17
    if let segmenter {
      self.segmenter = segmenter
    } else if #available(iOS 17.0, *) {
      self.segmenter = VisionStickerCutoutSegmenter()
    } else {
      self.segmenter = nil
    }
    onMain {
      Self.owners[self.messengerID]?.bridge?.close()
      Self.owners[self.messengerID] = Owner(self)
      self.channel.setMethodCallHandler { [weak self] call, result in
        guard let self else {
          if Thread.isMainThread { result(CutoutFailure.unavailable.flutter) }
          else { DispatchQueue.main.async { result(CutoutFailure.unavailable.flutter) } }
          return
        }
        self.onMain { self.handle(call, result: result) }
      }
    }
  }

  func close() {
    onMain {
      guard !self.closed else { return }
      self.closed = true
      if Self.owners[self.messengerID]?.bridge === self {
        Self.owners.removeValue(forKey: self.messengerID)
        self.channel.setMethodCallHandler(nil)
      }
      if let job = self.active { self.cancel(job, acknowledgement: nil) }
    }
  }

  private func onMain(_ body: () -> Void) {
    if Thread.isMainThread { body() }
    else { DispatchQueue.main.sync(execute: body) }
  }

  private var available: Bool {
    !closed && supportedVersion && segmenter?.isAvailable == true
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any]
    switch call.method {
    case "availability":
      result(available ? "ready" : "unsupported")
    case "cancel":
      if let id = arguments?["jobId"] as? String, let job = active, job.id == id {
        cancel(job, acknowledgement: result)
      } else {
        result(nil)
      }
    case "extract":
      guard available else { result(CutoutFailure.unsupported.flutter); return }
      guard active == nil else { result(CutoutFailure.unavailable.flutter); return }
      guard let id = arguments?["jobId"] as? String,
            let output = arguments?["outputPath"] as? String else {
        result(CutoutFailure.failed.flutter)
        return
      }
      guard let source = arguments?["sourceImagePath"] as? String,
            source.hasPrefix("/"), !source.utf8.contains(0) else {
        result(CutoutFailure.invalidSource.flutter)
        return
      }
      let job = CutoutJob(id: id, result: result)
      active = job
      queue.async { self.prepare(job, source: source, output: output) }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func prepare(_ job: CutoutJob, source: String, output: String) {
    do {
      try job.checkActive()
      job.output = try CutoutOutput(path: output, jobID: job.id)
      let image = try autoreleasepool { try cutoutThumbnail(source) }
      try job.checkActive()
      guard let segmenter else { throw CutoutFailure.unsupported }
      // The token lock orders backend admission against cancel. segment() only
      // enqueues work; even a synchronous fake callback is queued before handling.
      job.start(segmenter, image: image) { [weak self] outcome in
        guard let self else { return }
        self.queue.async { self.receive(outcome, for: job, input: image) }
      }
    } catch let failure as CutoutFailure {
      finish(job, outcome: .failure(failure))
    } catch {
      finish(job, outcome: .failure(.failed))
    }
  }

  private func receive(_ outcome: Result<CGImage?, Error>, for job: CutoutJob, input: CGImage) {
    guard !job.receivedCompletion, !job.isCancelled else { return }
    job.receivedCompletion = true
    do {
      guard let image = try outcome.get() else {
        finish(job, outcome: .success(nil))
        return
      }
      guard image.width == input.width, image.height == input.height else {
        throw CutoutFailure.failed
      }
      let png = try autoreleasepool { try cutoutPNG(image) }
      try job.checkActive()
      guard let png else {
        finish(job, outcome: .success(nil))
        return
      }
      guard let output = job.output else { throw CutoutFailure.failed }
      try output.write(png.bytes, job: job)
      finish(job, outcome: .success([
        "width": image.width, "height": image.height, "subjectBounds": png.bounds,
      ]))
    } catch {
      finish(job, outcome: .failure(.failed))
    }
  }

  // Called only on the worker queue. A cancelled job is settled by its cleanup.
  private func finish(_ job: CutoutJob, outcome: Result<[String: Any]?, CutoutFailure>) {
    guard !job.isCancelled else { return }
    switch outcome {
    case .success(.some(_)): break
    default: job.output?.discard(); job.output?.close()
    }
    DispatchQueue.main.async {
      guard !job.isCancelled, self.active === job else { return }
      self.active = nil
      // After the reply, the output belongs to Dart. No later callback can
      // discard it: admission is gone and receivedCompletion rejects duplicates.
      self.queue.async { job.output?.close() }
      switch outcome {
      case .success(let value): job.reply(value)
      case .failure(let failure): job.reply(failure.flutter)
      }
    }
  }

  private func cancel(_ job: CutoutJob, acknowledgement: FlutterResult?) {
    if let acknowledgement { job.cancellationReplies.append(acknowledgement) }
    guard job.beginCancellation() else { return }
    if job.started { segmenter?.cancel() }
    // Await already queued output work before acknowledging cancellation. Dart
    // can then delete its directory; this bridge never recreates that directory.
    queue.async {
      job.output?.discard()
      job.output?.close()
      DispatchQueue.main.async {
        if self.active === job { self.active = nil }
        job.reply(nil)
        let replies = job.cancellationReplies
        job.cancellationReplies.removeAll()
        replies.forEach { $0(nil) }
      }
    }
  }
}

private enum CutoutFailure: Error {
  case unsupported, unavailable, invalidSource, failed
  var flutter: FlutterError {
    FlutterError(code: String(describing: self), message: nil, details: nil)
  }
}

private final class CutoutJob: @unchecked Sendable {
  let id: String
  private let lock = NSLock()
  private var cancelled = false
  private var backendStarted = false
  private var result: FlutterResult?
  // The following two properties are worker-queue only.
  var output: CutoutOutput?
  var receivedCompletion = false
  // Main-queue only.
  var cancellationReplies: [FlutterResult] = []

  init(id: String, result: @escaping FlutterResult) { self.id = id; self.result = result }
  var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
  var started: Bool { lock.lock(); defer { lock.unlock() }; return backendStarted }
  func checkActive() throws { if isCancelled { throw CutoutFailure.failed } }
  func beginCancellation() -> Bool {
    lock.lock(); defer { lock.unlock() }
    guard !cancelled else { return false }
    cancelled = true
    return true
  }
  func start(
    _ segmenter: StickerCutoutSegmenting, image: CGImage,
    completion: @escaping (Result<CGImage?, Error>) -> Void
  ) {
    lock.lock(); defer { lock.unlock() }
    guard !cancelled else { return }
    backendStarted = true
    segmenter.segment(image, completion: completion)
  }
  func reply(_ value: Any?) {
    let callback = result
    result = nil
    callback?(value)
  }
}

/// Pins the existing private directory and unlinks only the inode this job made.
private final class CutoutOutput {
  private var directoryFD: Int32
  private let directory: URL
  private let directoryIdentity: stat
  private var fileIdentity: stat?

  init(path: String, jobID: String) throws {
    let prefix = "mknoon-sticker-cutout-"
    guard jobID.hasPrefix(prefix), jobID.count > prefix.count,
          jobID.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0)
            || (97...122).contains($0) || $0 == 45 || $0 == 95 }),
          path.hasPrefix("/"), !path.utf8.contains(0),
          !path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else {
      throw CutoutFailure.failed
    }
    let output = URL(fileURLWithPath: path)
    let directory = output.deletingLastPathComponent().standardizedFileURL
    let roots = (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
      + [FileManager.default.temporaryDirectory]).map {
        $0.standardizedFileURL.resolvingSymlinksInPath().path
      }
    guard output.lastPathComponent == "result.png", directory.lastPathComponent == jobID,
          directory.resolvingSymlinksInPath().path == directory.path,
          roots.contains(where: { directory.path.hasPrefix($0 + "/") }) else {
      throw CutoutFailure.failed
    }
    var fd = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
    guard fd >= 0 else { throw CutoutFailure.failed }
    for component in directory.path.split(separator: "/") {
      let next = String(component).withCString {
        Darwin.openat(fd, $0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
      }
      Darwin.close(fd)
      guard next >= 0 else { throw CutoutFailure.failed }
      fd = next
    }
    var identity = stat()
    var existing = stat()
    guard fstat(fd, &identity) == 0 else { Darwin.close(fd); throw CutoutFailure.failed }
    let exists = fstatat(fd, "result.png", &existing, AT_SYMLINK_NOFOLLOW)
    guard exists != 0, errno == ENOENT else { Darwin.close(fd); throw CutoutFailure.failed }
    self.directoryFD = fd
    self.directory = directory
    self.directoryIdentity = identity
  }

  private func directoryMatches() -> Bool {
    var current = stat()
    return directoryFD >= 0
      && lstat(directory.path, &current) == 0
      && current.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR)
      && current.st_dev == directoryIdentity.st_dev && current.st_ino == directoryIdentity.st_ino
      && directory.resolvingSymlinksInPath().path == directory.path
  }

  func write(_ bytes: Data, job: CutoutJob) throws {
    try job.checkActive()
    guard directoryMatches() else { throw CutoutFailure.failed }
    let fd = openat(directoryFD, "result.png", O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
    guard fd >= 0 else { throw CutoutFailure.failed }
    defer { Darwin.close(fd) }
    var identity = stat()
    guard fstat(fd, &identity) == 0 else { throw CutoutFailure.failed }
    fileIdentity = identity
    try bytes.withUnsafeBytes { buffer in
      guard let address = buffer.baseAddress else { throw CutoutFailure.failed }
      var offset = 0
      while offset < buffer.count {
        try job.checkActive()
        let count = Darwin.write(fd, address.advanced(by: offset), min(65536, buffer.count - offset))
        if count < 0 && errno == EINTR { continue }
        guard count > 0 else { throw CutoutFailure.failed }
        offset += count
      }
    }
    try job.checkActive()
    guard fsync(fd) == 0, directoryMatches(), ownsCurrentFile() else { throw CutoutFailure.failed }
  }

  private func ownsCurrentFile() -> Bool {
    guard directoryFD >= 0, let identity = fileIdentity else { return false }
    var current = stat()
    return fstatat(directoryFD, "result.png", &current, AT_SYMLINK_NOFOLLOW) == 0
      && current.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG)
      && current.st_dev == identity.st_dev && current.st_ino == identity.st_ino
  }

  func discard() {
    if ownsCurrentFile() { _ = unlinkat(directoryFD, "result.png", 0) }
    fileIdentity = nil
  }
  func close() {
    if directoryFD >= 0 { Darwin.close(directoryFD); directoryFD = -1 }
  }
  deinit { close() }
}

/// ImageIO reads a pinned, read-only source FD without loading the entire source
/// into a Data buffer or following a replacement of its final path component.
private final class CutoutSource {
  let fd: Int32
  init(_ fd: Int32) { self.fd = fd }
  deinit { Darwin.close(fd) }
}

private func cutoutThumbnail(_ path: String) throws -> CGImage {
  let fd = Darwin.open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
  guard fd >= 0 else { throw CutoutFailure.invalidSource }
  let file = CutoutSource(fd)
  var attributes = stat()
  guard fstat(fd, &attributes) == 0,
        attributes.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), attributes.st_size > 0 else {
    throw CutoutFailure.invalidSource
  }
  var callbacks = CGDataProviderDirectCallbacks(
    version: 0, getBytePointer: nil, releaseBytePointer: nil,
    getBytesAtPosition: { info, buffer, position, count in
      guard let info else { return 0 }
      let file = Unmanaged<CutoutSource>.fromOpaque(info).takeUnretainedValue()
      var readCount: Int
      repeat { readCount = pread(file.fd, buffer, count, position) } while readCount < 0 && errno == EINTR
      return max(0, readCount)
    },
    releaseInfo: { info in
      if let info { Unmanaged<CutoutSource>.fromOpaque(info).release() }
    }
  )
  let info = Unmanaged.passRetained(file).toOpaque()
  guard let provider = CGDataProvider(directInfo: info, size: attributes.st_size, callbacks: &callbacks) else {
    Unmanaged<CutoutSource>.fromOpaque(info).release()
    throw CutoutFailure.invalidSource
  }
  guard let source = CGImageSourceCreateWithDataProvider(provider, [kCGImageSourceShouldCache: false] as CFDictionary),
        CGImageSourceGetCount(source) > 0,
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
        let width = properties[kCGImagePropertyPixelWidth] as? Int,
        let height = properties[kCGImagePropertyPixelHeight] as? Int,
        width > 0, height > 0 else { throw CutoutFailure.invalidSource }
  let options: [CFString: Any] = [
    kCGImageSourceCreateThumbnailFromImageAlways: true,
    kCGImageSourceCreateThumbnailWithTransform: true,
    kCGImageSourceThumbnailMaxPixelSize: min(2048, max(width, height)),
    kCGImageSourceShouldCacheImmediately: true,
  ]
  guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
        image.width > 0, image.height > 0, image.width <= 2048, image.height <= 2048 else {
    throw CutoutFailure.invalidSource
  }
  return image
}

private struct CutoutPNG {
  let bytes: Data
  let bounds: [String: Double]
}

/// Emits only fresh, non-interlaced 8-bit RGBA samples and the three required
/// PNG chunk types. No source/ImageIO metadata enters the encoder.
private func cutoutPNG(_ image: CGImage) throws -> CutoutPNG? {
  let width = image.width, height = image.height
  guard width > 0, height > 0, width <= 2048, height <= 2048 else { throw CutoutFailure.failed }
  let stride = width * 4
  var pixels = [UInt8](repeating: 0, count: stride * height)
  try pixels.withUnsafeMutableBytes { buffer in
    guard let context = CGContext(
      data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
      bytesPerRow: stride, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw CutoutFailure.failed }
    context.interpolationQuality = .none
    context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
  }
  var left = width, top = height, right = 0, bottom = 0
  for y in 0..<height {
    for x in 0..<width {
      let index = y * stride + x * 4
      let alpha = Int(pixels[index + 3])
      if alpha == 0 {
        pixels[index] = 0; pixels[index + 1] = 0; pixels[index + 2] = 0
      } else {
        left = min(left, x); top = min(top, y)
        right = max(right, x + 1); bottom = max(bottom, y + 1)
        for component in 0..<3 {
          pixels[index + component] = UInt8(min(255, (Int(pixels[index + component]) * 255 + alpha / 2) / alpha))
        }
      }
    }
  }
  guard right > left, bottom > top else { return nil }
  var raw = [UInt8]()
  raw.reserveCapacity((stride + 1) * height)
  for y in 0..<height {
    raw.append(0)
    raw.append(contentsOf: pixels[(y * stride)..<((y + 1) * stride)])
  }
  var compressedSize = uLongf(compressBound(uLong(raw.count)))
  var compressed = [UInt8](repeating: 0, count: Int(compressedSize))
  let status = compressed.withUnsafeMutableBufferPointer { target in
    raw.withUnsafeBufferPointer { source in
      compress2(target.baseAddress, &compressedSize, source.baseAddress, uLong(source.count), Z_BEST_SPEED)
    }
  }
  guard status == Z_OK else { throw CutoutFailure.failed }
  var bytes = Data([137, 80, 78, 71, 13, 10, 26, 10])
  func uint32(_ value: Int) -> [UInt8] {
    [UInt8((value >> 24) & 255), UInt8((value >> 16) & 255), UInt8((value >> 8) & 255), UInt8(value & 255)]
  }
  func chunk(_ type: String, _ data: Data) {
    bytes.append(contentsOf: uint32(data.count))
    var payload = Data(type.utf8)
    payload.append(data)
    bytes.append(payload)
    let crc = payload.withUnsafeBytes { buffer in
      crc32(0, buffer.bindMemory(to: UInt8.self).baseAddress, uInt(buffer.count))
    }
    bytes.append(contentsOf: uint32(Int(UInt32(truncatingIfNeeded: crc))))
  }
  chunk("IHDR", Data(uint32(width) + uint32(height) + [8, 6, 0, 0, 0]))
  chunk("IDAT", Data(compressed.prefix(Int(compressedSize))))
  chunk("IEND", Data())
  guard bytes.count <= 24 * 1024 * 1024 else { throw CutoutFailure.failed }
  return CutoutPNG(bytes: bytes, bounds: [
    "left": Double(left) / Double(width), "top": Double(top) / Double(height),
    "right": Double(right) / Double(width), "bottom": Double(bottom) / Double(height),
  ])
}

@available(iOS 17.0, *)
private final class VisionStickerCutoutSegmenter: StickerCutoutSegmenting, @unchecked Sendable {
  private let queue = DispatchQueue(label: "mknoon.sticker-cutout-vision", qos: .userInitiated)
  private let lock = NSLock()
  private var request: VNGenerateForegroundInstanceMaskRequest?
  var isAvailable: Bool { true }

  func segment(_ image: CGImage, completion: @escaping (Result<CGImage?, Error>) -> Void) {
    let request = VNGenerateForegroundInstanceMaskRequest()
    lock.lock(); self.request = request; lock.unlock()
    queue.async {
      let outcome: Result<CGImage?, Error>
      do {
        guard self.isCurrent(request) else { throw CutoutFailure.failed }
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        try handler.perform([request])
        guard self.isCurrent(request) else { throw CutoutFailure.failed }
        if let observation = request.results?.first, !observation.allInstances.isEmpty {
          let buffer = try observation.generateMaskedImage(
            ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: false
          )
          let masked = CIImage(cvPixelBuffer: buffer)
          guard let result = CIContext(options: [.cacheIntermediates: false]).createCGImage(masked, from: masked.extent),
                self.isCurrent(request) else { throw CutoutFailure.failed }
          outcome = .success(result)
        } else {
          outcome = .success(nil)
        }
      } catch {
        outcome = .failure(CutoutFailure.failed)
      }
      self.lock.lock()
      if self.request === request { self.request = nil }
      self.lock.unlock()
      completion(outcome)
    }
  }

  private func isCurrent(_ request: VNGenerateForegroundInstanceMaskRequest) -> Bool {
    lock.lock(); defer { lock.unlock() }
    return self.request === request
  }

  func cancel() {
    lock.lock()
    let ownedRequest = request
    request = nil
    lock.unlock()
    ownedRequest?.cancel()
  }
}
