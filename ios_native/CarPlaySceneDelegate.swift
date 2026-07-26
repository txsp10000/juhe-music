import UIKit
import CarPlay
import MediaPlayer

class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
  var interfaceController: CPInterfaceController?
  private var nowPlayingObserver: Any?
  private let channel = "com.miaomiao.music/carplay"
  private var methodChannel: FlutterMethodChannel?
  
  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didConnect interfaceController: CPInterfaceController
  ) {
    self.interfaceController = interfaceController
    setupMethodChannel()
    showTabBar()
  }
  
  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didDisconnect interfaceController: CPInterfaceController
  ) {
    self.interfaceController = nil
    self.methodChannel = nil
  }
  
  private func setupMethodChannel() {
    guard let controller = UIApplication.shared.delegate?.window??.rootViewController as? FlutterViewController else { return }
    methodChannel = FlutterMethodChannel(
      name: channel,
      binaryMessenger: controller.binaryMessenger
    )
  }
  
  private func showTabBar() {
    let nowPlayingTab = createNowPlayingTab()
    let playlistTab = createPlaylistTab()
    let favoritesTab = createFavoritesTab()
    
    let tabBar = CPTabBarTemplate(templates: [nowPlayingTab, playlistTab, favoritesTab])
    interfaceController?.setRootTemplate(tabBar, animated: true, completion: nil)
  }
  
  // MARK: - Now Playing Tab
  private func createNowPlayingTab() -> CPNowPlayingTemplate {
    let nowPlaying = CPNowPlayingTemplate.shared
    nowPlaying.isUpNextButtonEnabled = true
    nowPlaying.isAlbumArtistButtonEnabled = false
    
    let tabImage = UIImage(systemName: "music.note") ?? UIImage()
    nowPlaying.tabImage = tabImage
    nowPlaying.tabTitle = "正在播放"
    
    // Up Next button shows current playlist
    nowPlaying.upNextTitle = "播放列表"
    
    return nowPlaying
  }
  
  // MARK: - Playlist Tab
  private func createPlaylistTab() -> CPListTemplate {
    let template = CPListTemplate(title: "播放列表", sections: [])
    template.tabImage = UIImage(systemName: "list.bullet") ?? UIImage()
    template.tabTitle = "播放列表"
    template.emptyViewTitleVariants = ["暂无播放列表"]
    template.emptyViewSubtitleVariants = ["在手机上播放音乐后这里会显示"]
    
    // Request playlist data from Flutter
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
    
    // Request favorites data from Flutter
    refreshFavorites(template: template)
    
    return template
  }
  
  // MARK: - Data Loading
  private func refreshPlaylist(template: CPListTemplate) {
    methodChannel?.invokeMethod("getPlaylist", arguments: nil) { result in
      guard let songs = result as? [[String: Any]] else { return }
      let items = self.buildListItems(from: songs, action: "playAtIndex")
      let section = CPListSection(items: items, header: "当前播放列表", sectionIndexTitle: nil)
      template.updateSections([section])
    }
  }
  
  private func refreshFavorites(template: CPListTemplate) {
    methodChannel?.invokeMethod("getFavorites", arguments: nil) { result in
      guard let songs = result as? [[String: Any]] else { return }
      let items = self.buildListItems(from: songs, action: "playFavorite")
      let section = CPListSection(items: items, header: "我的收藏", sectionIndexTitle: nil)
      template.updateSections([section])
    }
  }
  
  private func buildListItems(from songs: [[String: Any]], action: String) -> [CPListItem] {
    return songs.enumerated().map { (index, song) in
      let title = song["name"] as? String ?? "未知歌曲"
      let subtitle = song["singer"] as? String ?? "未知歌手"
      
      let item = CPListItem(text: title, detailText: subtitle)
      item.handler = { [weak self] _, completion in
        self?.methodChannel?.invokeMethod(action, arguments: index)
        // Switch to now playing after selecting a song
        if let intf = self?.interfaceController {
          let nowPlaying = CPNowPlayingTemplate.shared
          intf.pushTemplate(nowPlaying, animated: true, completion: nil)
        }
        completion()
      }
      
      // Load artwork async
      if let coverUrl = song["cover"] as? String, !coverUrl.isEmpty {
        self.loadImage(from: coverUrl) { image in
          if let img = image {
            item.setImage(img)
          }
        }
      }
      
      return item
    }
  }
  
  // MARK: - Image Loading
  private func loadImage(from urlString: String, completion: @escaping (UIImage?) -> Void) {
    let path: String
    if urlString.hasPrefix("file://") {
      path = String(urlString.dropFirst(7))
      let image = UIImage(contentsOfFile: path)
      DispatchQueue.main.async { completion(image) }
      return
    }
    guard let url = URL(string: urlString) else {
      completion(nil)
      return
    }
    var request = URLRequest(url: url)
    request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
    URLSession.shared.dataTask(with: request) { data, _, _ in
      let image = data.flatMap { UIImage(data: $0) }
      DispatchQueue.main.async { completion(image) }
    }.resume()
  }
}
