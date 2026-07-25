import Flutter
import UIKit
import AVFAudio
import MediaPlayer
import AVFoundation

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

    // 注册平台通道：MP3 → WAV 转换
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "com.miaomiao.music/converter",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] (call, result) in
        if call.method == "mp3ToWav" {
          guard let args = call.arguments as? [String: String],
                let inputPath = args["input"],
                let outputPath = args["output"] else {
            result(FlutterError(code: "INVALID_ARGS", message: "需要 input 和 output 路径", details: nil))
            return
          }
          self?.convertMp3ToWav(inputPath: inputPath, outputPath: outputPath, result: result)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// 使用 AVAssetExportSession 将 MP3 转为 WAV
  private func convertMp3ToWav(inputPath: String, outputPath: String, result: @escaping FlutterResult) {
    let inputURL = URL(fileURLWithPath: inputPath)
    let outputURL = URL(fileURLWithPath: outputPath)

    // 删除旧的输出文件
    try? FileManager.default.removeItem(at: outputURL)

    let asset = AVAsset(url: inputURL)
    guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
      result(FlutterError(code: "EXPORT_FAILED", message: "无法创建导出会话", details: nil))
      return
    }

    exportSession.outputURL = outputURL
    exportSession.outputFileType = .wav
    exportSession.exportAsynchronously {
      DispatchQueue.main.async {
        switch exportSession.status {
        case .completed:
          result(outputPath)
        case .failed, .cancelled:
          result(FlutterError(
            code: "EXPORT_FAILED",
            message: exportSession.error?.localizedDescription ?? "导出失败",
            details: nil
          ))
        default:
          result(FlutterError(code: "EXPORT_FAILED", message: "未知导出状态", details: nil))
        }
      }
    }
  }
}
