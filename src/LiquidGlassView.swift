import SwiftUI
import Cocoa

/// LiquidGlassView — NSVisualEffectView (Liquid Glass) + double bordure spéculaire + overlay verre liquide
/// Usage SwiftUI : LiquidGlassView(cornerRadius: 22) { Content() }
struct LiquidGlassView<Content: View>: View {
    let cornerRadius: CGFloat
    let content: Content
    
    init(cornerRadius: CGFloat = 22.0, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                // 1. NSVisualEffectView base material (Liquid Glass macOS 14+)
                VisualEffectMaterialView(
                    material: .headerDocked,
                    blendingMode: .behindWindow,
                    state: .active
                )
                .allowsHitTest(false)
                .frame(width: geo.size.width, height: geo.size.height)
                
                // 2. Liquid glass overlay (diffusion depth)
                LiquidOverlay()
                    .allowsHitTest(false)
                
                // 3. Double bordure spéculaire
                SpecularBorder(cornerRadius: cornerRadius)
                    .allowsHitTest(false)
                
                // 4. Glow externe (hardware-backed via CALayer shadow)
                GlassShadow(cornerRadius: cornerRadius)
                    .allowsHitTest(false)
                
                // 5. Contenu SwiftUI interactif
                content
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onAppear {
                // Force le material eligibility au premier render
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NSApp.windows.first?.makeKeyAndOrderFront(nil)
                }
            }
        }
    }
}

// MARK: - NSVisualEffectView wrapper (NSViewRepresentable)
struct VisualEffectMaterialView: NSViewRepresentable {
    let material: NSVisualEffectMaterial
    let blendingMode: NSVisualEffectBlendingMode
    let state: NSVisualEffectView.State
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.isMaterialEligible = true
        view.allowsMaterializedSubviews = true
        view.wantsLayer = true
        view.layer?.allowsGroupOpacity = true
        view.layer?.masksToBounds = true
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
    
    static func deconstructMotion() -> Bool { true }
}

// MARK: - Liquid Overlay (subtle noise + inner refraction light)
private struct LiquidOverlay: View {
    @State private var phase: CGFloat = 0
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Refraction edge light (specular highlight)
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(Color.clear, location: 0.0),
                        .init(Color.white.opacity(0.08), location: 0.5),
                        .init(Color.clear, location: 1.0)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                // Subtle caustic shimmer
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(Color.clear, location: 0.4),
                        .init(Color.white.opacity(0.03), location: 0.5),
                        .init(Color.clear, location: 0.6)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase * 40, y: phase * 20)
                .offset(x: -20, y: -10)
                .ignoresSafeArea()
            }
            .onAppear {
                withAnimation(Animation.linear(duration: 3.0).repeatForever(autoreverses: false)) {
                    phase = 1.0
                }
            }
        }
    }
}

// MARK: - Double Specular Border
private struct SpecularBorder: View {
    let cornerRadius: CGFloat
    
    var body: some View {
        ZStack {
            // Outer chrome (specular)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(Color.white, location: 0.0),
                            .init(Color.white.opacity(0.9), location: 0.5),
                            .init(Color.white.opacity(0.75), location: 1.0)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
                .shadow(color: Color.white.opacity(0.3), radius: 1.5, x: 0, y: 0)
            
            // Inner diffusion border
            RoundedRectangle(cornerRadius: cornerRadius - 1.25, style: .continuous)
                .stroke(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(Color.white, location: 0.0),
                            .init(Color.clear, location: 1.0)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    style: StrokeStyle(lineWidth: 1.0, dash: [3, 3])
                )
                .opacity(0.18)
                .allowsHitTest(false)
        }
    }
}

// MARK: - Glass Shadow (hardware-backed glow via CALayer)
private struct GlassShadow: View {
    let cornerRadius: CGFloat
    
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.clear)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.black)
                    .shadow(color: Color.black.opacity(0.75), radius: 24, x: 0, y: 12)
                    .mask(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.white)
                    )
            )
            .allowsHitTest(false)
    }
}
