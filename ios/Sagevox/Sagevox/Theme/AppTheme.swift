import SwiftUI

/// SageVox App Theme - based on the owl mascot colors
enum AppTheme {
    // MARK: - Colors

    /// Primary purple/lavender (owl body, headphone band)
    static let primaryPurple = Color("PrimaryPurple")

    /// Accent gold/amber (headphone cups, beak, feet)
    static let accentGold = Color("AccentGold")

    /// Light lavender background
    static let backgroundLavender = Color("BackgroundLavender")

    // MARK: - Gradients

    static let primaryGradient = LinearGradient(
        colors: [primaryPurple, primaryPurple.opacity(0.7)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cardGradient = LinearGradient(
        colors: [Color.white.opacity(0.9), backgroundLavender],
        startPoint: .top,
        endPoint: .bottom
    )

    // MARK: - Shadows

    static let cardShadow = Color.black.opacity(0.1)

    // MARK: - Button Styles

    struct PrimaryButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 25)
                        .fill(primaryPurple)
                )
                .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
        }
    }

    struct AccentButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 25)
                        .fill(accentGold)
                )
                .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}

// MARK: - View Extensions

extension View {
    func cardStyle() -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(UIColor.systemBackground))
                    .shadow(color: AppTheme.cardShadow, radius: 8, x: 0, y: 4)
            )
    }

    func primaryButtonStyle() -> some View {
        self.buttonStyle(AppTheme.PrimaryButtonStyle())
    }

    func accentButtonStyle() -> some View {
        self.buttonStyle(AppTheme.AccentButtonStyle())
    }
}
