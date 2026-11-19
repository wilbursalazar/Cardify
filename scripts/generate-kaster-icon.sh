#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$1"
if [[ -z "$DEST" ]]; then DEST="$ROOT/Resources/KasterIcon.icns"; fi
TMP="$(mktemp -d /tmp/kaster-icon.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/Kaster.iconset" "$(dirname "$DEST")"
cat > "$TMP/draw.swift" <<'SWIFT'
import AppKit
import Foundation

let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let graphics = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics
let context = graphics.cgContext
context.setAllowsAntialiasing(true)
func color(_ hex: UInt32) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1)
}
func polygon(_ vertices: [(CGFloat, CGFloat)], _ hex: UInt32) {
    guard let first = vertices.first else { return }
    context.beginPath()
    context.move(to: CGPoint(x: first.0, y: first.1))
    for vertex in vertices.dropFirst() { context.addLine(to: CGPoint(x: vertex.0, y: vertex.1)) }
    context.closePath()
    context.setFillColor(color(hex))
    context.fillPath()
}
func pixel(_ x: CGFloat, _ y: CGFloat, _ side: CGFloat, _ hex: UInt32) {
    context.setFillColor(color(hex))
    context.fill(CGRect(x: x, y: y, width: side, height: side))
}
let background = CGPath(roundedRect: CGRect(x: 0, y: 0, width: 1024, height: 1024),
                        cornerWidth: 220, cornerHeight: 220, transform: nil)
context.addPath(background)
context.clip()
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [color(0x8424CF), color(0x3C0B70)] as CFArray, locations: [0, 1])!
context.drawLinearGradient(gradient, start: CGPoint(x: 130, y: 1024),
                           end: CGPoint(x: 875, y: 0), options: [])
// Low-poly wizard silhouette casting a pixel spell.
polygon([(240, 265), (350, 485), (485, 460), (610, 240), (560, 148), (290, 156)], 0xF7F0FF)
polygon([(240, 265), (350, 485), (406, 310), (290, 156)], 0xD2B6FF)
polygon([(406, 310), (485, 460), (610, 240), (560, 148)], 0xB682F5)
polygon([(290, 156), (406, 310), (470, 156)], 0xFFFFFF)
polygon([(470, 156), (560, 148), (525, 300)], 0xEEE0FF)
polygon([(350, 485), (415, 630), (510, 580), (485, 460)], 0xFFFFFF)
polygon([(220, 633), (391, 875), (531, 657), (589, 625), (435, 606)], 0xF6EAFF)
polygon([(391, 875), (447, 712), (531, 657)], 0xC899FF)
polygon([(220, 633), (391, 875), (349, 689)], 0xB47BF4)
polygon([(280, 591), (584, 591), (526, 634), (337, 647)], 0xFFFFFF)
polygon([(349, 647), (520, 634), (462, 585)], 0xDCC4FF)
polygon([(389, 586), (495, 603), (523, 518), (472, 490), (421, 527)], 0xFFFFFF)
polygon([(439, 543), (531, 534), (488, 505)], 0xD6B1FF)
polygon([(465, 514), (523, 518), (493, 426), (446, 463)], 0xEEE0FF)
polygon([(470, 566), (500, 565), (490, 557)], 0x3C0B70)
polygon([(479, 470), (562, 566), (661, 600), (689, 554), (599, 502), (540, 404)], 0xFFFFFF)
polygon([(479, 470), (562, 566), (599, 502), (540, 404)], 0xD0A6FF)
polygon([(647, 581), (702, 610), (720, 579), (689, 554)], 0xF9F5FF)
context.setStrokeColor(color(0xFFFFFF))
context.setLineWidth(25)
context.setLineCap(.square)
context.move(to: CGPoint(x: 705, y: 596))
context.addLine(to: CGPoint(x: 792, y: 738))
context.strokePath()
let sparks: [(CGFloat,CGFloat,CGFloat,UInt32)] = [
    (789,766,28,0xFFFFFF), (832,796,40,0xFFFFFF),
    (851,738,23,0xD5B1FF), (764,824,20,0xD5B1FF),
    (886,840,27,0xFFFFFF), (919,772,15,0xF4E6FF),
    (742,747,16,0xFFFFFF), (807,877,13,0xE3CCFF),
    (900,697,18,0xFFFFFF), (765,681,13,0xD5B1FF)
]
for (x,y,s,h) in sparks { pixel(x,y,s,h) }
NSGraphicsContext.restoreGraphicsState()
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("PNG encoding failed") }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
SWIFT
swift "$TMP/draw.swift" "$TMP/Kaster.iconset/icon_512x512@2x.png"
BASE="$TMP/Kaster.iconset/icon_512x512@2x.png"
for entry in "16 icon_16x16" "32 icon_16x16@2x" "32 icon_32x32" "64 icon_32x32@2x" "128 icon_128x128" "256 icon_128x128@2x" "256 icon_256x256" "512 icon_256x256@2x" "512 icon_512x512"; do
    read -r px name <<< "$entry"
    sips -s format png -z "$px" "$px" "$BASE" --out "$TMP/Kaster.iconset/$name.png" >/dev/null
done
iconutil -c icns "$TMP/Kaster.iconset" -o "$DEST"
echo "Generated $DEST"
