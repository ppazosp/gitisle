import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else { fatalError("Provide an iconset directory") }
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

for size in [16, 32, 128, 256, 512] {
  for scale in [1, 2] {
    let pixels = size * scale
    let factor = CGFloat(pixels) / 1024
    let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
      bytesPerRow: pixels * 4, bitsPerPixel: 32)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    func rectangle(
      _ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ radius: CGFloat
    ) -> NSBezierPath {
      NSBezierPath(
        roundedRect: NSRect(
          x: x * factor, y: y * factor, width: width * factor, height: height * factor),
        xRadius: radius * factor, yRadius: radius * factor)
    }
    NSColor(deviceRed: 0.10, green: 0.14, blue: 0.23, alpha: 1).setFill()
    rectangle(48, 48, 928, 928, 206).fill()
    NSColor(deviceRed: 0.02, green: 0.03, blue: 0.05, alpha: 1).setFill()
    rectangle(146, 366, 732, 292, 146).fill()
    let accent = NSColor(deviceRed: 0.39, green: 0.87, blue: 0.83, alpha: 1)
    accent.setStroke()
    let connection = NSBezierPath()
    connection.move(to: NSPoint(x: 342 * factor, y: 466 * factor))
    connection.line(to: NSPoint(x: 474 * factor, y: 466 * factor))
    connection.curve(
      to: NSPoint(x: 618 * factor, y: 562 * factor),
      controlPoint1: NSPoint(x: 548 * factor, y: 466 * factor),
      controlPoint2: NSPoint(x: 546 * factor, y: 562 * factor))
    connection.lineWidth = 28 * factor
    connection.lineCapStyle = .round
    connection.stroke()
    accent.setFill()
    for (x, y) in [(342.0, 466.0), (618.0, 562.0), (682.0, 466.0)] {
      NSBezierPath(
        ovalIn: NSRect(
          x: (x - 28) * factor, y: (y - 28) * factor,
          width: 56 * factor, height: 56 * factor)
      ).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    let suffix = scale == 2 ? "@2x" : ""
    let destination = directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
    try bitmap.representation(using: .png, properties: [:])!.write(to: destination)
  }
}
