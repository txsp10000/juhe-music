import Flutter
import UIKit
import AVFAudio
import MediaPlayer

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // 配置音频会话：后台播放 + CarPlay
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.playback, mode: .default, policy: .longFormAudio)
      try session.setActive(true)
    } catch {
      print("AVAudioSession 配置失败: \(error)")
    }

    // 注册远程控制（锁屏 / CarPlay 控制中心）
    UIApplication.shared.beginReceivingRemoteControlEvents()

    // Flutter 引擎初始化
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    // CarPlay / 锁屏 Now Playing 信息更新通道
    // audio_service 的 updateMediaItem 在播放前调用，缺少 elapsedTime/playbackRate
    // 导致 CarPlay "播放中" 不显示，这里直接接管 MPNowPlayingInfoCenter 全量更新
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
