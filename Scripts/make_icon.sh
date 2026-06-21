#!/usr/bin/env bash
# Generate Icon.icns from scratch (no Xcode / Icon Composer needed).
# Renders a 1024px master with CoreGraphics, then builds the .iconset and .icns.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT_ROOT="${1:-$ROOT/build/icon}"
ICONSET="$OUT_ROOT/AppReset.iconset"
MASTER="$OUT_ROOT/icon_1024.png"
mkdir -p "$ICONSET"

SWIFT_SRC="$(mktemp -t make_icon).swift"
trap 'rm -f "$SWIFT_SRC"' EXIT

cat > "$SWIFT_SRC" <<'SWIFT'
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let outPath = CommandLine.arguments[1]
let size = 1024
let W = CGFloat(size)
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: size, height: size,
                          bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("no context")
}
ctx.clear(CGRect(x: 0, y: 0, width: W, height: W))

// Rounded-rect tile with a diagonal gradient.
let pad: CGFloat = 76
let rect = CGRect(x: pad, y: pad, width: W - 2 * pad, height: W - 2 * pad)
let radius = (W - 2 * pad) * 0.2237
let tile = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

// Soft drop shadow under the tile.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 46,
              color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.28))
ctx.addPath(tile)
ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(tile)
ctx.clip()
let colors = [
    CGColor(red: 0.30, green: 0.40, blue: 0.98, alpha: 1.0),
    CGColor(red: 0.58, green: 0.24, blue: 0.90, alpha: 1.0),
] as CFArray
let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(grad,
                       start: CGPoint(x: pad, y: W - pad),
                       end: CGPoint(x: W - pad, y: pad),
                       options: [])
ctx.restoreGState()

// White circular "reset" arrow.
let center = CGPoint(x: W / 2, y: W / 2)
let r = (W - 2 * pad) * 0.255
let lineWidth = W * 0.058
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.setLineWidth(lineWidth)
ctx.setLineCap(.round)

let gapHalf: CGFloat = 0.40           // radians; gap centered at the top
let startA = CGFloat.pi / 2 + gapHalf // just past top, going counter-clockwise
let sweep = CGFloat.pi * 2 - gapHalf * 2
let endA = startA + sweep
ctx.addArc(center: center, radius: r, startAngle: startA, endAngle: endA, clockwise: false)
ctx.strokePath()

// Arrowhead at the arc end, pointing along the (counter-clockwise) tangent.
func pt(_ a: CGFloat, _ rad: CGFloat) -> CGPoint {
    CGPoint(x: center.x + cos(a) * rad, y: center.y + sin(a) * rad)
}
let tipBase = pt(endA, r)
let tangent = CGVector(dx: -sin(endA), dy: cos(endA))
let normal = CGVector(dx: cos(endA), dy: sin(endA))
let headLen = lineWidth * 1.75
let headW = lineWidth * 1.45
let tip = CGPoint(x: tipBase.x + tangent.dx * headLen, y: tipBase.y + tangent.dy * headLen)
let b1 = CGPoint(x: tipBase.x + normal.dx * headW, y: tipBase.y + normal.dy * headW)
let b2 = CGPoint(x: tipBase.x - normal.dx * headW, y: tipBase.y - normal.dy * headW)
ctx.beginPath()
ctx.move(to: tip)
ctx.addLine(to: b1)
ctx.addLine(to: b2)
ctx.closePath()
ctx.fillPath()

guard let image = ctx.makeImage() else { fatalError("no image") }
let url = URL(fileURLWithPath: outPath)
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("no destination")
}
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("write failed") }
print("wrote \(outPath)")
SWIFT

swift "$SWIFT_SRC" "$MASTER"

# Build the iconset at the required sizes.
sizes=(16 32 64 128 256 512 1024)
for sz in "${sizes[@]}"; do
  sips -z "$sz" "$sz" "$MASTER" --out "$ICONSET/icon_${sz}x${sz}.png" >/dev/null
  if [[ "$sz" -ne 1024 ]]; then
    dbl=$((sz * 2))
    sips -z "$dbl" "$dbl" "$MASTER" --out "$ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null
  fi
done
cp "$MASTER" "$ICONSET/icon_512x512@2x.png"

iconutil -c icns "$ICONSET" -o "$ROOT/Icon.icns"
echo "Icon.icns generated at $ROOT/Icon.icns"
