import AppKit
import AIScreenshotCore

struct TranslatedOCRLine: Equatable, Sendable {
    let sourceText: String
    let translatedText: String
    let boundingBox: CGRect
    let confidence: Float
}

struct TranslatedImageRenderer {
    func render(
        image: CGImage,
        lines: [TranslatedOCRLine],
        mode: ScreenshotTranslationMode,
        targetLanguage: String
    ) throws -> CGImage {
        guard !lines.isEmpty else { throw ScreenshotTranslationServiceError.missingTextBoxes }
        switch mode {
        case .textOnly:
            return image
        case .fullImage:
            return try renderFullTranslation(image: image, lines: lines)
        case .bilingualImage:
            return try renderBilingualPanel(image: image, lines: lines, targetLanguage: targetLanguage)
        }
    }

    private func renderFullTranslation(
        image: CGImage,
        lines: [TranslatedOCRLine]
    ) throws -> CGImage {
        let size = CGSize(width: image.width, height: image.height)
        let representation = try bitmap(width: image.width, height: image.height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
        NSImage(cgImage: image, size: size).draw(in: CGRect(origin: .zero, size: size))

        for line in lines {
            var rect = pixelRect(from: line.boundingBox, image: image)
            rect = rect.insetBy(dx: -max(2, rect.height * 0.08), dy: -max(2, rect.height * 0.12))
                .intersection(CGRect(origin: .zero, size: size))
            guard rect.width >= 4, rect.height >= 4 else { continue }
            let background = averageColor(image: image, drawingRect: rect)
            background.withAlphaComponent(0.96).setFill()
            NSBezierPath(roundedRect: rect, xRadius: min(5, rect.height * 0.12), yRadius: min(5, rect.height * 0.12)).fill()
            drawFittedText(
                line.translatedText,
                in: rect.insetBy(dx: max(2, rect.height * 0.07), dy: max(1, rect.height * 0.05)),
                color: contrastingTextColor(for: background)
            )
        }

        NSGraphicsContext.restoreGraphicsState()
        guard let output = representation.cgImage else {
            throw ScreenshotTranslationServiceError.imageEncodingFailed
        }
        return output
    }

    private func renderBilingualPanel(
        image: CGImage,
        lines: [TranslatedOCRLine],
        targetLanguage: String
    ) throws -> CGImage {
        let width = image.width
        let horizontalPadding = max(28, CGFloat(width) * 0.035)
        let contentWidth = CGFloat(width) - horizontalPadding * 2
        let sourceFont = NSFont.systemFont(ofSize: max(15, min(24, CGFloat(width) / 70)), weight: .medium)
        let targetFont = NSFont.systemFont(ofSize: max(16, min(27, CGFloat(width) / 62)), weight: .semibold)
        let headerFont = NSFont.systemFont(ofSize: max(18, min(30, CGFloat(width) / 55)), weight: .bold)
        let rowSpacing: CGFloat = max(14, targetFont.pointSize * 0.7)
        let textSpacing: CGFloat = max(4, targetFont.pointSize * 0.22)

        let rowHeights = lines.map { line -> CGFloat in
            let sourceHeight = textHeight(line.sourceText, width: contentWidth, font: sourceFont)
            let targetHeight = textHeight(line.translatedText, width: contentWidth, font: targetFont)
            return sourceHeight + textSpacing + targetHeight + rowSpacing
        }
        let headerHeight = headerFont.pointSize * 2.4
        let panelHeight = Int(ceil(headerHeight + rowHeights.reduce(0, +) + horizontalPadding))
        let representation = try bitmap(width: width, height: image.height + panelHeight)
        let totalSize = CGSize(width: width, height: image.height + panelHeight)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
        NSColor(calibratedWhite: 0.97, alpha: 1).setFill()
        CGRect(origin: .zero, size: totalSize).fill()
        NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height)).draw(
            in: CGRect(x: 0, y: panelHeight, width: image.width, height: image.height)
        )

        let separatorY = CGFloat(panelHeight) - 1
        NSColor.separatorColor.setFill()
        CGRect(x: 0, y: separatorY, width: CGFloat(width), height: 1).fill()

        var cursorY = CGFloat(panelHeight) - headerFont.pointSize * 1.65
        "Bilingual Translation · \(targetLanguage)".draw(
            at: CGPoint(x: horizontalPadding, y: cursorY),
            withAttributes: [.font: headerFont, .foregroundColor: NSColor.labelColor]
        )
        cursorY -= headerFont.pointSize * 1.25

        for (index, line) in lines.enumerated() {
            let sourceHeight = textHeight(line.sourceText, width: contentWidth, font: sourceFont)
            cursorY -= sourceHeight
            line.sourceText.draw(
                in: CGRect(x: horizontalPadding, y: cursorY, width: contentWidth, height: sourceHeight),
                withAttributes: [.font: sourceFont, .foregroundColor: NSColor.secondaryLabelColor]
            )
            cursorY -= textSpacing
            let targetHeight = textHeight(line.translatedText, width: contentWidth, font: targetFont)
            cursorY -= targetHeight
            line.translatedText.draw(
                in: CGRect(x: horizontalPadding, y: cursorY, width: contentWidth, height: targetHeight),
                withAttributes: [.font: targetFont, .foregroundColor: NSColor.labelColor]
            )
            cursorY -= rowSpacing
            if index < lines.count - 1 {
                NSColor.separatorColor.withAlphaComponent(0.55).setFill()
                CGRect(x: horizontalPadding, y: cursorY + rowSpacing * 0.45, width: contentWidth, height: 1).fill()
            }
        }

        NSGraphicsContext.restoreGraphicsState()
        guard let output = representation.cgImage else {
            throw ScreenshotTranslationServiceError.imageEncodingFailed
        }
        return output
    }

    private func bitmap(width: Int, height: Int) throws -> NSBitmapImageRep {
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { throw ScreenshotTranslationServiceError.imageEncodingFailed }
        return representation
    }

    private func pixelRect(from normalized: CGRect, image: CGImage) -> CGRect {
        CGRect(
            x: normalized.minX * CGFloat(image.width),
            y: normalized.minY * CGFloat(image.height),
            width: normalized.width * CGFloat(image.width),
            height: normalized.height * CGFloat(image.height)
        ).integral
    }

    private func averageColor(image: CGImage, drawingRect: CGRect) -> NSColor {
        let cropRect = CGRect(
            x: drawingRect.minX,
            y: CGFloat(image.height) - drawingRect.maxY,
            width: drawingRect.width,
            height: drawingRect.height
        ).intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let crop = image.cropping(to: cropRect),
              let context = CGContext(
                data: nil,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ), let data = context.data else {
            return .white
        }
        context.interpolationQuality = .low
        context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let pixel = data.assumingMemoryBound(to: UInt8.self)
        return NSColor(
            calibratedRed: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: 1
        )
    }

    private func contrastingTextColor(for color: NSColor) -> NSColor {
        let rgb = color.usingColorSpace(.deviceRGB) ?? color
        let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
        return luminance > 0.54 ? .black : .white
    }

    private func drawFittedText(_ text: String, in rect: CGRect, color: NSColor) {
        var fontSize = min(72, max(8, rect.height * 0.72))
        var attributes = textAttributes(fontSize: fontSize, color: color)
        while fontSize > 7 {
            let size = (text as NSString).boundingRect(
                with: rect.size,
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes
            ).size
            if size.width <= rect.width + 0.5, size.height <= rect.height + 0.5 { break }
            fontSize -= 1
            attributes = textAttributes(fontSize: fontSize, color: color)
        }
        (text as NSString).draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
    }

    private func textAttributes(fontSize: CGFloat, color: NSColor) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.alignment = .left
        return [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
    }

    private func textHeight(_ text: String, width: CGFloat, font: NSFont) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        return ceil((text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font, .paragraphStyle: paragraph]
        ).height)
    }
}
