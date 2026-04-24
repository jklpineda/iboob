@preconcurrency import Vision
import AppKit

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - HUD
// ═══════════════════════════════════════════════════════════════════════════════

@MainActor final class HUD {
    static let shared = HUD()
    private var window: NSWindow?, hideTask: Task<Void, Never>?
    private init() {}

    func show(_ message: String, for dur: TimeInterval = 1.1) {
        if let w = window, let l = w.contentView?.subviews.compactMap({ $0 as? NSTextField }).first { l.stringValue = message; reschedule(dur); return }
        
        let w = NSWindow(contentRect: CGRect(x: NSEvent.mouseLocation.x - 110, y: NSEvent.mouseLocation.y - 82, width: 220, height: 44), styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false; w.backgroundColor = .clear; w.level = .statusBar; w.hasShadow = true; w.ignoresMouseEvents = true; w.collectionBehavior = [.transient, .canJoinAllSpaces]

        let fx = NSVisualEffectView(frame: CGRect(x: 0, y: 0, width: 220, height: 44))
        fx.material = .hudWindow; fx.blendingMode = .behindWindow; fx.state = .active; fx.wantsLayer = true; fx.layer?.cornerRadius = 10; fx.layer?.masksToBounds = true

        let l = NSTextField(labelWithString: message)
        l.alignment = .center; l.font = .systemFont(ofSize: 14, weight: .semibold); l.textColor = .labelColor; l.frame = CGRect(x: 12, y: 12, width: 196, height: 20)
        
        fx.addSubview(l); w.contentView = fx; w.alphaValue = 0
        
        // SOLUCIÓN AL ERROR DE KEYWINDOW
        w.orderFrontRegardless()
        
        NSAnimationContext.runAnimationGroup { $0.duration = 0.13; w.animator().alphaValue = 1 }
        window = w; reschedule(dur)
    }

    private func reschedule(_ s: TimeInterval) {
        hideTask?.cancel()
        hideTask = Task { try? await Task.sleep(for: .seconds(s)); if !Task.isCancelled { await MainActor.run { window.map { w in NSAnimationContext.runAnimationGroup({ $0.duration = 0.16; w.animator().alphaValue = 0 }, completionHandler: { w.orderOut(nil) }) }; window = nil } } }
    }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MARK: - OCR Capture
// ═══════════════════════════════════════════════════════════════════════════════

@MainActor final class OCRCapture {
    static let shared = OCRCapture()
    private init() {}

    func capture() async -> String? {
        let t = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".png")
        let p = Process()
        p.launchPath = "/usr/sbin/screencapture"
        p.arguments = ["-i", t.path]
        
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            p.terminationHandler = { _ in c.resume() }
            try? p.run()
        }

        guard let cg = NSImage(contentsOf: t)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            try? FileManager.default.removeItem(at: t)
            return nil
        }
        try? FileManager.default.removeItem(at: t)

        return await withCheckedContinuation { c in
            let req = VNRecognizeTextRequest { req, _ in
                let text = (req.results as? [VNRecognizedTextObservation])?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                c.resume(returning: text)
            }
            req.recognitionLevel = .accurate
            req.usesLanguageCorrection = true
            req.recognitionLanguages = ["es", "en"]
            try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([req])
        }
    }
}
