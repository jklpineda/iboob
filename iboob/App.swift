import AppKit
import SwiftUI

@main struct IboobApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene { Settings { EmptyView() } }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private let ax = AXEngine.shared, sel = SelectionEngine.shared
    private let hk = HotkeyEngine.shared, actions = ActionEngine.shared
    
    private var bar = PopBarWindow(), status: NSStatusItem!
    private var outsideMonitor: AnyObject?, consumer: Task<Void, Never>?
    private var cachedText = "", ownerPID: pid_t = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildStatusBar()
        ax.trusted ? axGranted() : showPermissionAlert()
        ax.onGrant = { [weak self] in self?.axGranted() }
        ax.onRevoke = { [weak self] in self?.axRevoked() }
        wireHotkeys()
        
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let isSelfBundle = app?.bundleIdentifier == Bundle.main.bundleIdentifier

            Task { @MainActor [weak self] in
                guard let self, !isSelfBundle, self.bar.isVisible else { return }
                self.dismiss()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        consumer?.cancel(); Task { await sel.stop() }; hk.unregister(); dismiss(animated: false)
    }

    private func axGranted() { updateIcon(true); startConsumer(); ax.startWatchdog() }
    
    private func axRevoked() {
        updateIcon(false); consumer?.cancel(); Task { await sel.stop() }; showPermissionAlert()
    }

    private func startConsumer() {
        consumer?.cancel(); Task { await sel.start() }
        consumer = Task {
            for await s in sel.stream {
                guard !Task.isCancelled else { break }
                if await sel.isIgnored(s.text) { continue }
                cachedText = s.text; ownerPID = s.ownerPID; show(s.text, s.rect)
            }
        }
    }

    private func wireHotkeys() {
        let trigger: () -> Void = { [weak self] in
            guard let self else { return }
            let txt = self.cachedText.isEmpty ? (NSPasteboard.general.string(forType: .string) ?? "") : self.cachedText
            if !txt.isEmpty { self.show(txt, CGRect(origin: NSEvent.mouseLocation, size: .zero)) }
        }
        hk.onMenu = trigger; hk.onToggle = trigger; hk.reregister()
    }

    private func show(_ text: String, _ rect: CGRect) {
        dismiss(animated: false)
        bar.onAction = { [weak self] a in self?.execute(a) }
        bar.onDismiss = { [weak self] in self?.dismiss() }
        bar.present(text: text, rect: rect)
        
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if let self, self.bar.isVisible, !self.bar.frame.contains(NSEvent.mouseLocation) { self.dismiss() }
        } as AnyObject
    }

    private func execute(_ action: PopAction) {
        let t = cachedText, p = ownerPID
        dismiss(animated: false)
        Task { await actions.execute(action, text: t, ownerPID: p) }
        cachedText = ""
    }

    func dismiss(animated: Bool = true) {
        if let m = outsideMonitor { NSEvent.removeMonitor(m); outsideMonitor = nil }
        bar.dismiss(animated: animated) { [weak self] in Task { await self?.sel.dismiss() } }
    }

    private func buildStatusBar() {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateIcon(ax.trusted)
        
        let m = NSMenu()
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self; login.state = LoginItems.enabled ? .on : .off
        
        let radial = NSMenuItem(title: "Radial Mode", action: #selector(toggleRadial), keyEquivalent: "")
        radial.target = self; radial.state = UserDefaults.standard.bool(forKey: "isRadialMode") ? .on : .off
        
        let ocr = NSMenuItem(title: "Capture Text (OCR)", action: #selector(captureOCR), keyEquivalent: ""); ocr.target = self
        let axItem = NSMenuItem(title: "Accessibility Settings…", action: #selector(openAX), keyEquivalent: ","); axItem.target = self

        [(NSMenuItem(title: "iboob", action: nil, keyEquivalent: ""), false),
         (.separator(), true), (login, true), (radial, true), (.separator(), true), (ocr, true),
         (NSMenuItem(title: "Menu: \(hk.menuKey?.label ?? "–")   Toggle: \(hk.toggleKey?.label ?? "–")", action: nil, keyEquivalent: ""), false),
         (.separator(), true), (axItem, true), (.separator(), true),
         (NSMenuItem(title: "Quit iboob", action: #selector(NSApplication.terminate), keyEquivalent: "q"), true)]
        .forEach { item, enabled in item.isEnabled = enabled; m.addItem(item) }
        status.menu = m
    }

    private func updateIcon(_ trusted: Bool) {
        if !trusted {
            status.button?.image = NSImage(systemSymbolName: "exclamationmark.lock.fill", accessibilityDescription: nil)
        } else {
            // Intenta cargar tu icono personalizado "StatusBarIcon" desde Assets
            if let customIcon = NSImage(named: "StatusBarIcon") {
                status.button?.image = customIcon
            } else {
                // Fallback a SFSymbol si no existe el asset
                status.button?.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
            }
        }
        status.button?.image?.isTemplate = true
    }

    @objc private func toggleLogin(_ sender: NSMenuItem) {
        LoginItems.enabled.toggle(); sender.state = LoginItems.enabled ? .on : .off
    }
    
    @objc private func toggleRadial(_ sender: NSMenuItem) {
        let current = UserDefaults.standard.bool(forKey: "isRadialMode")
        UserDefaults.standard.set(!current, forKey: "isRadialMode")
        sender.state = !current ? .on : .off
    }
    
    @objc private func openAX() { ax.request() }
    
    @objc private func captureOCR() {
        Task { guard let text = await OCRCapture.shared.capture(), !text.isEmpty else { return }
            actions.paste(text); HUD.shared.show("Text Copied ✓")
        }
    }

    private func showPermissionAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Accessibility Required"; alert.informativeText = "Enable iboob in System Settings → Privacy & Security → Accessibility."
        alert.addButton(withTitle: "Open Settings"); alert.addButton(withTitle: "Later"); alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn { ax.request() } else { ax.startPolling() }
        
        Task { while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(300)); if AXIsProcessTrusted() { ax.refresh(); break } } }
    }
}
