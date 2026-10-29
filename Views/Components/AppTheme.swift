import SwiftUI

// MARK: - App Theme (design tokens)

/// The app's colors in one place. Use these instead of Color(red:green:blue:).
enum AppTheme {
    /// Screen background (near-black)
    static let base = Color(red: 0.04, green: 0.04, blue: 0.06)
    /// Sheets and raised surfaces on top of `base`
    static let surface = Color(red: 0.07, green: 0.07, blue: 0.1)

    /// Primary brand purple (gradients, rings, icons)
    static let purple = Color(red: 0.39, green: 0.22, blue: 1.0)
    /// Brighter purple for spinners and accents
    static let violet = Color(red: 0.55, green: 0.43, blue: 1.0)
    /// Soft purple for text buttons and links
    static let lavender = Color(red: 0.65, green: 0.55, blue: 0.98)
    /// Secondary brand teal (success, saved, gradients)
    static let teal = Color(red: 0.0, green: 0.83, blue: 0.67)
    /// Warnings and "good" scores
    static let amber = Color(red: 0.98, green: 0.75, blue: 0.18)
    /// Errors and destructive actions
    static let coral = Color(red: 1.0, green: 0.48, blue: 0.45)

    /// The purple → teal brand gradient (primary buttons, logo)
    static let brandGradient = LinearGradient(
        colors: [purple, teal],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let brandGradientDiagonal = LinearGradient(
        colors: [purple, teal],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
