import Foundation

public struct ContentClassifier: Sendable {
    public init() {}

    public func classify(_ text: String) -> CaptureContentType {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .image }

        if looksLikeQRCodePayload(trimmed) {
            return .qrCode
        }

        if looksLikeTable(trimmed) {
            return .table
        }

        if looksLikeFormula(trimmed) {
            return .formula
        }

        if looksLikeCode(trimmed) {
            return .code
        }

        return .plainText
    }

    private func looksLikeQRCodePayload(_ text: String) -> Bool {
        guard !text.contains("\n") else { return false }
        return text.range(of: #"^(https?://|mailto:|tel:|otpauth://|WIFI:)"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func looksLikeTable(_ text: String) -> Bool {
        let rows = text.split(separator: "\n", omittingEmptySubsequences: true)
        guard rows.count >= 2 else { return false }

        let tabCounts = rows.map { $0.filter { $0 == "\t" }.count }
        if let first = tabCounts.first, first > 0,
           tabCounts.filter({ $0 == first }).count >= max(2, rows.count - 1) {
            return true
        }

        let pipeCounts = rows.map { $0.filter { $0 == "|" }.count }
        if let first = pipeCounts.first, first >= 2,
           pipeCounts.filter({ $0 == first }).count >= max(2, rows.count - 1) {
            return true
        }

        let multiColumnRows = rows.filter {
            $0.range(of: #"\S\s{2,}\S"#, options: .regularExpression) != nil
        }
        return multiColumnRows.count >= max(2, rows.count - 1)
    }

    private func looksLikeCode(_ text: String) -> Bool {
        let codePatterns = [
            #"\b(func|class|struct|enum|protocol|import|let|var|return|if|else|for|while|async|await)\b"#,
            #"\b(const|function|interface|type|export|from|def|lambda|public|private|void|static)\b"#,
            #"[{};]"#,
            #"(^|\n)\s{2,}\S"#,
            #"\w+\s*\([^\n]*\)\s*(\{|->|:)"#
        ]

        let matches = codePatterns.reduce(into: 0) { score, pattern in
            if text.range(of: pattern, options: [.regularExpression]) != nil {
                score += 1
            }
        }
        return matches >= 2
    }

    private func looksLikeFormula(_ text: String) -> Bool {
        let patterns = [
            #"\\(frac|sqrt|sum|int|begin|alpha|beta|theta)\b"#,
            #"[∫∑√≈≠≤≥∞∂]"#,
            #"[₀₁₂₃₄₅₆₇₈₉⁰¹²³⁴⁵⁶⁷⁸⁹]"#
        ]
        return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }
}
