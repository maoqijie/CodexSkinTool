import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: swift generate-icon.swift OUTPUT.png\n", stderr)
    exit(2)
}

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size, flipped: false) { rect in
    let outer = NSBezierPath(roundedRect: rect.insetBy(dx: 72, dy: 72), xRadius: 210, yRadius: 210)
    NSColor(red: 0.082, green: 0.357, blue: 0.816, alpha: 1).setFill()
    outer.fill()

    let innerRect = rect.insetBy(dx: 118, dy: 118)
    let inner = NSBezierPath(roundedRect: innerRect, xRadius: 174, yRadius: 174)
    NSColor.white.withAlphaComponent(0.12).setFill()
    inner.fill()

    guard let symbol = NSImage(
        systemSymbolName: "paintbrush.pointed.fill",
        accessibilityDescription: "Codex Skin Tool"
    ) else { return false }

    let configuration = NSImage.SymbolConfiguration(pointSize: 420, weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    let configured = symbol.withSymbolConfiguration(configuration) ?? symbol
    let symbolSize = configured.size
    let scale = min(510 / symbolSize.width, 510 / symbolSize.height)
    let target = NSSize(width: symbolSize.width * scale, height: symbolSize.height * scale)
    configured.draw(
        in: NSRect(x: (1024 - target.width) / 2, y: (1024 - target.height) / 2, width: target.width, height: target.height),
        from: .zero,
        operation: .sourceOver,
        fraction: 1
    )
    return true
}

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("failed to render icon\n", stderr)
    exit(1)
}

try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
