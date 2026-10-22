import AppKit
import SwiftUI

/// 与暖色小狗图标共用的界面色板，深色模式使用暖棕色表面。
enum AppTheme {
    static let accent = adaptive(light: 0xA84F24, dark: 0xFFB789)
    static let caramel = adaptive(light: 0x956530, dark: 0xE6BF88)
    static let cocoa = adaptive(light: 0x51372C, dark: 0xF5E6DC)
    static let secondary = adaptive(light: 0x80685D, dark: 0xC5ADA0)
    static let background = adaptive(light: 0xFFF6EC, dark: 0x211C19)
    static let surface = adaptive(light: 0xFFFCF7, dark: 0x2D2521)
    static let input = adaptive(light: 0xFFFFFF, dark: 0x251F1C)
    static let peach = adaptive(light: 0xFFE8D6, dark: 0x493126)
    static let border = adaptive(light: 0xEEDBCD, dark: 0x574337)
    static let success = adaptive(light: 0x537B58, dark: 0xA9CEA4)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(
                red: CGFloat((value >> 16) & 0xff) / 255,
                green: CGFloat((value >> 8) & 0xff) / 255,
                blue: CGFloat(value & 0xff) / 255,
                alpha: 1
            )
        })
    }
}

struct BrandIcon: View {
    var size: CGFloat = 52
    private static let icon: NSImage? = {
        guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    var body: some View {
        Group {
            if let icon = Self.icon {
                Image(nsImage: icon).resizable().interpolation(.high).scaledToFit()
            } else {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .resizable().scaledToFit().padding(10)
                    .foregroundStyle(AppTheme.accent)
                    .background(AppTheme.peach, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct WarmCard: ViewModifier {
    var fill: Color = AppTheme.surface
    var radius: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(AppTheme.border, lineWidth: 1))
    }
}

extension View {
    func warmCard(fill: Color = AppTheme.surface, radius: CGFloat = 18) -> some View {
        modifier(WarmCard(fill: fill, radius: radius))
    }
}

struct WarmActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(AppTheme.peach.opacity(configuration.isPressed ? 0.65 : (hovered ? 1 : 0.55)),
                        in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(AppTheme.accent.opacity(hovered ? 0.35 : 0.12)))
            .opacity(isEnabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovered)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct WarmButtonStyle: ButtonStyle {
    var prominent = false
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .foregroundStyle(prominent ? AppTheme.background : AppTheme.cocoa)
            .background(prominent ? AppTheme.accent : AppTheme.peach.opacity(0.65),
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(prominent ? Color.clear : AppTheme.border))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : (hovered ? 0.88 : 1)) : 0.45)
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovered)
    }
}
