#!/usr/bin/env swift
// Draws Nibble's artwork: a chocolate-chip cookie with a bite taken out.
// Run via `make icon` — regenerates Assets/ from scratch, no binary blobs to trust.
import AppKit

// MARK: - Palette

let dough      = NSColor(srgbRed: 0.85, green: 0.65, blue: 0.36, alpha: 1)
let doughDark  = NSColor(srgbRed: 0.72, green: 0.50, blue: 0.25, alpha: 1)
let doughLight = NSColor(srgbRed: 0.93, green: 0.78, blue: 0.52, alpha: 1)
let chip       = NSColor(srgbRed: 0.29, green: 0.17, blue: 0.10, alpha: 1)
let chipLight  = NSColor(srgbRed: 0.40, green: 0.25, blue: 0.15, alpha: 1)

/// Chip positions in unit space (-1...1 from cookie centre), with radius.
/// Hand-placed so none collide with the bite or the rim.
let chips: [(x: CGFloat, y: CGFloat, r: CGFloat)] = [
    (-0.42, 0.34, 0.13), (0.06, 0.50, 0.11), (-0.55, -0.22, 0.12),
    (-0.10, -0.05, 0.15), (0.34, -0.38, 0.12), (-0.24, -0.58, 0.11),
    (0.46, 0.06, 0.10), (0.10, -0.66, 0.09),
]

/// The bite: a circle subtracted from the cookie's upper-right edge.
let biteCentre = CGPoint(x: 0.80, y: 0.74)
let biteRadius: CGFloat = 0.46

// MARK: - Drawing

func drawCookie(in ctx: CGContext, size: CGFloat, monochrome: Bool) {
    let centre = CGPoint(x: size / 2, y: size / 2)
    // Leave headroom so the bite's scalloped edge isn't clipped.
    let radius = size * 0.40
    func p(_ ux: CGFloat, _ uy: CGFloat) -> CGPoint {
        CGPoint(x: centre.x + ux * radius, y: centre.y + uy * radius)
    }

    let biteC = p(biteCentre.x, biteCentre.y)
    let biteRect = CGRect(x: biteC.x - biteRadius * radius,
                          y: biteC.y - biteRadius * radius,
                          width: biteRadius * radius * 2,
                          height: biteRadius * radius * 2)

    ctx.saveGState()
    // Clip to the cookie, paint it, then punch the bite out. An even-odd fill of
    // both circles would also paint the part of the bite outside the cookie.
    ctx.addEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius,
                              width: radius * 2, height: radius * 2))
    ctx.clip()

    if monochrome {
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    } else {
        // Warm vertical gradient gives the dough a little roundness.
        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [doughLight.cgColor, dough.cgColor, doughDark.cgColor] as CFArray,
            locations: [0, 0.55, 1])!
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: 0, y: size),
                               end: CGPoint(x: 0, y: 0),
                               options: [])
    }

    ctx.setBlendMode(.clear)
    ctx.fillEllipse(in: biteRect)
    ctx.setBlendMode(.normal)
    ctx.restoreGState()

    // Chips. In monochrome they're knocked out so the glyph reads at 16px.
    for c in chips {
        let centrePoint = p(c.x, c.y)
        let r = c.r * radius
        let rect = CGRect(x: centrePoint.x - r, y: centrePoint.y - r, width: r * 2, height: r * 2)
        // Skip any chip that the bite would have removed.
        let dx = centrePoint.x - biteC.x, dy = centrePoint.y - biteC.y
        if (dx * dx + dy * dy).squareRoot() < biteRadius * radius + r * 0.4 { continue }

        if monochrome {
            ctx.setBlendMode(.clear)
            ctx.fillEllipse(in: rect)
            ctx.setBlendMode(.normal)
        } else {
            ctx.setFillColor(chipLight.cgColor)
            ctx.fillEllipse(in: rect.offsetBy(dx: 0, dy: -r * 0.12))
            ctx.setFillColor(chip.cgColor)
            ctx.fillEllipse(in: rect)
        }
    }
}

func render(size: CGFloat, monochrome: Bool) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let gctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gctx
    drawCookie(in: gctx.cgContext, size: size, monochrome: monochrome)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func write(_ rep: NSBitmapImageRep, to path: String) {
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
}

// MARK: - Output

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Assets"
try? FileManager.default.createDirectory(atPath: "\(out)/Nibble.iconset",
                                         withIntermediateDirectories: true)

// App icon: the sizes iconutil expects.
for (size, name) in [(16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"),
                     (128, "128x128"), (256, "128x128@2x"), (256, "256x256"),
                     (512, "256x256@2x"), (512, "512x512"), (1024, "512x512@2x")] {
    write(render(size: CGFloat(size), monochrome: false),
          to: "\(out)/Nibble.iconset/icon_\(name).png")
}

// Menu-bar glyph: template image, tinted by AppKit to match light/dark menu bars.
write(render(size: 18, monochrome: true), to: "\(out)/MenuBarIcon.png")
write(render(size: 36, monochrome: true), to: "\(out)/MenuBarIcon@2x.png")

// Standalone copy for the README.
write(render(size: 256, monochrome: false), to: "\(out)/icon.png")

print("wrote \(out)/Nibble.iconset and menu-bar glyphs")
