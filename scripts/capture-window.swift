// Records one app's windows with ScreenCaptureKit, keeping transparency, as ProRes 4444:
//   swift scripts/capture-window.swift <pid> <seconds> <output.mov> [width height]
// Only that app is captured: no desktop, no other apps, no cursor. The region is centred
// horizontally at the top of the app's display (the notch), default 1100 × 700 points.
//
// For product videos, record a tour of the example data:
//   bash scripts/build-app.sh
//   swiftc -O scripts/capture-window.swift -o /tmp/capture-window
//   open -n dist/GitIsle.app --args --tour pages -AppleLocale en_US -AppleLanguages "(en)"
//   /tmp/capture-window "$(pgrep -n -f GitIsle.app/Contents/MacOS/GitIsle)" 34 tour.mov
// `--tour` plays every state of the island (about 25 s); `--tour pages` plays a PR's page,
// its diff, a stack and a failed merge (about 32 s).
import AVFoundation
import AppKit
import CoreMedia
import ScreenCaptureKit

let arguments = CommandLine.arguments
guard arguments.count >= 4, let pid = pid_t(arguments[1]), let seconds = Double(arguments[2]) else {
  fatalError("Usage: capture-window.swift <pid> <seconds> <output.mov> [width height]")
}
let regionWidth = arguments.count > 4 ? Double(arguments[4]) ?? 1100 : 1100
let regionHeight = arguments.count > 5 ? Double(arguments[5]) ?? 700 : 700
let output = URL(fileURLWithPath: arguments[3])
// ScreenCaptureKit needs a window-server connection, which NSApplication sets up.
_ = NSApplication.shared

final class Recorder: NSObject, SCStreamOutput, SCStreamDelegate {
  func stream(_ stream: SCStream, didStopWithError error: Error) {
    print("stream stopped: \(error)")
  }

  let writer: AVAssetWriter
  let input: AVAssetWriterInput
  var started = false
  var frames = 0

  init(url: URL, width: Int, height: Int) throws {
    try? FileManager.default.removeItem(at: url)
    writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    input = AVAssetWriterInput(
      mediaType: .video,
      outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.proRes4444, AVVideoWidthKey: width,
        AVVideoHeightKey: height,
      ])
    input.expectsMediaDataInRealTime = true
    writer.add(input)
  }

  func stream(
    _ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType
  ) {
    guard type == .screen, buffer.isValid,
      let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false)
        as? [[SCStreamFrameInfo: Any]],
      let status = attachments.first?[.status] as? Int,
      SCFrameStatus(rawValue: status) == .complete
    else { return }
    if !started {
      writer.startWriting()
      writer.startSession(atSourceTime: buffer.presentationTimeStamp)
      started = true
    }
    if input.isReadyForMoreMediaData {
      input.append(buffer)
      frames += 1
    }
  }
}

let semaphore = DispatchSemaphore(value: 0)
Task {
  do {
    // The app may still be launching; wait up to ten seconds for its first window.
    var content = try await SCShareableContent.excludingDesktopWindows(
      false, onScreenWindowsOnly: true)
    for _ in 0..<100
    where !content.windows.contains(where: { $0.owningApplication?.processID == pid }) {
      try await Task.sleep(for: .milliseconds(100))
      content = try await SCShareableContent.excludingDesktopWindows(
        false, onScreenWindowsOnly: true)
    }
    guard let app = content.applications.first(where: { $0.processID == pid }),
      let window = content.windows.first(where: { $0.owningApplication?.processID == pid }),
      let display = content.displays.first(where: { $0.frame.intersects(window.frame) })
    else { fatalError("No on-screen window for pid \(pid)") }
    let scale = 2
    let width = Int(regionWidth) * scale
    let height = Int(regionHeight) * scale
    let configuration = SCStreamConfiguration()
    // Display coordinates are relative to the display; the notch is centred at the top.
    configuration.sourceRect = CGRect(
      x: (display.frame.width - regionWidth) / 2, y: 0, width: regionWidth, height: regionHeight)
    configuration.backgroundColor = .clear
    configuration.width = width
    configuration.height = height
    configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
    configuration.pixelFormat = kCVPixelFormatType_32BGRA
    configuration.showsCursor = false
    configuration.queueDepth = 8
    let recorder = try Recorder(url: output, width: width, height: height)
    let filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
    let stream = SCStream(filter: filter, configuration: configuration, delegate: recorder)
    try stream.addStreamOutput(
      recorder, type: .screen, sampleHandlerQueue: DispatchQueue(label: "frames"))
    try await stream.startCapture()
    print(
      "recording \(app.applicationName) on display \(display.displayID) \(width)x\(height) for \(seconds)s"
    )
    try await Task.sleep(for: .seconds(seconds))
    try await stream.stopCapture()
    recorder.input.markAsFinished()
    await recorder.writer.finishWriting()
    print("wrote \(recorder.frames) frames to \(output.path)")
  } catch {
    print("capture failed: \(error)")
  }
  semaphore.signal()
}
semaphore.wait()
