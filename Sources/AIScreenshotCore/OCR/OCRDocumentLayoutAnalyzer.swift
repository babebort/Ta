import CoreGraphics
import Foundation

public struct OCRDocumentLayoutAnalyzer: Sendable {
    public init() {}

    public func analyze(lines: [OCRTextLine]) -> OCRDocumentLayout {
        let ordered = lines.sorted(by: readingOrder)
        return OCRDocumentLayout(
            blocks: makeBlocks(from: ordered),
            tables: makeTables(from: ordered)
        )
    }

    private func makeBlocks(from lines: [OCRTextLine]) -> [OCRDocumentBlock] {
        guard let first = lines.first else { return [] }
        var blocks: [[OCRTextLine]] = [[first]]
        for line in lines.dropFirst() {
            let previous = blocks[blocks.count - 1].last!
            let verticalGap = previous.boundingBox.minY - line.boundingBox.maxY
            let typicalHeight = max(0.01, (previous.boundingBox.height + line.boundingBox.height) / 2)
            let largeGap = verticalGap > typicalHeight * 2.4
            let majorIndentChange = abs(previous.boundingBox.minX - line.boundingBox.minX) > 0.28
            if largeGap || majorIndentChange {
                blocks.append([line])
            } else {
                blocks[blocks.count - 1].append(line)
            }
        }
        return blocks.map(OCRDocumentBlock.init(lines:))
    }

    private func makeTables(from lines: [OCRTextLine]) -> [OCRTable] {
        let visualRows = groupIntoRows(lines)
        let multiCellRows = visualRows.map { row -> [String] in
            if row.count > 1 { return row.sorted { $0.boundingBox.minX < $1.boundingBox.minX }.map(\.text) }
            guard let text = row.first?.text else { return [] }
            return text.components(separatedBy: try! NSRegularExpression(pattern: "\\s{2,}")).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }
        }
        let candidates = multiCellRows.filter { $0.count >= 2 }
        guard candidates.count >= 2 else { return [] }
        let commonCount = Dictionary(grouping: candidates, by: \.count).max { $0.value.count < $1.value.count }?.key ?? 0
        let consistent = candidates.filter { abs($0.count - commonCount) <= 1 }
        guard consistent.count >= 2 else { return [] }
        return [OCRTable(rows: consistent)]
    }

    private func groupIntoRows(_ lines: [OCRTextLine]) -> [[OCRTextLine]] {
        var rows: [[OCRTextLine]] = []
        for line in lines {
            if let index = rows.firstIndex(where: { row in
                guard let first = row.first else { return false }
                let tolerance = max(0.012, max(first.boundingBox.height, line.boundingBox.height) * 0.65)
                return abs(first.boundingBox.midY - line.boundingBox.midY) <= tolerance
            }) {
                rows[index].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows.sorted { ($0.first?.boundingBox.midY ?? 0) > ($1.first?.boundingBox.midY ?? 0) }
    }

    private func readingOrder(_ lhs: OCRTextLine, _ rhs: OCRTextLine) -> Bool {
        let tolerance = max(0.012, max(lhs.boundingBox.height, rhs.boundingBox.height) * 0.65)
        if abs(lhs.boundingBox.midY - rhs.boundingBox.midY) <= tolerance {
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }
        return lhs.boundingBox.midY > rhs.boundingBox.midY
    }
}

private extension String {
    func components(separatedBy regex: NSRegularExpression) -> [String] {
        let range = NSRange(startIndex..<endIndex, in: self)
        var result: [String] = []
        var last = range.location
        for match in regex.matches(in: self, range: range) {
            let length = match.range.location - last
            if let swiftRange = Range(NSRange(location: last, length: length), in: self) {
                result.append(String(self[swiftRange]))
            }
            last = match.range.location + match.range.length
        }
        if let swiftRange = Range(NSRange(location: last, length: range.location + range.length - last), in: self) {
            result.append(String(self[swiftRange]))
        }
        return result
    }
}
