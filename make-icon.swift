// make-icon.swift -- draw the app icon: the PF1 keycap from an LK401/LK450.
//
// Not the gold-filled cap the panel draws when an overlay is active, but the
// real keycap: a pale cream cap with PF1 printed at the top and the orange
// GOLD marker below it, which is what DEC actually silk-screened.  Renders a
// 1024x1024 PNG; make-icon.sh turns it into DECkeys.icns.
import AppKit

let S: CGFloat = 1024
let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// macOS icons sit inside their canvas rather than filling it.
let inset: CGFloat = S * 0.11
let cap = NSRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)
let radius = S * 0.115

// A keycap is a slab: darker skirt, lighter top, so it reads as physical.
let skirt = NSBezierPath(roundedRect: cap, xRadius: radius, yRadius: radius)
NSColor(calibratedRed: 0.78, green: 0.76, blue: 0.71, alpha: 1).setFill()
ctx.setShadow(offset: CGSize(width: 0, height: -S * 0.012), blur: S * 0.03,
              color: NSColor(white: 0, alpha: 0.35).cgColor)
skirt.fill()
ctx.setShadow(offset: .zero, blur: 0, color: nil)

let lip = S * 0.035
let top = cap.insetBy(dx: lip, dy: lip).offsetBy(dx: 0, dy: lip * 0.55)
let face = NSBezierPath(roundedRect: top, xRadius: radius * 0.82, yRadius: radius * 0.82)
NSGradient(starting: NSColor(calibratedRed: 0.96, green: 0.95, blue: 0.91, alpha: 1),
           ending:   NSColor(calibratedRed: 0.88, green: 0.86, blue: 0.81, alpha: 1))!
    .draw(in: face, angle: -90)

// "PF1", upper left, as it is printed on the cap.
let label = NSAttributedString(string: "PF1", attributes: [
    .font: NSFont.monospacedSystemFont(ofSize: S * 0.15, weight: .medium),
    .foregroundColor: NSColor(calibratedWhite: 0.16, alpha: 1),
])
label.draw(at: NSPoint(x: top.minX + S * 0.075, y: top.maxY - S * 0.20))

// The orange GOLD marker.  This is the whole point of the key.
let blobW = top.width * 0.62, blobH = top.height * 0.17
let blob = NSRect(x: top.midX - blobW / 2, y: top.minY + top.height * 0.24,
                  width: blobW, height: blobH)
NSColor(calibratedRed: 0.93, green: 0.44, blue: 0.20, alpha: 1).setFill()
NSBezierPath(roundedRect: blob, xRadius: blobH / 2, yRadius: blobH / 2).fill()

img.unlockFocus()

guard let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("could not render")
}
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
