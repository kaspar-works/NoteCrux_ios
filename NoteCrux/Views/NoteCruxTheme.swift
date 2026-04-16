import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Theme Utility

enum NoteCruxTheme {
    static func preferredColorScheme(_ mode: String) -> ColorScheme? {
        switch mode {
        case "Light": return .light
        case "Dark": return .dark
        default: return nil
        }
    }

    static let accentGradient = LinearGradient(
        colors: [Color.ncPurple, Color(red: 0.58, green: 0.30, blue: 1.0)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let brandGradient = LinearGradient(
        colors: [Color(red: 0.04, green: 0.42, blue: 0.43), Color(red: 0.97, green: 0.72, blue: 0.45)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Adaptive Color Helper

extension Color {
    static func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        #if canImport(UIKit)
        Color(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
        #else
        Color(red: light.0, green: light.1, blue: light.2)
        #endif
    }
}

// MARK: - Color Palette

extension Color {
    // Brand
    static let ncPurple = Color.adaptive(light: (0.25, 0.18, 0.86), dark: (0.58, 0.50, 1.0))

    // Backgrounds
    static let ncBackground = Color.adaptive(light: (0.965, 0.968, 0.980), dark: (0.055, 0.056, 0.072))

    // Surfaces
    static let ncSurface = Color.adaptive(light: (1.0, 1.0, 1.0), dark: (0.105, 0.108, 0.135))
    static let ncSurfaceElevated = Color.adaptive(light: (0.98, 0.98, 0.99), dark: (0.14, 0.14, 0.17))

    // Text
    static let ncInk = Color.adaptive(light: (0.13, 0.13, 0.15), dark: (0.93, 0.94, 0.97))
    static let ncSecondary = Color.adaptive(light: (0.38, 0.38, 0.44), dark: (0.72, 0.74, 0.80))
    static let ncMuted = Color.adaptive(light: (0.56, 0.57, 0.64), dark: (0.62, 0.64, 0.72))

    // Dividers
    static let ncDivider = Color.adaptive(light: (0.90, 0.90, 0.92), dark: (0.18, 0.18, 0.22))

    // Semantic
    static let ncSuccess = Color.adaptive(light: (0.10, 0.68, 0.34), dark: (0.30, 0.84, 0.52))
    static let ncWarning = Color.adaptive(light: (0.85, 0.60, 0.10), dark: (0.96, 0.76, 0.28))
    static let ncDanger = Color.adaptive(light: (0.83, 0.20, 0.28), dark: (0.95, 0.40, 0.42))
}

// MARK: - Typography

extension Font {
    static let ncLargeTitle = Font.system(size: 32, weight: .bold)
    static let ncTitle1     = Font.system(size: 24, weight: .bold)
    static let ncTitle2     = Font.system(size: 20, weight: .semibold)
    static let ncTitle3     = Font.system(size: 17, weight: .semibold)
    static let ncHeadline   = Font.system(size: 15, weight: .semibold)
    static let ncBody       = Font.system(size: 15, weight: .regular)
    static let ncCallout    = Font.system(size: 13, weight: .regular)
    static let ncFootnote   = Font.system(size: 12, weight: .regular)
    static let ncCaption1   = Font.system(size: 11, weight: .regular)
    static let ncCaption2   = Font.system(size: 10, weight: .bold)
    static let ncOverline   = Font.system(size: 9, weight: .bold)
    static let ncMono       = Font.system(size: 15, weight: .medium, design: .monospaced)
    static let ncMonoLarge  = Font.system(size: 54, weight: .bold, design: .monospaced)
}

// MARK: - Spacing

enum NCSpacing {
    static let xs:   CGFloat = 4
    static let sm:   CGFloat = 8
    static let md:   CGFloat = 12
    static let lg:   CGFloat = 16
    static let xl:   CGFloat = 20
    static let xxl:  CGFloat = 24
    static let xxxl: CGFloat = 32
}

// MARK: - Corner Radii

enum NCRadius {
    static let small:  CGFloat = 8
    static let medium: CGFloat = 16
    static let large:  CGFloat = 24
}

// MARK: - Shadows

struct NCShadow {
    let color: Color
    let radius: CGFloat
    let y: CGFloat

    static let subtle   = NCShadow(color: .black.opacity(0.04), radius: 8, y: 2)
    static let card     = NCShadow(color: .black.opacity(0.06), radius: 16, y: 4)
    static let elevated = NCShadow(color: .black.opacity(0.10), radius: 24, y: 8)
}

extension View {
    func ncShadow(_ shadow: NCShadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, y: shadow.y)
    }
}

// MARK: - Animation

extension Animation {
    static let ncSpring = Animation.spring(response: 0.35, dampingFraction: 0.8)
    static let ncEaseOut = Animation.easeOut(duration: 0.25)
    static let ncSnappy = Animation.spring(response: 0.28, dampingFraction: 0.72)
}

// MARK: - Button Style

struct NCPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.ncSnappy, value: configuration.isPressed)
    }
}

// MARK: - Shared Components

struct NCCard<Content: View>: View {
    var padding: CGFloat = NCSpacing.lg
    var radius: CGFloat = NCRadius.medium
    var shadow: NCShadow = .card
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.ncSurface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .ncShadow(shadow)
    }
}

struct NCChip: View {
    let label: String
    var isSelected: Bool = false
    var color: Color = .ncPurple

    var body: some View {
        Text(label)
            .font(.ncOverline)
            .tracking(0.4)
            .foregroundStyle(isSelected ? .white : color)
            .padding(.horizontal, NCSpacing.sm + 2)
            .padding(.vertical, NCSpacing.xs + 1)
            .background(
                isSelected ? color : color.opacity(0.12),
                in: Capsule()
            )
    }
}

struct NCButton: View {
    enum Style { case primary, secondary, destructive }
    let title: String
    var icon: String? = nil
    var style: Style = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: NCSpacing.sm) {
                if let icon {
                    Image(systemName: icon)
                        .font(.ncCallout.bold())
                }
                Text(title)
                    .font(.ncCallout.bold())
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, NCSpacing.xl)
            .padding(.vertical, NCSpacing.md)
            .background(backgroundColor, in: Capsule())
        }
        .buttonStyle(NCPressButtonStyle())
    }

    private var foregroundColor: Color {
        switch style {
        case .primary: .white
        case .secondary: .ncPurple
        case .destructive: .white
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .primary: .ncPurple
        case .secondary: .ncPurple.opacity(0.12)
        case .destructive: .ncDanger
        }
    }
}

struct NCSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.ncOverline)
            .tracking(1.4)
            .foregroundStyle(Color.ncMuted)
    }
}

struct NCMetricCard: View {
    let title: String
    let value: String
    var icon: String? = nil
    var valueColor: Color = .ncInk
    var isPrimary: Bool = false

    var body: some View {
        NCCard {
            VStack(alignment: .leading, spacing: NCSpacing.sm) {
                if let icon {
                    Image(systemName: icon)
                        .font(.ncHeadline)
                        .foregroundStyle(isPrimary ? Color.ncPurple : Color.ncSecondary)
                }
                NCSectionHeader(title: title)
                Text(value)
                    .font(.ncTitle1)
                    .monospacedDigit()
                    .foregroundStyle(isPrimary ? Color.ncPurple : valueColor)
            }
        }
    }
}

struct NCEmptyState: View {
    let icon: String
    let title: String
    let message: String
    var action: (() -> Void)? = nil
    var actionTitle: String = "Get Started"

    var body: some View {
        VStack(spacing: NCSpacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.ncMuted)
            Text(title)
                .font(.ncTitle3)
                .foregroundStyle(Color.ncInk)
            Text(message)
                .font(.ncCallout)
                .foregroundStyle(Color.ncMuted)
                .multilineTextAlignment(.center)
            if let action {
                NCButton(title: actionTitle, action: action)
            }
        }
        .padding(NCSpacing.xxxl)
    }
}


