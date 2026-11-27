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

    // Both keyboards have an uninterrupted space bar between the Emoji and Return keys.
    // Scan near its top edge, above both the labels and the system's lower-right language indicator.
    func bottomRowSampleY() -> CGFloat? {
        let center = width * 42 / 100
        for y in stride(from: height - 1, through: height * 3 / 4, by: -1) {
            let offset = (y * width + center) * 4
            let color = pixels[offset..<(offset + 3)].map(Int.init)
            var left = center, right = center
            while left > 0, matches(color, x: left - 1, y: y) { left -= 1 }
            while right + 1 < width, matches(color, x: right + 1, y: y) { right += 1 }
            if (width / 5..<width / 3).contains(left),
               (width * 2 / 3..<width * 4 / 5).contains(right),
               matches(color, x: width * 8 / 100, y: y),
               matches(color, x: width * 35 / 100, y: y - 3) {
                var top = y
                while top > 0, matches(color, x: width * 35 / 100, y: top - 1) { top -= 1 }
                return CGFloat(top) / scale + 8
            }
        }
        return nil
    }

    func bottomKeycap(at point: CGPoint) -> CGRect? {
        let x = Int(point.x * scale), y = Int(point.y * scale)
        guard (1..<(width - 1)).contains(x), (1..<(height - 1)).contains(y) else { return nil }
        let color = keycapColor(in: CGRect(x: point.x - 4, y: point.y - 2, width: 8, height: 4))
        guard color.count == 3 else { return nil }
        func isFace(_ column: Int, _ row: Int) -> Bool {
            matches(color, x: column, y: row)
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

    func symbolColor(in face: CGRect, background: [Int]) -> [Int] {
        guard background.count == 3 else { return [] }
        let center = CGRect(x: face.midX - 17, y: face.midY - 15, width: 34, height: 30)
        var samples: [(contrast: Int, rgb: [Int])] = []
        for y in Int(center.minY * scale)..<Int(center.maxY * scale) {
            for x in Int(center.minX * scale)..<Int(center.maxX * scale) {
                let offset = (y * width + x) * 4
                let rgb = pixels[offset..<(offset + 3)].map(Int.init)
                let contrast = zip(background, rgb).reduce(0) { $0 + abs($1.0 - $1.1) }
                samples.append((contrast, rgb))
            }
        }
        return samples.sorted { $0.contrast < $1.contrast }[samples.count * 98 / 100].rgb
    }
}
