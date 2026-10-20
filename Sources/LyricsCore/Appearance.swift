import Foundation

public struct RGBColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    /// Most common visible color family; dark shadows and neutrals cannot drown out cover colors.
    public static func dominant(in pixels: [UInt8]) -> RGBColor? {
        var buckets: [Int: (count: Int, red: Int, green: Int, blue: Int)] = [:]
        for index in stride(from: 0, to: pixels.count - pixels.count % 4, by: 4) {
            guard pixels[index + 3] >= 128 else { continue }
            let red = Int(pixels[index]), green = Int(pixels[index + 1]), blue = Int(pixels[index + 2])
            let key = (red >> 4) << 8 | (green >> 4) << 4 | (blue >> 4)
            let bucket = buckets[key] ?? (0, 0, 0, 0)
            buckets[key] = (bucket.count + 1, bucket.red + red, bucket.green + green, bucket.blue + blue)
        }
        let colored = buckets.filter { _, bucket in
            let channels = [Double(bucket.red), Double(bucket.green), Double(bucket.blue)].map { $0 / Double(bucket.count) }
            let brightest = channels.max() ?? 0
            let darkest = channels.min() ?? 0
            return brightest >= 48 && brightest - darkest >= brightest * 0.15
        }
        let candidates = colored.isEmpty ? buckets : colored
        guard let bucket = candidates.sorted(by: { $0.key < $1.key }).max(by: { $0.value.count < $1.value.count })?.value else { return nil }
        let divisor = Double(bucket.count) * 255
        if colored.isEmpty, Double(max(bucket.red, bucket.green, bucket.blue)) / Double(bucket.count) < 48 {
            // Brightening tiny differences in near-black pixels invents a visible hue.
            let gray = Double(bucket.red + bucket.green + bucket.blue) / (divisor * 3)
            return RGBColor(red: gray, green: gray, blue: gray)
        }
        return RGBColor(red: Double(bucket.red) / divisor, green: Double(bucket.green) / divisor, blue: Double(bucket.blue) / divisor)
    }
}

public struct TimingPreferences {
    private let defaults: UserDefaults
    private let key = "trackTimingOffsets"
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func offset(for trackID: String) -> Double {
        (defaults.dictionary(forKey: key)?[trackID] as? Double) ?? 0
    }
    public func setOffset(_ value: Double, for trackID: String) {
        guard value.isFinite else { return }
        var offsets = defaults.dictionary(forKey: key) ?? [:]
        if value == 0 { offsets.removeValue(forKey: trackID) }
        else { offsets[trackID] = value }
        defaults.set(offsets, forKey: key)
    }
}
