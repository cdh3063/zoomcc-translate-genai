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

expectEqual(
    CaptionLine.latestText([
        CaptionLine(text: "old top line", midY: 0.9),
        CaptionLine(text: "new bottom line", midY: 0.1),
        CaptionLine(text: "middle line", midY: 0.5)
    ], limit: 2),
    "middle line new bottom line",
    "latest rows use lower Vision coordinates in reading order"
)
expectEqual(CaptionLine.latestText([], limit: 2), "", "empty OCR results")
expectEqual(CaptionLine.latestText([CaptionLine(text: "one", midY: 0.2)], limit: 3), "one", "fewer lines than the limit")

let continuous = CaptionStabilizer()
for sample in 0..<10 {
    expectNil(continuous.update("The program " + String(repeating: "grows ", count: sample), now: start.addingTimeInterval(Double(sample) * 0.2)), "continuous speech waits at most two seconds")
}
expectEqual(continuous.update("The program keeps growing", now: start.addingTimeInterval(2)), "The program keeps growing", "continuous updates cannot starve translation")
expectEqual(continuous.lastEmissionWasComplete, false, "maximum-wait output is a partial sentence")

let sentences = CaptionStabilizer()
expectNil(sentences.update("We invest in OCI. The next", now: start), "completed sentence starts its own debounce")
expectNil(sentences.update("We invest in OCI. The next program", now: start.addingTimeInterval(0.3)), "growing tail does not reset completed prefix")
expectEqual(sentences.update("We invest in OCI. The next program offers", now: start.addingTimeInterval(0.7)), "We invest in OCI.", "completed sentence emits while speech continues")
expectEqual(sentences.lastEmissionWasComplete, true, "completed prefix is marked final")
expectNil(sentences.update("We invest in OCI. The next program offers credits.", now: start.addingTimeInterval(0.8)), "new sentence becomes pending")
expectEqual(sentences.update("in OCI. The next program offers credits.", now: start.addingTimeInterval(1.5)), "The next program offers credits.", "scrolling overlap does not repeat committed sentence")
expectNil(sentences.update("The next program offers credits.", now: start.addingTimeInterval(2.2)), "committed sentence is not translated again")

let blanks = CaptionStabilizer()
expectNil(blanks.update("a caption", now: start), "blank test begins pending")
expectNil(blanks.update("", now: start.addingTimeInterval(1)), "blank breaks stability")
expectNil(blanks.update("a caption", now: start.addingTimeInterval(1.1)), "caption after a blank must stabilize again")
expectEqual(blanks.update("a caption", now: start.addingTimeInterval(1.8)), "a caption", "caption emits after recovering from blank")
blanks.reset()
expectNil(blanks.update("a caption", now: start.addingTimeInterval(2)), "reset clears emitted state")

expectEqual(CaptionText.completePrefix("Dr. Smith will invest 3.5 million dollars. Next"), "Dr. Smith will invest 3.5 million dollars.", "sentence tokenizer preserves abbreviations and decimals")
expectEqual(CaptionText.completePrefix("We might invest..."), "", "ellipsis is not a completed thought")
expectEqual(CaptionText.removingOverlap(previous: "We invest in OCI.", current: "in OCI. It offers credits."), "It offers credits.", "scroll overlap is removed")
expectEqual(CaptionText.removingOverlap(previous: "That is a benefit.", current: "Different benefit."), "Different benefit.", "unrelated sentences are preserved")

var context = CaptionContext()
expectEqual(context.prepare("Our partners").context, [], "first caption has no context")
context.remember("Our partners")
expectEqual(context.prepare("Our partners receive credits.").context, [], "revised partial is not its own context")
context.remember("Our partners receive credits.")
expectEqual(context.prepare("They can use them.").context, ["Our partners receive credits."], "prior statement is sent as context")
context.remember("They can use them.")
context.remember("Third.")
context.remember("Fourth.")
expectEqual(context.prepare("Fifth.").context, ["They can use them.", "Third.", "Fourth."], "context is bounded to three captions")
context.reset()
expectEqual(context.prepare("New meeting.").context, [], "context resets between conversations")

var events = ServerSentEvents()
let stream = ": keepalive\r\nevent: response.output_text.delta\r\ndata: {\"type\":\r\ndata: \"response.output_text.delta\",\"delta\":\"\u{d55c}\u{ae00}\"}\r\n\r\ndata: [DONE]\n\n"
let payloads = stream.utf8.compactMap { events.append($0) }
expectEqual(payloads.count, 2, "SSE dispatches complete events only")
expectEqual(payloads[0], "{\"type\":\n\"response.output_text.delta\",\"delta\":\"\u{d55c}\u{ae00}\"}", "SSE handles CRLF, UTF-8, comments and multiline data")
expectEqual(payloads[1], "[DONE]", "SSE done event")

print("core smoke tests passed")
