// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import AVFoundation
import XCTest

@testable import camera_avfoundation

private class FakeMediaSettingsAVWrapper: FLTCamMediaSettingsAVWrapper {
  let inputMock: MockAssetWriterInput

  init(inputMock: MockAssetWriterInput) {
    self.inputMock = inputMock
  }

  override func lockDevice(_ captureDevice: CaptureDevice) throws {
    // No-op.
  }

  override func unlockDevice(_ captureDevice: CaptureDevice) {
    // No-op.
  }

  override func beginConfiguration(for videoCaptureSession: CaptureSession) {
    // No-op.
  }

  override func commitConfiguration(for videoCaptureSession: CaptureSession) {
    // No-op.
  }

  override func setMinFrameDuration(_ duration: CMTime, on captureDevice: CaptureDevice) {
    // No-op.
  }

  override func setMaxFrameDuration(_ duration: CMTime, on captureDevice: CaptureDevice) {
    // No-op.
  }

  override func assetWriterAudioInput(withOutputSettings outputSettings: [String: Any]?)
    -> AssetWriterInput
  {
    return inputMock
  }

  override func assetWriterVideoInput(withOutputSettings outputSettings: [String: Any]?)
    -> AssetWriterInput
  {
    return inputMock
  }

  override func addInput(_ writerInput: AssetWriterInput, to writer: AssetWriter) {
    // No-op.
  }

  override func recommendedVideoSettingsForAssetWriter(
    withFileType fileType: AVFileType, for output: CaptureVideoDataOutput
  ) -> [String: Any]? {
    return [:]
  }
}

/// Includes test cases related to sample buffer handling for Camera class.
final class CameraSampleBufferTests: XCTestCase {
  private func createCamera() -> (
    DefaultCamera,
    MockAssetWriter,
    MockAssetWriterInputPixelBufferAdaptor,
    MockAssetWriterInput
  ) {
    let assetWriter = MockAssetWriter()
    let adaptor = MockAssetWriterInputPixelBufferAdaptor()
    let input = MockAssetWriterInput()

    let configuration = CameraTestUtils.createTestCameraConfiguration()
    configuration.mediaSettings = PlatformMediaSettings(
      resolutionPreset: .medium,
      framesPerSecond: nil,
      videoBitrate: nil,
      audioBitrate: nil,
      enableAudio: true)
    configuration.mediaSettingsWrapper = FakeMediaSettingsAVWrapper(inputMock: input)

    configuration.assetWriterFactory = { url, fileType in
      return assetWriter
    }
    configuration.inputPixelBufferAdaptorFactory = { input, settings in
      return adaptor
    }

    return (
      CameraTestUtils.createTestCamera(configuration),
      assetWriter,
      adaptor,
      input
    )
  }

  func testSampleBufferCallbackQueueMustBeCaptureSessionQueue() {
    let captureSessionQueue = DispatchQueue(label: "testing")
    let camera = CameraTestUtils.createCameraWithCaptureSessionQueue(captureSessionQueue)
    XCTAssertEqual(
      captureSessionQueue, camera.captureVideoOutput.avOutput.sampleBufferCallbackQueue,
      "Sample buffer callback queue must be the capture session queue.")
  }

  func testCopyPixelBuffer() {
    let (camera, _, _, _) = createCamera()
    let capturedSampleBuffer = CameraTestUtils.createTestSampleBuffer()
    let capturedPixelBuffer = CMSampleBufferGetImageBuffer(capturedSampleBuffer)!
    let testConnection = CameraTestUtils.createTestConnection(camera.captureVideoOutput.avOutput)

    // Mimic sample buffer callback when captured a new video sample.
    camera.captureOutput(
      camera.captureVideoOutput.avOutput,
      didOutput: capturedSampleBuffer,
      from: testConnection)
    let deliveredPixelBuffer = camera.copyPixelBuffer()?.takeRetainedValue()
    XCTAssertEqual(
      deliveredPixelBuffer, capturedPixelBuffer,
      "Camera must deliver the latest captured pixel buffer to copyPixelBuffer API.")
  }

  func testDidOutputSampleBuffer_mustNotChangeSampleBufferRetainCountAfterPauseResumeRecording() {
    let (camera, _, _, _) = createCamera()
    let sampleBuffer = CameraTestUtils.createTestSampleBuffer()
    let testConnection = CameraTestUtils.createTestConnection(camera.captureVideoOutput.avOutput)

    let initialRetainCount = CFGetRetainCount(sampleBuffer)

    // Pause then resume the recording.
    camera.startVideoRecording(completion: { error in }, messengerForStreaming: nil)
    camera.pauseVideoRecording()
    camera.resumeVideoRecording()

    camera.captureOutput(
      camera.captureVideoOutput.avOutput,
      didOutput: sampleBuffer,
      from: testConnection)

    let finalRetainCount = CFGetRetainCount(sampleBuffer)
    XCTAssertEqual(
      finalRetainCount, initialRetainCount,
      "didOutputSampleBuffer must not change the sample buffer retain count after pause resume recording."
    )
  }

  func testDidOutputSampleBufferIgnoreAudioSamplesBeforeVideoSamples() {
    let (camera, writerMock, adaptorMock, inputMock) = createCamera()
    var status = AVAssetWriter.Status.unknown
    writerMock.startWritingStub = {
      status = .writing
      return true
    }
    writerMock.statusStub = {
      return status
    }

    let videoSample = CameraTestUtils.createTestSampleBuffer()
    let testVideoConnection = CameraTestUtils.createTestConnection(
      camera.captureVideoOutput.avOutput)

    let audioSample = CameraTestUtils.createTestAudioSampleBuffer()
    let testAudioOutput = CameraTestUtils.createTestAudioOutput()
    let testAudioConnection = CameraTestUtils.createTestConnection(testAudioOutput)

    var writtenSamples: [String] = []
    adaptorMock.appendStub = { buffer, time in
      writtenSamples.append("video")
      return true
    }
    inputMock.isReadyForMoreMediaData = true
    inputMock.appendStub = { buffer in
      writtenSamples.append("audio")
      return true
    }

    camera.startVideoRecording(completion: { error in }, messengerForStreaming: nil)
    camera.captureOutput(testAudioOutput, didOutput: audioSample, from: testAudioConnection)
    camera.captureOutput(testAudioOutput, didOutput: audioSample, from: testAudioConnection)
    camera.captureOutput(
      camera.captureVideoOutput.avOutput,
      didOutput: videoSample,
      from: testVideoConnection)
    camera.captureOutput(testAudioOutput, didOutput: audioSample, from: testAudioConnection)

    let expectedSamples = ["video", "audio"]
    XCTAssertEqual(writtenSamples, expectedSamples, "First appended sample must be video.")
  }

  func testDidOutputSampleBufferSampleTimesMustBeNumericAfterPauseResume() {
    let (camera, writerMock, adaptorMock, inputMock) = createCamera()

    let videoSample = CameraTestUtils.createTestSampleBuffer()
    let testVideoConnection = CameraTestUtils.createTestConnection(
      camera.captureVideoOutput.avOutput)

    let audioSample = CameraTestUtils.createTestAudioSampleBuffer()
    let testAudioOutput = CameraTestUtils.createTestAudioOutput()
    let testAudioConnection = CameraTestUtils.createTestConnection(testAudioOutput)

    var status = AVAssetWriter.Status.unknown
    writerMock.startWritingStub = {
      status = .writing
      return true
    }
    writerMock.statusStub = {
      return status
    }

    var videoAppended = false
    adaptorMock.appendStub = { buffer, time in
      XCTAssert(CMTIME_IS_NUMERIC(time))
      videoAppended = true
      return true
    }

    var audioAppended = false
    inputMock.isReadyForMoreMediaData = true
    inputMock.appendStub = { buffer in
      let sampleTime = CMSampleBufferGetPresentationTimeStamp(buffer)
      XCTAssert(CMTIME_IS_NUMERIC(sampleTime))
      audioAppended = true
      return true
    }

    camera.startVideoRecording(completion: { error in }, messengerForStreaming: nil)
    camera.pauseVideoRecording()
    camera.resumeVideoRecording()
    camera.captureOutput(
      camera.captureVideoOutput.avOutput,
      didOutput: videoSample,
      from: testVideoConnection)
    camera.captureOutput(testAudioOutput, didOutput: audioSample, from: testAudioConnection)
    camera.captureOutput(
      camera.captureVideoOutput.avOutput,
      didOutput: videoSample,
      from: testVideoConnection)
    camera.captureOutput(testAudioOutput, didOutput: audioSample, from: testAudioConnection)

    XCTAssert(videoAppended && audioAppended, "Video or audio was not appended.")
  }

  func testDidOutputSampleBufferMustNotAppendSampleWhenReadyForMoreMediaDataIsFalse() {
    let (camera, _, adaptorMock, inputMock) = createCamera()

    let videoSample = CameraTestUtils.createTestSampleBuffer()
    let testVideoConnection = CameraTestUtils.createTestConnection(
      camera.captureVideoOutput.avOutput)

    var sampleAppended = false
    adaptorMock.appendStub = { buffer, time in
      sampleAppended = true
      return true
    }

    camera.startVideoRecording(completion: { error in }, messengerForStreaming: nil)

    inputMock.isReadyForMoreMediaData = true
    sampleAppended = false
    camera.captureOutput(
      camera.captureVideoOutput.avOutput,
      didOutput: videoSample,
      from: testVideoConnection)
    XCTAssertTrue(sampleAppended, "Sample was not appended.")

    inputMock.isReadyForMoreMediaData = false
    sampleAppended = false
    camera.captureOutput(
      camera.captureVideoOutput.avOutput,
      didOutput: videoSample,
      from: testVideoConnection)
    XCTAssertFalse(sampleAppended, "Sample cannot be appended when readyForMoreMediaData is NO.")
  }

  func testStopVideoRecordingWithCompletionMustCallCompletion() {
    let (camera, writerMock, _, _) = createCamera()

    var status = AVAssetWriter.Status.unknown
    writerMock.startWritingStub = {
      status = .writing
      return true
    }
    writerMock.statusStub = {
      return status
    }
    writerMock.finishWritingStub = { handler in
      XCTAssert(
        writerMock.status == .writing,
        "Cannot call finishWritingWithCompletionHandler when status is not AVAssetWriter.Status.writing."
      )
      handler()
    }

    camera.startVideoRecording(completion: { error in }, messengerForStreaming: nil)
    var completionCalled = false
    camera.stopVideoRecording(completion: { result in
      completionCalled = true
    })

    XCTAssert(completionCalled, "Completion was not called.")
  }

  func testStartWritingShouldNotBeCalledBetweenSampleCreationAndAppending() {
    let (camera, writerMock, adaptorMock, inputMock) = createCamera()

    let videoSample = CameraTestUtils.createTestSampleBuffer()
    let testVideoConnection = CameraTestUtils.createTestConnection(
      camera.captureVideoOutput.avOutput)

    var startWritingCalled = false
    writerMock.startWritingStub = {
      startWritingCalled = true
      return true

    }

    var videoAppended = false
    adaptorMock.appendStub = { buffer, time in
      videoAppended = true
      return true
    }

    inputMock.isReadyForMoreMediaData = true

    camera.startVideoRecording(completion: { error in }, messengerForStreaming: nil)

    let startWritingCalledBefore = startWritingCalled
    camera.captureOutput(
      camera.captureVideoOutput.avOutput,
      didOutput: videoSample,
      from: testVideoConnection)
    XCTAssert(
      (startWritingCalledBefore && videoAppended) || (startWritingCalled && !videoAppended),
      "The startWriting was called between sample creation and appending.")

    camera.captureOutput(
      camera.captureVideoOutput.avOutput,
      didOutput: videoSample,
      from: testVideoConnection)
    XCTAssert(videoAppended, "Video was not appended.")
  }

  func testStartVideoRecordingWithCompletionShouldNotDisableMixWithOthers() {
    let cam = CameraTestUtils.createCameraWithCaptureSessionQueue(DispatchQueue(label: "testing"))

    try? AVAudioSession.sharedInstance().setCategory(.playback, options: .mixWithOthers)
    cam.startVideoRecording(completion: { error in }, messengerForStreaming: nil)
    XCTAssert(
      AVAudioSession.sharedInstance().categoryOptions.contains(.mixWithOthers),
      "Flag MixWithOthers was removed.")
    XCTAssert(
      AVAudioSession.sharedInstance().category == .playAndRecord,
      "Category should be PlayAndRecord.")
  }

  func testDidOutputSampleBufferMustUseSingleOffsetForVideoAndAudio() {
    let (camera, writerMock, adaptorMock, inputMock) = createCamera()

    let testVideoConnection = CameraTestUtils.createTestConnection(
      camera.captureVideoOutput.avOutput)
    let testAudioOutput = CameraTestUtils.createTestAudioOutput()
    let testAudioConnection = CameraTestUtils.createTestConnection(testAudioOutput)

    var status = AVAssetWriter.Status.unknown
    writerMock.startWritingStub = {
      status = .writing
      return true
    }
    writerMock.statusStub = {
      return status
    }

    var appendedTime = CMTime.invalid

    adaptorMock.appendStub = { buffer, time in
      appendedTime = time
      return true
    }

    inputMock.isReadyForMoreMediaData = true
    inputMock.appendStub = { buffer in
      appendedTime = CMSampleBufferGetPresentationTimeStamp(buffer)
      return true
    }

    camera.startVideoRecording(completion: { error in }, messengerForStreaming: nil)

    let appendVideoSample = { (time: Int64) in
      camera.captureOutput(
        camera.captureVideoOutput.avOutput,
        didOutput: CameraTestUtils.createTestSampleBuffer(
          timestamp: CMTimeMake(value: time, timescale: 1),
          duration: .invalid),
        from: testVideoConnection)
    }

    let appendAudioSample = { (time: Int64, duration: Int64) in
      camera.captureOutput(
        testAudioOutput,
        didOutput: CameraTestUtils.createTestAudioSampleBuffer(
          timestamp: CMTimeMake(value: time, timescale: 1),
          duration: CMTimeMake(value: duration, timescale: 1)),
        from: testAudioConnection)
    }

    appendedTime = .invalid
    camera.pauseVideoRecording()
    camera.resumeVideoRecording()
    appendVideoSample(1)
    XCTAssertEqual(appendedTime, CMTimeMake(value: 1, timescale: 1))

    appendedTime = .invalid
    camera.pauseVideoRecording()
    camera.resumeVideoRecording()
    appendVideoSample(11)
    XCTAssertEqual(appendedTime, .invalid)
    appendVideoSample(12)
    XCTAssertEqual(appendedTime, CMTimeMake(value: 2, timescale: 1))

    appendedTime = .invalid
    camera.pauseVideoRecording()
    camera.resumeVideoRecording()
    appendAudioSample(20, 2)
    XCTAssertEqual(appendedTime, .invalid)
    appendVideoSample(23)
    XCTAssertEqual(appendedTime, CMTimeMake(value: 3, timescale: 1))

    appendedTime = .invalid
    camera.pauseVideoRecording()
    camera.resumeVideoRecording()
    appendVideoSample(28)
    XCTAssertEqual(appendedTime, .invalid)
    appendAudioSample(30, 2)
    XCTAssertEqual(appendedTime, .invalid)
    appendVideoSample(33)
    XCTAssertEqual(appendedTime, .invalid)
    appendAudioSample(32, 2)
    XCTAssertEqual(appendedTime, CMTimeMake(value: 2, timescale: 1))
  }

  func testDidOutputSampleBufferMustConnectVideoAfterSessionInterruption() {
    let (camera, writerMock, adaptorMock, inputMock) = createCamera()

    let testVideoConnection = CameraTestUtils.createTestConnection(
      camera.captureVideoOutput.avOutput)
    let testAudioOutput = CameraTestUtils.createTestAudioOutput()
    let testAudioConnection = CameraTestUtils.createTestConnection(testAudioOutput)

    var status = AVAssetWriter.Status.unknown
    writerMock.startWritingStub = {
      status = .writing
      return true
    }
    writerMock.statusStub = {
      return status
    }

    var appendedTime = CMTime.invalid

    adaptorMock.appendStub = { buffer, time in
      appendedTime = time
      return true
    }

    inputMock.isReadyForMoreMediaData = true
    inputMock.appendStub = { buffer in
      appendedTime = CMSampleBufferGetPresentationTimeStamp(buffer)
      return true
    }

    camera.startVideoRecording(completion: { error in }, messengerForStreaming: nil)

    let appendVideoSample = { (time: Int64) in
      camera.captureOutput(
        camera.captureVideoOutput.avOutput,
        didOutput: CameraTestUtils.createTestSampleBuffer(
          timestamp: CMTimeMake(value: time, timescale: 1),
          duration: .invalid),
        from: testVideoConnection)
    }

    let appendAudioSample = { (time: Int64, duration: Int64) in
      camera.captureOutput(
        testAudioOutput,
        didOutput: CameraTestUtils.createTestAudioSampleBuffer(
          timestamp: CMTimeMake(value: time, timescale: 1),
          duration: CMTimeMake(value: duration, timescale: 1)),
        from: testAudioConnection)
    }

    appendVideoSample(1)
    appendAudioSample(1, 1)

    NotificationCenter.default.post(
      name: AVCaptureSession.wasInterruptedNotification,
      object: camera.audioCaptureSession)

    appendedTime = .invalid
    appendAudioSample(11, 1)
    XCTAssertEqual(appendedTime, .invalid)
    appendVideoSample(12)
    XCTAssertEqual(appendedTime, CMTimeMake(value: 2, timescale: 1))
    appendedTime = .invalid
    appendAudioSample(12, 1)
    XCTAssertEqual(appendedTime, CMTimeMake(value: 2, timescale: 1))
  }

  func testStartVideoRecordingReportsErrorWhenStartWritingFails() {
    let (camera, writerMock, _, _) = createCamera()

    // Configure the mock to return false for startWriting
    writerMock.startWritingStub = {
      return false
    }

    // Configure a mock error
    let mockError = NSError(
      domain: "test", code: 123, userInfo: [NSLocalizedDescriptionKey: "Mock write error"])
    writerMock.error = mockError

    let expectation = self.expectation(description: "Completion handler called with error")

    camera.startVideoRecording(
      completion: { result in
        switch result {
        case .failure(let error as PigeonError):
          XCTAssertEqual(error.code, "IOError")
          XCTAssertEqual(error.message, "AVAssetWriter failed to start writing")
          XCTAssertEqual(error.details as? String, "Mock write error")
          XCTAssertFalse(camera.isRecording)
          expectation.fulfill()
        default:
          XCTFail("Expected PigeonError")
        }

      }, messengerForStreaming: nil)

    waitForExpectations(timeout: 1.0, handler: nil)
  }

  func testSetDescriptionWhileRecording_reconnectsBothOutputsAndUpdatesMaxPhotoDimensions()
    throws
  {
    guard #available(iOS 16.0, *) else {
      throw XCTSkip("maxPhotoDimensions requires iOS 16.")
    }

    let inputMock = MockAssetWriterInput()
    let configuration = CameraTestUtils.createTestCameraConfiguration()
    configuration.mediaSettingsWrapper = FakeMediaSettingsAVWrapper(inputMock: inputMock)

    let videoSessionMock = MockCaptureSession()
    videoSessionMock.canSetSessionPresetStub = { _ in true }
    configuration.videoCaptureSession = videoSessionMock

    let initialDeviceMock = MockCaptureDevice()
    let newFormatMock = MockCaptureDeviceFormat()
    newFormatMock.supportedMaxPhotoDimensions = [
      CMVideoDimensions(width: 1920, height: 1080),
      CMVideoDimensions(width: 4032, height: 3024),
    ]
    let newDeviceMock = MockCaptureDevice()
    newDeviceMock.activeFormatStub = { newFormatMock }

    configuration.videoCaptureDeviceFactory = { name in
      return name == "new_camera" ? newDeviceMock : initialDeviceMock
    }

    let camera = CameraTestUtils.createTestCamera(configuration)
    let mockPhotoOutput = MockCapturePhotoOutput()
    mockPhotoOutput.avOutput = camera.capturePhotoOutput.avOutput
    camera.capturePhotoOutput = mockPhotoOutput

    camera.startVideoRecording(completion: { _ in }, messengerForStreaming: nil)

    let expectation = self.expectation(description: "setDescriptionWhileRecording completed")
    camera.setDescriptionWhileRecording("new_camera") { result in
      let _ = self.assertSuccess(result)
      expectation.fulfill()
    }

    waitForExpectations(timeout: 1.0, handler: nil)

    XCTAssertEqual(videoSessionMock.connections.count, 2)
    XCTAssertTrue(
      videoSessionMock.connections.contains(where: {
        $0.output === camera.captureVideoOutput.avOutput
      }))
    XCTAssertTrue(
      videoSessionMock.connections.contains(where: {
        $0.output === mockPhotoOutput.avOutput
      }))
    XCTAssertEqual(mockPhotoOutput.maxPhotoDimensions.width, 4032)
    XCTAssertEqual(mockPhotoOutput.maxPhotoDimensions.height, 3024)
  }
  // These cases use the real DefaultCamera transaction and graph-owning native
  // mocks. The same tests also run against the retained upstream implementation.
  func testRecordingSwitchCreationFailurePreservesCapture() {
    assertRecordingSwitchRecovery(fault: .creation)
  }

  func testRecordingSwitchInputRejectionRestoresCapture() {
    assertRecordingSwitchRecovery(fault: .input)
  }

  func testRecordingSwitchOutputRejectionRestoresCapture() {
    assertRecordingSwitchRecovery(fault: .output)
  }

  func testRecordingSwitchConnectionRejectionRestoresCapture() {
    assertRecordingSwitchRecovery(fault: .connection)
  }

  private enum RecordingSwitchFault: Equatable { case creation, input, output, connection }

  private func assertRecordingSwitchRecovery(
    fault: RecordingSwitchFault, file: StaticString = #filePath, line: UInt = #line
  ) {
    let configuration = CameraTestUtils.createTestCameraConfiguration()
    configuration.mediaSettingsWrapper = FakeMediaSettingsAVWrapper(
      inputMock: MockAssetWriterInput())
    let video = configuration.videoCaptureSession as! MockCaptureSession
    let audio = configuration.audioCaptureSession as! MockCaptureSession
    let inputFactory = configuration.captureDeviceInputFactory as! MockCaptureDeviceInputFactory
    let initialDeviceFactory = configuration.videoCaptureDeviceFactory
    let nextDevice = MockCaptureDevice()
    configuration.videoCaptureDeviceFactory = { name in
      name == "replacement" ? nextDevice : initialDeviceFactory(name)
    }
    let writer = MockAssetWriter()
    var writerCreations = 0
    var writerStarts = 0
    var writerFinishes = 0
    var writerCompleted = false
    var writerURL: URL?
    writer.statusStub = { writerCompleted ? .completed : .writing }
    writer.startWritingStub = {
      writerStarts += 1
      return true
    }
    writer.finishWritingStub = { complete in
      writerFinishes += 1
      writerCompleted = true
      complete()
    }
    configuration.assetWriterFactory = { url, _ in
      writerCreations += 1
      writerURL = url
      return writer
    }
    var audioStarts = 0
    var audioStops = 0
    audio.startRunningStub = { audioStarts += 1 }
    audio.stopRunningStub = { audioStops += 1 }
    let camera = CameraTestUtils.createTestCamera(configuration)
    var starts = 0
    camera.startVideoRecording(
      completion: { result in
        _ = self.assertSuccess(result, file: file, line: line)
        starts += 1
      }, messengerForStreaming: nil)
    XCTAssertEqual(starts, 1, file: file, line: line)
    XCTAssertTrue(camera.isRecording, file: file, line: line)

    let oldDevice = camera.captureDevice
    let oldOutput = camera.captureVideoOutput.avOutput
    let oldInputs = video.captureInputs
    let oldOutputs = video.outputs
    let oldConnections = video.connections
    let oldAudioInputs = audio.captureInputs
    let oldAudioOutputs = audio.outputs
    let oldAudioStarts = audioStarts
    let oldAudioStops = audioStops
    let oldAudioOutputCount = audio.addedAudioOutputCount
    XCTAssertEqual(oldConnections.count, 2, file: file, line: line)
    XCTAssertTrue(
      oldOutput.sampleBufferDelegate === camera, "Initial capture delegate",
      file: file, line: line)
    var depth = 0
    var begins = 0
    var commits = 0
    video.beginConfigurationStub = {
      depth += 1
      begins += 1
    }
    video.commitConfigurationStub = {
      depth -= 1
      commits += 1
    }
    video.stopRunningStub = {
      XCTAssertEqual(
        depth, 0, "CAMERA_SWITCH_RECOVERY configuration balanced", file: file, line: line)
    }
    inputFactory.deviceInputStub = { _ in
      if fault == .creation { throw NSError(domain: "recording-switch-input", code: 1) }
      return MockCaptureInput()
    }
    if fault == .input { video.canAddInputStub = { _ in false } }
    if fault == .output { video.canAddOutputStub = { _ in false } }
    if fault == .connection { video.canAddConnectionStub = { _ in false } }

    func assertOriginalGraph() {
      XCTAssertEqual(
        depth, 0, "CAMERA_SWITCH_RECOVERY configuration balanced", file: file, line: line)
      XCTAssertEqual(begins, commits, file: file, line: line)
      XCTAssertTrue(
        camera.captureDevice === oldDevice, "CAMERA_SWITCH_RECOVERY original device", file: file,
        line: line)
      XCTAssertTrue(camera.captureVideoOutput.avOutput === oldOutput, file: file, line: line)
      XCTAssertTrue(
        oldOutput.sampleBufferDelegate === camera, "CAMERA_SWITCH_RECOVERY original delegate",
        file: file, line: line)
      XCTAssertEqual(video.captureInputs.count, oldInputs.count, file: file, line: line)
      for input in oldInputs {
        XCTAssertTrue(video.captureInputs.contains { $0 === input }, file: file, line: line)
      }
      XCTAssertEqual(video.outputs.count, oldOutputs.count, file: file, line: line)
      for output in oldOutputs {
        XCTAssertTrue(video.outputs.contains { $0 === output }, file: file, line: line)
      }
      XCTAssertEqual(video.connections.count, oldConnections.count, file: file, line: line)
      for connection in oldConnections {
        XCTAssertTrue(video.connections.contains { $0 === connection }, file: file, line: line)
      }
      XCTAssertTrue(camera.isRecording, file: file, line: line)
      XCTAssertEqual(writerCreations, 1, file: file, line: line)
      XCTAssertEqual(writerStarts, 1, file: file, line: line)
      XCTAssertEqual(writerFinishes, 0, file: file, line: line)
      XCTAssertEqual(audioStarts, oldAudioStarts, file: file, line: line)
      XCTAssertEqual(audioStops, oldAudioStops, file: file, line: line)
      XCTAssertEqual(audio.addedAudioOutputCount, oldAudioOutputCount, file: file, line: line)
      XCTAssertEqual(audio.captureInputs.count, oldAudioInputs.count, file: file, line: line)
      for input in oldAudioInputs {
        XCTAssertTrue(audio.captureInputs.contains { $0 === input }, file: file, line: line)
      }
      XCTAssertEqual(audio.outputs.count, oldAudioOutputs.count, file: file, line: line)
      for output in oldAudioOutputs {
        XCTAssertTrue(audio.outputs.contains { $0 === output }, file: file, line: line)
      }
    }
    var completions = 0
    var failures = 0
    camera.setDescriptionWhileRecording("replacement") { result in
      completions += 1
      if case .failure(let error) = result {
        failures += 1
        XCTAssertEqual((error as? PigeonError)?.code, "VideoError", file: file, line: line)
        assertOriginalGraph()  // Rollback must finish before reporting the error.
      }
    }
    XCTAssertEqual(completions, 1, "CAMERA_SWITCH_RECOVERY completion once", file: file, line: line)
    XCTAssertEqual(failures, 1, file: file, line: line)
    assertOriginalGraph()
    XCTAssertEqual(begins, fault == .creation ? 0 : 1, file: file, line: line)

    inputFactory.deviceInputStub = nil
    video.canAddInputStub = nil
    video.canAddOutputStub = nil
    video.canAddConnectionStub = nil
    var retries = 0
    camera.setDescriptionWhileRecording("replacement") { result in
      _ = self.assertSuccess(result, file: file, line: line)
      retries += 1
      XCTAssertEqual(
        depth, 0, "CAMERA_SWITCH_RECOVERY configuration balanced", file: file, line: line)
    }
    XCTAssertEqual(retries, 1, file: file, line: line)
    XCTAssertTrue(camera.captureDevice === nextDevice, file: file, line: line)
    XCTAssertEqual(video.connections.count, 2, file: file, line: line)
    XCTAssertTrue(
      video.connections.contains { $0.output === camera.captureVideoOutput.avOutput },
      file: file, line: line)
    XCTAssertTrue(
      video.connections.contains { $0.output === camera.capturePhotoOutput.avOutput },
      file: file, line: line)
    XCTAssertTrue(
      camera.captureVideoOutput.avOutput.sampleBufferDelegate === camera,
      file: file, line: line)
    XCTAssertEqual(writerCreations, 1, file: file, line: line)
    XCTAssertEqual(writerStarts, 1, file: file, line: line)
    XCTAssertEqual(writerFinishes, 0, file: file, line: line)
    XCTAssertEqual(audioStarts, oldAudioStarts, file: file, line: line)
    XCTAssertEqual(audioStops, oldAudioStops, file: file, line: line)
    var stops = 0
    camera.stopVideoRecording { result in
      XCTAssertEqual(
        self.assertSuccess(result, file: file, line: line), writerURL?.path,
        file: file, line: line)
      stops += 1
    }
    XCTAssertEqual(stops, 1, file: file, line: line)
    XCTAssertEqual(writerFinishes, 1, file: file, line: line)
    XCTAssertFalse(camera.isRecording, file: file, line: line)
    XCTAssertEqual(begins, commits, file: file, line: line)
    camera.close()
  }
}
