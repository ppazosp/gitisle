// Renders an SVG to a square PNG: swift scripts/render-svg.swift input.svg output.png 1024
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 4, let pixels = Int(arguments[3]),
  let image = NSImage(contentsOf: URL(fileURLWithPath: arguments[1]))
else { fatalError("Usage: render-svg.swift input.svg output.png size") }
let bitmap = NSBitmapImageRep(
  bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
  samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
  bytesPerRow: pixels * 4, bitsPerPixel: 32)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSGraphicsContext.current?.imageInterpolation = .high
image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(
  to: URL(fileURLWithPath: arguments[2]))
