// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import AVFoundation
import CoreMedia
import UIKit

/// Factory block returning an FLTCaptureDevice.
/// Used in tests to inject a video capture device into DefaultCamera.
typealias VideoCaptureDeviceFactory = (_ cameraName: String) -> CaptureDevice
typealias VideoRotationAngleProvider = (
  _ orientation: AVCaptureVideoOrientation, _ deltaFromCurrentOrientation: CGFloat
) -> CGFloat

typealias AudioCaptureDeviceFactory = () -> CaptureDevice

typealias CaptureSessionFactory = () -> CaptureSession

typealias AssetWriterFactory = (_ assetUrl: URL, _ fileType: AVFileType) throws -> AssetWriter

typealias InputPixelBufferAdaptorFactory = (
  _ input: AssetWriterInput, _ settings: [String: Any]?
) ->
  AssetWriterInputPixelBufferAdaptor

/// A configuration object that centralizes dependencies for `DefaultCamera`.
class CameraConfiguration {
  var mediaSettings: PlatformMediaSettings
  var mediaSettingsWrapper: FLTCamMediaSettingsAVWrapper
  var captureSessionQueue: DispatchQueue
  var videoCaptureSession: CaptureSession
  var audioCaptureSession: CaptureSession
  var videoCaptureDeviceFactory: VideoCaptureDeviceFactory
  var videoRotationAngleProviderFactory: (CaptureDevice) -> VideoRotationAngleProvider? = { device in
    guard #available(iOS 17.0, *), let avDevice = device as? AVCaptureDevice else {
      return nil
    }
    let coordinator = AVCaptureDevice.RotationCoordinator(device: avDevice, previewLayer: nil)
    return { orientation, deltaFromCurrentOrientation in
      if #available(iOS 27.0, *) {
        return coordinator.videoRotationAngleRelative(toDeviceOrientation: orientation)
      }
      let angle = (coordinator.videoRotationAngleForHorizonLevelCapture + deltaFromCurrentOrientation)
        .truncatingRemainder(dividingBy: 360)
      return angle < 0 ? angle + 360 : angle
    }
  }
  let audioCaptureDeviceFactory: AudioCaptureDeviceFactory
  let captureDeviceInputFactory: CaptureDeviceInputFactory
  var assetWriterFactory: AssetWriterFactory
  var inputPixelBufferAdaptorFactory: InputPixelBufferAdaptorFactory
  var videoDimensionsConverter: VideoDimensionsConverter
  var deviceOrientationProvider: DeviceOrientationProvider
  let initialCameraName: String
  var orientation: UIDeviceOrientation

  init(
    mediaSettings: PlatformMediaSettings,
    mediaSettingsWrapper: FLTCamMediaSettingsAVWrapper,
    captureDeviceFactory: @escaping VideoCaptureDeviceFactory,
    audioCaptureDeviceFactory: @escaping AudioCaptureDeviceFactory,
    captureSessionFactory: @escaping CaptureSessionFactory,
    captureSessionQueue: DispatchQueue,
    captureDeviceInputFactory: CaptureDeviceInputFactory,
    initialCameraName: String
  ) {
    self.mediaSettings = mediaSettings
    self.mediaSettingsWrapper = mediaSettingsWrapper
    self.videoCaptureDeviceFactory = captureDeviceFactory
    self.audioCaptureDeviceFactory = audioCaptureDeviceFactory
    self.captureSessionQueue = captureSessionQueue
    self.videoCaptureSession = captureSessionFactory()
    self.audioCaptureSession = captureSessionFactory()
    self.captureDeviceInputFactory = captureDeviceInputFactory
    self.initialCameraName = initialCameraName
    self.orientation = UIDevice.current.orientation
    self.deviceOrientationProvider = DefaultDeviceOrientationProvider()

    self.videoDimensionsConverter = { format in
      return CMVideoFormatDescriptionGetDimensions(format.formatDescription)
    }

    self.assetWriterFactory = { url, fileType in
      return try AVAssetWriter(outputURL: url, fileType: fileType)
    }

    self.inputPixelBufferAdaptorFactory = { assetWriterInput, sourcePixelBufferAttributes in
      return AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: assetWriterInput.avInput,
        sourcePixelBufferAttributes: sourcePixelBufferAttributes
      )
    }
  }
}
