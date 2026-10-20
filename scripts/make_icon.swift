import AppKit

// 生成 1024x1024 App 图标：绿色渐变圆角矩形 + 白色垃圾桶符号
guard CommandLine.arguments.count > 1 else {
    print("usage: make_icon.swift <output.png>")
    exit(1)
}

let canvas: CGFloat = 1024
let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()

let iconRect = NSRect(x: 0, y: 0, width: canvas, height: canvas).insetBy(dx: 72, dy: 72)
let bezel = NSBezierPath(roundedRect: iconRect, xRadius: 200, yRadius: 200)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.23, green: 0.80, blue: 0.56, alpha: 1),
    NSColor(calibratedRed: 0.04, green: 0.50, blue: 0.40, alpha: 1),
])!
gradient.draw(in: bezel, angle: -90)

if let symbol = NSImage(systemSymbolName: "trash.fill", accessibilityDescription: nil),
   let configured = symbol.withSymbolConfiguration(.init(pointSize: 430, weight: .semibold)) {
    let symbolSize = configured.size
    let tinted = NSImage(size: symbolSize, flipped: false) { rect in
        configured.draw(in: rect)
        NSColor.white.set()
        rect.fill(using: .sourceIn)
        return true
    }
    let drawRect = NSRect(
        x: (canvas - symbolSize.width) / 2,
        y: (canvas - symbolSize.height) / 2,
        width: symbolSize.width,
        height: symbolSize.height
    )
    NSGraphicsContext.current?.imageInterpolation = .high
    tinted.draw(in: drawRect)
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    print("failed to render icon")
    exit(1)
}
do {
    try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    print("icon written to \(CommandLine.arguments[1])")
} catch {
    print("write failed: \(error.localizedDescription)")
    exit(1)
}
