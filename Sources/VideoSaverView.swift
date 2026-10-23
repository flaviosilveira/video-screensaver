import AVFoundation
import OSLog
import ScreenSaver

private let log = Logger(subsystem: "com.local.videosaver", category: "VideoSaverView")

// make-saver.sh renames this class per saver: legacyScreenSaver loads every
// installed saver into one process, so ObjC class names must not collide.
@objc(VideoSaverView)
final class VideoSaverView: ScreenSaverView {
    private static let instances = NSHashTable<VideoSaverView>.weakObjects()

    private static let pixelBufferAttributes: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
    ]

    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var videoLayer: CALayer?
    private var currentFrame: CVPixelBuffer?

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        animationTimeInterval = 1.0 / 60
        Self.instances.add(self)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func startAnimation() {
        super.startAnimation()
        startPlayback()
    }

    override func stopAnimation() {
        stopPlayback()
        super.stopAnimation()
    }

    override func layout() {
        super.layout()
        videoLayer?.frame = bounds
    }

    override func draw(_ rect: NSRect) {
        NSColor.black.setFill()
        rect.fill()
    }

    // Frames are copied into a plain in-process CALayer instead of using AVPlayerLayer.
    // AVPlayerLayer (like WKWebView) composites from another process, and with several
    // displays legacyScreenSaver positions those nested layers wrong: cropped quarters
    // and duplicated fragments on displays not centered with the main one.
    override func animateOneFrame() {
        guard let item = player?.currentItem else { return }
        let output = item.outputs.first as? AVPlayerItemVideoOutput ?? addVideoOutput(to: item)
        let time = output.itemTime(forHostTime: CACurrentMediaTime())
        guard output.hasNewPixelBuffer(forItemTime: time),
              let frame = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil),
              let surface = CVPixelBufferGetIOSurface(frame)?.takeUnretainedValue()
        else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoLayer?.contents = surface
        CATransaction.commit()
        currentFrame = frame
    }

    override var hasConfigureSheet: Bool { false }
    override var configureSheet: NSWindow? { nil }

    private var videoURL: URL? {
        let bundle = Bundle(for: Self.self)
        return ["mp4", "mov", "m4v"].lazy.compactMap { bundle.url(forResource: "video", withExtension: $0) }.first
    }

    @discardableResult
    private func addVideoOutput(to item: AVPlayerItem) -> AVPlayerItemVideoOutput {
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: Self.pixelBufferAttributes)
        item.add(output)
        return output
    }

    private func startPlayback() {
        guard player == nil, let url = videoURL else { return }

        // The host may leave a stale instance in the same window; only one should play.
        for other in Self.instances.allObjects where other !== self && other.window != nil && other.window === window {
            other.stopPlayback()
            other.removeFromSuperview()
        }

        log.notice("""
            start preview=\(self.isPreview, privacy: .public) \
            frame=\(NSStringFromRect(self.frame), privacy: .public) \
            window=\(NSStringFromRect(self.window?.frame ?? .zero), privacy: .public) \
            screen=\(NSStringFromRect(self.window?.screen?.frame ?? .zero), privacy: .public) \
            scale=\(self.window?.backingScaleFactor ?? 0, privacy: .public) \
            instances=\(Self.instances.count, privacy: .public)
            """)

        let queuePlayer = AVQueuePlayer()
        queuePlayer.isMuted = true
        queuePlayer.preventsDisplaySleepDuringVideoPlayback = false
        queuePlayer.allowsExternalPlayback = false
        let playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: AVPlayerItem(url: url))
        playerLooper.loopingPlayerItems.forEach { addVideoOutput(to: $0) }

        let frameLayer = CALayer()
        frameLayer.contentsGravity = .resizeAspectFill
        frameLayer.masksToBounds = true
        frameLayer.frame = bounds
        frameLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        frameLayer.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(frameLayer)

        player = queuePlayer
        looper = playerLooper
        videoLayer = frameLayer
        queuePlayer.play()

        // Since macOS 14 legacyScreenSaver often skips stopAnimation and keeps old
        // instances alive, so this is the only reliable signal to release the player.
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(screenSaverWillStop),
            name: Notification.Name("com.apple.screensaver.willstop"),
            object: nil
        )
    }

    @objc private func screenSaverWillStop(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.stopPlayback() }
    }

    private func stopPlayback() {
        DistributedNotificationCenter.default().removeObserver(self)
        player?.pause()
        looper?.disableLooping()
        looper = nil
        player?.removeAllItems()
        player = nil
        videoLayer?.contents = nil
        videoLayer?.removeFromSuperlayer()
        videoLayer = nil
        currentFrame = nil
    }
}
