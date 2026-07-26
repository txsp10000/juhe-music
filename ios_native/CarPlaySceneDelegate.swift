import UIKit
import CarPlay
import MediaPlayer
import Flutter

@available(iOS 14.0, *)
class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
  var interfaceController: CPInterfaceController?
  private var methodChannel: FlutterMethodChannel?

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didConnect interfaceController: CPInterfaceController
  ) {
    self.interfaceController = interfaceController
    setupMethodChannel()
    showRootTemplate()
  }

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didDisconnect interfaceController: CPInterfaceController
  ) {
    self.interfaceController = nil
    self.methodChannel = nil
  }

  private func setupMethodChannel() {
    // Try multiple ways to get the Flutter engine's binary messenger
    var messenger: FlutterBinaryMessenger?

    // Method 1: Get from the app delegate's window root view controller
    if let appDelegate = UIApplication.shared.delegate as? FlutterAppDelegate,
       let controller = appDelegate.window?.rootViewController as? FlutterViewController {
      messenger = controller.binaryMessenger
    }

    // Method 2: Search connected scenes for the Flutter window scene
    if messenger == nil {
      for scene in UIApplication.shared.connectedScenes {
        if let windowScene = scene as? UIWindowScene {
          for window in windowScene.windows {
            if let flutterVC = window.rootViewController as? FlutterViewController {
              messenger = flutterVC.binaryMessenger
              break
            }
          }
        }
        if messenger != nil { break }
      }
    }

    guard let binaryMessenger = messenger else {
      // Retry after a short delay if Flutter engine isn't ready yet
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
        self?.setupMethodChannel()
        if self?.methodChannel != nil {
          self?.showRootTemplate()
        }
      }
      return
    }

    methodChannel = FlutterMethodChannel(
      name: "com.miaomiao.music/carplay",
      binaryMessenger: binaryMessenger
    )
  }

  private func showRootTemplate() {
    guard methodChannel != nil else { return }

    let favoritesTab = createFavoritesTab()
    let playlistTab = createPlaylistTab()

    let tabBar = CPTabBarTemplate(templates: [favoritesTab, playlistTab])
    tabBar.delegate = self
    interfaceController?.setRootTemplate(tabBar, animated: true, completion: nil)
  }

  // MARK: - Playlist Tab
  private func createPlaylistTab() -> CPListTemplate {
    let template = CPListTemplate(title: "播放列表", sections: [])
    template.tabImage = UIImage(systemName: "music.note.list") ?? UIImage()
    template.tabTitle = "播放列表"
    template.emptyViewTitleVariants = ["暂无播放列表"]
    template.emptyViewSubtitleVariants = ["在手机上播放音乐后这里会显示"]

    refreshPlaylist(template: template)

    return template
  }

  // MARK: - Favorites Tab
  private func createFavoritesTab() -> CPListTemplate {
    let template = CPListTemplate(title: "收藏", sections: [])
    template.tabImage = UIImage(systemName: "heart.fill") ?? UIImage()
    template.tabTitle = "收藏"
    template.emptyViewTitleVariants = ["暂无收藏"]
    template.emptyViewSubtitleVariants = ["收藏歌曲后会在这里显示"]

    refreshFavorites(template: template)

    return template
  }

  // MARK: - Data Loading
  private func refreshPlaylist(template: CPListTemplate) {
    methodChannel?.invokeMethod("getCurrentSongId", arguments: nil) { currentId in
      let songId = currentId as? String
      self.methodChannel?.invokeMethod("getPlaylist", arguments: nil) { result in
        guard let songs = result as? [[String: Any]] else { return }
        let items = self.buildListItems(from: songs, action: "playAtIndex", currentSongId: songId)
        let section = CPListSection(items: items, header: "当前播放列表", sectionIndexTitle: nil)
        template.updateSections([section])
      }
    }
  }

  private func refreshFavorites(template: CPListTemplate) {
    methodChannel?.invokeMethod("getCurrentSongId", arguments: nil) { currentId in
      let songId = currentId as? String
      self.methodChannel?.invokeMethod("getFavorites", arguments: nil) { result in
        guard let songs = result as? [[String: Any]] else { return }
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
        // Push now playing template
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