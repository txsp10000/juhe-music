import UIKit
import CarPlay
import MediaPlayer
import Flutter

@available(iOS 14.0, *)
@objc class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
  var interfaceController: CPInterfaceController?
  private var methodChannel: FlutterMethodChannel?
  private var retryTimer: Timer?
  private var probeCount = 0
  private let maxProbes = 40
  private var rootList: CPListTemplate?
  private var dartReady = false
  private var refreshScheduled = false
  private var sessionConfig: CPSessionConfiguration?

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didConnect interfaceController: CPInterfaceController
  ) {
    DiagLog.log("车机", "★ didConnect 触发, CarPlay 场景已连接")
    DiagLog.log("车机", "场景状态=\(templateApplicationScene.activationState.rawValue)")
    sessionConfig = CPSessionConfiguration(delegate: self)
    if let cfg = sessionConfig {
      DiagLog.log("车机", "限制=\(cfg.limitedUserInterfaces.rawValue) 内容样式=\(cfg.contentStyle.rawValue)")
    }
    self.interfaceController = interfaceController
    probeCount = 0
    dartReady = false
    showRootTemplate()
  }

  func sceneDidBecomeActive(_ scene: UIScene) {
    DiagLog.log("车机", "sceneDidBecomeActive, 通道=\(methodChannel == nil ? "无" : "有")")
    if methodChannel == nil {
      setupMethodChannel()
    } else {
      scheduleRefresh()
    }
  }

  func sceneWillEnterForeground(_ scene: UIScene) {
    DiagLog.log("车机", "sceneWillEnterForeground")
  }

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didDisconnect interfaceController: CPInterfaceController
  ) {
    DiagLog.log("车机", "didDisconnect, 场景已断开")
    self.interfaceController = nil
    self.methodChannel = nil
    self.rootList = nil
    dartReady = false
    retryTimer?.invalidate()
    retryTimer = nil
  }

  private func setupMethodChannel() {
    guard let binaryMessenger = AppDelegate.resolveBinaryMessenger() else {
      DiagLog.log("车机", "messenger 未就绪, 启动 2 秒重试")
      startRetryTimer()
      return
    }

    retryTimer?.invalidate()
    retryTimer = nil

    let channel = FlutterMethodChannel(
      name: "com.miaomiao.music/carplay",
      binaryMessenger: binaryMessenger
    )
    methodChannel = channel
    DiagLog.log("车机", "通道已建立 com.miaomiao.music/carplay")

    channel.setMethodCallHandler { [weak self] call, result in
      if call.method == "dartReady" {
        DiagLog.log("车机", "收到 Dart 就绪通知")
        self?.dartReady = true
        self?.scheduleRefresh()
      }
      result(nil)
    }

    probeDartReady()
  }

  private func probeDartReady() {
    if dartReady { return }
    guard let channel = methodChannel else { return }
    guard probeCount < maxProbes else {
      DiagLog.log("车机", "探测超时, Dart 侧始终未就绪")
      return
    }
    probeCount += 1

    channel.invokeMethod("ping", arguments: nil) { [weak self] reply in
      guard let self = self else { return }
      if self.dartReady { return }
      guard (reply as? String) == "ok" else {
        DiagLog.log("车机", "ping 第 \(self.probeCount) 次未就绪, 0.5 秒后重试")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
          self.probeDartReady()
        }
        return
      }
      DiagLog.log("车机", "ping 成功, Dart 已就绪")
      self.dartReady = true
      self.scheduleRefresh()
    }
  }

  private func scheduleRefresh() {
    if refreshScheduled { return }
    refreshScheduled = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
      self?.refreshScheduled = false
      self?.refreshAll()
    }
  }

  private func startRetryTimer() {
    retryTimer?.invalidate()
    retryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
      guard let self = self else { timer.invalidate(); return }
      self.setupMethodChannel()
    }
  }



  private func showRootTemplate() {
    let loading = CPListItem(text: "加载中...", detailText: "正在读取手机数据")
    let template = CPListTemplate(
      title: "苗苗music",
      sections: [CPListSection(items: [loading])]
    )
    rootList = template
    DiagLog.log("车机", "准备 setRootTemplate (CPListTemplate 单模板)")

    guard let intf = interfaceController else {
      DiagLog.log("车机", "错误: interfaceController 为空, 无法设置模板")
      return
    }

    intf.setRootTemplate(template, animated: false) { success, error in
      if let error = error {
        DiagLog.log("车机", "setRootTemplate 回调: 失败 \(error.localizedDescription)")
      } else {
        DiagLog.log("车机", "setRootTemplate 回调: 成功=\(success)")
      }
    }
    DiagLog.log("车机", "setRootTemplate 已调用, rootTemplate=\(String(describing: type(of: intf.rootTemplate)))")
    DiagLog.log("车机", "模板栈深度=\(intf.templates.count)")
    DiagLog.log("车机", "host 上限: 分区=\(CPListTemplate.maximumSectionCount) 条目=\(CPListTemplate.maximumItemCount)")

    setupMethodChannel()
  }

  // MARK: - Data Loading
  private var isRootAttached: Bool {
    return interfaceController?.rootTemplate is CPListTemplate
  }

  private static func describe(_ value: Any?) -> String {
    guard let v = value else { return "nil (Dart 未响应或未注册 handler)" }
    if let err = v as? FlutterError {
      return "FlutterError(\(err.code))"
    }
    if let arr = v as? [Any] {
      return "数组 空=\(arr.isEmpty) 条数=\(arr.count)"
    }
    return "类型=\(type(of: v)) 值=\(v)"
  }

  private func applySections(_ sections: [CPListSection]) {
    guard let template = rootList else {
      DiagLog.log("车机", "rootList 为空, 无法写入")
      return
    }
    guard isRootAttached else {
      DiagLog.log("车机", "根模板未挂载, 跳过 updateSections")
      return
    }
    template.updateSections(sections)
    let total = sections.reduce(0) { $0 + $1.items.count }
    DiagLog.log("车机", "已写入 \(sections.count) 个分区共 \(total) 项")
  }

  private func refreshAll() {
    guard let channel = methodChannel else {
      DiagLog.log("车机", "通道未就绪, 显示等待提示")
      let item = CPListItem(text: "等待手机端连接", detailText: "请在手机上打开苗苗music")
      applySections([CPListSection(items: [item])])
      return
    }

    DiagLog.log("车机", "开始拉取数据")
    channel.invokeMethod("getCurrentSongId", arguments: nil) { [weak self] currentId in
      guard let self = self else { return }
      let songId = currentId as? String
      channel.invokeMethod("getFavorites", arguments: nil) { favResult in
        let favs = favResult as? [[String: Any]] ?? []
        DiagLog.log("车机", "收藏 \(favs.count) 首 (\(Self.describe(favResult)))")
        channel.invokeMethod("getPlaylist", arguments: nil) { listResult in
          let plays = listResult as? [[String: Any]] ?? []
          DiagLog.log("车机", "播放列表 \(plays.count) 首 (\(Self.describe(listResult)))")
          self.buildAndApply(favs: favs, plays: plays, songId: songId)
        }
      }
    }
  }

  private func buildAndApply(favs: [[String: Any]], plays: [[String: Any]], songId: String?) {
    var sections: [CPListSection] = []

    if !plays.isEmpty {
      let items = buildListItems(from: plays, action: "playAtIndex", currentSongId: songId)
      sections.append(CPListSection(items: items, header: "正在播放列表", sectionIndexTitle: nil))
    }

    if !favs.isEmpty {
      let items = buildListItems(from: favs, action: "playFavorite", currentSongId: songId)
      sections.append(CPListSection(items: items, header: "我的收藏", sectionIndexTitle: nil))
    }

    if sections.isEmpty {
      let item = CPListItem(text: "暂无歌曲", detailText: "请先在手机上收藏或播放音乐")
      sections = [CPListSection(items: [item])]
    }

    applySections(sections)
  }

  private func buildListItems(from songs: [[String: Any]], action: String, currentSongId: String? = nil) -> [CPListItem] {
    return songs.enumerated().map { (index, song) in
      let title = song["name"] as? String ?? "未知歌曲"
      let subtitle = song["singer"] as? String ?? "未知歌手"
      let songId = song["id"] as? String ?? ""

      let item = CPListItem(text: title, detailText: subtitle)
      if songId == currentSongId && !songId.isEmpty {
        item.isPlaying = true
      }
      item.handler = { [weak self] _, completion in
        DiagLog.log("车机", "点击第 \(index) 项, 调用 \(action)")
        self?.methodChannel?.invokeMethod(action, arguments: index)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
          if let intf = self?.interfaceController {
            let nowPlaying = CPNowPlayingTemplate.shared
            intf.pushTemplate(nowPlaying, animated: true, completion: nil)
          }
        }
        completion()
      }

      return item
    }
  }
}

@available(iOS 14.0, *)
extension CarPlaySceneDelegate: CPSessionConfigurationDelegate {
  func sessionConfiguration(
    _ sessionConfiguration: CPSessionConfiguration,
    limitedUserInterfacesChanged limitedUserInterfaces: CPLimitableUserInterface
  ) {
    DiagLog.log("车机", "限制变化: \(limitedUserInterfaces.rawValue)")
  }
}

