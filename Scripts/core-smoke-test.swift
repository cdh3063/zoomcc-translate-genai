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

let scrolling = CaptionStabilizer()
let scrollingFrames = [
    "Partners can use the credits to",
    "use the credits to offset infrastructure",
    "to offset infrastructure costs, but unused",
    "infrastructure costs, but unused credits do not",
    "unused credits do not roll over."
]
for (index, frame) in scrollingFrames.enumerated() {
    expectNil(scrolling.update(frame, now: start.addingTimeInterval(Double(index) * 0.2)), "scrolling sentence is still being collected")
}
expectEqual(
    scrolling.update(scrollingFrames.last!, now: start.addingTimeInterval(1.5)),
    "Partners can use the credits to offset infrastructure costs, but unused credits do not roll over.",
    "scrolling keeps the beginning and negation of the whole sentence"
)
expectNil(scrolling.update(scrollingFrames.last!, now: start.addingTimeInterval(2.2)), "the assembled sentence is committed only once")

let revisions = CaptionStabilizer()
expectNil(revisions.update("Partners can use credits to", now: start), "partial sentence begins")
expectEqual(revisions.update("Partners can use credits to", now: start.addingTimeInterval(0.7)), "Partners can use credits to", "initial partial can be displayed promptly")
let partialID = revisions.lastEmissionID
expectNil(revisions.update("use credits to offset infrastructure", now: start.addingTimeInterval(0.8)), "scrolling extends the current partial")
expectEqual(revisions.update("use credits to offset infrastructure", now: start.addingTimeInterval(1.5)), "Partners can use credits to offset infrastructure", "partial revisions retain the sentence start")
expectEqual(revisions.lastEmissionID, partialID, "partial revisions share the same utterance ID")
expectNil(revisions.update("credits to offset operating costs.", now: start.addingTimeInterval(1.6)), "corrected final wording becomes pending")
expectEqual(revisions.update("credits to offset operating costs.", now: start.addingTimeInterval(2.3)), "Partners can use credits to offset operating costs.", "corrections replace visible words without losing the start")
expectEqual(revisions.lastEmissionID, partialID, "the final translation replaces its partial previews")
expectEqual(revisions.lastEmissionWasComplete, true, "completed revision is final")
expectNil(revisions.update("costs. They expire tomorrow.", now: start.addingTimeInterval(2.4)), "next sentence begins after committed suffix")
expectEqual(revisions.update("They expire tomorrow.", now: start.addingTimeInterval(3.1)), "They expire tomorrow.", "next sentence is a separate utterance")
expectEqual(revisions.lastEmissionID > partialID, true, "new utterance gets a new ID")

expectEqual(CaptionText.continuing(previous: "Our partners receive credits", current: "A different topic begins"), nil, "unrelated captions are not joined")
expectEqual(CaptionText.continuing(previous: "Our partners can use credits to offset", current: "They can use credits to offset costs."), nil, "matching phrases do not manufacture an unobserved subject")
expectEqual(CaptionText.continuing(previous: "The price is 20 dollars", current: "The price is 30 dollars"), "The price is 30 dollars", "recognition corrections replace old numbers")
expectEqual(CaptionText.continuing(previous: "We plan to invest", current: "We plan to invest more"), "We plan to invest more", "growing words and phrases are preserved")

let resetOnGap = CaptionStabilizer()
expectNil(resetOnGap.update("Partners can use credits", now: start), "gap test starts a sentence")
expectNil(resetOnGap.update("credits expire tomorrow.", now: start.addingTimeInterval(6)), "long capture gap starts a new utterance")
expectEqual(resetOnGap.update("credits expire tomorrow.", now: start.addingTimeInterval(6.7)), "credits expire tomorrow.", "old sentence is not carried over a capture gap")

let bounded = CaptionStabilizer()
expectNil(bounded.update("The program grows", now: start), "bounded buffer starts")
expectNil(bounded.update("The program grows " + String(repeating: "steadily ", count: 270), now: start.addingTimeInterval(0.2)), "unpunctuated text can be longer than the retained prefix limit")
expectNil(bounded.update("steadily steadily continues today", now: start.addingTimeInterval(0.4)), "oversized carried text is released")
expectEqual(bounded.update("steadily steadily continues today", now: start.addingTimeInterval(1.1)), "steadily steadily continues today", "retained history cannot grow indefinitely")

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
expectEqual(context.prepare("Our partners", utteranceID: 1).context, [], "first caption has no context")
context.remember("Our partners", utteranceID: 1)
expectEqual(context.prepare("Our partners receive credits.", utteranceID: 1).context, [], "revised partial is not its own context")
context.remember("Our partners receive credits.", utteranceID: 1)
expectEqual(context.prepare("They can use them.", utteranceID: 2).context, ["Our partners receive credits."], "prior statement is sent as context")
context.remember("They can use", utteranceID: 2)
expectEqual(context.prepare("They can use them.", utteranceID: 2).context, ["Our partners receive credits."], "partial previews never become separate context sentences")
expectEqual(context.prepare("They can use", utteranceID: 2, isComplete: false).isComplete, false, "unfinished state is included in translation input")
context.remember("They can use them.", utteranceID: 2)
context.remember("Third.", utteranceID: 3)
context.remember("Fourth.", utteranceID: 4)
expectEqual(context.prepare("Fifth.", utteranceID: 5).context, ["They can use them.", "Third.", "Fourth."], "context is bounded to three captions")
expectEqual(context.prepare("Fourth revised.", utteranceID: 4).context, ["Our partners receive credits.", "They can use them.", "Third."], "revisions retain all three preceding captions")
context.reset()
expectEqual(context.prepare("New meeting.", utteranceID: 5).context, [], "context resets between conversations")

var replacedCueContext = CaptionContext()
let replacingCues = CaptionStabilizer()
_ = replacingCues.update("The fellowship covers her tuition", now: start)
let firstCue = replacingCues.update("The fellowship covers her tuition", now: start.addingTimeInterval(0.7))!
expectEqual(replacingCues.lastEmissionWasComplete, false, "a cue without punctuation remains incomplete")
let firstCueID = replacingCues.lastEmissionID
replacedCueContext.remember(firstCue, utteranceID: firstCueID)
_ = replacingCues.update("It also pays for housing.", now: start.addingTimeInterval(0.8))
let nextCue = replacingCues.update("It also pays for housing.", now: start.addingTimeInterval(1.5))!
expectEqual(replacingCues.lastEmissionID > firstCueID, true, "a replacement with no overlap gets a separate ID")
expectEqual(replacedCueContext.prepare(nextCue, utteranceID: replacingCues.lastEmissionID).context, [firstCue], "a replaced unpunctuated cue remains available to resolve pronouns")
replacedCueContext.remember("The fellowship covers all her tuition", utteranceID: firstCueID)
expectEqual(replacedCueContext.prepare(nextCue, utteranceID: replacingCues.lastEmissionID).context, ["The fellowship covers all her tuition"], "only the latest revision is retained")

var limitedContext = CaptionContext()
for id in 1...10 {
    limitedContext.remember(String(repeating: "x", count: 1000), utteranceID: id)
}
expectEqual(limitedContext.prepare("Next.", utteranceID: 11).context.map(\.count), [600, 600, 600], "context stays bounded for long unpunctuated streams")

var presentation = CaptionPresentation()
expectEqual(presentation.update("Partners can use credits", utteranceID: 1, isFinal: true), "Partners can use credits", "first partial translation is visible")
expectNil(presentation.update("Partners", utteranceID: 1, isFinal: false), "retranslation does not erase an already visible sentence")
expectEqual(presentation.update("Partners can use credits for costs", utteranceID: 1, isFinal: false), "Partners can use credits for costs", "extended translation replaces its preview")
expectEqual(presentation.update("Credits offset costs.", utteranceID: 1, isFinal: true), "Credits offset costs.", "a corrected final can be shorter than the preview")
expectEqual(presentation.update("Unused", utteranceID: 2, isFinal: false), "Unused", "a new utterance starts independently")

var events = ServerSentEvents()
let stream = ": keepalive\r\nevent: response.output_text.delta\r\ndata: {\"type\":\r\ndata: \"response.output_text.delta\",\"delta\":\"\u{d55c}\u{ae00}\"}\r\n\r\ndata: [DONE]\n\n"
let payloads = stream.utf8.compactMap { events.append($0) }
expectEqual(payloads.count, 2, "SSE dispatches complete events only")
expectEqual(payloads[0], "{\"type\":\n\"response.output_text.delta\",\"delta\":\"\u{d55c}\u{ae00}\"}", "SSE handles CRLF, UTF-8, comments and multiline data")
expectEqual(payloads[1], "[DONE]", "SSE done event")

print("core smoke tests passed")
