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

    // UIKit exposes expanded hit regions. Measure the painted faces, including the space bar.
    func bottomKeycap(at point: CGPoint) -> CGRect? {
        let x = Int(point.x * scale), y = Int((point.y - 12) * scale)
        guard (1..<(width - 1)).contains(x), (1..<(height - 1)).contains(y) else { return nil }
        let color = keycapColor(in: CGRect(x: point.x - 4, y: point.y - 15, width: 8, height: 6))
        guard color.count == 3 else { return nil }
        func isFace(_ column: Int, _ row: Int) -> Bool {
            let offset = (row * width + column) * 4
            return (0..<3).allSatisfy { abs(Int(pixels[offset + $0]) - color[$0]) <= 4 }
        }
        var left = x, right = x
        while left > 0, isFace(left - 1, y) { left -= 1 }
        while right + 1 < width, isFace(right + 1, y) { right += 1 }
        guard right - left > 7 else { return nil }
        func hasFace(at row: Int) -> Bool {
            (left...right).filter { isFace($0, row) }.count > (right - left) * 2 / 5
        }
        var top = y, bottom = y
        while top > 0, hasFace(at: top - 1) { top -= 1 }
        while bottom + 1 < height, hasFace(at: bottom + 1) { bottom += 1 }
        return CGRect(x: CGFloat(left) / scale, y: CGFloat(top) / scale,
                      width: CGFloat(right - left + 1) / scale, height: CGFloat(bottom - top + 1) / scale)
    }
}
