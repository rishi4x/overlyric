import Foundation

public struct LyricEmphasis {
    public let opacity: Double
    public let blur: Double

    public static func at(_ index: Int, activeIndex: Int?) -> LyricEmphasis {
        guard let activeIndex else {
            if index < 2 { return .init(opacity: 0.52, blur: index == 0 ? 0 : 0.45) }
            return .init(opacity: max(0.14, 0.42 - Double(index - 2) * 0.09), blur: min(4.6, Double(index - 1) * 1.1))
        }
        let distance = index - activeIndex
        if distance == 0 { return .init(opacity: 0.9, blur: 0) }
        if distance == 1 { return .init(opacity: 0.4, blur: 0.45) }
        if distance < 0 {
            return .init(opacity: max(0.11, 0.41 - Double(-distance) * 0.105), blur: min(4.8, Double(-distance) * 1.5))
        }
        return .init(opacity: max(0.14, 0.5 - Double(distance - 1) * 0.1), blur: min(4.6, Double(distance - 1) * 1.15))
    }
}

public struct LyricScrollMetrics: Equatable {
    public var offset: Double
    public var contentHeight: Double
    public var viewportHeight: Double

    public init(offset: Double = 0, contentHeight: Double = 0, viewportHeight: Double = 0) {
        self.offset = offset; self.contentHeight = contentHeight; self.viewportHeight = viewportHeight
    }

    public var maximumOffset: Double { max(0, contentHeight - viewportHeight) }
    public var progress: Double { maximumOffset > 0 ? min(1, max(0, offset / maximumOffset)) : 0 }
    public func thumbHeight(in trackHeight: Double) -> Double {
        guard contentHeight > 0 else { return max(0, trackHeight) }
        return min(max(0, trackHeight), max(28, trackHeight * min(1, viewportHeight / contentHeight)))
    }
    public func offset(at progress: Double) -> Double { min(1, max(0, progress)) * maximumOffset }
}
