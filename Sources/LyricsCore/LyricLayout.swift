import Foundation

public struct LyricLayout {
    public static let minimumWidth = 340.0
    public static let minimumHeight = 360.0
    public let scale: Double

    public init(width: Double, height: Double) {
        // Sublinear growth leaves room for natural wrapping as the panel widens.
        let widthScale = pow(max(1, width) / 390, 0.55)
        let heightScale = min(1.08, max(0.95, pow(max(1, height) / 510, 0.12)))
        scale = min(1.55, max(0.88, widthScale * heightScale))
    }

    public var horizontalPadding: Double { 28 * sqrt(scale) }
    public var rowSpacing: Double { 22 * scale }
    public func rowSpacing(after index: Int, activeIndex: Int?) -> Double {
        guard let activeIndex else { return rowSpacing }
        let nearCurrent = abs(index - activeIndex) <= 1 || abs(index + 1 - activeIndex) <= 1
        return rowSpacing * (nearCurrent ? 1 : 0.6)
    }
    public func fontSize(base: Double) -> Double { base * scale }
    public func blurRadius(base: Double, fontSize: Double) -> Double { base * self.fontSize(base: fontSize) / 30 }
}
