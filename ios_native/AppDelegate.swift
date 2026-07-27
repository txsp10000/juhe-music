import Flutter
import UIKit
import AVFAudio
import MediaPlayer

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var lastArtUri: String = ""
  private var cachedArtwork: MPMediaItemArtwork?
  private var nowPlayingChannel: FlutterMethodChannel?
  private var wasInterrupted: Bool = false
  private var wasOverriddenBySystem: Bool = false
  private var pausedForResignActive: Bool = false

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

    nc.addObserver(self,
                   selector: #selector(handleInterruption(_:)),
                   name: AVAudioSession.interruptionNotification,
                   object: nil)

    nc.addObserver(self,
                   selector: #selector(handleRouteChange(_:)),
                   name: AVAudioSession.routeChangeNotification,
                   object: nil)

    nc.addObserver(self,
                   selector: #selector(handleMediaServicesReset(_:)),
                   name: AVAudioSession.mediaServicesWereResetNotification,
                   object: nil)

    nc.addObserver(self,
                   selector: #selector(handleSilenceSecondaryAudio(_:)),
                   name: AVAudioSession.silenceSecondaryAudioHintNotification,
                   object: nil)

    // Phone 端 Siri / Control Center 兜底：App 进入 Inactive 但非后台 → 暂停
    nc.addObserver(self,
                   selector: #selector(handleResignActive),
                   name: UIApplication.willResignActiveNotification,
                   object: nil)
    nc.addObserver(self,
                   selector: #selector(handleBecomeActive),
                   name: UIApplication.didBecomeActiveNotification,
                   object: nil)
  }

  /// Siri / 通话等音频中断处理
  @objc private func handleInterruption(_ notification: Notification) {
    guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
      return
    }

    switch type {
    case .began:
      // 中断开始（Siri 唤醒 / 来电），通知 Flutter 暂停
      wasInterrupted = true
      DispatchQueue.main.async {
        self.nowPlayingChannel?.invokeMethod("audioInterruption", arguments: ["active": true])
      }

    case .ended:
      wasInterrupted = false
      guard let optionsValue = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt else {
        // 无恢复选项，不做处理
        return
      }
      let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
      if options.contains(.shouldResume) {
        // 中断结束（Siri 关闭 / 通话挂断），重新激活音频并恢复播放
        let session = AVAudioSession.sharedInstance()
        do {
          try session.setActive(true)
        } catch {
          // 激活失败，延迟重试一次
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            try? AVAudioSession.sharedInstance().setActive(true)
          }
        }
        DispatchQueue.main.async {
          self.nowPlayingChannel?.invokeMethod("audioInterruption", arguments: ["active": false])
        }
      }

    @unknown default:
      break
    }
  }

  /// 蓝牙 / CarPlay / 耳机等音频路由切换处理
  @objc private func handleRouteChange(_ notification: Notification) {
    guard let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
          let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
      return
    }

    let session = AVAudioSession.sharedInstance()

    switch reason {
    case .oldDeviceUnavailable:
      // 设备断开（蓝牙耳机掉电 / 车载熄火等）
      if let previousRoute = notification.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription {
        let wasHeadphonesOrBluetooth = previousRoute.outputs.contains { output in
          output.portType == .headphones ||
          output.portType == .bluetoothA2DP ||
          output.portType == .bluetoothHFP ||
          output.portType == .bluetoothLE ||
          output.portType == .carAudio
        }
        let isSpeaker = session.currentRoute.outputs.contains { $0.portType == .builtInSpeaker }
        if wasHeadphonesOrBluetooth && isSpeaker {
          // 外设断开切到扬声器，暂停播放避免公放
          DispatchQueue.main.async {
            self.nowPlayingChannel?.invokeMethod("audioRouteDisconnected", arguments: nil)
          }
        }
      }

    case .newDeviceAvailable:
      // 新设备接入（连接蓝牙 / CarPlay / 插耳机）
      let isExternalDevice = session.currentRoute.outputs.contains { output in
        output.portType == .headphones ||
        output.portType == .bluetoothA2DP ||
        output.portType == .bluetoothHFP ||
        output.portType == .bluetoothLE ||
        output.portType == .carAudio
      }
      if isExternalDevice {
        DispatchQueue.main.async {
          self.nowPlayingChannel?.invokeMethod("audioRouteConnected", arguments: nil)
        }
      }

    case .override:
      // Siri / 系统覆盖音频通道（CarPlay 场景 Siri 走此路径，非 interruption）
      if wasOverriddenBySystem {
        // 覆盖结束，重新激活并恢复
        wasOverriddenBySystem = false
        try? session.setActive(true)
        DispatchQueue.main.async {
          self.nowPlayingChannel?.invokeMethod("audioInterruption", arguments: ["active": false])
        }
      } else {
        // 覆盖开始（Siri 启动），暂停播放
        wasOverriddenBySystem = true
        DispatchQueue.main.async {
          self.nowPlayingChannel?.invokeMethod("audioInterruption", arguments: ["active": true])
        }
      }

    case .categoryChange:
      // 音频类别变更（某些 iOS 版本 Siri 走此路径）
      if wasOverriddenBySystem {
        wasOverriddenBySystem = false
        try? session.setActive(true)
        DispatchQueue.main.async {
          self.nowPlayingChannel?.invokeMethod("audioInterruption", arguments: ["active": false])
        }
      } else {
        wasOverriddenBySystem = true
        DispatchQueue.main.async {
          self.nowPlayingChannel?.invokeMethod("audioInterruption", arguments: ["active": true])
        }
      }

    default:
      break
    }
  }

  /// 媒体服务重置处理
  @objc private func handleMediaServicesReset(_ notification: Notification) {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.playback, mode: .default, policy: .longFormAudio)
      try session.setActive(true)
    } catch {}
    DispatchQueue.main.async {
      self.nowPlayingChannel?.invokeMethod("audioInterruption", arguments: ["active": false])
    }
  }

  /// 其他 App 播放音频时的静音提示（导航语音 / 其他音乐 App 等）
  @objc private func handleSilenceSecondaryAudio(_ notification: Notification) {
    guard let typeValue = notification.userInfo?[AVAudioSessionSilenceSecondaryAudioHintTypeKey] as? UInt,
          let type = AVAudioSession.SilenceSecondaryAudioHintType(rawValue: typeValue) else {
      return
    }

    switch type {
    case .begin:
      DispatchQueue.main.async {
        self.nowPlayingChannel?.invokeMethod("audioInterruption", arguments: ["active": true])
      }

    case .end:
      DispatchQueue.main.async {
        self.nowPlayingChannel?.invokeMethod("audioInterruption", arguments: ["active": false])
      }

    @unknown default:
      break
    }
  }

  /// Phone 端 Siri 呼出 → App ResignActive，暂停播放
  @objc private func handleResignActive() {
    // 延迟检查：如果 App 没有进入后台（即未触发 didEnterBackground），说明是 Siri / Control Center
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
      guard let self = self else { return }
      // 仍在 Inactive 或 Active 状态且未进后台 → Siri 或控制中心
      let state = UIApplication.shared.applicationState
      if state != .background {
        self.pausedForResignActive = true
        self.nowPlayingChannel?.invokeMethod("audioInterruption", arguments: ["active": true])
      }
    }
  }

  /// Phone 端 Siri 退出 → App BecomeActive，恢复播放
  @objc private func handleBecomeActive() {
    guard pausedForResignActive else { return }
    pausedForResignActive = false
    let session = AVAudioSession.sharedInstance()
    try? session.setActive(true)
    DispatchQueue.main.async {
      self.nowPlayingChannel?.invokeMethod("audioInterruption", arguments: ["active": false])
    }
  }

  private func setupNowPlayingChannel(messenger: FlutterBinaryMessenger) {
    guard nowPlayingChannel == nil else { return }
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
