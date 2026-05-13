import SwiftUI

struct AppLockView: View {
    let useBiometrics: Bool
    let pinHash: String
    let unlock: () -> Void

    @State private var pin = ""
    @State private var message: String?
    @State private var shakeOffset: CGFloat = 0
    @State private var showContent = false
    @State private var iconBreathing = false
    @State private var glowPulsing = false
    @State private var pinFocused = false
    @FocusState private var isPinFieldFocused: Bool

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Welcome back"
        }
    }

    var body: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.03, blue: 0.12),
                    Color(red: 0.10, green: 0.06, blue: 0.22),
                    Color(red: 0.05, green: 0.04, blue: 0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Ambient particles
            FloatingParticlesView()
                .ignoresSafeArea()
                .opacity(0.6)

            // Main content
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 80)

                // Lock icon with glow
                ZStack {
                    // Outer glow
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.ncPurple.opacity(0.25), Color.clear],
                                center: .center,
                                startRadius: 30,
                                endRadius: 100
                            )
                        )
                        .frame(width: 200, height: 200)
                        .scaleEffect(glowPulsing ? 1.1 : 0.9)

                    // Glass circle
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 96, height: 96)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.3),
                                            Color.ncPurple.opacity(0.4),
                                            Color.white.opacity(0.1)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.5
                                )
                        )
                        .shadow(color: Color.ncPurple.opacity(0.3), radius: 20, y: 4)

                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.white, Color.ncPurple.opacity(0.8)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .scaleEffect(iconBreathing ? 1.04 : 1.0)
                }
                .padding(.bottom, 36)

                // Greeting
                Text(greeting)
                    .font(.system(size: 14, weight: .medium))
                    .tracking(2.0)
                    .foregroundStyle(Color.ncPurple.opacity(0.7))
                    .textCase(.uppercase)
                    .padding(.bottom, 12)

                // Title
                Text("NoteCrux Locked")
                    .font(.system(size: 30, weight: .bold, design: .default))
                    .foregroundStyle(.white)
                    .padding(.bottom, 8)

                // Subtitle
                Text("Your private thoughts, protected.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(red: 0.55, green: 0.52, blue: 0.72))
                    .padding(.bottom, 40)

                // PIN input
                if !pinHash.isEmpty {
                    VStack(spacing: 20) {
                        // PIN dots display
                        HStack(spacing: 16) {
                            ForEach(0..<4, id: \.self) { index in
                                PINDot(
                                    isFilled: index < pin.count,
                                    isActive: isPinFieldFocused && index == pin.count,
                                    hasError: message != nil
                                )
                            }
                        }
                        .offset(x: shakeOffset)
                        .padding(.bottom, 4)

                        // Hidden text field for PIN input
                        SecureField("", text: $pin)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .focused($isPinFieldFocused)
                            .frame(width: 1, height: 1)
                            .opacity(0.01)
                            .onChange(of: pin) { _, newValue in
                                if newValue.count > 4 {
                                    pin = String(newValue.prefix(4))
                                }
                                if message != nil {
                                    message = nil
                                }
                                if newValue.count == 4 {
                                    attemptPINUnlock()
                                }
                            }

                        // Tap area to focus
                        Button {
                            isPinFieldFocused = true
                        } label: {
                            Text("Enter PIN")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color(red: 0.55, green: 0.52, blue: 0.72))
                        }
                    }
                    .padding(.bottom, 24)
                }

                // Biometric button
                if useBiometrics {
                    Button {
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()
                        Task { await biometricUnlock() }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "faceid")
                                .font(.system(size: 20, weight: .medium))
                            Text("Unlock with Face ID")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color.ncPurple,
                                    Color(red: 0.35, green: 0.25, blue: 0.90)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: Capsule()
                        )
                        .shadow(color: Color.ncPurple.opacity(0.4), radius: 16, y: 6)
                    }
                    .buttonStyle(LockButtonStyle())
                    .padding(.bottom, 16)
                }

                // Error message
                if let message {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text(message)
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.55))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.red.opacity(0.10), in: Capsule())
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                Spacer()

                // Bottom branding
                HStack(spacing: 6) {
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 11, weight: .medium))
                    Text("End-to-end local encryption")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(Color(red: 0.40, green: 0.38, blue: 0.52))
                .padding(.bottom, 32)
            }
            .padding(.horizontal, 32)
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 20)
        }
        .task {
            withAnimation(.easeOut(duration: 0.7)) {
                showContent = true
            }
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                iconBreathing = true
            }
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                glowPulsing = true
            }
            if useBiometrics {
                await biometricUnlock()
            }
        }
    }

    private func attemptPINUnlock() {
        if AppSecurity.validatePIN(pin, storedHash: pinHash) {
            let impact = UINotificationFeedbackGenerator()
            impact.notificationOccurred(.success)
            unlock()
        } else {
            let impact = UINotificationFeedbackGenerator()
            impact.notificationOccurred(.error)
            withAnimation(.default) {
                message = "Incorrect PIN. Please try again."
            }
            // Shake animation
            withAnimation(Animation.spring(response: 0.08, dampingFraction: 0.2)) {
                shakeOffset = 12
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                withAnimation(Animation.spring(response: 0.08, dampingFraction: 0.2)) {
                    shakeOffset = -12
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                withAnimation(Animation.spring(response: 0.08, dampingFraction: 0.2)) {
                    shakeOffset = 8
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
                withAnimation(.spring(response: 0.15, dampingFraction: 0.5)) {
                    shakeOffset = 0
                }
            }
            pin = ""
        }
    }

    private func biometricUnlock() async {
        let success = await AppSecurity.unlockWithBiometrics(reason: "Unlock NoteCrux.")
        if success {
            let impact = UINotificationFeedbackGenerator()
            impact.notificationOccurred(.success)
            unlock()
        } else if pinHash.isEmpty {
            withAnimation(.default) {
                message = "Face ID unavailable. Set a PIN in Settings for alternative access."
            }
        }
    }
}

// MARK: - PIN Dot

private struct PINDot: View {
    let isFilled: Bool
    let isActive: Bool
    let hasError: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(dotFill)
                .frame(width: 16, height: 16)
                .overlay(
                    Circle()
                        .strokeBorder(dotBorder, lineWidth: 1.5)
                )
                .scaleEffect(isActive ? 1.2 : 1.0)
                .shadow(color: isFilled ? Color.ncPurple.opacity(0.4) : .clear, radius: 6)
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isFilled)
        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isActive)
    }

    private var dotFill: Color {
        if hasError { return Color(red: 1.0, green: 0.40, blue: 0.42) }
        if isFilled { return Color.ncPurple }
        return Color.white.opacity(0.08)
    }

    private var dotBorder: Color {
        if hasError { return Color(red: 1.0, green: 0.40, blue: 0.42).opacity(0.6) }
        if isFilled { return Color.ncPurple.opacity(0.6) }
        if isActive { return Color.ncPurple.opacity(0.5) }
        return Color.white.opacity(0.15)
    }
}

// MARK: - Lock Button Style

private struct LockButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Floating Particles

private struct FloatingParticlesView: View {
    @State private var particles: [Particle] = (0..<20).map { _ in Particle() }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                for particle in particles {
                    let x = particle.x * size.width
                    let y = particle.y * size.height
                    let opacity = particle.opacity
                    let radius = particle.radius

                    context.fill(
                        Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                        with: .color(Color.ncPurple.opacity(opacity))
                    )
                }
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                for i in particles.indices {
                    particles[i].y -= particles[i].speed
                    particles[i].x += sin(particles[i].y * 10) * 0.001
                    if particles[i].y < -0.05 {
                        particles[i] = Particle(startAtBottom: true)
                    }
                }
            }
        }
    }

    struct Particle {
        var x: Double
        var y: Double
        var radius: Double
        var opacity: Double
        var speed: Double

        init(startAtBottom: Bool = false) {
            x = Double.random(in: 0...1)
            y = startAtBottom ? Double.random(in: 1.0...1.2) : Double.random(in: 0...1)
            radius = Double.random(in: 1...3)
            opacity = Double.random(in: 0.05...0.20)
            speed = Double.random(in: 0.0005...0.002)
        }
    }
}
