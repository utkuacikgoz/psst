import AppKit
import ImageIO

// Native vector artwork for the optional Mischief icon; no downloaded assets.
let side = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(srgbRed: 113/255, green: 63/255, blue: 147/255, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: side, height: side).fill()
let w: CGFloat = 650, h: CGFloat = 520, x: CGFloat = 187, y: CGFloat = 275
func point(_ a: CGFloat, _ b: CGFloat) -> NSPoint { NSPoint(x: x + a * w, y: y + (1 - b) * h) }
let cat = NSBezierPath()
cat.move(to: point(0.12, 0.86))
cat.curve(to: point(0.15, 0.30), controlPoint1: point(-0.01, 0.68), controlPoint2: point(0.08, 0.4))
cat.line(to: point(0.13, 0.05)); cat.line(to: point(0.38, 0.24))
cat.curve(to: point(0.65, 0.24), controlPoint1: point(0.46, 0.18), controlPoint2: point(0.57, 0.18))
cat.line(to: point(0.88, 0.04)); cat.line(to: point(0.86, 0.33))
cat.curve(to: point(0.88, 0.86), controlPoint1: point(0.98, 0.46), controlPoint2: point(0.98, 0.70))
cat.close(); NSColor.white.setFill(); cat.fill()
let face = NSBezierPath(); face.lineWidth = 25; face.lineCapStyle = .round; face.lineJoinStyle = .round
face.move(to: point(0.27, 0.48)); face.line(to: point(0.40, 0.53))
face.move(to: point(0.61, 0.52)); face.curve(to: point(0.75, 0.47), controlPoint1: point(0.65, 0.46), controlPoint2: point(0.71, 0.44))
face.move(to: point(0.47, 0.66)); face.line(to: point(0.52, 0.71)); face.line(to: point(0.57, 0.66))
NSColor(srgbRed: 113/255, green: 63/255, blue: 147/255, alpha: 1).setStroke(); face.stroke()
let label = NSAttributedString(string: "psst", attributes: [.font: NSFont.systemFont(ofSize: 170, weight: .heavy), .foregroundColor: NSColor.white])
label.draw(at: NSPoint(x: (1024 - label.size().width) / 2, y: 125))
NSGraphicsContext.current?.flushGraphics()
NSGraphicsContext.restoreGraphicsState()
let output = CommandLine.arguments[1]
let cg = bitmap.cgImage!
let opaque = CGImage(width: cg.width, height: cg.height, bitsPerComponent: 8, bitsPerPixel: 32,
    bytesPerRow: cg.bytesPerRow, space: cg.colorSpace!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
    provider: cg.dataProvider!, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: output) as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(destination, opaque, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Could not export icon") }
