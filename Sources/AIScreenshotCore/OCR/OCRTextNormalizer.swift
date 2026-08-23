import Foundation

public struct OCRTextNormalizer: Sendable {
    public init() {}

    public func normalize(_ rawText: String, mergeWrappedLines: Bool = false) -> String {
        let normalizedNewlines = rawText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let trimmedLines = normalizedNewlines
            .components(separatedBy: "\n")
            .map { $0.replacingOccurrences(of: #"[ \t]+$"#, with: "", options: .regularExpression) }

        var output: [String] = []
        var previousWasBlank = false

        for line in trimmedLines {
            let isBlank = line.trimmingCharacters(in: .whitespaces).isEmpty
            if isBlank {
                if !previousWasBlank, !output.isEmpty {
                    output.append("")
                }
                previousWasBlank = true
                continue
            }

            if mergeWrappedLines,
               let previous = output.last,
               !previous.isEmpty,
               shouldMerge(previous: previous, next: line) {
                output[output.count - 1] = previous + joiner(previous: previous, next: line) + line
            } else {
                output.append(line)
            }
            previousWasBlank = false
        }

        while output.last == "" {
            output.removeLast()
        }

        return output.joined(separator: "\n")
    }

    private func shouldMerge(previous: String, next: String) -> Bool {
        guard !previous.hasSuffix("。"),
              !previous.hasSuffix("！"),
              !previous.hasSuffix("？"),
              !previous.hasSuffix("."),
              !previous.hasSuffix(":"),
              !previous.hasSuffix("："),
              !next.hasPrefix("•"),
              !next.hasPrefix("-") else {
            return false
        }

        return !previous.hasSuffix(";") && !previous.hasSuffix("{") && !previous.hasSuffix("}")
    }

    private func joiner(previous: String, next: String) -> String {
        let previousEndsASCII = previous.unicodeScalars.last.map { $0.value < 128 } ?? false
        let nextStartsASCII = next.unicodeScalars.first.map { $0.value < 128 } ?? false
        return previousEndsASCII && nextStartsASCII ? " " : ""
    }
}
