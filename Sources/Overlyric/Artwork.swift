import Foundation
import ImageIO
import CoreGraphics
import LyricsCore

struct ArtworkAsset: Sendable {
    let data: Data
    let dominant: RGBColor?
}

actor ArtworkLoader {
    private var cache: [URL: ArtworkAsset] = [:]

    func load(_ url: URL) async throws -> ArtworkAsset {
        if let cached = cache[url] { return cached }
        guard url.scheme == "https" else { throw URLError(.unsupportedURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 64
              ] as CFDictionary) else { throw URLError(.cannotDecodeContentData) }
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let dominant = pixels.withUnsafeMutableBytes { buffer -> RGBColor? in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return RGBColor.dominant(in: Array(buffer))
        }
        let asset = ArtworkAsset(data: data, dominant: dominant)
        if cache.count >= 50 { cache.removeAll() }
        cache[url] = asset
        return asset
    }
}
