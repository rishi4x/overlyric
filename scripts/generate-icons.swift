import AppKit
import Foundation

// Render the supplied SVG's cubic quote path directly, preserving its geometry.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let output = root.appendingPathComponent("Resources/Icons")
let svg = try String(contentsOf: output.appendingPathComponent("quote-icon.svg"), encoding: .utf8)
let expression = try NSRegularExpression(pattern: #"\sd="([^"]+)""#)
let match = expression.firstMatch(in: svg, range: NSRange(svg.startIndex..., in: svg))!
let pathText = String(svg[Range(match.range(at: 1), in: svg)!])
let tokenExpression = try NSRegularExpression(pattern: #"[MCZ]|[-+]?\d*\.?\d+"#)
let tokens = tokenExpression.matches(in: pathText, range: NSRange(pathText.startIndex..., in: pathText))
    .map { String(pathText[Range($0.range, in: pathText)!]) }
var cursor = 0
func number() -> CGFloat {
    defer { cursor += 1 }
    return CGFloat(Double(tokens[cursor])!)
}
let quote = CGMutablePath()
while cursor < tokens.count {
    let command = tokens[cursor]
    cursor += 1
    switch command {
    case "M": quote.move(to: CGPoint(x: number(), y: number()))
    case "C":
        let first = CGPoint(x: number(), y: number())
        let second = CGPoint(x: number(), y: number())
        let end = CGPoint(x: number(), y: number())
        quote.addCurve(to: end, control1: first, control2: second)
    case "Z": quote.closeSubpath()
    default: fatalError("Unsupported SVG command: \(command)")
    }
}

func drawQuotes(_ context: CGContext, in rect: CGRect) {
    context.saveGState()
    context.translateBy(x: rect.minX, y: rect.maxY)
    context.scaleBy(x: rect.width / 435, y: -rect.height / 328)
    context.addPath(quote)
    context.fillPath()
    context.translateBy(x: 232, y: 0)
    context.addPath(quote)
    context.fillPath()
    context.restoreGState()
}

func render(size: Int, menuBar: Bool, to url: URL) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    let context = graphics.cgContext
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    if menuBar {
        context.setFillColor(NSColor.black.cgColor)
        context.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: 1024, height: 1024),
            cornerWidth: 230, cornerHeight: 230, transform: nil))
        context.fillPath()
        context.setBlendMode(.clear)
        drawQuotes(context, in: CGRect(x: 150, y: 239, width: 724, height: 546))
    } else {
        context.setFillColor(NSColor(srgbRed: 0.95, green: 0.94, blue: 0.91, alpha: 1).cgColor)
        context.addPath(CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
            cornerWidth: 184, cornerHeight: 184, transform: nil))
        context.fillPath()
        context.setFillColor(NSColor(srgbRed: 0.22, green: 0.23, blue: 0.24, alpha: 1).cgColor)
        drawQuotes(context, in: CGRect(x: 217, y: 289.5, width: 590, height: 445))
    }
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: url)
}

let iconset = root.appendingPathComponent(".build/AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try render(size: size, menuBar: false, to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size: size * 2, menuBar: false, to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
try render(size: 1024, menuBar: false, to: output.appendingPathComponent("AppIcon.png"))
try render(size: 18, menuBar: true, to: output.appendingPathComponent("MenuBarIcon.png"))
try render(size: 36, menuBar: true, to: output.appendingPathComponent("MenuBarIcon@2x.png"))
try render(size: 54, menuBar: true, to: output.appendingPathComponent("MenuBarIcon@3x.png"))
