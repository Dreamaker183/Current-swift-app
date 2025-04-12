import SwiftUI

struct LoadingView: View {
    @State private var batteryFill: CGFloat = 0
    @State private var pulseOpacity: Double = 0
    @State private var finalGlow: Bool = false  // Triggers the full green effect

    @State private var dot1Scale: CGFloat = 0.8
    @State private var dot2Scale: CGFloat = 0.8
    @State private var dot3Scale: CGFloat = 0.8
    @State private var statusIndex: Int = 0
    @State private var isReady: Bool = false
    @State private var ambientGlowOpacity: Double = 0.5
    @State private var plusScale: CGFloat = 1.0

    // Fade‐in states for text elements.
    @State private var appNameOpacity: Double = 0
    @State private var loadingTextOpacity: Double = 0
    @State private var statusOpacity: Double = 0

    let statusMessages = [
        "Connecting to your smart home devices",
        "Syncing usage data",
        "Loading power management tools",
        "Finalizing setup"
    ]
    
    // Scaling factor to make battery look smaller.
    let scaleFactor: CGFloat = 0.8
    
    var body: some View {
        ZStack {
            // Background.
            Color(hex: "#111111")
                .ignoresSafeArea()
            
            // Ambient glow overlay with two radial gradients.
            ZStack {
                RadialGradient(
                    gradient: Gradient(colors: [Color(hex: "#6366f1").opacity(0.1), .clear]),
                    center: .init(x: 0.2, y: 0.3),
                    startRadius: 0,
                    endRadius: 200
                )
                RadialGradient(
                    gradient: Gradient(colors: [Color(hex: "#22d3ee").opacity(0.1), .clear]),
                    center: .init(x: 0.8, y: 0.7),
                    startRadius: 0,
                    endRadius: 200
                )
            }
            .ignoresSafeArea()
            // Ambient glow animation sped up to 4 seconds instead of 8.
            .opacity(ambientGlowOpacity)
            
            VStack(spacing: 30) {
                // Battery container.
                ZStack {
                    // Battery outline.
                    RoundedRectangle(cornerRadius: 15 * scaleFactor)
                        .frame(width: 120 * scaleFactor, height: 220 * scaleFactor)
                        .foregroundColor(.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 15 * scaleFactor)
                                .stroke(finalGlow ? Color.green.opacity(0.8) : Color.white.opacity(0.2), lineWidth: 3)
                        )
                    // Battery cap.
                    RoundedRectangle(cornerRadius: 5 * scaleFactor)
                        .frame(width: 40 * scaleFactor, height: 10 * scaleFactor)
                        .foregroundColor(Color.white.opacity(0.2))
                        .offset(y: -115 * scaleFactor)
                    // Battery fill.
                    RoundedRectangle(cornerRadius: 10 * scaleFactor)
                        .frame(width: 114 * scaleFactor, height: 214 * batteryFill * scaleFactor)
                        .foregroundStyle(
                            finalGlow ?
                            LinearGradient(gradient: Gradient(colors: [Color.green, Color.green]),
                                           startPoint: .bottom, endPoint: .top) :
                            LinearGradient(gradient: Gradient(colors: [Color(hex: "#22c55e"), Color(hex: "#6366f1")]),
                                           startPoint: .bottom, endPoint: .top)
                        )
                        .offset(y: (214 * (1 - batteryFill) * scaleFactor) / 2)
                    // Battery pulse overlay (glow).
                    RoundedRectangle(cornerRadius: 15 * scaleFactor)
                        .frame(width: 120 * scaleFactor, height: 220 * scaleFactor)
                        .foregroundStyle(
                            RadialGradient(
                                gradient: Gradient(colors: finalGlow ?
                                    [Color.green.opacity(0.8), Color.clear] :
                                    [Color.blue.opacity(0.3), Color.clear]),
                                center: .center,
                                startRadius: 0,
                                endRadius: 100 * scaleFactor
                            )
                        )
                        .opacity(pulseOpacity)
                }
                // Add a shadow when finalGlow is active.
                .shadow(color: finalGlow ? Color.green.opacity(0.9) : Color.clear, radius: finalGlow ? 10 : 0)
                .frame(width: 160 * scaleFactor, height: 280 * scaleFactor)
                
                // App name ("Current+") using the custom "Nano" font.
                HStack(spacing: 0) {
                    Text("Current")
                        .foregroundStyle(
                            LinearGradient(
                                gradient: Gradient(colors: [.white, Color(hex: "#94a3b8")]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    Text("+")
                        .foregroundColor(Color(hex: "#22d3ee"))
                        .scaleEffect(plusScale)
                }
                .font(Font.custom("Nano", size: 36))
                .opacity(appNameOpacity)
                
                // Loading text with animated dots.
                HStack(spacing: 5) {
                    if !isReady {
                        HStack(spacing: 3) {
                            Circle().frame(width: 6, height: 6).scaleEffect(dot1Scale)
                            Circle().frame(width: 6, height: 6).scaleEffect(dot2Scale)
                            Circle().frame(width: 6, height: 6).scaleEffect(dot3Scale)
                        }
                    }
                }
                .foregroundColor(.white)
                .opacity(loadingTextOpacity)
                
                // Status message.
                Text(statusMessages[statusIndex])
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "#94a3b8"))
                    .offset(y: 100 * scaleFactor)
                    .opacity(statusOpacity)
            }
        }
        .onAppear {
            // Ambient glow animation sped up to 4 seconds.
            withAnimation(Animation.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                ambientGlowOpacity = 1
            }
            // Fade in text elements faster.
            withAnimation(.easeInOut(duration: 0.5)) { appNameOpacity = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                withAnimation(.easeInOut(duration: 0.5)) { loadingTextOpacity = 1 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeInOut(duration: 0.5)) { statusOpacity = 1 }
            }
            
            // Battery fill animation sequence (sped up).
            withAnimation(.easeInOut(duration: 1.0)) { batteryFill = 0.6 }  // 0 -> 0.6 over 1 sec
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation(.easeInOut(duration: 0.5)) { batteryFill = 0.8 }  // to 0.8 by 2 sec
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                withAnimation(.easeInOut(duration: 0.5)) { batteryFill = 0.95 }  // to 0.95 by 3.5 sec
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
                withAnimation(.easeInOut(duration: 0.5)) {
                    batteryFill = 1.0    // Final fill to 1.0 by 4 sec
                    finalGlow = true     // Trigger the full green effect
                }
                // Keep the green effect for 2.5 sec.
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        finalGlow = false
                    }
                }
            }
            
            // Battery pulse (glow) animation.
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                pulseOpacity = 0.6
            }
            
            // Dot pulse animations (sped up).
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) { dot1Scale = 1.2 }
            withAnimation(.easeInOut(duration: 1.0).delay(0.3).repeatForever(autoreverses: true)) { dot2Scale = 1.2 }
            withAnimation(.easeInOut(duration: 1.0).delay(0.6).repeatForever(autoreverses: true)) { dot3Scale = 1.2 }
            
            // Plus sign pulse animation (sped up).
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) { plusScale = 1.1 }
            
            // Cycle through status messages faster.
            Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.5)) {
                    statusIndex = (statusIndex + 1) % statusMessages.count
                }
            }
            
            // Mark completion (ready state) after 7 seconds.
            DispatchQueue.main.asyncAfter(deadline: .now() + 7) {
                isReady = true
            }
        }
    }
}

// Hex Color Extension.
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b)
    }
}
