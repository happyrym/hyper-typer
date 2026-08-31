import AppKit

// 사용법: swift make-icon.swift <iconset_dir> [설치된_앱_경로]
//  - <iconset_dir>에 Apple 규격 PNG들을 쓴다(이후 iconutil로 .icns 생성).
//  - 앱 경로를 주면 그 앱에 커스텀 아이콘을 입힌다(확장 속성 방식 — 번들/서명 불변 → 접근성 권한 유지).
let iconsetDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
let appPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : ""

func makeIcon(_ px: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: px, height: px))
    img.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high

    // macOS 스타일 스퀘어클(둥근 사각형) + 대각 그라디언트(블루→퍼플).
    let margin = px * 0.10
    let rect = NSRect(x: margin, y: margin, width: px - 2 * margin, height: px - 2 * margin)
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.2237, yRadius: rect.width * 0.2237)
    let grad = NSGradient(colors: [
        NSColor(srgbRed: 0.36, green: 0.56, blue: 0.96, alpha: 1),
        NSColor(srgbRed: 0.60, green: 0.42, blue: 0.95, alpha: 1)])!
    grad.draw(in: path, angle: -60)

    // ✨ sparkles 심볼을 흰색으로 틴트해 중앙에.
    let cfg = NSImage.SymbolConfiguration(pointSize: px * 0.44, weight: .bold)
    if let base = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
        let sz = base.size
        let tinted = NSImage(size: sz)
        tinted.lockFocus()
        base.draw(in: NSRect(origin: .zero, size: sz))
        NSColor.white.set()
        NSRect(origin: .zero, size: sz).fill(using: .sourceAtop)
        tinted.unlockFocus()
        tinted.draw(in: NSRect(x: (px - sz.width) / 2, y: (px - sz.height) / 2, width: sz.width, height: sz.height))
    }
    img.unlockFocus()
    return img
}

func writePNG(_ px: Int, _ path: String) {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    makeIcon(CGFloat(px)).draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    if let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: path))
    }
}

let specs: [(Int, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
]
try? FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)
for (px, name) in specs { writePNG(px, "\(iconsetDir)/\(name)") }
print("iconset written → \(iconsetDir)")

if !appPath.isEmpty {
    let ok = NSWorkspace.shared.setIcon(makeIcon(1024), forFile: appPath, options: [])
    print("setIcon(\(appPath)) = \(ok)")
}
