import Foundation
import ZoomCaptionCore

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    if actual != expected {
        fputs("FAIL: \(message). Expected \(expected), got \(actual)\n", stderr)
        exit(1)
    }
}

func expectNil<T>(_ actual: T?, _ message: String) {
    if let actual {
        fputs("FAIL: \(message). Expected nil, got \(actual)\n", stderr)
        exit(1)
    }
}

let normalizer = CaptionNormalizer()
expectEqual(
    normalizer.normalize("  hello   world\n\n from   zoom  "),
    "hello world from zoom",
    "normalizer collapses whitespace"
)

let stabilizer = CaptionStabilizer(stableAfter: 1)
let start = Date(timeIntervalSince1970: 100)
expectNil(stabilizer.update("hello   world", now: start), "first caption sample is pending")
expectNil(stabilizer.update("hello world", now: start.addingTimeInterval(0.5)), "caption is not stable yet")
expectEqual(
    stabilizer.update("hello world", now: start.addingTimeInterval(1.1)),
    "hello world",
    "stable caption emits once"
)
expectNil(stabilizer.update("hello world", now: start.addingTimeInterval(2)), "same caption is not emitted twice")

print("core smoke tests passed")
