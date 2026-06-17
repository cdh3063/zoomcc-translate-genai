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
    private let normalizer: CaptionNormalizer
    private var pendingText: String?
    private var pendingSince: Date?
    private var emittedText: String?

    public init(stableAfter: TimeInterval = 0.6, normalizer: CaptionNormalizer = CaptionNormalizer()) {
        self.stableAfter = stableAfter
        self.normalizer = normalizer
    }

    public func update(_ raw: String, now: Date = Date()) -> String? {
        let text = normalizer.normalize(raw)

        guard !text.isEmpty, text != emittedText else {
            return nil
        }

        guard text == pendingText, let pendingSince else {
            pendingText = text
            pendingSince = now
            return nil
        }

        guard now.timeIntervalSince(pendingSince) >= stableAfter else {
            return nil
        }

        emittedText = text
        return text
    }

    public func reset() {
        pendingText = nil
        pendingSince = nil
        emittedText = nil
    }
}
