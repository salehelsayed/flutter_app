import AVFoundation
import CoreGraphics
import Flutter
import Foundation

/// Extracts oriented camera frames into the Dart-owned cache job directory.
final class StickerClipFrameBridge: @unchecked Sendable {
  private static let side = 512
  private static let maximumSourceBytes = 64 * 1024 * 1024
  private static let maximumSourcePixels = 4 * 1024 * 1024
  private static let jobPrefix = "mknoon-sticker-animation-"

  private let channel: FlutterMethodChannel
  private let queue = DispatchQueue(label: "mknoon.sticker-clip-frames", qos: .userInitiated)
  // The channel, active job and close state are used on the main queue.
  private var active: Job?
  private var closed = false

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "mknoon/custom_sticker_clip_frames", binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "unavailable", message: nil, details: nil))
        return
      }
      self.handle(call, result: result)
    }
  }

  func close() {
    closed = true
    channel.setMethodCallHandler(nil)
    active?.cancel()
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "cancel":
      if let id = args?["jobId"] as? String, active?.id == id {
        active?.cancel()
      }
      result(nil)
    case "extract":
      guard !closed, active == nil else {
        result(ClipError.unavailable.flutter)
        return
      }
      guard
        let id = args?["jobId"] as? String, !id.isEmpty,
        let clipPath = args?["clipPath"] as? String, !clipPath.isEmpty,
        let framesPath = args?["framesPath"] as? String, !framesPath.isEmpty,
        let crop = args?["crop"] as? [Double], crop.count == 4,
        crop.allSatisfy({ $0.isFinite }),
        crop[0] >= 0, crop[1] >= 0, crop[2] <= 1, crop[3] <= 1,
        crop[0] < crop[2], crop[1] < crop[3]
      else {
        result(ClipError.invalidClip.flutter)
        return
      }
      let job = Job(id: id, result: result)
      active = job
      queue.async {
        self.extract(job, clipPath: clipPath, framesPath: framesPath, crop: crop)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func extract(_ job: Job, clipPath: String, framesPath: String, crop: [Double]) {
    let fm = FileManager.default
    var ownedOutput: URL?
    let outcome: Result<[String: Int], ClipError>
    do {
      let roots = (
        fm.urls(for: .cachesDirectory, in: .userDomainMask) + [fm.temporaryDirectory]
      ).map { $0.standardizedFileURL.resolvingSymlinksInPath() }
      let clip = URL(fileURLWithPath: clipPath).standardizedFileURL.resolvingSymlinksInPath()
      let values = try clip.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
      let sourceSize = values.fileSize ?? 0
      guard
        roots.contains(where: { clip.path.hasPrefix($0.path + "/") }),
        values.isRegularFile == true,
        sourceSize > 0, sourceSize <= Self.maximumSourceBytes
      else {
        throw ClipError.invalidClip
      }
      let requested = URL(fileURLWithPath: framesPath)
      let parent = requested.deletingLastPathComponent().standardizedFileURL
        .resolvingSymlinksInPath()
      guard
        requested.lastPathComponent == "frames.rgba",
        roots.contains(where: { $0.path == parent.deletingLastPathComponent().path }),
        parent.lastPathComponent == job.id,
        parent.lastPathComponent.hasPrefix(Self.jobPrefix)
      else {
        throw ClipError.invalidClip
      }
      try job.checkActive()
      let asset = AVURLAsset(url: clip)
      let tracks = asset.tracks(withMediaType: .video)
      guard tracks.count == 1, asset.tracks(withMediaType: .audio).isEmpty else {
        throw ClipError.invalidClip
      }
      let track = tracks[0]
      let size = CGRect(origin: .zero, size: track.naturalSize)
        .applying(track.preferredTransform).standardized.size
      try Self.validateDimensions(width: size.width, height: size.height)
      let start = track.timeRange.start
      let seconds = CMTimeGetSeconds(track.timeRange.duration)
      guard CMTimeGetSeconds(start).isFinite, seconds.isFinite, seconds >= 0.002 else {
        throw ClipError.invalidClip
      }
      let duration = Int(min(seconds, 2) * 1000)
      let count = max(2, (duration * 12 + 999) / 1000)
      let generator = AVAssetImageGenerator(asset: asset)
      generator.appliesPreferredTrackTransform = true
      let tolerance = CMTime(value: 1, timescale: 24)
      generator.requestedTimeToleranceBefore = tolerance
      generator.requestedTimeToleranceAfter = tolerance

      let output = parent.appendingPathComponent("frames.rgba", isDirectory: false)
      try Data().write(to: output, options: .withoutOverwriting)
      ownedOutput = output
      let handle = try FileHandle(forWritingTo: output)
      do {
        for i in 0..<count {
          try job.checkActive()
          let ms = (i * duration + count / 2) / count
          let time = CMTimeAdd(start, CMTime(value: CMTimeValue(ms), timescale: 1000))
          let bytes = try autoreleasepool {
            var actual = CMTime.invalid
            let image = try generator.copyCGImage(at: time, actualTime: &actual)
            let difference = CMTimeGetSeconds(CMTimeSubtract(actual, time))
            guard difference.isFinite, abs(difference) <= 0.043 else {
              throw ClipError.unavailable
            }
            return try Self.rgbaFrame(image, crop: crop)
          }
          try job.checkActive()
          try handle.write(contentsOf: bytes)
        }
        try handle.close()
      } catch {
        try? handle.close()
        throw error
      }
      try job.checkActive()
      outcome = .success(["durationMs": duration, "frameCount": count])
    } catch let error as ClipError {
      outcome = .failure(error)
    } catch {
      outcome = .failure(.unavailable)
    }

    let output = ownedOutput
    if case .failure = outcome, let output {
      try? fm.removeItem(at: output)
    }
    DispatchQueue.main.async {
      if self.active === job { self.active = nil }
      if job.isCancelled {
        if let output { try? fm.removeItem(at: output) }
        if !self.closed { job.result(ClipError.cancelled.flutter) }
      } else if !self.closed {
        switch outcome {
        case .success(let receipt): job.result(receipt)
        case .failure(let error): job.result(error.flutter)
        }
      }
    }
  }

  private static func validateDimensions(width: CGFloat, height: CGFloat) throws {
    guard
      width.isFinite, height.isFinite,
      width >= 1, height >= 1, width <= 4096, height <= 4096,
      width * height <= CGFloat(maximumSourcePixels)
    else {
      throw ClipError.invalidClip
    }
  }

  private static func rgbaFrame(_ image: CGImage, crop: [Double]) throws -> Data {
    try validateDimensions(width: CGFloat(image.width), height: CGFloat(image.height))
    let width = Double(image.width)
    let height = Double(image.height)
    let spanWidth = (crop[2] - crop[0]) * width
    let spanHeight = (crop[3] - crop[1]) * height
    let x = Int((crop[0] * width).rounded())
    let y = Int((crop[1] * height).rounded())
    let cropSide = min(
      Int(spanWidth.rounded()), Int(spanHeight.rounded()),
      image.width - x, image.height - y
    )
    guard
      abs(spanWidth - spanHeight) <= 1, cropSide >= 1,
      let cropped = image.cropping(
        to: CGRect(
          x: CGFloat(x), y: CGFloat(y),
          width: CGFloat(cropSide), height: CGFloat(cropSide)
        )
      ),
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
    else {
      throw ClipError.invalidClip
    }
    var bytes = Data(count: side * side * 4)
    let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
      guard let context = CGContext(
        data: buffer.baseAddress, width: side, height: side,
        bitsPerComponent: 8, bytesPerRow: side * 4, space: colorSpace,
        bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue |
          CGImageAlphaInfo.premultipliedLast.rawValue
      ) else {
        return false
      }
      context.interpolationQuality = .medium
      context.draw(
        cropped,
        in: CGRect(x: 0, y: 0, width: CGFloat(side), height: CGFloat(side))
      )
      return true
    }
    guard drawn else { throw ClipError.unavailable }
    return bytes
  }

  private enum ClipError: String, Error {
    case invalidClip = "invalid_clip"
    case unavailable
    case cancelled

    var flutter: FlutterError {
      FlutterError(code: rawValue, message: nil, details: nil)
    }
  }

  private final class Job: @unchecked Sendable {
    let id: String
    let result: FlutterResult
    private let lock = NSLock()
    private var cancelled = false

    init(id: String, result: @escaping FlutterResult) {
      self.id = id
      self.result = result
    }

    var isCancelled: Bool {
      lock.lock()
      defer { lock.unlock() }
      return cancelled
    }

    func cancel() {
      lock.lock()
      cancelled = true
      lock.unlock()
    }

    func checkActive() throws {
      if isCancelled { throw ClipError.cancelled }
    }
  }
}
