import Foundation

public struct CaptionNormalizer {
    public init() {}

    public func normalize(_ raw: String) -> String {
        let lines = raw
            .split(whereSeparator: { $0.isNewline })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let joined = lines.joined(separator: " ")
        return joined
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public final class CaptionStabilizer {
    private let stableAfter: TimeInterval
    private let maxWait: TimeInterval
    private let normalizer: CaptionNormalizer
    private var pendingText: String?
    private var pendingSince: Date?
    private var pendingStartedAt: Date?
    private var emittedText: String?
    private var committedText = ""
    public private(set) var lastWait: TimeInterval = 0
    public private(set) var lastEmissionWasComplete = false

    public init(stableAfter: TimeInterval = 0.6, maxWait: TimeInterval = 2, normalizer: CaptionNormalizer = CaptionNormalizer()) {
        self.stableAfter = stableAfter
        self.maxWait = max(stableAfter, maxWait)
        self.normalizer = normalizer
    }

    public func update(_ raw: String, now: Date = Date()) -> String? {
        let text = normalizer.normalize(raw)
        let remaining = CaptionText.removingOverlap(previous: committedText, current: text)
        guard !remaining.isEmpty else {
            clearPending()
            return nil
        }

        let complete = CaptionText.completePrefix(remaining)
        let candidate = complete.isEmpty ? remaining : complete

        guard candidate != emittedText else {
            clearPending()
            return nil
        }

        if pendingStartedAt == nil {
            pendingStartedAt = now
        }
        if candidate != pendingText {
            pendingText = candidate
            pendingSince = now
        }

        guard let pendingSince, let pendingStartedAt,
              now.timeIntervalSince(pendingSince) >= stableAfter || now.timeIntervalSince(pendingStartedAt) >= maxWait else {
            return nil
        }

        lastWait = now.timeIntervalSince(pendingStartedAt)
        lastEmissionWasComplete = !complete.isEmpty
        if lastEmissionWasComplete {
            committedText = String(text.prefix(text.count - remaining.count + candidate.count))
            emittedText = nil
        } else {
            emittedText = candidate
        }
        clearPending()
        return candidate
    }

    public func reset() {
        clearPending()
        emittedText = nil
        committedText = ""
        lastWait = 0
        lastEmissionWasComplete = false
    }

    private func clearPending() {
        pendingText = nil
        pendingSince = nil
        pendingStartedAt = nil
    }
}

public enum CaptionText {
    public static func completePrefix(_ text: String) -> String {
        var end = text.startIndex
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .bySentences) { sentence, range, _, stop in
            let trimmed = sentence?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let withoutQuotes = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\"'\u{2019}\u{201d})]"))
            guard let last = withoutQuotes.last, ".!?\u{3002}\u{ff01}\u{ff1f}".contains(last), !withoutQuotes.hasSuffix("...") else {
                stop = true
                return
            }
            end = range.upperBound
        }
        return String(text[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func removingOverlap(previous: String, current: String) -> String {
        guard !previous.isEmpty else { return current }
        if current == previous || previous.hasSuffix(" " + current) { return "" }
        if current.hasPrefix(previous + " ") {
            return String(current.dropFirst(previous.count)).trimmingCharacters(in: .whitespaces)
        }
        let oldWords = previous.split(separator: " ")
        let newWords = current.split(separator: " ")
        let count = min(oldWords.count, newWords.count)
        guard count >= 2 else { return current }
        for overlap in stride(from: count, through: 2, by: -1) {
            if oldWords.suffix(overlap).elementsEqual(newWords.prefix(overlap)) {
                return newWords.dropFirst(overlap).joined(separator: " ")
            }
        }
        return current
    }
}

public struct CaptionLine {
    public let text: String
    public let midY: Double

    public init(text: String, midY: Double) {
        self.text = text
        self.midY = midY
    }

    public static func latestText(_ lines: [CaptionLine], limit: Int) -> String {
        // Vision's origin is at the bottom left; smaller Y means newer, lower rows.
        lines.sorted { $0.midY < $1.midY }
            .prefix(max(0, limit))
            .sorted { $0.midY > $1.midY }
            .map(\.text)
            .joined(separator: " ")
    }
}

public struct CaptionTranslation: Hashable, Sendable {
    public let text: String
    public let context: [String]

    public init(text: String, context: [String] = []) {
        self.text = text
        self.context = context
    }
}

public struct CaptionContext {
    private var recent: [String] = []

    public init() {}

    public mutating func prepare(_ text: String) -> CaptionTranslation {
        if let last = recent.last, text.hasPrefix(last) {
            recent.removeLast()
        }
        return CaptionTranslation(text: text, context: recent)
    }

    public mutating func remember(_ text: String) {
        recent.append(String(text.suffix(600)))
        recent = Array(recent.suffix(3))
    }

    public mutating func reset() {
        recent.removeAll()
    }
}

public struct ServerSentEvents {
    private var line: [UInt8] = []
    private var dataLines: [String] = []

    public init() {}

    public mutating func append(_ byte: UInt8) -> String? {
        guard byte == 10 else {
            line.append(byte)
            return nil
        }
        var text = String(decoding: line, as: UTF8.self)
        line.removeAll(keepingCapacity: true)
        if text.hasSuffix("\r") { text.removeLast() }
        if text.isEmpty {
            guard !dataLines.isEmpty else { return nil }
            let event = dataLines.joined(separator: "\n")
            dataLines.removeAll(keepingCapacity: true)
            return event
        }
        if text.hasPrefix("data:") {
            var data = String(text.dropFirst(5))
            if data.hasPrefix(" ") { data.removeFirst() }
            dataLines.append(data)
        }
        return nil
    }
}
