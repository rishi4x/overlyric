import Foundation

public struct RGBColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    /// Most common color family, averaged within that family rather than across the cover.
    public static func dominant(in pixels: [UInt8]) -> RGBColor? {
        var buckets: [Int: (count: Int, red: Int, green: Int, blue: Int)] = [:]
        for index in stride(from: 0, to: pixels.count - pixels.count % 4, by: 4) {
            guard pixels[index + 3] >= 128 else { continue }
            let red = Int(pixels[index]), green = Int(pixels[index + 1]), blue = Int(pixels[index + 2])
            let key = (red >> 4) << 8 | (green >> 4) << 4 | (blue >> 4)
            let bucket = buckets[key] ?? (0, 0, 0, 0)
            buckets[key] = (bucket.count + 1, bucket.red + red, bucket.green + green, bucket.blue + blue)
        }
        guard let bucket = buckets.sorted(by: { $0.key < $1.key }).max(by: { $0.value.count < $1.value.count })?.value else { return nil }
        let divisor = Double(bucket.count) * 255
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
