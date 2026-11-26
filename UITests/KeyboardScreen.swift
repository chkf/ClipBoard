import XCTest
import UIKit

struct KeyboardScreen {
    private let pixels: [UInt8]
    private let width: Int
    private let height: Int
    private let scale: CGFloat

    init?(_ screenshot: XCUIScreenshot, screen: CGRect) {
        guard let source = screenshot.image.cgImage else { return nil }
        width = Int(screen.width / 2)
        scale = CGFloat(width) / screen.width
        height = Int((screen.height * scale).rounded())
        var bitmap = [UInt8](repeating: 0, count: width * height * 4)
        let w = width, h = height
        let rendered = bitmap.withUnsafeMutableBytes { bytes -> Bool in
            guard let ctx = CGContext(data: bytes.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard rendered else { return nil }
        pixels = bitmap
    }
    func keycapColor(in rect: CGRect) -> [Int] {
        var red = [Int](), green = [Int](), blue = [Int]()
        for y in max(0, Int(rect.minY * scale))..<min(height, Int(rect.maxY * scale)) {
            for x in max(0, Int(rect.minX * scale))..<min(width, Int(rect.maxX * scale)) {
                let p = (y * width + x) * 4
                red.append(Int(pixels[p]))
                green.append(Int(pixels[p + 1]))
                blue.append(Int(pixels[p + 2]))
            }
        }
        guard !red.isEmpty else { return [] }
        return [red, green, blue].map { $0.sorted()[$0.count / 2] }
    }
}
