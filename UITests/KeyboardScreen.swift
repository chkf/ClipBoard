import XCTest
import UIKit

struct KeyboardScreen {
    private let pixels: [UInt8]
    private let width: Int
    private let height: Int
    private let scale: CGFloat

    init?(_ screenshot: XCUIScreenshot, screen: CGRect) {
        guard let source = screenshot.image.cgImage else { return nil }
        width = Int(screen.width)
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

    private func matches(_ color: [Int], x: Int, y: Int) -> Bool {
        let offset = (y * width + x) * 4
        return (0..<3).allSatisfy { abs(Int(pixels[offset + $0]) - color[$0]) <= 4 }
    }

    func verticalFace(at point: CGPoint) -> ClosedRange<CGFloat>? {
        let x = Int(point.x * scale), y = Int(point.y * scale)
        guard (1..<(width - 1)).contains(x), (1..<(height - 1)).contains(y) else { return nil }
        let color = keycapColor(in: CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4))
        guard color.count == 3 else { return nil }
        var top = y, bottom = y
        while top > 0, matches(color, x: x, y: top - 1) { top -= 1 }
        while bottom + 1 < height, matches(color, x: x, y: bottom + 1) { bottom += 1 }
        return (CGFloat(top) / scale)...(CGFloat(bottom + 1) / scale)
    }
}
