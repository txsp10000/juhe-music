import Flutter
import UIKit
import AVFAudio
import MediaPlayer

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var lastArtUri: String = ""
  private var cachedArtwork: MPMediaItemArtwork?
  private var nowPlayingChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.playback, mode: .default, policy: .longFormAudio)
      try session.setActive(true)
    } catch {
      print("AVAudioSession 配置失败: \(error)")
    }

    UIApplication.shared.beginReceivingRemoteControlEvents()

    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    setupNowPlayingChannel()

    return result
  }

  static func resolveBinaryMessenger() -> FlutterBinaryMessenger? {
    if let appDelegate = UIApplication.shared.delegate as? FlutterAppDelegate,
       let controller = appDelegate.window?.rootViewController as? FlutterViewController {
      return controller.binaryMessenger
    }
    for scene in UIApplication.shared.connectedScenes {
      guard let windowScene = scene as? UIWindowScene else { continue }
      for window in windowScene.windows {
        if let flutterVC = window.rootViewController as? FlutterViewController {
          return flutterVC.binaryMessenger
        }
      }
    }
    return nil
  }

  private func setupNowPlayingChannel() {
    guard let messenger = AppDelegate.resolveBinaryMessenger() else {
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
        self?.setupNowPlayingChannel()
      }
      return
    }

    if nowPlayingChannel == nil {
      let channel = FlutterMethodChannel(
        name: "com.miaomiao.music/nowplaying",
        binaryMessenger: messenger
      )
      nowPlayingChannel = channel
      channel.setMethodCallHandler { [weak self] (call, result) in
        guard let self = self else { result(nil); return }
        if call.method == "update", let args = call.arguments as? [String: Any] {
          var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
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
          info[MPNowPlayingInfoPropertyPlaybackRate] = (args["playbackRate"] as? Double) ?? 1.0

          if let artwork = self.cachedArtwork {
            info[MPMediaItemPropertyArtwork] = artwork
          }
          MPNowPlayingInfoCenter.default().nowPlayingInfo = info

          if let artUri = args["artUri"] as? String, !artUri.isEmpty, artUri != self.lastArtUri {
            self.lastArtUri = artUri
            self.loadArtwork(from: artUri)
          }
          result(nil)
        }
      }
    }
  }

  private func loadArtwork(from urlString: String) {
    if urlString.hasPrefix("file://") || urlString.hasPrefix("/") {
      let path = urlString.hasPrefix("file://")
        ? String(urlString.dropFirst(7))
        : urlString
      guard let data = FileManager.default.contents(atPath: path),
            let image = UIImage(data: data) else { return }
      let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
      DispatchQueue.main.async {
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
        self.cachedArtwork = artwork
        if var info = MPNowPlayingInfoCenter.default().nowPlayingInfo {
          info[MPMediaItemPropertyArtwork] = artwork
          MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        }
      }
    }.resume()
  }
}
