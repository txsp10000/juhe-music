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

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didConnect interfaceController: CPInterfaceController
  ) {
    DiagLog.log("车机", "★ didConnect 触发, CarPlay 场景已连接")
    self.interfaceController = interfaceController
    showRootTemplate()
  }

  func sceneDidBecomeActive(_ scene: UIScene) {
    DiagLog.log("车机", "sceneDidBecomeActive, 通道=\(methodChannel == nil ? "无" : "有")")
    if methodChannel == nil {
      setupMethodChannel()
    } else {
      refreshAllTabs()
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
        DiagLog.log("车机", "收到 Dart 就绪通知, 立即刷新")
        self?.probeCount = 0
        self?.refreshAllTabs()
      }
      result(nil)
    }

    probeCount = 0
    probeDartReady()
  }

  private func probeDartReady() {
    guard let channel = methodChannel else { return }
    guard probeCount < maxProbes else {
      DiagLog.log("车机", "探测超时, Dart 侧始终未就绪")
      return
    }
    probeCount += 1

    channel.invokeMethod("ping", arguments: nil) { [weak self] reply in
      guard let self = self else { return }
      guard (reply as? String) == "ok" else {
        DiagLog.log("车机", "ping 第 \(self.probeCount) 次未就绪 (\(Self.describe(reply))), 0.5 秒后重试")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
          self.probeDartReady()
        }
        return
      }
      DiagLog.log("车机", "ping 成功, Dart 已就绪")
      self.refreshAllTabs()
    }
  }

  private func startRetryTimer() {
    retryTimer?.invalidate()
    retryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
      guard let self = self else { timer.invalidate(); return }
      self.setupMethodChannel()
    }
  }

  private func refreshAllTabs() {
    guard let tabBar = interfaceController?.rootTemplate as? CPTabBarTemplate else { return }
    for template in tabBar.templates {
      if let listTemplate = template as? CPListTemplate {
        if listTemplate.tabTitle == "播放列表" {
          refreshPlaylist(template: listTemplate)
        } else if listTemplate.tabTitle == "收藏" {
          refreshFavorites(template: listTemplate)
        }
      }
    }
  }

  private func showRootTemplate() {
    let favoritesTab = createFavoritesTab()
    let playlistTab = createPlaylistTab()

    let tabBar = CPTabBarTemplate(templates: [favoritesTab, playlistTab])
    tabBar.delegate = self
    DiagLog.log("车机", "准备 setRootTemplate, 页签数=\(tabBar.templates.count)")

    guard let intf = interfaceController else {
      DiagLog.log("车机", "错误: interfaceController 为空, 无法设置模板")
      return
    }

    intf.setRootTemplate(tabBar, animated: true) { success, error in
      if let error = error {
        DiagLog.log("车机", "setRootTemplate 回调: 失败 \(error.localizedDescription)")
      } else {
        DiagLog.log("车机", "setRootTemplate 回调: 成功=\(success)")
      }
    }

    setupMethodChannel()
  }

  // MARK: - Playlist Tab
  private func createPlaylistTab() -> CPListTemplate {
    let loadingItem = CPListItem(text: "加载中...", detailText: "正在获取播放列表")
    let section = CPListSection(items: [loadingItem])
    let template = CPListTemplate(title: "播放列表", sections: [section])
    template.tabImage = UIImage(systemName: "music.note.list") ?? UIImage()
    template.tabTitle = "播放列表"
    template.emptyViewTitleVariants = ["暂无播放列表"]
    template.emptyViewSubtitleVariants = ["在手机上播放音乐后这里会显示"]

    return template
  }

  // MARK: - Favorites Tab
  private func createFavoritesTab() -> CPListTemplate {
    let loadingItem = CPListItem(text: "加载中...", detailText: "正在获取收藏列表")
    let section = CPListSection(items: [loadingItem])
    let template = CPListTemplate(title: "收藏", sections: [section])
    template.tabImage = UIImage(systemName: "heart.fill") ?? UIImage()
    template.tabTitle = "收藏"
    template.emptyViewTitleVariants = ["暂无收藏"]
    template.emptyViewSubtitleVariants = ["收藏歌曲后会在这里显示"]

    return template
  }

  // MARK: - Data Loading
  private var isRootAttached: Bool {
    return interfaceController?.rootTemplate is CPTabBarTemplate
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

  private func showChannelWaiting(template: CPListTemplate) {
    DiagLog.log("车机", "通道未就绪, 显示等待提示 (\(template.tabTitle ?? "?"))")
    guard isRootAttached else {
      DiagLog.log("车机", "根模板未挂载, 跳过 updateSections")
      return
    }
    let item = CPListItem(text: "等待手机端连接", detailText: "请在手机上打开苗苗music")
    template.updateSections([CPListSection(items: [item])])
  }

  private func refreshPlaylist(template: CPListTemplate) {
    guard let channel = methodChannel else {
      showChannelWaiting(template: template)
      return
    }
    DiagLog.log("车机", "刷新播放列表: 发起 getCurrentSongId")
    channel.invokeMethod("getCurrentSongId", arguments: nil) { currentId in
      let songId = currentId as? String
      DiagLog.log("车机", "getCurrentSongId 返回: \(Self.describe(currentId))")
      channel.invokeMethod("getPlaylist", arguments: nil) { result in
        if let err = result as? FlutterError {
          DiagLog.log("车机", "getPlaylist 出错: \(err.code) \(err.message ?? "")")
        }
        guard let songs = result as? [[String: Any]], !songs.isEmpty else {
          DiagLog.log("车机", "getPlaylist 无数据: \(Self.describe(result))")
          let emptyItem = CPListItem(text: "暂无歌曲", detailText: "在手机上播放音乐后显示")
          let section = CPListSection(items: [emptyItem])
          template.updateSections([section])
          return
        }
        DiagLog.log("车机", "getPlaylist 返回 \(songs.count) 首")
        let items = self.buildListItems(from: songs, action: "playAtIndex", currentSongId: songId)
        let section = CPListSection(items: items, header: "当前播放列表", sectionIndexTitle: nil)
        template.updateSections([section])
        DiagLog.log("车机", "播放列表已写入模板")
      }
    }
  }

  private func refreshFavorites(template: CPListTemplate) {
    guard let channel = methodChannel else {
      showChannelWaiting(template: template)
      return
    }
    DiagLog.log("车机", "刷新收藏: 发起 getFavorites")
    channel.invokeMethod("getCurrentSongId", arguments: nil) { currentId in
      let songId = currentId as? String
      channel.invokeMethod("getFavorites", arguments: nil) { result in
        if let err = result as? FlutterError {
          DiagLog.log("车机", "getFavorites 出错: \(err.code) \(err.message ?? "")")
        }
        guard let songs = result as? [[String: Any]], !songs.isEmpty else {
          DiagLog.log("车机", "getFavorites 无数据: \(Self.describe(result))")
          let emptyItem = CPListItem(text: "暂无收藏", detailText: "收藏歌曲后会在这里显示")
          let section = CPListSection(items: [emptyItem])
          template.updateSections([section])
          return
        }
        DiagLog.log("车机", "getFavorites 返回 \(songs.count) 首")
        let items = self.buildListItems(from: songs, action: "playFavorite", currentSongId: songId)
        let section = CPListSection(items: items, header: "我的收藏", sectionIndexTitle: nil)
        template.updateSections([section])
        DiagLog.log("车机", "收藏已写入模板")
      }
    }
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
extension CarPlaySceneDelegate: CPTabBarTemplateDelegate {
  func tabBarTemplate(_ tabBarTemplate: CPTabBarTemplate, didSelect selectedTemplate: CPTemplate) {
    if let listTemplate = selectedTemplate as? CPListTemplate {
      if listTemplate.tabTitle == "播放列表" {
        refreshPlaylist(template: listTemplate)
      } else if listTemplate.tabTitle == "收藏" {
        refreshFavorites(template: listTemplate)
      }
    }
  }
}
