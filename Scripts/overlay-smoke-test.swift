import AppKit

@MainActor
func runOverlaySmokeTests() {
    _ = NSApplication.shared
    let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let previous = "파트너는 크레딧으로 인프라 비용을 충당할 수 있습니다."
    let current = "다만 사용하지 않은 크레딧은 다음 기간으로 이월되지 않습니다."
    let cases: [(String, NSSize, String, String)] = [
        ("default", NSSize(width: 980, height: 240), previous, current),
        ("compact", NSSize(width: 440, height: 180), previous, current),
        ("minimum", NSSize(width: 320, height: 180), previous, current),
        ("long", NSSize(width: 980, height: 240), String(repeating: previous + " ", count: 4), String(repeating: current + " ", count: 4))
    ]
    for (name, size, previousText, currentText) in cases {
        let view = DraggableOverlayView(frame: NSRect(origin: .zero, size: size), fontSize: 30)
        view.update(text: currentText, previousText: previousText)
        let labels = view.subviews.compactMap { $0 as? NSTextField }
        precondition(labels.count == 2)
        precondition(labels[0].stringValue == previousText && labels[1].stringValue == currentText)
        precondition(labels[0].frame.minY >= labels[1].frame.maxY + 12)
        precondition(labels[0].textColor!.alphaComponent < labels[1].textColor!.alphaComponent)
        for label in labels {
            precondition(view.bounds.contains(label.frame), "\(name): label outside overlay")
            let measured = label.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: label.bounds.width, height: .greatestFiniteMagnitude))
            precondition(measured.height <= label.bounds.height, "\(name): text does not fit at \(label.font!.pointSize)pt")
            precondition(label.font!.pointSize >= 12)
        }
        precondition(view.hitTest(labels[0].frame.origin) === view, "history must remain draggable")
        precondition(view.hitTest(labels[1].frame.origin) === view, "current caption must remain draggable")
        let previousFrame = labels[0].frame
        let currentFrame = labels[1].frame
        let image = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: image)
        try! image.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("overlay-\(name).png"))

        view.update(text: "Translation error: test")
        precondition(labels[0].stringValue == previousText, "status updates must not erase history")
        precondition(labels[0].frame == previousFrame && labels[1].frame == currentFrame, "stream updates must not move caption regions")
        view.update(text: "Next.", previousText: "")
        precondition(labels[0].stringValue.isEmpty, "explicit empty history must clear the previous caption")
    }
    print("overlay layout tests passed (\(cases.count) sizes/content cases)")
}
