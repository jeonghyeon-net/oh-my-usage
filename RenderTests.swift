import AppKit

@main struct RenderTests {
    static func main() {
        _ = NSApplication.shared
        let examples = [("  4% Pro $100", true), ("   — Pro $200!", false), ("100% Plus", false)]
        var passes = 0
        // Repeated font/appearance changes reproduce the intermittent CoreText exception.
        // Keep each image in its own autorelease pool, as in separate app run-loop turns.
        for iteration in 0..<10_000 {
            autoreleasepool {
                let count = iteration % 3 + 1
                let rows = Array(examples.prefix(count))
                let imageHeight: CGFloat = count == 3 ? (iteration % 2 == 0 ? 22 : 32) : 22
                let height: CGFloat = count == 3 ? floor(imageHeight / 3) : count == 2 ? 10 : 16
                let size: CGFloat = count == 3 ? min(9, height - 0.5) : count == 2 ? 9 : 11
                let font = NSFont.monospacedSystemFont(ofSize: size, weight: .medium)
                let image = statusImage(rows: rows, width: 100, imageHeight: imageHeight, height: height,
                                        size: size, font: font, dark: iteration % 2 == 0, drawContent: true)
                let scale = iteration % 2 + 1
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 100 * scale,
                                              pixelsHigh: Int(imageHeight) * scale, bitsPerSample: 8,
                                              samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                bitmap.size = image.size
                let context = NSGraphicsContext(bitmapImageRep: bitmap)!
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = context
                image.draw(in: NSRect(origin: .zero, size: image.size))
                NSGraphicsContext.restoreGraphicsState()
                passes += 1
            }
        }
        for count in 1...3 {
            for barHeight: CGFloat in [22, 32] {
                for dark in [false, true] {
                    for active in [false, true] {
                        for visible in [false, true] {
                            autoreleasepool {
                                let rows = examples.prefix(count).map { ($0.0, active && $0.1) }
                                let imageHeight: CGFloat = count == 3 ? barHeight : 22
                                let height: CGFloat = count == 3 ? floor(imageHeight / 3) : count == 2 ? 10 : 16
                                let size: CGFloat = count == 3 ? min(9, height - 0.5) : count == 2 ? 9 : 11
                                let font = NSFont.monospacedSystemFont(ofSize: size, weight: .medium)
                                let width = ceil(("100% Pro $200! " as NSString).size(withAttributes: [.font: font]).width) + 4
                                let image = statusImage(rows: rows, width: width, imageHeight: imageHeight,
                                                        height: height, size: size, font: font, dark: dark, drawContent: visible)
                                // Drawing the same lazy image repeatedly also covers AppKit cache invalidation.
                                for scale in [1, 2, 1, 2] {
                                    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width) * scale,
                                                                  pixelsHigh: Int(imageHeight) * scale, bitsPerSample: 8,
                                                                  samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                                    bitmap.size = image.size
                                    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
                                    NSGraphicsContext.saveGraphicsState()
                                    NSGraphicsContext.current = context
                                    image.recache()
                                    image.draw(in: NSRect(origin: .zero, size: image.size))
                                    NSGraphicsContext.restoreGraphicsState()
                                    var hasInk = false
                                    for y in 0..<bitmap.pixelsHigh {
                                        for x in 0..<bitmap.pixelsWide {
                                            if (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0 { hasInk = true }
                                        }
                                    }
                                    // fatalError stays enabled in the same optimized build as the released app.
                                    guard hasInk == visible else { fatalError("Incorrect startup/content visibility") }
                                    passes += 1
                                }
                            }
                        }
                    }
                }
            }
        }
        print("Render checks passed: \(passes) draws, 1–3 rows, light/dark, active/inactive, startup, 1x/2x")
    }
}
