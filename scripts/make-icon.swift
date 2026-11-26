// Draws PhoneBox's app icon (design §12): a dark ocean tile with a phone whose screen shows the dashboard's CPU and
// RAM rings, in the page's colours. Writes an .iconset folder for `iconutil` (scripts/bundle.sh makes AppIcon.icns).
// Usage: swiftc -O make-icon.swift -o make-icon && ./make-icon <output.iconset>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

/// The icon at 1024 × 1024 points, scaled to `pixels`. The tile follows Apple's macOS grid: 824 points with a
/// 100-point margin and a soft shadow below.
func draw(pixels: Int) -> CGImage {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { fail("no drawing context") }
    let scale = CGFloat(pixels) / 1024
    context.scaleBy(x: scale, y: scale)

    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    context.saveGState()
    // Shadows ignore the scale above (they are in pixels), so they are scaled by hand: a 16-pixel icon gets a
    // 16-pixel-sized shadow, not a 1024-pixel one.
    context.setShadow(offset: CGSize(width: 0, height: -12 * scale), blur: 28 * scale, color: color(0x000000, 0.45))
    context.addPath(tilePath)
    context.setFillColor(color(0x04101f))
    context.fillPath()
    context.restoreGState()

    // The tile: deep ocean, lighter at the top.
    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    let ocean = CGGradient(colorsSpace: space, colors: [color(0x0d3557), color(0x041222)] as CFArray,
                           locations: [0, 1])!
    context.drawLinearGradient(ocean, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    // A faint glow behind the phone.
    let glow = CGGradient(colorsSpace: space, colors: [color(0x00c2ff, 0.28), color(0x00c2ff, 0)] as CFArray,
                          locations: [0, 1])!
    context.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 512), startRadius: 0,
                               endCenter: CGPoint(x: 512, y: 512), endRadius: 400, options: [])
    context.restoreGState()

    // The phone: a dark screen in a light frame.
    let phone = CGRect(x: 512 - 190, y: 512 - 320, width: 380, height: 640)
    let body = CGPath(roundedRect: phone, cornerWidth: 78, cornerHeight: 78, transform: nil)
    context.addPath(body)
    context.setFillColor(color(0x01060d))
    context.fillPath()
    context.addPath(body)
    context.setLineWidth(18)
    context.setStrokeColor(color(0xbfe6ff, 0.92))
    context.strokePath()
    // The Dynamic Island.
    let island = CGRect(x: 512 - 52, y: phone.maxY - 62, width: 104, height: 28)
    context.addPath(CGPath(roundedRect: island, cornerWidth: 14, cornerHeight: 14, transform: nil))
    context.setFillColor(color(0xbfe6ff, 0.92))
    context.fillPath()

    // The dashboard's rings: CPU outside, RAM inside, each a track and a bright arc from 12 o'clock.
    let center = CGPoint(x: 512, y: 512)
    func ring(radius: CGFloat, fraction: CGFloat, hex: UInt32) {
        context.setLineWidth(46)
        context.setLineCap(.butt)
        context.setStrokeColor(color(hex, 0.2))
        context.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        context.strokePath()
        context.setLineCap(.round)
        context.setStrokeColor(color(hex))
        let top = CGFloat.pi / 2
        context.addArc(center: center, radius: radius, startAngle: top, endAngle: top - fraction * 2 * .pi,
                       clockwise: true)
        context.strokePath()
    }
    ring(radius: 128, fraction: 0.7, hex: 0x00c2ff)  // CPU
    ring(radius: 72, fraction: 0.45, hex: 0x3d6bff)  // RAM

    guard let image = context.makeImage() else { fail("no image") }
    return image
}

func write(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fail("cannot create \(url.path)") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fail("cannot write \(url.path)") }
}

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset", isDirectory: true)
try? FileManager.default.removeItem(at: output)
do {
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
} catch {
    fail("cannot create \(output.path)")
}
for points in [16, 32, 128, 256, 512] {
    write(draw(pixels: points), to: output.appendingPathComponent("icon_\(points)x\(points).png"))
    write(draw(pixels: points * 2), to: output.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
