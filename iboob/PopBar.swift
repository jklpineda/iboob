import AppKit
import SwiftUI

// MARK: - PopBarWindow
@MainActor final class PopBarWindow: NSPanel {
    static let barSize = CGSize(width: 481, height: 60)
    static let radialSize = CGSize(width: 256, height: 256)
    
    var onAction: ((PopAction) -> Void)?
    var onDismiss: (() -> Void)?
    private var taskClose: Task<Void, Never>?
    private var taskProx: Task<Void, Never>?
    private var proxMon: AnyObject?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating; isFloatingPanel = true; backgroundColor = .clear; isOpaque = false; hasShadow = true
        hidesOnDeactivate = false; isMovableByWindowBackground = false; animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]; acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func present(text: String, rect: CGRect) {
        cancelTimers()
        let isRadial = UserDefaults.standard.bool(forKey: "isRadialMode")
        let sz = isRadial ? Self.radialSize : Self.barSize
        let origin = computeOrigin(rect, sz)
        setFrame(CGRect(origin: origin, size: sz), display: true)
        
        let host = contentView as? NSHostingView<AnyView> ?? { let h = NSHostingView<AnyView>(rootView: AnyView(EmptyView())); h.wantsLayer = true; contentView = h; return h }()
        host.frame = CGRect(origin: .zero, size: sz)
        
        host.rootView = AnyView(Group {
            if isRadial { RadialBarView(actions: PopAction.all, text: text) { [weak self] in self?.onAction?($0) } }
            else { BarView(actions: PopAction.all) { [weak self] in self?.onAction?($0) } }
        })

        if !isVisible { alphaValue = 0; orderFrontRegardless(); NSAnimationContext.runAnimationGroup { $0.duration = 0.06; animator().alphaValue = 1 } }
        else { orderFrontRegardless() }
        
        DispatchQueue.main.async { self.contentView?.needsDisplay = true }
        taskClose = Task { try? await Task.sleep(for: .seconds(7)); guard !Task.isCancelled else { return }; onDismiss?() }
        startProximity(origin, sz)
    }

    func dismiss(animated: Bool = true, completion: (() -> Void)? = nil) {
        cancelTimers()
        guard isVisible else { completion?(); return }
        if animated {
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.12; $0.timingFunction = CAMediaTimingFunction(name: .easeIn); animator().alphaValue = 0 }) { [weak self] in
                self?.orderOut(nil); self?.contentView = nil; completion?()
            }
        } else { orderOut(nil); contentView = nil; completion?() }
    }

    private func cancelTimers() { taskClose?.cancel(); taskProx?.cancel(); if let m = proxMon { NSEvent.removeMonitor(m); proxMon = nil } }

    private func startProximity(_ orig: CGPoint, _ sz: CGSize) {
        let env = CGRect(x: orig.x - 36, y: orig.y - 36, width: sz.width + 72, height: sz.height + 72)
        var inside = true
        proxMon = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            if env.contains(NSEvent.mouseLocation) { inside = true; self?.taskProx?.cancel() }
            else if inside {
                inside = false; self?.taskProx?.cancel()
                self?.taskProx = Task { try? await Task.sleep(for: .milliseconds(250)); if !Task.isCancelled, !env.contains(NSEvent.mouseLocation) { self?.onDismiss?() } }
            }
        } as AnyObject
    }

    private func computeOrigin(_ r: CGRect, _ sz: CGSize) -> CGPoint {
        let v = NSScreen.screens.first?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let x = (r.width > 0 ? r.midX : r.origin.x) - sz.width / 2
        var y = (r.height > 0 ? r.maxY : r.origin.y) + 12
        if y + sz.height > v.maxY - 4 { y = (r.height > 0 ? r.minY : r.origin.y) - sz.height - 12 }
        return CGPoint(x: max(v.minX + 8, min(x.rounded(), v.maxX - sz.width - 8)), y: max(v.minY + 8, min(y.rounded(), v.maxY - sz.height - 4)))
    }
}

// MARK: - SwiftUI Shapes & Modifiers
struct IntelligenceHalo<S: Shape>: ViewModifier {
    let s: S
    @State private var phase: CGFloat = 0
    
    func body(content: Content) -> some View {
        content.background(s.stroke(LinearGradient(colors: [.purple, .pink, .blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2.5).hueRotation(.degrees(phase)).blur(radius: 6).opacity(0.85).mask(s))
            .overlay(s.stroke(LinearGradient(colors: [.white.opacity(0.6), .purple.opacity(0.4), .blue.opacity(0.4), .white.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1).hueRotation(.degrees(phase)))
            .onAppear { withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) { phase = 360 } }
    }
}

struct Sector: Shape {
    let s: CGFloat, e: CGFloat, inner: CGFloat, outer: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var p = Path(); let c = CGPoint(x: rect.midX, y: rect.midY)
        p.addArc(center: c, radius: outer, startAngle: .radians(Double(s)), endAngle: .radians(Double(e)), clockwise: false)
        p.addArc(center: c, radius: inner, startAngle: .radians(Double(e)), endAngle: .radians(Double(s)), clockwise: true)
        p.closeSubpath(); return p
    }
}

struct Wheel: Shape {
    let n: Int, outer: CGFloat, inner: CGFloat, gap: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var p = Path(); let a = (2 * .pi - gap * CGFloat(n)) / CGFloat(n)
        for i in 0..<n { let s = .pi / 2 + CGFloat(i) * (a + gap); p.addPath(Sector(s: s, e: s + a, inner: inner, outer: outer).path(in: rect)) }
        let cr = inner - 6; p.addEllipse(in: CGRect(x: rect.midX - cr, y: rect.midY - cr, width: cr * 2, height: cr * 2)); return p
    }
}

// MARK: - RadialBarView (Hit-Testing Matemático Exacto)
struct RadialBarView: View {
    let actions: [PopAction]
    let text: String
    let onAction: (PopAction) -> Void
    
    @State private var hover: Int? = nil
    @State private var press: Int? = nil
    @State private var appeared = false
    
    private let R: CGFloat = 128, r: CGFloat = 50, gap: CGFloat = 0.04
    private var n: CGFloat { CGFloat(actions.count) }
    private var a: CGFloat { (2 * .pi - gap * n) / n }

    private func indexFor(_ p: CGPoint) -> Int? {
        let dx = p.x - R, dy = p.y - R, d = sqrt(dx*dx + dy*dy)
        guard d >= r && d <= R else { return nil }
        
        var ang = atan2(dy, dx) - .pi / 2
        if ang < 0 { ang += 2 * .pi }
        
        let step = 2 * .pi / n
        let i = Int(ang / step)
        
        return (ang - CGFloat(i) * step) <= a ? i : nil
    }

    var body: some View {
        ZStack {
            VisualFX(material: .hudWindow, blending: .behindWindow)
                .clipShape(Wheel(n: Int(n), outer: R, inner: r, gap: gap))
                .opacity(0.84)
            
            ForEach(0..<actions.count, id: \.self) { i in
                let act = actions[i]
                let s = .pi / 2 + CGFloat(i) * (a + gap), mid = s + a / 2
                let isH = hover == i, isP = press == i, ir = (r + R) / 2
                
                Sector(s: s, e: s + a, inner: r, outer: R)
                   .fill(isH ? act.tint.opacity(isP ? 0.95 : 0.7) : Color.primary.opacity(0.065))
                   .stroke(isH ? act.tint.opacity(0.85) : .primary.opacity(0.11), lineWidth: isH ? 1.6 : 0.8)
                   .animation(.spring(response: 0.18, dampingFraction: 0.62), value: isH)
                
                Image(systemName: act.symbol).font(.system(size: 22, weight: .semibold)).symbolRenderingMode(.hierarchical)
                   .foregroundStyle(isH ? act.tint : .primary.opacity(0.75)).scaleEffect(isH ? (isP ? 0.9 : 1.12) : 1)
                   .animation(.spring(response: 0.18, dampingFraction: 0.62), value: isH)
                   .position(x: R + ir * cos(mid), y: R + ir * sin(mid))
            }
            
            // Núcleo Central
            Circle().fill(Color.primary.opacity(0.05)).stroke(.primary.opacity(0.1), lineWidth: 0.7).frame(width: (r - 6) * 2)
            Group {
                if let h = hover { Text(actions[h].label).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(actions[h].tint).id("l-\(h)").transition(.scale(scale: 0.75).combined(with: .opacity)) }
                else if !text.isEmpty { Text(text.count > 30 ? String(text.prefix(29)) + "…" : text).font(.system(size: 9.5, weight: .medium, design: .rounded)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineLimit(3) }
            }.frame(width: (r - 6) * 2).animation(.spring(response: 0.22, dampingFraction: 0.7), value: hover)
        }
        .frame(width: R * 2, height: R * 2)
        .contentShape(Circle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let p): hover = indexFor(p)
            case .ended: hover = nil
            }
        }
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { v in
                press = indexFor(v.location)
                hover = indexFor(v.location)
            }
            .onEnded { v in
                if let i = indexFor(v.location), press == i { onAction(actions[i]) }
                press = nil
            }
        )
        .modifier(IntelligenceHalo(s: Wheel(n: Int(n), outer: R, inner: r, gap: gap)))
        .scaleEffect(appeared ? 1 : 0.5).opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(.spring(response: 0.28, dampingFraction: 0.65)) { appeared = true } }
    }
}

// MARK: - Linear BarView
struct BarView: View {
    let actions: [PopAction]
    let onAction: (PopAction) -> Void
    
    @State private var appeared = false
    
    var body: some View {
        ZStack {
            VisualFX(material: .hudWindow, blending: .behindWindow).clipShape(Capsule())
            HStack(spacing: 0) {
                ForEach(Array(actions.enumerated()), id: \.element.id) { i, a in
                    if i > 0 { Rectangle().fill(Color.primary.opacity(0.09)).frame(width: 1, height: 28) }
                    ActionBtn(action: a, onTap: { onAction(a) })
                }
            }.padding(.horizontal, 5)
        }
        .frame(width: PopBarWindow.barSize.width - 10, height: PopBarWindow.barSize.height - 10)
        .clipShape(Capsule()).modifier(IntelligenceHalo(s: Capsule()))
        .scaleEffect(appeared ? 1 : 0.74, anchor: .bottom).opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(.spring(response: 0.10, dampingFraction: 0.8)) { appeared = true } }
    }
}

struct ActionBtn: View {
    let action: PopAction
    let onTap: () -> Void
    
    // Variables estrictamente separadas para evitar errores del compilador
    @State private var hover = false
    @State private var press = false
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2.5) {
                Image(systemName: action.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(hover ? action.tint : .primary)
                Text(action.label)
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .tracking(0.2)
                    .foregroundStyle(hover ? action.tint : .secondary)
            }
            .frame(width: 55, height: 46)
            .background(Capsule().fill(press ? action.tint.opacity(0.22) : hover ? action.tint.opacity(0.12) : .clear))
            .scaleEffect(press ? 0.88 : 1)
            .animation(.spring(response: 0.16, dampingFraction: 0.6), value: press)
            .animation(.easeInOut(duration: 0.1), value: hover)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in press = true }
            .onEnded { _ in press = false }
        )
    }
}

struct VisualFX: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blending: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active
        v.wantsLayer = true
        v.layer?.cornerRadius = 20
        v.layer?.masksToBounds = true
        return v
    }
    
    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blending
    }
}
