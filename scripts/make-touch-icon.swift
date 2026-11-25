// Draws the dashboard's Home Screen icon (design §8 "Ana ekran"): black, with a green and a blue ring like the
// page's CPU and RAM rings. iOS rounds the corners itself.
// Usage: swiftc -O make-touch-icon.swift -o make-touch-icon && ./make-touch-icon <output.png>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

let size = 180
let output = CommandLine.arguments.dropFirst().first ?? "apple-touch-icon.png"
guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else { fail("no drawing context") }

context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: size, height: size))
let center = CGPoint(x: size / 2, y: size / 2)

/// A grey track with a coloured arc that starts at 12 o'clock and runs clockwise for `fraction` of the circle.
func ring(radius: CGFloat, fraction: CGFloat, red: CGFloat, green: CGFloat, blue: CGFloat) {
    context.setLineWidth(18)
    context.setStrokeColor(CGColor(red: 0.173, green: 0.173, blue: 0.18, alpha: 1))
    context.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    context.strokePath()
    context.setLineCap(.round)
    context.setStrokeColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
    let top = CGFloat.pi / 2
    context.addArc(center: center, radius: radius, startAngle: top, endAngle: top - fraction * 2 * .pi, clockwise: true)
    context.strokePath()
}

ring(radius: 62, fraction: 0.68, red: 0.188, green: 0.82, blue: 0.345)  // CPU green #30d158
ring(radius: 36, fraction: 0.45, red: 0.039, green: 0.518, blue: 1)     // RAM blue #0a84ff

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: output) as CFURL,
                                                        UTType.png.identifier as CFString, 1, nil)
else { fail("cannot create \(output)") }
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fail("cannot write \(output)") }
