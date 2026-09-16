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
    private var sentenceText = ""
    private var utteranceID = 0
    private var lastObservedAt: Date?
    public private(set) var lastWait: TimeInterval = 0
    public private(set) var lastEmissionWasComplete = false
    public private(set) var lastEmissionID = 0

    public init(stableAfter: TimeInterval = 0.6, maxWait: TimeInterval = 2, normalizer: CaptionNormalizer = CaptionNormalizer()) {
        self.stableAfter = stableAfter
        self.maxWait = max(stableAfter, maxWait)
        self.normalizer = normalizer
    }

    public func update(_ raw: String, now: Date = Date()) -> String? {
        let text = normalizer.normalize(raw)
        guard !text.isEmpty else {
            clearPending()
            return nil
        }
        if let lastObservedAt, now.timeIntervalSince(lastObservedAt) > 5 {
            reset()
        }
        lastObservedAt = now
        let remaining = CaptionText.removingOverlap(previous: committedText, current: text)
        guard !remaining.isEmpty else {
            clearPending()
            return nil
        }

        if !sentenceText.isEmpty,
           let joined = CaptionText.continuing(previous: sentenceText, current: remaining),
           joined.count <= max(2400, remaining.count) {
            sentenceText = joined
        } else {
            sentenceText = remaining
            utteranceID += 1
            emittedText = nil
            clearPending()
        }

        let complete = CaptionText.completePrefix(sentenceText)
        let candidate = complete.isEmpty ? sentenceText : complete

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
        lastEmissionID = utteranceID
        if lastEmissionWasComplete {
            committedText = String((committedText + " " + candidate).trimmingCharacters(in: .whitespaces).suffix(4800))
            sentenceText = String(sentenceText.dropFirst(candidate.count)).trimmingCharacters(in: .whitespaces)
            utteranceID += 1
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
        sentenceText = ""
        lastObservedAt = nil
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
    public static func continuing(previous: String, current: String) -> String? {
        if previous == current || previous.hasSuffix(" " + current) { return previous }
        if current.hasPrefix(previous) || previous.hasPrefix(current) { return current }

        let oldWords = previous.split(separator: " ").map(String.init)
        let newWords = current.split(separator: " ").map(String.init)
        let oldKeys = oldWords.map { $0.lowercased() }
        let newKeys = newWords.map { $0.lowercased() }
        let count = min(oldWords.count, newWords.count)
        guard count >= 2 else { return nil }

        for overlap in stride(from: count, through: 2, by: -1) {
            if oldKeys.suffix(overlap).elementsEqual(newKeys.prefix(overlap)) {
                return (oldWords.dropLast(overlap) + newWords).joined(separator: " ")
            }
        }

        // Anchor revisions to matching words so corrections replace the visible
        // window while the start of the sentence stays in the buffer.
        var bestCount = 0
        var bestOffset = 0
        for oldIndex in oldKeys.indices {
            for newIndex in newKeys.indices where oldKeys[oldIndex] == newKeys[newIndex] {
                var matched = 0
                while oldIndex + matched < oldKeys.count,
                      newIndex + matched < newKeys.count,
                      oldKeys[oldIndex + matched] == newKeys[newIndex + matched] {
                    matched += 1
                }
                let sameStart = oldIndex == 0 && newIndex == 0 && matched >= 2
                let anchored = matched >= 3 && (oldIndex + matched == oldKeys.count || matched * 2 >= count)
                let offset = max(0, oldIndex - newIndex)
                if offset > 0, newIndex > 0, oldKeys[offset] != newKeys[0] { continue }
                if (sameStart || anchored), matched > bestCount {
                    bestCount = matched
                    bestOffset = offset
                }
            }
        }
        guard bestCount > 0 else { return nil }
        return (oldWords.prefix(bestOffset) + newWords).joined(separator: " ")
    }

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
        guard count >= 1 else { return current }
        for overlap in stride(from: count, through: 1, by: -1) {
            if overlap == 1, completePrefix(String(newWords[0])) != String(newWords[0]) { continue }
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
    public let isComplete: Bool

    public init(text: String, context: [String] = [], isComplete: Bool = true) {
        self.text = text
        self.context = context
        self.isComplete = isComplete
    }
}

public struct CaptionContext {
    private var recent: [(utteranceID: Int, text: String)] = []

    public init() {}

    public func prepare(_ text: String, utteranceID: Int, isComplete: Bool = true) -> CaptionTranslation {
        let context = recent.filter { $0.utteranceID != utteranceID }.suffix(3).map(\.text)
        return CaptionTranslation(text: text, context: context, isComplete: isComplete)
    }

    public mutating func remember(_ text: String, utteranceID: Int) {
        // Retain replaced subtitle cues even without punctuation, but keep only
        // the latest revision so a preview cannot become its own context.
        recent.removeAll { $0.utteranceID == utteranceID }
        recent.append((utteranceID, String(text.suffix(600))))
        recent = Array(recent.suffix(4))
    }

    public mutating func reset() {
        recent.removeAll()
    }
}

public struct CaptionPresentation {
    private var utteranceID: Int?
    private var text = ""
    private var finishedText = ""
    public private(set) var previousText = ""

    public init() {}

    public mutating func update(_ translation: String, utteranceID: Int, isFinal: Bool) -> String? {
        guard !translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if self.utteranceID == utteranceID {
            if !isFinal, translation.count < text.count { return nil }
            if isFinal { finishedText = translation }
            if translation == text { return nil }
        } else {
            if !finishedText.isEmpty { previousText = finishedText }
            finishedText = isFinal ? translation : ""
        }
        self.utteranceID = utteranceID
        text = translation
        return translation
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
