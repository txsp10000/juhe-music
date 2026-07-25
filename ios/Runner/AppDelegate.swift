import Flutter
import UIKit
import AVFAudio
import AVFoundation
import MediaPlayer

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    AVPlayerPreciseSeekSwizzle.activate()
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

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "com.miaomiao.music/nowplaying",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { (call, result) in
        if call.method == "update", let args = call.arguments as? [String: Any] {
          var info: [String: Any] = [:]
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
          MPNowPlayingInfoCenter.default().nowPlayingInfo = info
          result(nil)
        }
      }
    }

    return result
  }
}

class AVPlayerPreciseSeekSwizzle {
  static func activate() {
    let originalSelector = NSSelectorFromString("seekToTime:completionHandler:")
    let swizzledSelector = #selector(AVPlayer.preciseSeekToTime(_:completionHandler:))
    guard let originalMethod = class_getInstanceMethod(AVPlayer.self, originalSelector),
          let swizzledMethod = class_getInstanceMethod(AVPlayer.self, swizzledSelector) else {
      return
    }
    method_exchangeImplementations(originalMethod, swizzledMethod)
  }
}

extension AVPlayer {
  @objc func preciseSeekToTime(_ time: CMTime, completionHandler: @escaping (Bool) -> Void) {
    self.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero, completionHandler: completionHandler)
  }
}
