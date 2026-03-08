import SwiftUI

/// アプリ全体のデザインシステム
enum AppTheme {
    // MARK: - カラー（スレート＋インディゴアクセント）
    static let background = Color(hex: "F8FAFC")
    static let surface = Color.white
    static let surfaceElevated = Color(hex: "F1F5F9")
    static let accent = Color(hex: "4F46E5")
    static let accentSecondary = Color(hex: "6366F1")
    static let textPrimary = Color(hex: "0F172A")
    static let textSecondary = Color(hex: "64748B")
    static let userBubble = Color(hex: "4F46E5")
    static let aiBubble = Color(hex: "F1F5F9")
    static let errorRed = Color(hex: "DC2626")
    static let successGreen = Color(hex: "16A34A")

    // MARK: - フォント
    static let titleFont = Font.system(.title, design: .rounded).weight(.bold)
    static let headlineFont = Font.system(.headline, design: .rounded).weight(.semibold)
    static let bodyFont = Font.system(.body, design: .default)
    static let captionFont = Font.system(.caption, design: .rounded)
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
