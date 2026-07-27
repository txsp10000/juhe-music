import Flutter
import UIKit
import AVFAudio
import MediaPlayer

@main
@objc class AppDelegate: FlutterAppDelegate {
  static var flutterEngine: FlutterEngine?

  private var lastArtUri: String = ""
  private var cachedArtwork: MPMediaItemArtwork?
  private var nowPlayingChannel: FlutterMethodChannel?
  private var diagChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    DiagLog.log("App", "didFinishLaunching 开始")

    let engine = FlutterEngine(name: "miaomiao.main")
    let ran = engine.run()
    DiagLog.log("App", "engine.run() = \(ran)")
    GeneratedPluginRegistrant.register(with: engine)
    AppDelegate.flutterEngine = engine
    DiagLog.log("App", "插件已注册, engine 就绪")

    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.playback, mode: .default, policy: .longFormAudio)
      try session.setActive(true)
      DiagLog.log("App", "AVAudioSession 已激活")
    } catch {
      DiagLog.log("App", "AVAudioSession 配置失败: \(error)")
    }

    UIApplication.shared.beginReceivingRemoteControlEvents()

    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    setupNowPlayingChannel()

    return result
  }

  static func resolveBinaryMessenger() -> FlutterBinaryMessenger? {
    if let engine = AppDelegate.flutterEngine {
      return engine.binaryMessenger
    }
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
      DiagLog.log("App", "nowplaying: messenger 未就绪, 1 秒后重试")
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
        self?.setupNowPlayingChannel()
      }
      return
    }
    DiagLog.log("App", "nowplaying: messenger 已获取")

    setupDiagChannel(messenger)

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

  private func setupDiagChannel(_ messenger: FlutterBinaryMessenger) {
    guard diagChannel == nil else { return }
    let channel = FlutterMethodChannel(
      name: "com.miaomiao.music/diag",
      binaryMessenger: messenger
    )
    diagChannel = channel
    channel.setMethodCallHandler { (call, result) in
      switch call.method {
      case "read":
        result(DiagLog.readAll())
      case "clear":
        DiagLog.clear()
        result(nil)
      case "path":
        result(DiagLog.logPath)
      case "write":
        if let args = call.arguments as? [String: Any],
           let msg = args["message"] as? String {
          DiagLog.log(args["tag"] as? String ?? "Dart", msg)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
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

@available(iOS 13.0, *)
@objc class MainSceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    DiagLog.log("手机场景", "willConnectTo 触发, role=\(session.role.rawValue)")
    guard let windowScene = scene as? UIWindowScene else {
      DiagLog.log("手机场景", "错误: scene 不是 UIWindowScene, 实际=\(type(of: scene))")
      return
    }

    if AppDelegate.flutterEngine == nil {
      DiagLog.log("手机场景", "警告: 共享 engine 为空, 走兜底新建")
    }

    let engine = AppDelegate.flutterEngine ?? {
      let e = FlutterEngine(name: "miaomiao.fallback")
      e.run()
      GeneratedPluginRegistrant.register(with: e)
      AppDelegate.flutterEngine = e
      return e
    }()

    let controller = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
    let win = UIWindow(windowScene: windowScene)
    win.rootViewController = controller
    self.window = win
    win.makeKeyAndVisible()
    DiagLog.log("手机场景", "window 已创建并可见, rootVC=\(type(of: controller))")
  }
}
