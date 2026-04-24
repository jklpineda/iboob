import AppKit
import ApplicationServices
import Carbon
import Observation
import ServiceManagement
import SwiftUI

// MARK: - Models
struct Selection: Sendable { let text: String, rect: CGRect, ownerPID: pid_t }

struct PopAction: Identifiable, Sendable {
    let id = UUID()
    let label: String
    let symbol: String
    let tint: Color
    
    enum Kind: Sendable { case search, copy, capture, ai(Character) }
    let kind: Kind

    // Se han actualizado los colores para usar .accentColor donde sea apropiado
    static let all: [PopAction] = [
        .init(label: "Search", symbol: "safari", tint: .accentColor, kind: .search),
        .init(label: "Copy", symbol: "doc.on.doc.fill", tint: .green, kind: .copy),
        .init(label: "Tools", symbol: "sparkles", tint: .purple, kind: .ai("w")),
        .init(label: "Rewrite", symbol: "pencil.and.outline", tint: .orange, kind: .ai("r")),
        .init(label: "Proof", symbol: "text.magnifyingglass", tint: .teal, kind: .ai("p")),
        .init(label: "Summ.", symbol: "doc.text", tint: .pink, kind: .ai("s")),
        .init(label: "Points", symbol: "list.bullet", tint: .indigo, kind: .ai("k")),
        .init(label: "Capture", symbol: "camera.viewfinder", tint: .cyan, kind: .capture)
    ]
}

// MARK: - AX Engine
@Observable @MainActor final class AXEngine {
    static let shared = AXEngine()
    private(set) var trusted = AXIsProcessTrusted()
    
    var onGrant: (() -> Void)?
    var onRevoke: (() -> Void)?
    private var polling: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?

    func request() {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        startPolling()
    }

    func refresh() { let now = AXIsProcessTrusted(); if now != trusted { trusted = now; if now { polling?.cancel(); onGrant?() } } }

    func startPolling() {
        polling?.cancel()
        polling = Task { while !Task.isCancelled { if AXIsProcessTrusted() { await MainActor.run { trusted = true; onGrant?() }; break }; try? await Task.sleep(for: .seconds(1.5)) } }
    }

    func startWatchdog() {
        watchdog?.cancel()
        guard trusted else { return }
        watchdog = Task { while !Task.isCancelled { try? await Task.sleep(for: .seconds(5)); if !AXIsProcessTrusted() { await MainActor.run { trusted = false; onRevoke?() }; break } } }
    }
}

// MARK: - Selection Engine
actor SelectionEngine {
    static let shared = SelectionEngine()
    nonisolated let stream: AsyncStream<Selection>
    private let continuation: AsyncStream<Selection>.Continuation
    
    private var lastText = ""
    private var lastEvID = -1
    private var evID = 0
    private var ignored = false
    private var running = false
    private var pending: Task<Void, Never>?
    private var monitors: [AnyObject] = []
    
    private var mouseDownPos: CGPoint = .zero

    private init() { (stream, continuation) = AsyncStream.makeStream(of: Selection.self, bufferingPolicy: .bufferingNewest(4)) }

    func start() { guard !running else { return }; running = true; Task { await installMonitors() } }
    func stop() { running = false; pending?.cancel(); Task { await removeMonitors() } }

    func bump() { evID &+= 1; ignored = false }
    func dismiss() { ignored = true }
    func consumeSelection() { ignored = true }
    func isIgnored(_ text: String) -> Bool { ignored && text == lastText }

    func schedule() {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
            await attemptRead()
        }
    }

    @discardableResult private func attemptRead() async -> Bool {
        guard AXIsProcessTrusted() else { return false }
        
        let buttonsDown = await MainActor.run { NSEvent.pressedMouseButtons != 0 }
        guard !buttonsDown else { return false }
        
        guard let frontApp = await MainActor.run(body: { NSWorkspace.shared.frontmostApplication }),
              frontApp.bundleIdentifier != Bundle.main.bundleIdentifier else { return false }
        
        let pid = frontApp.processIdentifier
        let app = AXUIElementCreateApplication(pid)
        let focused = axElement(app, kAXFocusedUIElementAttribute) ?? app
        
        var text: String?
        var textRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(focused, kAXSelectedTextAttribute as CFString, &textRef) == .success,
           let val = textRef as? String, !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = val
        }
        
        if text == nil {
            let currentPos = await MainActor.run { NSEvent.mouseLocation }
            let dist = sqrt(pow(currentPos.x - mouseDownPos.x, 2) + pow(currentPos.y - mouseDownPos.y, 2))
            if dist > 4 {
                text = await readByForcingCopy(pid: pid)
            }
        }

        guard let finalText = text?.trimmingCharacters(in: .whitespacesAndNewlines), 
              !finalText.isEmpty, 
              !shouldSuppress(text: finalText) else { return false }

        var rect = await MainActor.run { CGRect(origin: NSEvent.mouseLocation, size: .zero) }
        if let r = selectionRect(for: focused) {
            let d = sqrt(pow(r.midX - rect.minX, 2) + pow(r.midY - rect.minY, 2))
            if r.height <= 250 && d <= 250 { rect = r }
        }

        lastText = finalText; lastEvID = evID; ignored = false
        continuation.yield(Selection(text: finalText, rect: rect, ownerPID: pid))
        return true
    }

    private func shouldSuppress(text: String) -> Bool { text == lastText && (ignored || lastEvID == evID) }

    private func readByForcingCopy(pid: pid_t) async -> String? {
        let pb = NSPasteboard.general
        let oldChangeCount = pb.changeCount
        
        let savedItems = pb.pasteboardItems?.compactMap { item -> NSPasteboardItem? in
            let new = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { new.setData(data, forType: type) } }
            return new
        } ?? []

        let src = CGEventSource(stateID: .combinedSessionState)
        let cDown = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: true)
        let cUp = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: false)
        cDown?.flags = .maskCommand; cUp?.flags = .maskCommand
        
        cDown?.postToPid(pid)
        cUp?.postToPid(pid)

        var resultText: String?
        for _ in 0..<10 {
            try? await Task.sleep(for: .milliseconds(20))
            if pb.changeCount != oldChangeCount {
                resultText = pb.string(forType: .string)
                break
            }
        }

        if pb.changeCount != oldChangeCount {
            pb.clearContents()
            if !savedItems.isEmpty { pb.writeObjects(savedItems) }
        }

        return resultText
    }

    private func selectionRect(for el: AXUIElement) -> CGRect? {
        var ref1: CFTypeRef?, ref2: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, &ref1) == .success,
           AXUIElementCopyParameterizedAttributeValue(el, kAXBoundsForRangeParameterizedAttribute as CFString, ref1!, &ref2) == .success {
            var r = CGRect.zero; if AXValueGetValue(ref2 as! AXValue, .cgRect, &r), !r.isEmpty { return flip(r) }
        }
        if AXUIElementCopyAttributeValue(el, "AXFrame" as CFString, &ref1) == .success, AXValueGetType(ref1 as! AXValue) == .cgRect {
            var r = CGRect.zero; if AXValueGetValue(ref1 as! AXValue, .cgRect, &r), !r.isEmpty { return flip(r) }
        }
        return nil
    }

    private func flip(_ r: CGRect) -> CGRect? {
        guard !r.isEmpty, let s = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: r.midX, y: r.midY)) }) ?? NSScreen.screens.first else { return nil }
        return CGRect(x: r.minX, y: s.frame.maxY - r.maxY, width: r.width, height: r.height)
    }

    private func axElement(_ el: AXUIElement, _ attr: String) -> AXUIElement? { var r: CFTypeRef?; return AXUIElementCopyAttributeValue(el, attr as CFString, &r) == .success && CFGetTypeID(r!) == AXUIElementGetTypeID() ? unsafeBitCast(r!, to: AXUIElement.self) : nil }

    private func installMonitors() async {
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] e in
                let pos = NSEvent.mouseLocation
                Task { await self?.setMouseDownPos(pos); await self?.bump() }
            },
            NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
                Task { await self?.schedule() }
            },
            NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] e in
                let m = e.modifierFlags
                if m.contains(.shift) || m.contains(.command) { Task { await self?.schedule() } }
            }
        ].compactMap { $0 as AnyObject }
    }
    
    private func setMouseDownPos(_ pos: CGPoint) { self.mouseDownPos = pos }
    private func removeMonitors() async { monitors.forEach { NSEvent.removeMonitor($0) }; monitors.removeAll() }
}

// MARK: - Action Engine
@MainActor final class ActionEngine {
    static let shared = ActionEngine()
    private let codes: [Character: (Int, CGKeyCode)] = ["w": (13,13), "r": (15,15), "p": (35,35), "s": (1,1), "k": (40,40)]
    private init() {}

    func execute(_ action: PopAction, text: String, ownerPID pid: pid_t) async {
        switch action.kind {
        case .search: if let q = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed), let u = URL(string: "https://www.google.com/search?q=\(q)") { NSWorkspace.shared.open(u) }
        case .copy: HUD.shared.show(paste(text) ? "Copied ✓" : "Error")
        case .capture: if let t = await OCRCapture.shared.capture(), !t.isEmpty, paste(t) { HUD.shared.show("Captured ✓") }
        case .ai(let k): await sendAIHotkey(key: k, pid: pid)
        }
        await SelectionEngine.shared.consumeSelection()
    }

    @discardableResult func paste(_ text: String) -> Bool { let pb = NSPasteboard.general; pb.clearContents(); return pb.setString(text, forType: .string) }

    private func sendAIHotkey(key: Character, pid: pid_t) async {
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier == pid }) { app.activate(options: .activateAllWindows) }
        try? await Task.sleep(for: .milliseconds(100))
        guard let c = codes[key] else { return }
        let script = "tell application \"System Events\" to key code \(c.0) using {control down, option down, command down}"
        DispatchQueue.global().async { NSAppleScript(source: script)?.executeAndReturnError(nil) }
    }
}

// MARK: - Hotkey Engine
final class HotkeyEngine {
    static let shared = HotkeyEngine()
    
    struct Key: Equatable, Codable {
        var code: UInt32, mods: UInt32
        static let menu = Key(code: 0x02, mods: UInt32(shiftKey | optionKey)), toggle = Key(code: 0x07, mods: UInt32(shiftKey | optionKey))
        
        var label: String {
            let m = mods
            var s = ""
            if m & UInt32(cmdKey) != 0 { s += "⌘" }
            if m & UInt32(shiftKey) != 0 { s += "⇧" }
            if m & UInt32(optionKey) != 0 { s += "⌥" }
            if m & UInt32(controlKey) != 0 { s += "⌃" }
            let keys = ["A","S","D","F","H","G","Z","X","C","V","B","Q","W","E","R","Y","T","1","2","3","4","6","5","=","9","7","-","8","0","]","O","U","[","I","P","\n","L","J","'","K",";","\\",",","/","N","M",".","\t"," ","`","\u{0008}"]
            s += Int(code) < keys.count ? keys[Int(code)] : "Key"
            return s
        }
    }
    
    var menuKey: Key? { didSet { reregister() } }
    var toggleKey: Key? { didSet { reregister() } }
    var onMenu: (() -> Void)?, onToggle: (() -> Void)?
    
    private var menuRef: EventHotKeyRef?, toggleRef: EventHotKeyRef?, handler: EventHandlerRef?

    private init() { reregister() }

    func unregister() {
        if let r = menuRef { UnregisterEventHotKey(r); menuRef = nil }
        if let r = toggleRef { UnregisterEventHotKey(r); toggleRef = nil }
        if let h = handler { RemoveEventHandler(h); handler = nil }
    }

    func reregister() {
        unregister()
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, e, _ in
            var id = EventHotKeyID()
            GetEventParameter(e, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            DispatchQueue.main.async { id.id == 1 ? HotkeyEngine.shared.onMenu?() : HotkeyEngine.shared.onToggle?() }
            return noErr
        }, 1, &spec, nil, &handler)
        
        RegisterEventHotKey(menuKey?.code ?? 0x02, menuKey?.mods ?? UInt32(shiftKey|optionKey), EventHotKeyID(signature: 0x49424F42, id: 1), GetApplicationEventTarget(), 0, &menuRef)
        RegisterEventHotKey(toggleKey?.code ?? 0x07, toggleKey?.mods ?? UInt32(shiftKey|optionKey), EventHotKeyID(signature: 0x49424F42, id: 2), GetApplicationEventTarget(), 0, &toggleRef)
    }
}

// MARK: - Login Items
enum LoginItems {
    static var enabled: Bool {
        get { if #available(macOS 13, *) { return SMAppService.mainApp.status == .enabled } else { return false } }
        set { if #available(macOS 13, *) { try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister() } }
    }
}
