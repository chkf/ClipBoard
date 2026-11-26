import CoreImage
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageContent {
    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private static let renderer = CIContext(options: [.cacheIntermediates: false, .useSoftwareRenderer: true])

    static func prepare(_ data: Data) throws -> PreparedClip {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options),
              let identifier = CGImageSourceGetType(source) as String?,
              UTType(identifier)?.conforms(to: .image) == true,
              CGImageSourceGetStatus(source) == .statusComplete
        else { throw HistoryError.unreadable }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { throw HistoryError.unreadable }
        var hash = SHA256()
        func append(_ value: UInt64) {
            var value = value.bigEndian
            withUnsafeBytes(of: &value) { hash.update(bufferPointer: $0) }
        }
        append(UInt64(count))
        for index in 0..<count {
            try autoreleasepool {
                try Task.checkCancellation()
                guard let frame = CGImageSourceCreateImageAtIndex(source, index, options) else { throw HistoryError.unreadable }
                let properties = CGImageSourceCopyPropertiesAtIndex(source, index, options) as? [CFString: Any]
                let orientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.int32Value ?? 1
                let image = CIImage(cgImage: frame).oriented(forExifOrientation: orientation)
                let bounds = image.extent.integral
                let width = Int(bounds.width), height = Int(bounds.height)
                guard width > 0, height > 0 else { throw HistoryError.unreadable }
                append(UInt64(width))
                append(UInt64(height))
                if count > 1 {
                    let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
                    let png = properties?[kCGImagePropertyPNGDictionary] as? [CFString: Any]
                    let delay = gif?[kCGImagePropertyGIFUnclampedDelayTime] ?? gif?[kCGImagePropertyGIFDelayTime]
                        ?? png?[kCGImagePropertyAPNGUnclampedDelayTime] ?? png?[kCGImagePropertyAPNGDelayTime]
                    append(((delay as? NSNumber)?.doubleValue ?? 0).bitPattern)
                }
                let rowBytes = width * 4
                let rowsPerStrip = max(1, min(height, 1_048_576 / rowBytes))
                var buffer = Data(count: rowBytes * rowsPerStrip)
                try buffer.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
                    for y in stride(from: 0, to: height, by: rowsPerStrip) {
                        try Task.checkCancellation()
                        let rows = min(rowsPerStrip, height - y)
                        let region = CGRect(x: bounds.minX, y: bounds.minY + CGFloat(y), width: bounds.width, height: CGFloat(rows))
                        renderer.render(image, toBitmap: bytes.baseAddress!, rowBytes: rowBytes,
                                        bounds: region, format: .RGBA8, colorSpace: colorSpace)
                        hash.update(bufferPointer: UnsafeRawBufferPointer(start: bytes.baseAddress, count: rows * rowBytes))
                    }
                }
            }
        }
        let thumbOptions: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                             kCGImageSourceCreateThumbnailWithTransform: true,
                                             kCGImageSourceThumbnailMaxPixelSize: 256]
        let thumbData = NSMutableData()
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary),
              let destination = CGImageDestinationCreateWithData(thumbData, UTType.png.identifier as CFString, 1, nil)
        else { throw HistoryError.unreadable }
        CGImageDestinationAddImage(destination, thumb, nil)
        guard CGImageDestinationFinalize(destination) else { throw HistoryError.unreadable }
        return PreparedClip(key: "i-" + hash.finalize().hex, preview: "",
                            body: ClipBody(type: identifier, data: data), thumbnail: thumbData as Data)
    }
}
