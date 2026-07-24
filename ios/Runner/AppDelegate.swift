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

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
