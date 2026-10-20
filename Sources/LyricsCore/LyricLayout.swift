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
    public func fontSize(base: Double) -> Double { base * scale }
}
