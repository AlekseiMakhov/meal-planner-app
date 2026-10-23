// Draws the Meal Planner app icon: a plate with a leaf between a fork and a knife, on a warm gradient; the Debug
// build's icon is the same on blue, so the two copies are told apart in the Dock. Full bleed: macOS rounds the
// corners. `make icon` writes every size into the asset catalog.
// Usage: swift draw_icon.swift <output folder> <release|debug>
import AppKit
import CoreGraphics

let output = URL(filePath: CommandLine.arguments[1], directoryHint: .isDirectory)
let isDebug = CommandLine.arguments.count > 2 && CommandLine.arguments[2] == "debug"

func rgb(_ r: Int, _ g: Int, _ b: Int, _ a: Double = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let top = isDebug ? rgb(110, 170, 255) : rgb(255, 166, 77)
let bottom = isDebug ? rgb(58, 86, 214) : rgb(236, 74, 42)

func draw(_ ctx: CGContext) {
    // Background, full bleed: the system rounds the corners.
    let background = CGGradient(colorsSpace: space, colors: [top, bottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(
        background, start: CGPoint(x: 160, y: 1024), end: CGPoint(x: 864, y: 0),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    let glow = CGGradient(colorsSpace: space, colors: [rgb(255, 255, 255, 0.22), rgb(255, 255, 255, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 980), startRadius: 0, endCenter: CGPoint(x: 512, y: 980), endRadius: 640, options: [])

    let white = rgb(255, 255, 255)
    let shadow = rgb(90, 20, 0, 0.30)

    // Plate.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 44, color: shadow)
    ctx.setFillColor(white)
    ctx.fillEllipse(in: CGRect(x: 512 - 268, y: 512 - 268, width: 536, height: 536))
    ctx.restoreGState()
    ctx.setFillColor(rgb(246, 240, 233))
    ctx.fillEllipse(in: CGRect(x: 512 - 200, y: 512 - 200, width: 400, height: 400))
    ctx.setStrokeColor(rgb(231, 222, 211))
    ctx.setLineWidth(6)
    ctx.strokeEllipse(in: CGRect(x: 512 - 200, y: 512 - 200, width: 400, height: 400))

    // Leaf, tilted.
    ctx.saveGState()
    ctx.translateBy(x: 512, y: 512)
    ctx.rotate(by: .pi / 5)
    let leaf = CGMutablePath()
    leaf.move(to: CGPoint(x: -128, y: 0))
    leaf.addCurve(to: CGPoint(x: 138, y: 6), control1: CGPoint(x: -80, y: 112), control2: CGPoint(x: 70, y: 112))
    leaf.addCurve(to: CGPoint(x: -128, y: 0), control1: CGPoint(x: 64, y: -96), control2: CGPoint(x: -84, y: -100))
    leaf.closeSubpath()
    ctx.setStrokeColor(rgb(58, 140, 58))
    ctx.setLineCap(.round)
    ctx.setLineWidth(10)
    let stem = CGMutablePath()
    stem.move(to: CGPoint(x: -168, y: -14))
    stem.addLine(to: CGPoint(x: -120, y: 0))
    ctx.addPath(stem)
    ctx.strokePath()
    ctx.saveGState()
    ctx.addPath(leaf)
    ctx.clip()
    let green = CGGradient(colorsSpace: space, colors: [rgb(132, 210, 88), rgb(52, 146, 60)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(green, start: CGPoint(x: -40, y: 100), end: CGPoint(x: 40, y: -100), options: [])
    ctx.setStrokeColor(rgb(232, 248, 220, 0.85))
    ctx.setLineWidth(8)
    let vein = CGMutablePath()
    vein.move(to: CGPoint(x: -128, y: 0))
    vein.addQuadCurve(to: CGPoint(x: 138, y: 6), control: CGPoint(x: 0, y: 14))
    ctx.addPath(vein)
    ctx.strokePath()
    ctx.setLineWidth(5)
    for x in [-70.0, -14, 42] {
        let side = CGMutablePath()
        side.move(to: CGPoint(x: x, y: 8))
        side.addQuadCurve(to: CGPoint(x: x + 44, y: 62), control: CGPoint(x: x + 30, y: 18))
        side.move(to: CGPoint(x: x, y: 8))
        side.addQuadCurve(to: CGPoint(x: x + 44, y: -52), control: CGPoint(x: x + 30, y: 0))
        ctx.addPath(side)
    }
    ctx.strokePath()
    ctx.restoreGState()
    ctx.restoreGState()

    // Fork on the left, knife on the right.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: shadow)
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.setFillColor(white)
    func fill(_ rect: CGRect, radius: CGFloat) {
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.fillPath()
    }
    // Fork: handle, a neck that widens into the head, three tines.
    fill(CGRect(x: 145, y: 262, width: 30, height: 300), radius: 15)
    let neck = CGMutablePath()
    neck.move(to: CGPoint(x: 145, y: 540))
    neck.addCurve(to: CGPoint(x: 118, y: 610), control1: CGPoint(x: 145, y: 575), control2: CGPoint(x: 118, y: 580))
    neck.addLine(to: CGPoint(x: 202, y: 610))
    neck.addCurve(to: CGPoint(x: 175, y: 540), control1: CGPoint(x: 202, y: 580), control2: CGPoint(x: 175, y: 575))
    neck.closeSubpath()
    ctx.addPath(neck)
    ctx.fillPath()
    for x in [118.0, 151, 184] {
        fill(CGRect(x: x, y: 590, width: 18, height: 170), radius: 9)
    }
    // Knife: handle and a blade with a rounded back.
    fill(CGRect(x: 852, y: 262, width: 30, height: 280), radius: 15)
    let blade = CGMutablePath()
    blade.move(to: CGPoint(x: 846, y: 530))
    blade.addLine(to: CGPoint(x: 846, y: 694))
    blade.addQuadCurve(to: CGPoint(x: 893, y: 762), control: CGPoint(x: 849, y: 755))
    blade.addLine(to: CGPoint(x: 893, y: 530))
    blade.closeSubpath()
    ctx.addPath(blade)
    ctx.fillPath()
    ctx.endTransparencyLayer()
    ctx.restoreGState()
}

try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for pixels in [16, 32, 64, 128, 256, 512, 1024] {
    let ctx = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    draw(ctx)
    let image = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    try rep.representation(using: .png, properties: [:])!.write(to: output.appending(path: "icon_\(pixels).png"))
}
print("ok", output.path)
