import Flutter
import UIKit
import AVFAudio
import MediaPlayer

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var lastArtUri: String = ""
  private var cachedArtwork: MPMediaItemArtwork?
  private var nowPlayingChannel: FlutterMethodChannel?
  private var isPlaybackActive: Bool = false
  private var wasPlayingBeforeInterruption: Bool = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.playback, mode: .default, policy: .longFormAudio)
      try session.setActive(true)
    } catch {}

    UIApplication.shared.beginReceivingRemoteControlEvents()
    setupAudioObservers()

    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    DispatchQueue.main.async {
      if let controller = self.window?.rootViewController as? FlutterViewController {
        self.setupNowPlayingChannel(messenger: controller.binaryMessenger)
      }
    }

    return result
  }

  // MARK: - Audio Session Observers

  private func setupAudioObservers() {
    let nc = NotificationCenter.default
    nc.addObserver(self, selector: #selector(handleInterruption(_:)),
                   name: AVAudioSession.interruptionNotification, object: nil)
    nc.addObserver(self, selector: #selector(handleRouteChange(_:)),
                   name: AVAudioSession.routeChangeNotification, object: nil)
    nc.addObserver(self, selector: #selector(handleMediaServicesReset(_:)),
                   name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
    nc.addObserver(self, selector: #selector(handleSilenceSecondaryAudio(_:)),
                   name: AVAudioSession.silenceSecondaryAudioHintNotification, object: nil)
  }

  private func sendEvent(_ event: String, reason: String, extra: [String: Any] = [:]) {
    DispatchQueue.main.async {
      var arguments = extra
      arguments["event"] = event
      arguments["reason"] = reason
      self.nowPlayingChannel?.invokeMethod("audioEvent", arguments: arguments)
    }
  }

  @objc private func handleInterruption(_ notification: Notification) {
    guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

    switch type {
    case .began:
      wasPlayingBeforeInterruption = isPlaybackActive
      sendEvent("pause", reason: "interruption", extra: [
        "wasPlaying": wasPlayingBeforeInterruption
      ])

    case .ended:
      try? AVAudioSession.sharedInstance().setActive(true)
      let optionsValue = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
      let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
      let shouldResume = options.contains(.shouldResume) && wasPlayingBeforeInterruption
      wasPlayingBeforeInterruption = false
      if shouldResume {
        sendEvent("resume", reason: "interruption")
      }

    @unknown default: break
    }
  }

  @objc private func handleRouteChange(_ notification: Notification) {
    guard let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
          let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

    let session = AVAudioSession.sharedInstance()

    switch reason {
    case .oldDeviceUnavailable:
      if let previousRoute = notification.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription {
        let hadExternalOutput = previousRoute.outputs.contains { output in
          [.headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .carAudio].contains(output.portType)
        }
        let nowSpeaker = session.currentRoute.outputs.contains { $0.portType == .builtInSpeaker }
        if hadExternalOutput && nowSpeaker {
          sendEvent("pause", reason: "routeDisconnected")
        }
      }

    case .newDeviceAvailable:
      break

    case .override:
      sendEvent("pause", reason: "siriOverride")

    case .categoryChange:
      break

    default: break
    }
  }

  @objc private func handleMediaServicesReset(_ notification: Notification) {
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .default, policy: .longFormAudio)
      try session.setActive(true)
    } catch {}
  }

  @objc private func handleSilenceSecondaryAudio(_ notification: Notification) {
    guard let typeValue = notification.userInfo?[AVAudioSessionSilenceSecondaryAudioHintTypeKey] as? UInt,
          let type = AVAudioSession.SilenceSecondaryAudioHintType(rawValue: typeValue) else { return }

    switch type {
    case .begin:
      sendEvent("pause", reason: "secondaryAudio")
    case .end:
      break
    @unknown default: break
    }
  }

  private func setupNowPlayingChannel(messenger: FlutterBinaryMessenger) {
    guard nowPlayingChannel == nil else { return }
    let channel = FlutterMethodChannel(
      name: "com.sandian.music/nowplaying",
      binaryMessenger: messenger
    )
    nowPlayingChannel = channel
    channel.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else { result(nil); return }
      if call.method == "update", let args = call.arguments as? [String: Any] {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        var artworkToLoad: String?
        if let title = args["title"] as? String, !title.isEmpty {
          info[MPMediaItemPropertyTitle] = title
        }
        if let artist = args["artist"] as? String, !artist.isEmpty {
          info[MPMediaItemPropertyArtist] = artist
        }
        if let album = args["album"] as? String, !album.isEmpty {
          info[MPMediaItemPropertyAlbumTitle] = album
        }
        if let duration = args["duration"] as? Double, duration > 0 {
          info[MPMediaItemPropertyPlaybackDuration] = NSNumber(value: duration)
        }
        if let elapsed = args["elapsedTime"] as? Double {
          info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = NSNumber(value: elapsed)
        }
        let playbackRate = (args["playbackRate"] as? Double) ?? 1.0
        self.isPlaybackActive = playbackRate > 0
        info[MPNowPlayingInfoPropertyPlaybackRate] = playbackRate

        let artUri = (args["artUri"] as? String) ?? ""
        if artUri != self.lastArtUri {
          self.lastArtUri = artUri
          self.cachedArtwork = nil
          info.removeValue(forKey: MPMediaItemPropertyArtwork)
          if !artUri.isEmpty {
            artworkToLoad = artUri
          }
        } else if let artwork = self.cachedArtwork {
          info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        if let artworkToLoad = artworkToLoad {
          self.loadArtwork(from: artworkToLoad)
        }
        result(nil)
      }
    }
  }

  private func loadArtwork(from urlString: String) {
    if urlString.hasPrefix("file://") || urlString.hasPrefix("/") {
      let path = urlString.hasPrefix("file://")
        ? (URL(string: urlString)?.path ?? String(urlString.dropFirst(7)))
        : urlString
      guard let data = FileManager.default.contents(atPath: path),
            let image = UIImage(data: data) else { return }
      let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
      DispatchQueue.main.async {
        guard self.lastArtUri == urlString else { return }
        self.cachedArtwork = artwork
        if var info = MPNowPlayingInfoCenter.default().nowPlayingInfo {
          info[MPMediaItemPropertyArtwork] = artwork
          MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
      }
      return
    }
    guard let url = URL(string: urlString) else { return }
    var request = URLRequest(url: url)
    request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
    URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
      guard let self = self, let data = data, !data.isEmpty,
            let image = UIImage(data: data) else { return }
      let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
      DispatchQueue.main.async {
        guard self.lastArtUri == urlString else { return }
        self.cachedArtwork = artwork
        if var info = MPNowPlayingInfoCenter.default().nowPlayingInfo {
          info[MPMediaItemPropertyArtwork] = artwork
          MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
      }
    }.resume()
  }
}
