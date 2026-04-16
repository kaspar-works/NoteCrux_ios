import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum NoteCruxTheme {
    static let background = LinearGradient(
        colors: [
            Color(red: 0.05, green: 0.07, blue: 0.06),
            Color(red: 0.08, green: 0.11, blue: 0.09),
            Color(red: 0.02, green: 0.03, blue: 0.03)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func background(for scheme: ColorScheme) -> LinearGradient {
        if scheme == .light {
            return LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.98, blue: 0.97),
                    Color(red: 0.90, green: 0.95, blue: 0.93),
                    Color(red: 0.98, green: 0.98, blue: 0.96)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return background
    }

    static func preferredColorScheme(_ mode: String) -> ColorScheme? {
        switch mode {
        case "Light":
            return .light
        case "Dark":
            return .dark
        default:
            return nil
        }
    }
}

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

struct PremiumCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardFill, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(colorScheme == .light ? 0.08 : 0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(colorScheme == .light ? 0.07 : 0.22), radius: 14, y: 6)
    }

    private var cardFill: Color {
        colorScheme == .light ? Color.white.opacity(0.86) : Color.white.opacity(0.08)
    }
}

struct MetricTile: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        PremiumCard {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(.green)
                Text(value)
                    .font(.title2.bold())
                    .monospacedDigit()
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
