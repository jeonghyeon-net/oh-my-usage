import AppKit

@main struct RenderTests {
    static func main() {
        _ = NSApplication.shared
        checkMenuColumns()
        let examples = [StatusRow(remaining: "4%", plan: "Pro $100", active: true),
                        StatusRow(remaining: "—", plan: "Pro $200", active: false, hasError: true),
                        StatusRow(remaining: "100%", plan: "Plus", active: false)]
        let placeholders = examples.map { StatusRow(remaining: "—", plan: $0.plan, active: false) }
        let loaded = examples.map { StatusRow(remaining: "<1%", plan: $0.plan, active: true, hasError: true) }
        for size: CGFloat in [6.5, 9, 11] {
            guard StatusLayout(rows: placeholders, size: size).width == StatusLayout(rows: loaded, size: size).width else {
                fatalError("Menu bar width changed after loading, selection or an error")
            }
        }
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
                let width = StatusLayout(rows: rows, size: size).width
                let image = statusImage(rows: rows, width: width, imageHeight: imageHeight, height: height,
                                        size: size, font: font, dark: iteration % 2 == 0, drawContent: true)
                let scale = iteration % 2 + 1
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width) * scale,
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
                                let rows = examples.prefix(count).map {
                                    StatusRow(remaining: $0.remaining, plan: $0.plan, active: active && $0.active, hasError: $0.hasError)
                                }
                                let imageHeight: CGFloat = count == 3 ? barHeight : 22
                                let height: CGFloat = count == 3 ? floor(imageHeight / 3) : count == 2 ? 10 : 16
                                let size: CGFloat = count == 3 ? min(9, height - 0.5) : count == 2 ? 9 : 11
                                let font = NSFont.monospacedSystemFont(ofSize: size, weight: .medium)
                                let width = StatusLayout(rows: rows, size: size).width
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

    static func checkMenuColumns() {
        let rows = [AccountMenuRow(remaining: "4%", plan: "Pro $100", email: "primary@example.invalid", reset: "초기화 10/3 (토) 14:30", credits: "1"),
                    AccountMenuRow(remaining: "100%", plan: "Enterprise", email: "work@example.invalid", reset: "초기화 12/31 (목) 23:59", credits: "12"),
                    AccountMenuRow(remaining: "—", plan: "Plus", email: "예시@example.invalid", reset: "초기화 —", credits: "—")]
        let layout = AccountMenuLayout(rows: rows)
        var reference: [NSRect] = []
        for (index, row) in rows.enumerated() {
            let title = layout.title(for: row, active: index == 0)
            let storage = NSTextStorage(attributedString: title)
            let manager = NSLayoutManager()
            let container = NSTextContainer(size: NSSize(width: 2000, height: 100))
            container.lineFragmentPadding = 0
            storage.addLayoutManager(manager)
            manager.addTextContainer(container)
            manager.ensureLayout(for: container)
            var cursor = 1
            var bounds: [NSRect] = []
            for column in row.columns {
                let range = NSRange(location: cursor, length: (column as NSString).length)
                bounds.append(manager.boundingRect(forGlyphRange: manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil), in: container))
                cursor += range.length + 1
            }
            for column in 0..<5 {
                if column > 0 && bounds[column].minX - bounds[column - 1].maxX < 17 {
                    fatalError("Menu columns overlap or lose their spacing")
                }
                if !reference.isEmpty {
                    let rightAligned = column == 0 || column == 4
                    let actual = rightAligned ? bounds[column].maxX : bounds[column].minX
                    let expected = rightAligned ? reference[column].maxX : reference[column].minX
                    guard abs(actual - expected) < 1 else { fatalError("Menu column alignment differs across rows") }
                }
            }
            reference = bounds
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1600, pixelsHigh: 60, bitsPerSample: 8,
                                          samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                          colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            title.draw(in: NSRect(x: 0, y: 0, width: 1600, height: 60))
            NSGraphicsContext.restoreGraphicsState()
        }
        print("Menu checks passed: aligned columns, spacing, missing values, Korean text, offscreen drawing")
    }
}
