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
    // Locate the counter's dark blue video surface in the system compositor screenshot.
    // The separate fixture has no surface in this colour.
    func pictureFrame() -> CGRect? {
        var mask = [Bool](repeating: false, count: width * height)
        for i in mask.indices {
            let r = Int(pixels[i * 4]), g = Int(pixels[i * 4 + 1]), b = Int(pixels[i * 4 + 2])
            mask[i] = abs(r - 20) < 14 && abs(g - 26) < 14 && abs(b - 33) < 14 && b >= r + 5 && g >= r + 1
        }
        var biggest = 0, result: CGRect?
        for start in mask.indices where mask[start] {
            var queue = [start], cursor = 0, minX = width, maxX = 0, minY = height, maxY = 0
            mask[start] = false
            while cursor < queue.count {
                let i = queue[cursor], x = i % width, y = i / width
                cursor += 1
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                for next in [x > 0 ? i - 1 : -1, x + 1 < width ? i + 1 : -1, i - width, i + width]
                    where next >= 0 && next < mask.count && mask[next] {
                    mask[next] = false; queue.append(next)
                }
            }
            let w = CGFloat(maxX - minX + 1) / scale, h = CGFloat(maxY - minY + 1) / scale
            if queue.count > biggest, w > 70, h > 25, w > h, w < CGFloat(width) / scale * 0.95 {
                biggest = queue.count
                result = CGRect(x: CGFloat(minX) / scale, y: CGFloat(minY) / scale, width: w, height: h)
            }
        }
        return result
    }
}
