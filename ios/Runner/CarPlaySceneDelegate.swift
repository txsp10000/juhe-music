import UIKit
import CarPlay
import MediaPlayer
import Flutter

@available(iOS 14.0, *)
class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
  var interfaceController: CPInterfaceController?
  private var methodChannel: FlutterMethodChannel?
  private var retryTimer: Timer?

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didConnect interfaceController: CPInterfaceController
  ) {
    self.interfaceController = interfaceController
    showRootTemplate()
    setupMethodChannel()
  }

  func sceneDidBecomeActive(_ scene: UIScene) {
    if methodChannel == nil {
      setupMethodChannel()
    } else {
      refreshAllTabs()
    }
  }

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didDisconnect interfaceController: CPInterfaceController
  ) {
    self.interfaceController = nil
    self.methodChannel = nil
    retryTimer?.invalidate()
    retryTimer = nil
  }

  private func setupMethodChannel() {
    guard let binaryMessenger = AppDelegate.resolveBinaryMessenger() else {
      startRetryTimer()
      return
    }

    retryTimer?.invalidate()
    retryTimer = nil

    methodChannel = FlutterMethodChannel(
      name: "com.miaomiao.music/carplay",
      binaryMessenger: binaryMessenger
    )

    refreshAllTabs()
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
    interfaceController?.setRootTemplate(tabBar, animated: true, completion: nil)
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

    refreshPlaylist(template: template)

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

    refreshFavorites(template: template)

    return template
  }

  // MARK: - Data Loading
  private func showChannelWaiting(template: CPListTemplate) {
    let item = CPListItem(text: "等待手机端连接", detailText: "请在手机上打开苗苗music")
    template.updateSections([CPListSection(items: [item])])
  }

  private func refreshPlaylist(template: CPListTemplate) {
    guard let channel = methodChannel else {
      showChannelWaiting(template: template)
      return
    }
    channel.invokeMethod("getCurrentSongId", arguments: nil) { currentId in
      let songId = currentId as? String
      channel.invokeMethod("getPlaylist", arguments: nil) { result in
        guard let songs = result as? [[String: Any]], !songs.isEmpty else {
          let emptyItem = CPListItem(text: "暂无歌曲", detailText: "在手机上播放音乐后显示")
          let section = CPListSection(items: [emptyItem])
          template.updateSections([section])
          return
        }
        let items = self.buildListItems(from: songs, action: "playAtIndex", currentSongId: songId)
        let section = CPListSection(items: items, header: "当前播放列表", sectionIndexTitle: nil)
        template.updateSections([section])
      }
    }
  }

  private func refreshFavorites(template: CPListTemplate) {
    guard let channel = methodChannel else {
      showChannelWaiting(template: template)
      return
    }
    channel.invokeMethod("getCurrentSongId", arguments: nil) { currentId in
      let songId = currentId as? String
      channel.invokeMethod("getFavorites", arguments: nil) { result in
        guard let songs = result as? [[String: Any]], !songs.isEmpty else {
          let emptyItem = CPListItem(text: "暂无收藏", detailText: "收藏歌曲后会在这里显示")
          let section = CPListSection(items: [emptyItem])
          template.updateSections([section])
          return
        }
        let items = self.buildListItems(from: songs, action: "playFavorite", currentSongId: songId)
        let section = CPListSection(items: items, header: "我的收藏", sectionIndexTitle: nil)
        template.updateSections([section])
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
