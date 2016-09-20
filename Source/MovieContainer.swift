import UIKit
import AVFoundation
import AVKit

#if os(iOS)
    import Photos
#endif

protocol MovieContainerDelegate: class {
    func movieContainerDidStartedPlayingMovie(_ movieContainer: MovieContainer)
    func movieContainer(_ movieContainer: MovieContainer, didRequestToUpdateProgressBar duration: Double, currentTime: Double)
}

class MovieContainer: UIView {
    weak var viewDelegate: MovieContainerDelegate?

    private lazy var playerLayer: AVPlayerLayer = {
        let playerLayer = AVPlayerLayer()
        playerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill

        return playerLayer
    }()

    var image: UIImage?

    private lazy var loadingIndicator: UIActivityIndicatorView = {
        let view = UIActivityIndicatorView(activityIndicatorStyle: .whiteLarge)
        view.autoresizingMask = [.flexibleRightMargin, .flexibleLeftMargin, .flexibleBottomMargin, .flexibleTopMargin]

        return view
    }()

    private lazy var loadingIndicatorBackground: UIImageView = {
        let view = UIImageView(image: UIImage(named: "dark-circle")!)
        view.alpha = 0

        return view
    }()

    private var shouldRegisterForNotifications = true
    private var player: AVPlayer?

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.isUserInteractionEnabled = false
        self.layer.addSublayer(self.playerLayer)
        self.addSubview(self.loadingIndicatorBackground)
        self.addSubview(self.loadingIndicator)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        guard let image = self.image else { return }
        self.frame = image.centeredFrame()

        var playerLayerFrame = image.centeredFrame()
        playerLayerFrame.origin.x = 0
        playerLayerFrame.origin.y = 0
        self.playerLayer.frame = playerLayerFrame

        let loadingBackgroundHeight = self.loadingIndicatorBackground.frame.size.height
        let loadingBackgroundWidth = self.loadingIndicatorBackground.frame.size.width
        self.loadingIndicatorBackground.frame = CGRect(x: (self.frame.size.width - loadingBackgroundWidth) / 2, y: (self.frame.size.height - loadingBackgroundHeight) / 2, width: loadingBackgroundWidth, height: loadingBackgroundHeight)

        let loadingHeight = self.loadingIndicator.frame.size.height
        let loadingWidth = self.loadingIndicator.frame.size.width
        self.loadingIndicator.frame = CGRect(x: (self.frame.size.width - loadingWidth) / 2, y: (self.frame.size.height - loadingHeight) / 2, width: loadingWidth, height: loadingHeight)
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard let player = object as? AVPlayer else { return }

        if player.status == .readyToPlay {
            self.stopPlayerAndRemoveObserverIfNecessary()
            player.play()
            self.viewDelegate?.movieContainerDidStartedPlayingMovie(self)
        }
    }

    func stopPlayerAndRemoveObserverIfNecessary() {
        self.loadingIndicator.stopAnimating()
        self.loadingIndicatorBackground.alpha = 0
        self.player?.pause()

        if self.shouldRegisterForNotifications == false {
            self.player?.removeObserver(self, forKeyPath: "status")
            self.shouldRegisterForNotifications = true
        }
    }

    var timeObserver: Any?

    func start(_ viewerItem: ViewerItem) {
        if let url = viewerItem.url {
            let steamingURL = URL(string: url)!
            self.player = AVPlayer(url: steamingURL)
            self.playerLayer.player = self.player
            self.start()
        } else if viewerItem.isLocal == true {
            #if os(iOS)
                let result = PHAsset.fetchAssets(withLocalIdentifiers: [viewerItem.id], options: nil)
                guard let asset = result.firstObject else { fatalError("Couldn't get asset for id: \(viewerItem.id)") }
                let requestOptions = PHVideoRequestOptions()
                requestOptions.isNetworkAccessAllowed = true
                requestOptions.version = .original
                PHImageManager.default().requestPlayerItem(forVideo: asset, options: requestOptions) { playerItem, info in
                    guard let playerItem = playerItem else { fatalError("Player item was nil: \(info)") }
                    DispatchQueue.main.async(execute: {
                        self.player = AVPlayer(playerItem: playerItem)
                        guard let player = self.player else { fatalError("Couldn't create player from playerItem: \(playerItem)") }
                        player.rate = Float(playerItem.preferredPeakBitRate)
                        self.playerLayer.player = player
                        self.start()

                        if let timeObserver = self.timeObserver {
                            player.removeTimeObserver(timeObserver)
                        }

                        if asset.mediaSubtypes == .videoHighFrameRate {
                            let interval = CMTime(seconds: 1.0, preferredTimescale: Int32(NSEC_PER_SEC))
                            self.timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: nil) { time in
                                let currentTime = CMTimeGetSeconds(player.currentTime())
                                if currentTime >= 2 {
                                    if player.rate != 0.000001 {
                                        player.rate = 0.000001
                                    }
                                } else if player.rate != 1.0 {
                                    player.rate = 1.0
                                }
                            }
                        }
                    })
                }
            #endif
        }
    }

    func start() {
        guard let player = self.player, let currentItem = player.currentItem else { return }

        let interval = CMTime(seconds: 1/60, preferredTimescale: Int32(NSEC_PER_SEC))
        player.addPeriodicTimeObserver(forInterval: interval, queue: nil) {
            time in

            let duration = CMTimeGetSeconds(currentItem.asset.duration)
            let currentTime = CMTimeGetSeconds(player.currentTime())

            self.updateProgressBar(forDuration: duration, currentTime: currentTime)
        }

        self.playerLayer.isHidden = false

        if self.shouldRegisterForNotifications {
            guard let player = self.player else { fatalError("No player item was found") }

            if player.status == .unknown {
                self.loadingIndicator.startAnimating()
                self.loadingIndicatorBackground.alpha = 1
            }

            player.addObserver(self, forKeyPath: "status", options: [], context: nil)
            self.shouldRegisterForNotifications = false
        }
    }

    func stop() {
        self.playerLayer.isHidden = true
        self.player?.pause()
        self.player?.seek(to: kCMTimeZero)
        self.playerLayer.player = nil
        if let timeObserver = self.timeObserver {
            self.player?.removeTimeObserver(timeObserver)
        }
    }

    func play() {
        self.player?.play()
        self.playerLayer.isHidden = false
    }

    func pause() {
        self.player?.pause()
    }

    func isPlaying() -> Bool {
        if let player = self.player {
            let isPlaying = player.rate != 0 && player.error == nil
            return isPlaying
        }

        return false
    }

    func updateProgressBar(forDuration duration: Double, currentTime: Double) {
        self.viewDelegate?.movieContainer(self, didRequestToUpdateProgressBar: duration, currentTime: currentTime)
    }
}
