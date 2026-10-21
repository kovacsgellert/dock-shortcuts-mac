#!/usr/bin/env swift
// Renders DockUtils artwork without design tools:
//   assets/icon-1024.png  - full-color app icon (dark glass tile + badges 1/2/3)
//   assets/menubar.png    - monochrome template (glass "1" disc, knocked-out glyph)
// Run: swift scripts/render-icon.swift
import Cocoa

let outDir = URL(fileURLWithPath: "assets", relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))

func write(_ image: NSImage, to name: String) throws {
  guard let tiff = image.tiffRepresentation,
        let rep = NSBitmapImageRep(data: tiff),
        let png = rep.representation(using: .png, properties: [:]) else {
    throw NSError(domain: "icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "encode failed"])
  }
  try png.write(to: outDir.appendingPathComponent(name))
}

// MARK: - App icon

func appIcon(size: CGFloat) -> NSImage {
  NSImage(size: CGSize(width: size, height: size), flipped: false) { rect in
    let tile = NSBezierPath(roundedRect: rect.insetBy(dx: size * 0.06, dy: size * 0.06),
                            xRadius: size * 0.24, yRadius: size * 0.24)
    // Dark glass tile.
    let bg = NSGradient(colors: [NSColor(calibratedWhite: 0.23, alpha: 1),
                                 NSColor(calibratedWhite: 0.08, alpha: 1)])!
    bg.draw(in: tile, angle: 90)
    // Rim light.
    NSColor.white.withAlphaComponent(0.35).setStroke()
    tile.lineWidth = size * 0.008
    tile.stroke()
    // Top gloss, fading smoothly over the whole tile (no seam).
    NSGraphicsContext.saveGraphicsState()
    tile.setClip()
    let gloss = NSGradient(colors: [NSColor.white.withAlphaComponent(0.20),
                                    NSColor.white.withAlphaComponent(0.0)])!
    gloss.draw(in: rect, angle: 90)
    NSGraphicsContext.restoreGraphicsState()

    // Mini dock bar with three badge dots, centered (echoes the menu-bar icon).
    let dotD = size * 0.137
    let dotGap = size * 0.055
    let barW = dotD * 3 + dotGap * 2 + size * 0.09
    let barH = size * 0.15
    let stackGap = size * 0.055
    let groupH = dotD + stackGap + barH
    var dx = (size - (dotD * 3 + dotGap * 2)) / 2
    let dotsY = (size + groupH) / 2 - dotD
    let barY = dotsY - stackGap - barH
    let frost: (NSBezierPath) -> Void = { path in
      NSColor(calibratedWhite: 0.32, alpha: 0.95).setFill()
      path.fill()
      NSColor.white.withAlphaComponent(0.55).setStroke()
      path.lineWidth = size * 0.006
      path.stroke()
    }
    for _ in 0..<3 {
      frost(NSBezierPath(ovalIn: CGRect(x: dx, y: dotsY, width: dotD, height: dotD)))
      dx += dotD + dotGap
    }
    frost(NSBezierPath(roundedRect: CGRect(x: (size - barW) / 2, y: barY, width: barW, height: barH),
                       xRadius: barH / 2, yRadius: barH / 2))
    return true
  }
}

// MARK: - Menu bar template (alpha-only black shapes)

func menuBarIcon() -> NSImage {
  let size: CGFloat = 44
  return NSImage(size: CGSize(width: size, height: size), flipped: false) { _ in
    NSColor.black.setFill()
    // Mini dock bar with three badge dots above it.
    NSBezierPath(roundedRect: CGRect(x: 5, y: 9, width: 34, height: 11), xRadius: 5.5, yRadius: 5.5).fill()
    for x in [11, 19, 27] as [CGFloat] {
      NSBezierPath(ovalIn: CGRect(x: x, y: 25, width: 8, height: 8)).fill()
    }
    return true
  }
}

try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
try write(appIcon(size: 1024), to: "icon-1024.png")
try write(menuBarIcon(), to: "menubar.png")
print("Wrote assets/icon-1024.png + assets/menubar.png")
