import AVFoundation
import ScreenSaver

// make-saver.sh renames this class per saver: legacyScreenSaver loads every
// installed saver into one process, so ObjC class names must not collide.
@objc(VideoSaverView)
final class VideoSaverView: ScreenSaverView {
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var playerLayer: AVPlayerLayer?

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        // Nothing to draw per frame; AVPlayerLayer renders on its own.
        animationTimeInterval = 3600
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
        playerLayer?.frame = bounds
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        playerLayer?.contentsScale = window?.backingScaleFactor ?? 2
    }

    override func draw(_ rect: NSRect) {
        NSColor.black.setFill()
        rect.fill()
    }

    override func animateOneFrame() {}

    override var hasConfigureSheet: Bool { false }
    override var configureSheet: NSWindow? { nil }

    private var videoURL: URL? {
        let bundle = Bundle(for: Self.self)
        return ["mp4", "mov", "m4v"].lazy.compactMap { bundle.url(forResource: "video", withExtension: $0) }.first
    }

    private func startPlayback() {
        guard player == nil, let url = videoURL else { return }

        let item = AVPlayerItem(asset: AVURLAsset(url: url))
        let queuePlayer = AVQueuePlayer()
        queuePlayer.isMuted = true
        queuePlayer.preventsDisplaySleepDuringVideoPlayback = false
        queuePlayer.allowsExternalPlayback = false
        looper = AVPlayerLooper(player: queuePlayer, templateItem: item)

        let videoLayer = AVPlayerLayer(player: queuePlayer)
        videoLayer.videoGravity = .resizeAspectFill
        videoLayer.frame = bounds
        videoLayer.contentsScale = window?.backingScaleFactor ?? 2
        videoLayer.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(videoLayer)

        player = queuePlayer
        playerLayer = videoLayer
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
        playerLayer?.player = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
    }
}
