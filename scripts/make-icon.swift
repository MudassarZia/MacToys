import AppKit
import Foundation

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let size = points * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: size * 4, bitsPerPixel: 32)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
        let background = NSBezierPath(roundedRect: NSRect(x: 50, y: 50, width: 924, height: 924), xRadius: 210, yRadius: 210)
        NSGradient(starting: NSColor(calibratedRed: 0.20, green: 0.22, blue: 0.26, alpha: 1), ending: NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.12, alpha: 1))!.draw(in: background, angle: -65)
        for (offset, alpha) in [(CGFloat(-125), CGFloat(0.35)), (CGFloat(0), CGFloat(0.65)), (CGFloat(125), CGFloat(1))] {
            let shape = NSBezierPath()
            shape.move(to: NSPoint(x: 250, y: 515 + offset))
            shape.line(to: NSPoint(x: 510, y: 665 + offset))
            shape.line(to: NSPoint(x: 774, y: 515 + offset))
            shape.line(to: NSPoint(x: 510, y: 365 + offset))
            shape.close()
            NSColor(calibratedRed: 1, green: 0.47, blue: 0.24, alpha: alpha).setFill()
            shape.fill()
            NSColor(calibratedRed: 1, green: 0.7, blue: 0.4, alpha: alpha).setStroke()
            shape.lineWidth = 5; shape.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(points)x\(points)" + (scale == 2 ? "@2x" : "") + ".png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name))
    }
}

// PNG-backed ICNS records avoid dependence on iconutil's image-conversion service.
func uint32(_ value: UInt32) -> Data {
    var encoded = value.bigEndian
    return withUnsafeBytes(of: &encoded) { Data($0) }
}
let entries = [("icp4", "16x16"), ("ic11", "16x16@2x"), ("icp5", "32x32"), ("ic12", "32x32@2x"), ("ic07", "128x128"), ("ic13", "128x128@2x"), ("ic08", "256x256"), ("ic14", "256x256@2x"), ("ic09", "512x512"), ("ic10", "512x512@2x")]
var records = Data()
for (type, name) in entries {
    let png = try Data(contentsOf: directory.appendingPathComponent("icon_\(name).png"))
    records.append(Data(type.utf8)); records.append(uint32(UInt32(png.count + 8))); records.append(png)
}
var family = Data("icns".utf8)
family.append(uint32(UInt32(records.count + 8))); family.append(records)
try family.write(to: directory.deletingPathExtension().appendingPathExtension("icns"))
