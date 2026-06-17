import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import Vision
import ZoomCaptionCore

protocol CaptionReader {
    func readText() -> String?
}

protocol Translator {
    func translate(_ text: String) async throws -> String
}

enum AppError: Error, CustomStringConvertible {
    case missingValue(String)
    case invalidOption(String)
    case invalidNumber(String)
    case invalidRegion(String)
    case invalidOCIConfig(String)
    case missingEnvironment(String)
    case invalidURL(String)
    case httpStatus(Int, String)
    case cancelledRegionSelection
    case emptyTranslation

    var description: String {
        switch self {
        case .missingValue(let option):
            return "Missing value for \(option)."
        case .invalidOption(let option):
            return "Unknown option: \(option)."
        case .invalidNumber(let value):
            return "Invalid number: \(value)."
        case .invalidRegion(let value):
            return "Invalid OCR region. Use x,y,width,height, got: \(value)."
        case .invalidOCIConfig(let message):
            return "Invalid OCI configuration: \(message)"
        case .missingEnvironment(let name):
            return "Missing environment variable: \(name)."
        case .invalidURL(let value):
            return "Invalid URL: \(value)."
        case .httpStatus(let status, let body):
            return "Translation request failed with HTTP \(status): \(body)"
        case .cancelledRegionSelection:
            return "OCR region selection was cancelled."
        case .emptyTranslation:
            return "Translation provider returned an empty result."
        }
    }
}

enum ProviderName: String {
    case mock
    case oci
    case deepl
}

struct AppConfig {
    var appName = "Zoom"
    var windowTitle: String?
    var provider = ProviderName.mock
    var targetLanguage = "KO"
    var sourceLanguage: String?
    var pollInterval: TimeInterval = 0.2
    var stableAfter: TimeInterval = 0.6
    var forceOCR = false
    var selectOCRRegion = false
    var ocrRegion: CGRect?
    var ocrDisplay: Int?
    var ocrAnchor: OCRAnchor?
    var ocrLineLimit = 2
    var overlayWidth: CGFloat = 980
    var overlayHeight: CGFloat = 132
    var overlayX: CGFloat?
    var overlayY: CGFloat?
    var overlayFontSize: CGFloat = 30
    var overlayDraggable = true
    var debug = false
    var listWindows = false
    var showHelp = false

    static func parse(_ arguments: [String]) throws -> AppConfig {
        var config = AppConfig()
        var index = 1

        while index < arguments.count {
            let raw = arguments[index]

            if raw == "-h" || raw == "--help" {
                config.showHelp = true
                index += 1
                continue
            }

            if raw == "--debug" {
                config.debug = true
                index += 1
                continue
            }

            if raw == "--list-windows" {
                config.listWindows = true
                index += 1
                continue
            }

            if raw == "--force-ocr" {
                config.forceOCR = true
                index += 1
                continue
            }

            if raw == "--select-ocr-region" {
                config.selectOCRRegion = true
                config.forceOCR = true
                index += 1
                continue
            }

            if raw == "--overlay-click-through" {
                config.overlayDraggable = false
                index += 1
                continue
            }

            guard raw.hasPrefix("--") else {
                throw AppError.invalidOption(raw)
            }

            let option: String
            let value: String
            if let equals = raw.firstIndex(of: "=") {
                option = String(raw[..<equals])
                value = String(raw[raw.index(after: equals)...])
            } else {
                option = raw
                index += 1
                guard index < arguments.count else {
                    throw AppError.missingValue(option)
                }
                value = arguments[index]
            }

            switch option {
            case "--app-name":
                config.appName = value
            case "--window-title":
                config.windowTitle = value
            case "--provider":
                guard let provider = ProviderName(rawValue: value.lowercased()) else {
                    throw AppError.invalidOption("\(option) \(value)")
                }
                config.provider = provider
            case "--target-lang":
                config.targetLanguage = value
            case "--source-lang":
                config.sourceLanguage = value
            case "--interval":
                config.pollInterval = try parseTimeInterval(value)
            case "--stable-after":
                config.stableAfter = try parseTimeInterval(value)
            case "--ocr-region":
                config.ocrRegion = try parseRegion(value)
            case "--ocr-display":
                config.ocrDisplay = try parsePositiveInt(value)
            case "--ocr-anchor":
                config.ocrAnchor = try parseOCRAnchor(value)
                config.forceOCR = true
            case "--ocr-lines":
                config.ocrLineLimit = try parsePositiveInt(value)
            case "--overlay-width":
                config.overlayWidth = try parseCGFloat(value)
            case "--overlay-height":
                config.overlayHeight = try parseCGFloat(value)
            case "--overlay-x":
                config.overlayX = try parseCGFloat(value)
            case "--overlay-y":
                config.overlayY = try parseCGFloat(value)
            case "--font-size":
                config.overlayFontSize = try parseCGFloat(value)
            default:
                throw AppError.invalidOption(option)
            }

            index += 1
        }

        if config.forceOCR, config.ocrRegion == nil, config.ocrAnchor == nil, !config.selectOCRRegion {
            throw AppError.missingValue("--ocr-region, --ocr-anchor, or --select-ocr-region is required when --force-ocr is set")
        }

        return config
    }

    static var help: String {
        """
        zoomcc-translate-genai

        Usage:
          zoomcc-translate-genai [options]

        Options:
          --app-name NAME             Source app name to scan with Accessibility. Default: Zoom
          --window-title TEXT         Only scan windows whose title contains this text.
          --provider mock|oci|deepl
                                     Translation provider. Default: mock
          --target-lang CODE          Target language. Default: KO
          --source-lang CODE          Optional source language.
          --interval SECONDS          Poll interval. Default: 0.2
          --stable-after SECONDS      Wait until caption text is stable. Default: 0.6
          --ocr-region x,y,w,h        OCR fallback region on the main display.
          --ocr-display NUMBER        Display number for OCR capture. Usually 1 for main display.
          --ocr-anchor ID:x,y,w,h     Stable display ID and normalized region from a prior selection.
          --ocr-lines COUNT           Keep the largest OCR text lines. Default: 2
          --select-ocr-region         Drag to select the OCR fallback region before starting.
          --force-ocr                 Skip Accessibility and use OCR only.
          --overlay-width POINTS      Overlay width. Default: 980
          --overlay-height POINTS     Overlay height. Default: 132
          --overlay-x POINTS          Overlay x position from the lower-left screen origin.
          --overlay-y POINTS          Overlay y position from the lower-left screen origin.
          --font-size POINTS          Overlay font size. Default: 30
          --overlay-click-through     Disable overlay dragging and pass mouse events through.
          --debug                     Print caption reader diagnostics to stderr.
          --list-windows              Print matching app window titles and exit.
          -h, --help                  Show this help.

        Environment:
          OCI_REGION                  Required unless OCI_GENAI_API_URL or OCI_GENAI_API_BASE_URL is set
          OCI_GENAI_API_KEY           Required for --provider oci
          OCI_GENAI_API_MODE          Optional. responses|chat. Default: responses
          OCI_GENAI_API_BASE_URL      Optional. Default: region-based /20231130/actions/v1
          OCI_GENAI_API_URL           Optional exact Generative AI API URL
          GPT_MODEL                   Optional model alias for --provider oci
          OCI_MODEL_ID                Optional. Default: openai.gpt-5.4-nano
          DEEPL_API_KEY               Required for --provider deepl
          DEEPL_API_URL               Optional. Default: https://api-free.deepl.com/v2/translate
        """
    }

    private static func parseTimeInterval(_ value: String) throws -> TimeInterval {
        guard let number = TimeInterval(value), number > 0 else {
            throw AppError.invalidNumber(value)
        }
        return number
    }

    private static func parseCGFloat(_ value: String) throws -> CGFloat {
        guard let number = Double(value) else {
            throw AppError.invalidNumber(value)
        }
        return CGFloat(number)
    }

    private static func parseRegion(_ value: String) throws -> CGRect {
        let parts = value.split(separator: ",").map(String.init)
        guard parts.count == 4,
              let x = Double(parts[0]),
              let y = Double(parts[1]),
              let width = Double(parts[2]),
              let height = Double(parts[3]),
              width > 0,
              height > 0 else {
            throw AppError.invalidRegion(value)
        }

        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func parsePositiveInt(_ value: String) throws -> Int {
        guard let number = Int(value), number > 0 else {
            throw AppError.invalidNumber(value)
        }

        return number
    }

    private static func parseOCRAnchor(_ value: String) throws -> OCRAnchor {
        let pieces = value.split(separator: ":", maxSplits: 1).map(String.init)
        guard pieces.count == 2,
              let displayID = UInt32(pieces[0]) else {
            throw AppError.invalidOption("--ocr-anchor \(value)")
        }

        let parts = pieces[1].split(separator: ",").map(String.init)
        guard parts.count == 4,
              let x = Double(parts[0]),
              let y = Double(parts[1]),
              let width = Double(parts[2]),
              let height = Double(parts[3]),
              x >= 0,
              y >= 0,
              width > 0,
              height > 0 else {
            throw AppError.invalidOption("--ocr-anchor \(value)")
        }

        return OCRAnchor(
            displayID: CGDirectDisplayID(displayID),
            normalizedRect: CGRect(x: x, y: y, width: width, height: height)
        )
    }
}

final class AccessibilityCaptionReader: CaptionReader {
    private let appName: String
    private let windowTitle: String?
    private let normalizer = CaptionNormalizer()
    private let ignoredLabels: Set<String> = [
        "apps",
        "chat",
        "leave",
        "more",
        "mute",
        "participants",
        "reactions",
        "record",
        "share screen",
        "show captions",
        "stop video",
        "whiteboards"
    ]

    init(appName: String, windowTitle: String?) {
        self.appName = appName
        self.windowTitle = windowTitle
    }

    static func requestPermission(prompt: Bool) -> Bool {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt
        ] as CFDictionary

        return AXIsProcessTrustedWithOptions(options)
    }

    static func windowSummaries(appName: String) -> [String] {
        let applications = NSWorkspace.shared.runningApplications.filter {
            matchesSourceApp($0, appName: appName)
        }

        return applications.flatMap { application -> [String] in
            let appElement = AXUIElementCreateApplication(application.processIdentifier)
            guard let windows = copyAttribute(appElement, kAXWindowsAttribute as String) as? [AXUIElement] else {
                return ["\(application.localizedName ?? "unknown") pid=\(application.processIdentifier) windows=<not readable>"]
            }

            if windows.isEmpty {
                return ["\(application.localizedName ?? "unknown") pid=\(application.processIdentifier) windows=<none>"]
            }

            return windows.enumerated().map { index, window in
                let title = copyStringAttribute(window, kAXTitleAttribute as String) ?? "<untitled>"
                return "\(application.localizedName ?? "unknown") pid=\(application.processIdentifier) window[\(index)] title=\(title)"
            }
        }
    }

    func readText() -> String? {
        let applications = NSWorkspace.shared.runningApplications.filter {
            Self.matchesSourceApp($0, appName: appName)
        }

        let candidates = applications.flatMap(readTexts)
        return bestCandidate(from: candidates)
    }

    private func readTexts(from application: NSRunningApplication) -> [String] {
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        guard let windows = attribute(appElement, kAXWindowsAttribute as String) as? [AXUIElement] else {
            return []
        }

        var texts: [String] = []
        for window in windows where shouldScan(window: window) {
            collectTexts(from: window, depth: 0, into: &texts)
        }

        return texts
    }

    private func shouldScan(window: AXUIElement) -> Bool {
        guard let windowTitle else {
            return true
        }

        let title = stringAttribute(window, kAXTitleAttribute as String) ?? ""
        return title.localizedCaseInsensitiveContains(windowTitle)
    }

    private func collectTexts(from element: AXUIElement, depth: Int, into texts: inout [String]) {
        guard depth <= 8 else {
            return
        }

        let role = stringAttribute(element, kAXRoleAttribute as String) ?? ""
        let isTextRole = role == (kAXStaticTextRole as String)
            || role == (kAXTextAreaRole as String)
            || role == (kAXTextFieldRole as String)

        if isTextRole {
            if let value = stringAttribute(element, kAXValueAttribute as String) {
                texts.append(value)
            } else if let title = stringAttribute(element, kAXTitleAttribute as String) {
                texts.append(title)
            }
        }

        guard let children = attribute(element, kAXChildrenAttribute as String) as? [AXUIElement] else {
            return
        }

        for child in children.prefix(400) {
            collectTexts(from: child, depth: depth + 1, into: &texts)
        }
    }

    private func bestCandidate(from rawTexts: [String]) -> String? {
        var seen = Set<String>()
        var ordered: [String] = []

        for rawText in rawTexts {
            let text = normalizer.normalize(rawText)
            guard !text.isEmpty else {
                continue
            }

            let key = text.lowercased()
            guard !ignoredLabels.contains(key), !seen.contains(key) else {
                continue
            }

            seen.insert(key)
            ordered.append(text)
        }

        guard !ordered.isEmpty else {
            return nil
        }

        return ordered.suffix(4).joined(separator: " ")
    }

    private func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        let value = attribute(element, name)

        if let string = value as? String {
            return string
        }

        if let attributed = value as? NSAttributedString {
            return attributed.string
        }

        return nil
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> Any? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        guard result == .success else {
            return nil
        }

        return value
    }

    private static func copyStringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        let value = copyAttribute(element, name)

        if let string = value as? String {
            return string
        }

        if let attributed = value as? NSAttributedString {
            return attributed.string
        }

        return nil
    }

    private static func copyAttribute(_ element: AXUIElement, _ name: String) -> Any? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        guard result == .success else {
            return nil
        }

        return value
    }

    private static func matchesSourceApp(_ application: NSRunningApplication, appName: String) -> Bool {
        guard application.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return false
        }

        let needle = appName.lowercased()
        let name = application.localizedName?.lowercased() ?? ""
        let bundle = application.bundleIdentifier?.lowercased() ?? ""

        if needle == "zoom" {
            return name == "zoom.us" || name == "zoom" || bundle == "us.zoom.xos"
        }

        return name == needle || bundle == needle || name.contains(needle) || bundle.contains(needle)
    }
}

struct OCRAnchor {
    let displayID: CGDirectDisplayID
    let normalizedRect: CGRect

    var encoded: String {
        "\(displayID):\(format(normalizedRect.minX)),\(format(normalizedRect.minY)),\(format(normalizedRect.width)),\(format(normalizedRect.height))"
    }

    private func format(_ value: CGFloat) -> String {
        String(format: "%.6f", Double(value))
    }
}

struct OCRDisplayTarget {
    let region: CGRect
    let displayIndex: Int?
}

enum OCRDisplayResolver {
    static func resolve(anchor: OCRAnchor, debug: Bool) -> OCRDisplayTarget? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            return nil
        }

        let screen = screens.first { displayID(for: $0) == anchor.displayID }
            ?? NSScreen.main
            ?? screens[0]
        let displayIndex = screencaptureDisplayIndex(for: screen, screens: screens)
        let displayBounds = displayBounds(for: screen)
        let region = CGRect(
            x: anchor.normalizedRect.minX * displayBounds.width,
            y: anchor.normalizedRect.minY * displayBounds.height,
            width: anchor.normalizedRect.width * displayBounds.width,
            height: anchor.normalizedRect.height * displayBounds.height
        ).integral

        if debug {
            let matched = displayID(for: screen) == anchor.displayID ? "matched" : "fallback"
            fputs("[debug] resolved OCR anchor (\(matched)): \(anchor.encoded)\n", stderr)
            fputs("[debug] resolved OCR display: \(displayIndex.map(String.init) ?? "<auto>")\n", stderr)
            fputs("[debug] resolved OCR region: \(formatRect(region))\n", stderr)
        }

        return OCRDisplayTarget(region: region, displayIndex: displayIndex)
    }

    static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }

        return CGDirectDisplayID(screenNumber.uint32Value)
    }

    static func displayBounds(for screen: NSScreen) -> CGRect {
        guard let displayID = displayID(for: screen) else {
            return screen.frame
        }

        return CGDisplayBounds(displayID)
    }

    static func screencaptureDisplayIndex(for screen: NSScreen, screens: [NSScreen]) -> Int? {
        guard let targetDisplayID = displayID(for: screen) else {
            return nil
        }

        let maxDisplays: UInt32 = 16
        var activeDisplays = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
        var displayCount: UInt32 = 0
        let result = CGGetActiveDisplayList(maxDisplays, &activeDisplays, &displayCount)
        guard result == .success else {
            return screens.firstIndex(of: screen).map { $0 + 1 }
        }

        let displays = Array(activeDisplays.prefix(Int(displayCount)))
        if let index = displays.firstIndex(of: targetDisplayID) {
            return index + 1
        }

        return screens.firstIndex(of: screen).map { $0 + 1 }
    }

    static func formatRect(_ rect: CGRect) -> String {
        "\(Int(rect.origin.x)),\(Int(rect.origin.y)),\(Int(rect.width)),\(Int(rect.height))"
    }
}

final class OCRCaptionReader: CaptionReader {
    private struct Candidate {
        let text: String
        let boundingBox: CGRect
    }

    private struct Row {
        var midY: CGFloat
        var items: [Candidate]
    }

    private let region: CGRect
    private let displayIndex: Int?
    private let sourceLanguage: String?
    private let debug: Bool
    private let lineLimit: Int
    private let normalizer = CaptionNormalizer()
    private var debugImageAnnounced = false

    init(region: CGRect, displayIndex: Int?, sourceLanguage: String?, debug: Bool, lineLimit: Int) {
        self.region = region
        self.displayIndex = displayIndex
        self.sourceLanguage = sourceLanguage
        self.debug = debug
        self.lineLimit = lineLimit
    }

    func readText() -> String? {
        guard let image = captureRegion() else {
            return nil
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = recognitionLanguages(for: sourceLanguage)

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        let candidates = request.results?
            .compactMap { observation -> Candidate? in
                guard let text = observation.topCandidates(1).first?.string else {
                    return nil
                }

                let normalized = normalizer.normalize(text)
                guard !normalized.isEmpty else {
                    return nil
                }

                return Candidate(text: normalized, boundingBox: observation.boundingBox)
            } ?? []

        let text = selectCaptionText(from: candidates)

        let normalized = normalizer.normalize(text)
        return normalized.isEmpty ? nil : normalized
    }

    private func captureRegion() -> CGImage? {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("zoomcc-translate-genai-ocr-\(UUID().uuidString).png")
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        var arguments = ["-x"]
        if let displayIndex {
            arguments.append(contentsOf: ["-D", "\(displayIndex)"])
            arguments.append(fileURL.path)
        } else {
            arguments.append(contentsOf: [
                "-R",
                "\(Int(region.origin.x)),\(Int(region.origin.y)),\(Int(region.width)),\(Int(region.height))",
                fileURL.path
            ])
        }
        process.arguments = arguments

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0,
              let image = NSImage(contentsOf: fileURL) else {
            return nil
        }

        var proposedRect = CGRect(origin: .zero, size: image.size)
        guard let fullImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            return nil
        }

        let croppedImage: CGImage
        if displayIndex != nil {
            guard let cropped = cropDisplayImage(fullImage) else {
                return nil
            }
            croppedImage = cropped
        } else {
            croppedImage = fullImage
        }

        saveLatestImage(croppedImage)
        return croppedImage
    }

    private func cropDisplayImage(_ image: CGImage) -> CGImage? {
        let cropRect = scaledCropRect(for: image)
        if debug {
            fputs("[debug] full display capture size: \(image.width),\(image.height)\n", stderr)
            fputs("[debug] image crop rect: \(formatRect(cropRect))\n", stderr)
        }

        return image.cropping(to: cropRect)
    }

    private func scaledCropRect(for image: CGImage) -> CGRect {
        let displayBounds = displayIndex.flatMap(displayBoundsForScreencaptureIndex)
        let baseWidth = displayBounds?.width ?? CGFloat(image.width)
        let baseHeight = displayBounds?.height ?? CGFloat(image.height)
        let scaleX = CGFloat(image.width) / max(baseWidth, 1)
        let scaleY = CGFloat(image.height) / max(baseHeight, 1)
        let rect = CGRect(
            x: region.minX * scaleX,
            y: region.minY * scaleY,
            width: region.width * scaleX,
            height: region.height * scaleY
        ).integral

        return rect.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }

    private func displayBoundsForScreencaptureIndex(_ displayIndex: Int) -> CGRect? {
        let maxDisplays: UInt32 = 16
        var activeDisplays = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
        var displayCount: UInt32 = 0
        let result = CGGetActiveDisplayList(maxDisplays, &activeDisplays, &displayCount)
        guard result == .success, displayIndex > 0, displayIndex <= Int(displayCount) else {
            return nil
        }

        return CGDisplayBounds(activeDisplays[displayIndex - 1])
    }

    private func saveLatestImage(_ image: CGImage) {
        let debugURL = URL(fileURLWithPath: "/tmp/zoomcc-translate-genai-ocr-latest.png")
        let bitmap = NSBitmapImageRep(cgImage: image)
        let data = bitmap.representation(using: .png, properties: [:])
        try? data?.write(to: debugURL)

        if debug, !debugImageAnnounced {
            debugImageAnnounced = true
            fputs("[debug] latest OCR capture: \(debugURL.path)\n", stderr)
        }
    }

    private func formatRect(_ rect: CGRect) -> String {
        "\(Int(rect.origin.x)),\(Int(rect.origin.y)),\(Int(rect.width)),\(Int(rect.height))"
    }

    private func selectCaptionText(from candidates: [Candidate]) -> String {
        let useful = candidates.filter { candidate in
            let lower = candidate.text.lowercased()
            guard !lower.contains("http"), !lower.contains("www.") else {
                return false
            }

            return candidate.text.count > 1
        }

        let source = useful.isEmpty ? candidates : useful
        guard let maxHeight = source.map(\.boundingBox.height).max(), maxHeight > 0 else {
            return ""
        }

        let largest = source.filter {
            $0.boundingBox.height >= maxHeight * 0.62
        }
        let focused = largest.isEmpty ? source : largest
        let rows = groupRows(focused)
        let selectedRows = rows
            .sorted { $0.midY < $1.midY }
            .suffix(lineLimit)
            .sorted { $0.midY > $1.midY }

        return selectedRows
            .flatMap { row in
                row.items.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
            }
            .map(\.text)
            .joined(separator: " ")
    }

    private func groupRows(_ candidates: [Candidate]) -> [Row] {
        let sorted = candidates.sorted {
            abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.02
                ? $0.boundingBox.midY > $1.boundingBox.midY
                : $0.boundingBox.minX < $1.boundingBox.minX
        }

        var rows: [Row] = []
        for candidate in sorted {
            if let index = rows.firstIndex(where: { abs($0.midY - candidate.boundingBox.midY) <= 0.035 }) {
                rows[index].items.append(candidate)
                rows[index].midY = rows[index].items.map(\.boundingBox.midY).reduce(0, +) / CGFloat(rows[index].items.count)
            } else {
                rows.append(Row(midY: candidate.boundingBox.midY, items: [candidate]))
            }
        }

        return rows
    }

    private func recognitionLanguages(for sourceLanguage: String?) -> [String] {
        guard let sourceLanguage else {
            return []
        }

        switch sourceLanguage.lowercased() {
        case "en":
            return ["en-US"]
        case "ko":
            return ["ko-KR"]
        case "ja":
            return ["ja-JP"]
        case "zh":
            return ["zh-Hans"]
        default:
            return [sourceLanguage]
        }
    }
}

struct OCRSelection {
    let region: CGRect
    let displayIndex: Int?
    let anchor: OCRAnchor?
}

final class OCRRegionSelector {
    static func select(debug: Bool) -> OCRSelection? {
        guard !NSScreen.screens.isEmpty else {
            return nil
        }

        let controller = OCRRegionSelectionController(screens: NSScreen.screens, debug: debug)
        return controller.select()
    }
}

private final class OCRRegionSelectionController {
    private let screens: [NSScreen]
    private let debug: Bool
    private var selectedRegion: OCRSelection?
    private var windows: [NSWindow] = []
    private var isSelecting = false

    init(screens: [NSScreen], debug: Bool) {
        self.screens = screens
        self.debug = debug
    }

    func select() -> OCRSelection? {
        if debug {
            fputs("[debug] screen layout:\n", stderr)
            for screen in screens {
                fputs("[debug] \(screenDescription(screen))\n", stderr)
            }
        }

        isSelecting = true
        windows = screens.map(makeSelectionWindow)
        NSApp.activate(ignoringOtherApps: true)
        windows.forEach { $0.orderFrontRegardless() }
        if let keyWindow = windows.first(where: { $0.screen == NSScreen.main }) ?? windows.first {
            keyWindow.makeKey()
        }

        while isSelecting {
            autoreleasepool {
                if let event = NSApp.nextEvent(
                    matching: .any,
                    until: Date.distantFuture,
                    inMode: .default,
                    dequeue: true
                ) {
                    NSApp.sendEvent(event)
                }
            }
        }

        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()

        return selectedRegion
    }

    private func makeSelectionWindow(for screen: NSScreen) -> NSWindow {
        let contentRect = NSRect(origin: .zero, size: screen.frame.size)
        let view = OCRRegionSelectionView(frame: contentRect)
        view.onFinish = { [weak self] rect in
            self?.selectedRegion = self?.captureRect(on: screen, fromLocalRect: rect)
            self?.isSelecting = false
        }
        view.onCancel = { [weak self] in
            self?.selectedRegion = nil
            self?.isSelecting = false
        }

        let selectionWindow = OCRSelectionWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        selectionWindow.level = .screenSaver
        selectionWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        selectionWindow.backgroundColor = .clear
        selectionWindow.isOpaque = false
        selectionWindow.hasShadow = false
        selectionWindow.contentView = view
        selectionWindow.makeFirstResponder(view)
        return selectionWindow
    }

    private func captureRect(on screen: NSScreen, fromLocalRect localRect: CGRect) -> OCRSelection {
        let displayIndex = OCRDisplayResolver.screencaptureDisplayIndex(for: screen, screens: screens)
        let displayBounds = OCRDisplayResolver.displayBounds(for: screen)
        let scaleX = displayBounds.width / screen.frame.width
        let scaleY = displayBounds.height / screen.frame.height

        let captureRect = CGRect(
            x: localRect.minX * scaleX,
            y: (screen.frame.height - localRect.maxY) * scaleY,
            width: localRect.width * scaleX,
            height: localRect.height * scaleY
        ).integral
        let anchor = OCRDisplayResolver.displayID(for: screen).map { displayID in
            OCRAnchor(
                displayID: displayID,
                normalizedRect: CGRect(
                    x: captureRect.minX / displayBounds.width,
                    y: captureRect.minY / displayBounds.height,
                    width: captureRect.width / displayBounds.width,
                    height: captureRect.height / displayBounds.height
                )
            )
        }

        if debug {
            fputs("[debug] selected local rect: \(OCRDisplayResolver.formatRect(localRect))\n", stderr)
            fputs("[debug] selected screen: \(screenDescription(screen))\n", stderr)
            fputs("[debug] screencapture display: \(displayIndex.map(String.init) ?? "<auto>")\n", stderr)
            fputs("[debug] screencapture local rect: \(OCRDisplayResolver.formatRect(captureRect))\n", stderr)
            if let anchor {
                fputs("[debug] stable OCR anchor: \(anchor.encoded)\n", stderr)
            }
        }

        return OCRSelection(region: captureRect, displayIndex: displayIndex, anchor: anchor)
    }

    private func screenDescription(_ screen: NSScreen) -> String {
        let displayBounds = OCRDisplayResolver.displayBounds(for: screen)
        let index = OCRDisplayResolver.screencaptureDisplayIndex(for: screen, screens: screens).map(String.init) ?? "<auto>"
        let displayID = OCRDisplayResolver.displayID(for: screen).map(String.init) ?? "<unknown>"
        return "display=\(index) id=\(displayID) frame=\(OCRDisplayResolver.formatRect(screen.frame)) scale=\(screen.backingScaleFactor) displayBounds=\(OCRDisplayResolver.formatRect(displayBounds))"
    }
}

private final class OCRSelectionWindow: NSWindow {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}

private final class OCRRegionSelectionView: NSView {
    var onFinish: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.black.withAlphaComponent(0.28).setFill()
        bounds.fill()
        drawInstructions()

        guard let selectionRect else {
            return
        }

        NSColor.systemBlue.withAlphaComponent(0.22).setFill()
        selectionRect.fill()
        NSColor.systemBlue.setStroke()
        let path = NSBezierPath(rect: selectionRect)
        path.lineWidth = 3
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = event.locationInWindow
        currentPoint = startPoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = event.locationInWindow
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = event.locationInWindow
        guard let selectionRect, selectionRect.width >= 16, selectionRect.height >= 16 else {
            startPoint = nil
            currentPoint = nil
            needsDisplay = true
            return
        }

        onFinish?(selectionRect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    private var selectionRect: NSRect? {
        guard let startPoint, let currentPoint else {
            return nil
        }

        return NSRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(startPoint.x - currentPoint.x),
            height: abs(startPoint.y - currentPoint.y)
        )
    }

    private func drawInstructions() {
        let text = "Drag over the Zoom captions area. Press Esc to cancel."
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph
        ]
        let rect = NSRect(x: 40, y: bounds.midY + 28, width: bounds.width - 80, height: 36)
        text.draw(in: rect, withAttributes: attributes)
    }
}

final class CompositeCaptionReader: CaptionReader {
    private let accessibilityReader: AccessibilityCaptionReader?
    private let ocrReader: OCRCaptionReader?
    private let forceOCR: Bool

    init(accessibilityReader: AccessibilityCaptionReader?, ocrReader: OCRCaptionReader?, forceOCR: Bool) {
        self.accessibilityReader = accessibilityReader
        self.ocrReader = ocrReader
        self.forceOCR = forceOCR
    }

    func readText() -> String? {
        if !forceOCR, let text = accessibilityReader?.readText(), !text.isEmpty {
            return text
        }

        if let text = ocrReader?.readText(), !text.isEmpty {
            return text
        }

        return nil
    }
}

struct MockTranslator: Translator {
    let targetLanguage: String

    func translate(_ text: String) async throws -> String {
        "[\(targetLanguage)] \(text)"
    }
}

struct ResponsesAPIRequest: Encodable {
    let model: String
    let instructions: String
    let input: String
}

struct ResponsesAPIResponse: Decodable {
    struct OutputItem: Decodable {
        let content: [ContentItem]?
    }

    struct ContentItem: Decodable {
        let text: String?
    }

    let outputText: String?
    let output: [OutputItem]?

    enum CodingKeys: String, CodingKey {
        case outputText = "output_text"
        case output
    }

    func translationText() -> String? {
        if let outputText = outputText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !outputText.isEmpty {
            return outputText
        }

        let joined = output?
            .flatMap { $0.content ?? [] }
            .compactMap { $0.text }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return joined?.isEmpty == false ? joined : nil
    }
}

enum OCIGenAIAPIKeyMode: String {
    case responses
    case chat
}

struct OCIGenAIAPIKeyConfig {
    let apiKey: String
    let model: String
    let endpoint: URL
    let mode: OCIGenAIAPIKeyMode

    static func load(environment: [String: String]) throws -> OCIGenAIAPIKeyConfig {
        guard let apiKey = environment["OCI_GENAI_API_KEY"] ?? environment["GENAI_API_KEY"], !apiKey.isEmpty else {
            throw AppError.missingEnvironment("OCI_GENAI_API_KEY")
        }

        let modeValue = (environment["OCI_GENAI_API_MODE"] ?? "responses").lowercased()
        guard let mode = OCIGenAIAPIKeyMode(rawValue: modeValue) else {
            throw AppError.invalidOCIConfig("OCI_GENAI_API_MODE must be responses or chat.")
        }

        let model = environment["GPT_MODEL"] ?? environment["OCI_MODEL_ID"] ?? environment["OCI_GENAI_MODEL_ID"] ?? "openai.gpt-5.4-nano"
        let endpointValue = try endpointValue(
            environment: environment,
            mode: mode
        )

        guard let endpoint = URL(string: endpointValue) else {
            throw AppError.invalidURL(endpointValue)
        }

        return OCIGenAIAPIKeyConfig(
            apiKey: apiKey,
            model: model,
            endpoint: endpoint,
            mode: mode
        )
    }

    private static func endpointValue(
        environment: [String: String],
        mode: OCIGenAIAPIKeyMode
    ) throws -> String {
        if let explicitURL = environment["OCI_GENAI_API_URL"], !explicitURL.isEmpty {
            return explicitURL
        }

        let base: String
        if let explicitBase = environment["OCI_GENAI_API_BASE_URL"], !explicitBase.isEmpty {
            base = explicitBase
        } else {
            let region = environment["OCI_REGION"]
            guard let region, !region.isEmpty else {
                throw AppError.invalidOCIConfig("Missing OCI_REGION for OCI_GENAI_API_KEY endpoint.")
            }

            base = "https://inference.generativeai.\(region).oci.oraclecloud.com"
        }

        return endpoint(from: base, mode: mode)
    }

    private static func endpoint(from baseValue: String, mode: OCIGenAIAPIKeyMode) -> String {
        var base = baseValue
        while base.hasSuffix("/") {
            base.removeLast()
        }

        if base.hasSuffix("/chat/completions") || base.hasSuffix("/responses") {
            return base
        }

        if base.hasSuffix("/20231130") {
            base += "/actions/v1"
        } else if !base.hasSuffix("/20231130/actions/v1") {
            base += "/20231130/actions/v1"
        }

        switch mode {
        case .responses:
            return base + "/responses"
        case .chat:
            return base + "/chat/completions"
        }
    }
}

struct OCIGenAIAPIKeyTranslator: Translator {
    let config: OCIGenAIAPIKeyConfig
    let sourceLanguage: String?
    let targetLanguage: String

    func translate(_ text: String) async throws -> String {
        switch config.mode {
        case .responses:
            return try await translateWithResponsesAPI(text)
        case .chat:
            return try await translateWithChatCompletionsAPI(text)
        }
    }

    private func translateWithResponsesAPI(_ text: String) async throws -> String {
        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        let body = ResponsesAPIRequest(
            model: config.model,
            instructions: instructions,
            input: text
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)

        let decoded = try JSONDecoder().decode(ResponsesAPIResponse.self, from: data)
        guard let translated = decoded.translationText(), !translated.isEmpty else {
            throw AppError.emptyTranslation
        }

        return translated
    }

    private func translateWithChatCompletionsAPI(_ text: String) async throws -> String {
        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        let body = ChatCompletionsRequest(
            model: config.model,
            messages: [
                ChatMessage(role: "system", content: instructions),
                ChatMessage(role: "user", content: text)
            ],
            temperature: 0.0,
            maxTokens: 192
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)

        let decoded = try JSONDecoder().decode(ChatCompletionsResponse.self, from: data)
        guard let translated = decoded.translationText(), !translated.isEmpty else {
            throw AppError.emptyTranslation
        }

        return translated
    }

    private var instructions: String {
        let source = sourceLanguage.map { " from \($0)" } ?? ""
        return """
        You are a real-time meeting caption translator.
        Translate the user's caption\(source) to \(targetLanguage).
        Return only the translation. Preserve names, numbers, product terms, and acronyms.
        If the text is already in \(targetLanguage), return it unchanged.
        """
    }
}

struct ChatCompletionsRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
    let maxTokens: Int

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
    }
}

struct ChatMessage: Encodable {
    let role: String
    let content: String
}

struct ChatCompletionsResponse: Decodable {
    struct Choice: Decodable {
        let message: Message?
        let text: String?
    }

    struct Message: Decodable {
        let content: ChatContent?
    }

    enum ChatContent: Decodable {
        case text(String)
        case parts([ContentPart])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                self = .text(text)
                return
            }

            self = .parts(try container.decode([ContentPart].self))
        }

        var text: String? {
            switch self {
            case .text(let text):
                return text
            case .parts(let parts):
                let joined = parts
                    .compactMap(\.text)
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return joined.isEmpty ? nil : joined
            }
        }
    }

    struct ContentPart: Decodable {
        let text: String?
    }

    let choices: [Choice]?

    func translationText() -> String? {
        choices?
            .compactMap { choice in
                choice.message?.content?.text ?? choice.text
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }
}

struct DeepLTranslator: Translator {
    let apiKey: String
    let endpoint: URL
    let sourceLanguage: String?
    let targetLanguage: String

    func translate(_ text: String) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")

        var form = [
            "auth_key": apiKey,
            "text": text,
            "target_lang": targetLanguage.uppercased()
        ]

        if let sourceLanguage, !sourceLanguage.isEmpty {
            form["source_lang"] = sourceLanguage.uppercased()
        }

        request.httpBody = form.formEncodedBody()

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)

        let decoded = try JSONDecoder().decode(DeepLResponse.self, from: data)
        guard let translated = decoded.translations.first?.text, !translated.isEmpty else {
            throw AppError.emptyTranslation
        }

        return translated
    }
}

struct DeepLResponse: Decodable {
    struct Translation: Decodable {
        let text: String
    }

    let translations: [Translation]
}

private final class DraggableOverlayView: NSView {
    var onMoved: ((NSPoint) -> Void)?
    private var dragStartMouseLocation: NSPoint?
    private var dragStartFrameOrigin: NSPoint?
    private var didPushCursor = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        self
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else {
            return
        }

        dragStartMouseLocation = NSEvent.mouseLocation
        dragStartFrameOrigin = window.frame.origin
        NSCursor.closedHand.push()
        didPushCursor = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let dragStartMouseLocation, let dragStartFrameOrigin else {
            return
        }

        let currentMouseLocation = NSEvent.mouseLocation
        let frame = window.frame
        let proposedOrigin = NSPoint(
            x: dragStartFrameOrigin.x + currentMouseLocation.x - dragStartMouseLocation.x,
            y: dragStartFrameOrigin.y + currentMouseLocation.y - dragStartMouseLocation.y
        )

        window.setFrameOrigin(Self.constrainedOrigin(proposedOrigin, for: frame))
    }

    override func mouseUp(with event: NSEvent) {
        finishDrag()
    }

    override func mouseExited(with event: NSEvent) {
        if event.type == .leftMouseUp {
            finishDrag()
        }
    }

    private func finishDrag() {
        if didPushCursor {
            NSCursor.pop()
            didPushCursor = false
        }

        if let origin = window?.frame.origin {
            onMoved?(origin)
        }

        dragStartMouseLocation = nil
        dragStartFrameOrigin = nil
    }

    private static func constrainedOrigin(_ origin: NSPoint, for frame: NSRect) -> NSPoint {
        let visibleFrame = NSScreen.screens
            .map(\.visibleFrame)
            .reduce(NSRect.null) { partial, frame in
                partial.isNull ? frame : partial.union(frame)
            }

        guard !visibleFrame.isNull else {
            return origin
        }

        let visibleMargin: CGFloat = 80
        let minX = visibleFrame.minX - frame.width + visibleMargin
        let maxX = visibleFrame.maxX - visibleMargin
        let minY = visibleFrame.minY - frame.height + visibleMargin
        let maxY = visibleFrame.maxY - visibleMargin

        guard minX <= maxX, minY <= maxY else {
            return origin
        }

        return NSPoint(
            x: min(max(origin.x, minX), maxX),
            y: min(max(origin.y, minY), maxY)
        )
    }
}

final class OverlayWindowController {
    private let panel: NSPanel
    private let label: NSTextField
    private static let savedPositionURL = URL(fileURLWithPath: "/tmp/zoomcc-translate-genai-overlay-position.txt")

    init(config: AppConfig) {
        let frame = Self.makeFrame(config: config)
        panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = !config.overlayDraggable
        panel.isOpaque = false

        let container = DraggableOverlayView(frame: NSRect(origin: .zero, size: frame.size))
        container.onMoved = { origin in
            Self.savePosition(origin)
        }
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.76).cgColor
        container.layer?.cornerRadius = 8

        label = NSTextField(labelWithString: "")
        label.frame = container.bounds.insetBy(dx: 18, dy: 14)
        label.autoresizingMask = [.width, .height]
        label.alignment = .center
        label.font = .systemFont(ofSize: config.overlayFontSize, weight: .semibold)
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 4
        label.textColor = .white
        label.cell?.usesSingleLineMode = false
        label.cell?.wraps = true

        container.addSubview(label)
        panel.contentView = container
    }

    func show() {
        panel.orderFrontRegardless()
    }

    func update(text: String) {
        label.stringValue = text
        panel.orderFrontRegardless()
    }

    private static func makeFrame(config: AppConfig) -> NSRect {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = min(config.overlayWidth, max(320, screen.width - 40))
        let height = min(config.overlayHeight, max(90, screen.height - 40))
        let savedPosition = config.overlayX == nil && config.overlayY == nil ? loadSavedPosition() : nil
        let x = config.overlayX ?? savedPosition?.x ?? (screen.midX - width / 2)
        let y = config.overlayY ?? savedPosition?.y ?? (screen.minY + 80)

        return NSRect(x: x, y: y, width: width, height: height)
    }

    private static func loadSavedPosition() -> NSPoint? {
        guard let text = try? String(contentsOf: savedPositionURL, encoding: .utf8) else {
            return nil
        }

        let values = Dictionary(uniqueKeysWithValues: text
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> (String, String)? in
                guard let equals = line.firstIndex(of: "=") else {
                    return nil
                }

                let key = line[..<equals].trimmingCharacters(in: .whitespacesAndNewlines)
                let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespacesAndNewlines)
                return (String(key), String(value))
            })

        guard let xValue = values["x"],
              let yValue = values["y"],
              let x = Double(xValue),
              let y = Double(yValue) else {
            return nil
        }

        return NSPoint(x: x, y: y)
    }

    private static func savePosition(_ origin: NSPoint) {
        let text = [
            "timestamp=\(ISO8601DateFormatter().string(from: Date()))",
            "x=\(String(format: "%.0f", origin.x))",
            "y=\(String(format: "%.0f", origin.y))"
        ].joined(separator: "\n") + "\n"

        try? text.write(to: savedPositionURL, atomically: true, encoding: .utf8)
    }
}

final class AppController: NSObject, NSApplicationDelegate {
    private let config: AppConfig
    private let reader: CaptionReader
    private let translator: Translator
    private let stabilizer: CaptionStabilizer
    private let overlay: OverlayWindowController
    private var timer: Timer?
    private var isTranslating = false
    private var queuedText: String?
    private var translationCache: [String: String] = [:]
    private var lastDebugNoTextAt = Date.distantPast
    private var lastDebugRawText: String?

    init(config: AppConfig, reader: CaptionReader, translator: Translator) {
        self.config = config
        self.reader = reader
        self.translator = translator
        self.stabilizer = CaptionStabilizer(stableAfter: config.stableAfter)
        self.overlay = OverlayWindowController(config: config)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlay.show()
        overlay.update(text: "Waiting for captions...")

        timer = Timer.scheduledTimer(withTimeInterval: config.pollInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        guard let raw = reader.readText() else {
            debugEveryFewSeconds("No caption text read yet. Check Accessibility permission, remove --window-title, or use --ocr-region.")
            return
        }

        if config.debug, raw != lastDebugRawText {
            lastDebugRawText = raw
            fputs("[debug] raw caption candidate: \(raw)\n", stderr)
        }

        guard let text = stabilizer.update(raw) else {
            return
        }

        if config.debug {
            fputs("[debug] stable caption: \(text)\n", stderr)
        }

        if let cached = translationCache[text] {
            overlay.update(text: cached)
            return
        }

        guard !isTranslating else {
            queuedText = text
            if config.debug {
                fputs("[debug] queued latest caption while translating\n", stderr)
            }
            return
        }

        translate(text)
    }

    private func translate(_ text: String) {
        isTranslating = true
        Task {
            do {
                let translated = try await translator.translate(text)
                await MainActor.run {
                    self.translationCache[text] = translated
                    self.overlay.update(text: translated)
                    self.finishTranslation(completedText: text)
                }
            } catch {
                await MainActor.run {
                    self.overlay.update(text: "Translation error: \(error)")
                    self.finishTranslation(completedText: text)
                }
            }
        }
    }

    private func finishTranslation(completedText: String) {
        isTranslating = false

        guard let next = queuedText, next != completedText else {
            queuedText = nil
            return
        }

        queuedText = nil
        if let cached = translationCache[next] {
            overlay.update(text: cached)
            return
        }

        if config.debug {
            fputs("[debug] translating queued latest caption\n", stderr)
        }
        translate(next)
    }

    private func debugEveryFewSeconds(_ message: String) {
        guard config.debug else {
            return
        }

        let now = Date()
        guard now.timeIntervalSince(lastDebugNoTextAt) >= 3 else {
            return
        }

        lastDebugNoTextAt = now
        fputs("[debug] \(message)\n", stderr)
    }
}

private func makeReader(config: AppConfig) -> CaptionReader {
    let accessibilityReader = config.forceOCR ? nil : AccessibilityCaptionReader(
        appName: config.appName,
        windowTitle: config.windowTitle
    )
    let ocrReader = config.ocrRegion.map {
        OCRCaptionReader(
            region: $0,
            displayIndex: config.ocrDisplay,
            sourceLanguage: config.sourceLanguage,
            debug: config.debug,
            lineLimit: config.ocrLineLimit
        )
    }

    return CompositeCaptionReader(
        accessibilityReader: accessibilityReader,
        ocrReader: ocrReader,
        forceOCR: config.forceOCR
    )
}

private func makeTranslator(config: AppConfig) throws -> Translator {
    let environment = ProcessInfo.processInfo.environment

    switch config.provider {
    case .mock:
        return MockTranslator(targetLanguage: config.targetLanguage)
    case .oci:
        return OCIGenAIAPIKeyTranslator(
            config: try OCIGenAIAPIKeyConfig.load(environment: environment),
            sourceLanguage: config.sourceLanguage,
            targetLanguage: config.targetLanguage
        )
    case .deepl:
        guard let apiKey = environment["DEEPL_API_KEY"], !apiKey.isEmpty else {
            throw AppError.missingEnvironment("DEEPL_API_KEY")
        }

        let endpointValue = environment["DEEPL_API_URL"] ?? "https://api-free.deepl.com/v2/translate"
        guard let endpoint = URL(string: endpointValue) else {
            throw AppError.invalidURL(endpointValue)
        }

        return DeepLTranslator(
            apiKey: apiKey,
            endpoint: endpoint,
            sourceLanguage: config.sourceLanguage,
            targetLanguage: config.targetLanguage
        )
    }
}

private func validate(response: URLResponse, data: Data) throws {
    guard let http = response as? HTTPURLResponse else {
        return
    }

    guard (200..<300).contains(http.statusCode) else {
        let body = String(data: data, encoding: .utf8) ?? ""
        throw AppError.httpStatus(http.statusCode, body)
    }
}

private extension Dictionary where Key == String, Value == String {
    func formEncodedBody() -> Data {
        map { key, value in
            "\(key.formEncoded)=\(value.formEncoded)"
        }
        .joined(separator: "&")
        .data(using: .utf8) ?? Data()
    }
}

private extension String {
    var formEncoded: String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":#[]@!$&'()*+,;=")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}

private func saveOCRSelectionState(config: AppConfig) {
    guard config.forceOCR, let region = config.ocrRegion else {
        return
    }

    var lines = [
        "timestamp=\(ISO8601DateFormatter().string(from: Date()))",
        "region=\(OCRDisplayResolver.formatRect(region))"
    ]

    if let display = config.ocrDisplay {
        lines.append("display=\(display)")
    }

    if let anchor = config.ocrAnchor {
        lines.append("anchor=\(anchor.encoded)")
    }

    let text = lines.joined(separator: "\n") + "\n"
    try? text.write(to: URL(fileURLWithPath: "/tmp/zoomcc-translate-genai-ocr-selection.txt"), atomically: true, encoding: .utf8)
}

private var retainedDelegate: AppController?

do {
    var config = try AppConfig.parse(CommandLine.arguments)

    if config.showHelp {
        print(AppConfig.help)
        exit(0)
    }

    if config.listWindows {
        let trusted = AccessibilityCaptionReader.requestPermission(prompt: true)
        if !trusted {
            fputs("Accessibility permission is not granted yet. Grant it in System Settings and rerun this command.\n", stderr)
        }

        let summaries = AccessibilityCaptionReader.windowSummaries(appName: config.appName)
        if summaries.isEmpty {
            print("No running app windows matched app name: \(config.appName)")
        } else {
            print(summaries.joined(separator: "\n"))
        }
        exit(0)
    }

    if let anchor = config.ocrAnchor {
        guard let target = OCRDisplayResolver.resolve(anchor: anchor, debug: config.debug) else {
            throw AppError.invalidOption("--ocr-anchor \(anchor.encoded)")
        }

        config.ocrRegion = target.region
        config.ocrDisplay = target.displayIndex
        config.forceOCR = true
    }

    if config.selectOCRRegion {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        guard let selection = OCRRegionSelector.select(debug: config.debug) else {
            throw AppError.cancelledRegionSelection
        }

        config.ocrRegion = selection.region
        config.ocrDisplay = selection.displayIndex
        config.ocrAnchor = selection.anchor
        config.forceOCR = true
        let regionText = "\(Int(selection.region.origin.x)),\(Int(selection.region.origin.y)),\(Int(selection.region.width)),\(Int(selection.region.height))"
        if let displayIndex = selection.displayIndex {
            fputs("Selected OCR display: \(displayIndex)\n", stderr)
        }
        fputs("Selected OCR region: \(regionText)\n", stderr)
        if let anchor = selection.anchor {
            fputs("Selected OCR anchor: \(anchor.encoded)\n", stderr)
        }
    }

    if !config.forceOCR {
        let trusted = AccessibilityCaptionReader.requestPermission(prompt: true)
        if config.debug, !trusted {
            fputs("[debug] Accessibility permission is not granted yet. Grant it in System Settings, then restart the app.\n", stderr)
        }
    }

    saveOCRSelectionState(config: config)

    let translator = try makeTranslator(config: config)
    let reader = makeReader(config: config)
    let app = NSApplication.shared

    app.setActivationPolicy(.accessory)
    retainedDelegate = AppController(config: config, reader: reader, translator: translator)
    app.delegate = retainedDelegate
    app.run()
} catch {
    fputs("Error: \(error)\n\n\(AppConfig.help)\n", stderr)
    exit(2)
}
