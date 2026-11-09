import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum AccountImageCodec {
    static let inputLimit = 20 * 1024 * 1024
    static let storedLimit = 1024 * 1024

    private static func source(_ data: Data, maximum: Int) throws -> CGImageSource {
        guard !data.isEmpty, data.count <= maximum,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 20000, height <= 20000, width * height <= 100_000_000 else { throw AccountError.image }
        return source
    }

    static func normalize(_ data: Data) throws -> Data {
        let source = try source(data, maximum: inputLimit)
        for dimension in [512, 256] {
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: dimension,
                kCGImageSourceShouldCacheImmediately: true]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw AccountError.image }
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { throw AccountError.image }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { throw AccountError.image }
            if output.length <= storedLimit { return output as Data }
        }
        throw AccountError.image
    }

    static func validate(_ data: Data) throws {
        let source = try source(data, maximum: storedLimit)
        guard CGImageSourceGetType(source) as String? == UTType.png.identifier,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, width <= 512,
              let height = properties[kCGImagePropertyPixelHeight] as? Int, height <= 512,
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else { throw AccountError.image }
    }
}
