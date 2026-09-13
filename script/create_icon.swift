import AppKit

let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let outer = NSBezierPath(roundedRect: NSRect(x: 30, y: 30, width: 964, height: 964), xRadius: 216, yRadius: 216)
    NSColor(calibratedRed: 0.17, green: 0.23, blue: 0.27, alpha: 1).setFill(); outer.fill()
    let shadow = NSShadow(); shadow.shadowBlurRadius = 30; shadow.shadowOffset = NSSize(width: 0, height: -12); shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    NSGraphicsContext.saveGraphicsState(); shadow.set()
    let paper = NSBezierPath(roundedRect: NSRect(x: 215, y: 150, width: 594, height: 732), xRadius: 32, yRadius: 32)
    NSColor(calibratedRed: 0.96, green: 0.945, blue: 0.90, alpha: 1).setFill(); paper.fill(); NSGraphicsContext.restoreGraphicsState()
    let serif = NSFont(name: "Baskerville", size: 570) ?? NSFont.systemFont(ofSize: 540, weight: .regular)
    let letter = "T" as NSString
    let attributes: [NSAttributedString.Key: Any] = [.font: serif, .foregroundColor: NSColor(calibratedRed: 0.17, green: 0.23, blue: 0.27, alpha: 1)]
    letter.draw(at: NSPoint(x: 512 - letter.size(withAttributes: attributes).width / 2, y: 220), withAttributes: attributes)
    NSColor(calibratedRed: 0.48, green: 0.66, blue: 0.69, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 326, y: 226, width: 372, height: 20), xRadius: 10, yRadius: 10).fill()
    image.unlockFocus()
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    let data = bitmap.representation(using: .png, properties: [:])!
    let names: [String]
    switch size {
    case 16: names = ["icon_16x16.png"]
    case 32: names = ["icon_16x16@2x.png", "icon_32x32.png"]
    case 64: names = ["icon_32x32@2x.png"]
    case 128: names = ["icon_128x128.png"]
    case 256: names = ["icon_128x128@2x.png", "icon_256x256.png"]
    case 512: names = ["icon_256x256@2x.png", "icon_512x512.png"]
    default: names = ["icon_512x512@2x.png"]
    }
    for name in names { try data.write(to: folder.appendingPathComponent(name)) }
}
