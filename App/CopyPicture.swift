import AVFoundation
import AVKit
import UIKit

@MainActor
final class CopyPicture: NSObject, AVPictureInPictureControllerDelegate, AVPictureInPictureSampleBufferPlaybackDelegate {
    let layer = AVSampleBufferDisplayLayer()
    private var controller: AVPictureInPictureController?
    private var readiness: NSKeyValueObservation?
    var started: (() -> Void)?
    var stopped: (() -> Void)?
    var failed: ((String) -> Void)?
    private var waiting = false
    private var paused = false
    private var timeout: Task<Void, Never>?
    var supported: Bool { AVPictureInPictureController.isPictureInPictureSupported() }

    func start() throws {
        guard supported else { throw NSError(domain: "Clipboard", code: 1, userInfo: [NSLocalizedDescriptionKey: "这台设备当前不支持画中画。"]) }
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
        try audio.setActive(true)
        let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: layer, playbackDelegate: self)
        let pip = AVPictureInPictureController(contentSource: source)
        pip.delegate = self
        pip.requiresLinearPlayback = true
        controller = pip
        waiting = true
        paused = false
        render(count: 0)
        readiness = pip.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor in self?.startIfReady() }
        }
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(9))
            guard !Task.isCancelled, let self, self.controller?.isPictureInPictureActive != true else { return }
            self.failed?("小窗没有启动。请在前台点「开始连拷」重试，并检查系统画中画设置。")
        }
    }
    private func startIfReady() {
        guard waiting, let controller, controller.isPictureInPicturePossible,
              UIApplication.shared.applicationState == .active else { return }
        waiting = false
        controller.startPictureInPicture()
    }
    func stop() {
        waiting = false
        timeout?.cancel()
        readiness?.invalidate()
        readiness = nil
        let pip = controller
        controller = nil
        pip?.delegate = nil
        pip?.stopPictureInPicture()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        timeout?.cancel()
        started?()
    }
    func pictureInPictureControllerWillStopPictureInPicture(_ controller: AVPictureInPictureController) { stopped?() }
    func pictureInPictureController(_ controller: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        failed?("画中画启动失败：" + error.localizedDescription)
    }
    func pictureInPictureControllerTimeRangeForPlayback(_ controller: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .zero, duration: .positiveInfinity)
    }
    func pictureInPictureControllerIsPlaybackPaused(_ controller: AVPictureInPictureController) -> Bool { paused }
    func pictureInPictureController(_ controller: AVPictureInPictureController, setPlaying playing: Bool) {
        paused = !playing
        controller.invalidatePlaybackState()
    }
    func pictureInPictureController(_ controller: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}
    func pictureInPictureController(_ controller: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion completionHandler: @escaping () -> Void) { completionHandler() }
    func pictureInPictureControllerShouldProhibitBackgroundAudioPlayback(_ controller: AVPictureInPictureController) -> Bool { true }

    func render(count: Int) {
        guard !paused else { return }
        let size = CGSize(width: 320, height: 112)
        var buffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
        guard CVPixelBufferCreate(nil, Int(size.width), Int(size.height), kCVPixelFormatType_32BGRA, attributes, &buffer) == kCVReturnSuccess,
              let buffer else { return }
        CVPixelBufferLockBaseAddress(buffer, [])
        let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: Int(size.width), height: Int(size.height),
                                bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)
        if let context {
            context.setFillColor(UIColor(red: 0.08, green: 0.10, blue: 0.13, alpha: 1).cgColor)
            context.fill(CGRect(origin: .zero, size: size))
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
            UIGraphicsPushContext(context)
            ("连拷" as NSString).draw(at: CGPoint(x: 24, y: 37), withAttributes: [.font: UIFont.systemFont(ofSize: 27, weight: .medium), .foregroundColor: UIColor.white])
            let text = "\(count) 条" as NSString
            let style: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedDigitSystemFont(ofSize: 36, weight: .semibold), .foregroundColor: UIColor.systemMint]
            text.draw(at: CGPoint(x: size.width - text.size(withAttributes: style).width - 25, y: 31), withAttributes: style)
            UIGraphicsPopContext()
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: buffer, formatDescriptionOut: &format) == noErr,
              let format else { return }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 2),
                                        presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: buffer, formatDescription: format,
                                                       sampleTiming: &timing, sampleBufferOut: &sample) == noErr, let sample else { return }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) as? [NSMutableDictionary] {
            attachments.first?[kCMSampleAttachmentKey_DisplayImmediately] = true
        }
        let renderer = layer.sampleBufferRenderer
        if renderer.status == .failed { renderer.flush() }
        renderer.enqueue(sample)
    }
}
