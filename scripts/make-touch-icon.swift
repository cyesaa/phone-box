// Draws the dashboard's Home Screen icon (design §8 "Ana ekran"): the page's dark background with its CPU and RAM
// rings in their colours, like the Mac app's icon (scripts/make-icon.swift). iOS rounds the corners itself.
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

context.setFillColor(CGColor(red: 0.004, green: 0.024, blue: 0.051, alpha: 1))  // #01060d, the page's background
context.fill(CGRect(x: 0, y: 0, width: size, height: size))
let center = CGPoint(x: size / 2, y: size / 2)

/// A grey track with a coloured arc that starts at 12 o'clock and runs clockwise for `fraction` of the circle.
func ring(radius: CGFloat, fraction: CGFloat, red: CGFloat, green: CGFloat, blue: CGFloat) {
    context.setLineWidth(18)
    context.setStrokeColor(CGColor(red: red, green: green, blue: blue, alpha: 0.2))
    context.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    context.strokePath()
    context.setLineCap(.round)
    context.setStrokeColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
    let top = CGFloat.pi / 2
    context.addArc(center: center, radius: radius, startAngle: top, endAngle: top - fraction * 2 * .pi, clockwise: true)
    context.strokePath()
}

ring(radius: 62, fraction: 0.7, red: 0, green: 0.761, blue: 1)        // CPU #00c2ff
ring(radius: 36, fraction: 0.45, red: 0.239, green: 0.42, blue: 1)    // RAM #3d6bff

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: output) as CFURL,
                                                        UTType.png.identifier as CFString, 1, nil)
else { fail("cannot create \(output)") }
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fail("cannot write \(output)") }
