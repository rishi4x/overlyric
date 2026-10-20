import SwiftUI

struct FlatButtonStyle: ButtonStyle {
    var tint: Color = .white
    var compact = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 10 : 11, weight: .semibold))
            .foregroundStyle(.white.opacity(enabled ? 0.88 : 0.3))
            .padding(.horizontal, compact ? 10 : 12).padding(.vertical, compact ? 7 : 10)
            .background(tint.opacity(configuration.isPressed ? 0.2 : 0.1), in: RoundedRectangle(cornerRadius: compact ? 10 : 12))
            .overlay { RoundedRectangle(cornerRadius: compact ? 10 : 12).strokeBorder(.white.opacity(0.07), lineWidth: 1) }
            .contentShape(RoundedRectangle(cornerRadius: compact ? 10 : 12))
    }
}
