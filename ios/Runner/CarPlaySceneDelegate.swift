import CarPlay
import Flutter
import UIKit

final class CarPlayBridge {
  static let shared = CarPlayBridge()

  private struct PendingInvocation {
    let method: String
    let arguments: Any?
    let completion: (Any?, Error?) -> Void
  }

  private var channel: FlutterMethodChannel?
  private var pendingInvocations: [PendingInvocation] = []

  private init() {}

  func configure(messenger: FlutterBinaryMessenger) {
    guard channel == nil else { return }
    channel = FlutterMethodChannel(
      name: "com.music/carplay",
      binaryMessenger: messenger
    )
    let pending = pendingInvocations
    pendingInvocations.removeAll()
    pending.forEach { invocation in
      invoke(
        invocation.method,
        arguments: invocation.arguments,
        completion: invocation.completion
      )
    }
  }

  func invoke(
    _ method: String,
    arguments: Any? = nil,
    completion: @escaping (Any?, Error?) -> Void
  ) {
    guard let channel else {
      pendingInvocations.append(
        PendingInvocation(
          method: method,
          arguments: arguments,
          completion: completion
        )
      )
      return
    }
    channel.invokeMethod(method, arguments: arguments) { result in
      if let error = result as? FlutterError {
        completion(nil, CarPlayBridgeError.flutter(error.message))
      } else {
        completion(result, nil)
      }
    }
  }
}

private enum CarPlayBridgeError: LocalizedError {
  case flutter(String?)

  var errorDescription: String? {
    switch self {
    case .flutter(let message):
      return message ?? "暂时无法完成此操作"
    }
  }
}

final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
  private weak var interfaceController: CPInterfaceController?
  private var searchResults: [[String: Any]] = []
  private var searchGeneration = 0

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didConnect interfaceController: CPInterfaceController
  ) {
    self.interfaceController = interfaceController
    installRootTemplate(on: interfaceController)
    refreshLibrary()
  }

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didDisconnectInterfaceController interfaceController: CPInterfaceController
  ) {
    self.interfaceController = nil
    searchResults = []
    searchGeneration += 1
  }

  private func installRootTemplate(on interfaceController: CPInterfaceController) {
    let library = makeLibraryTemplate()
    let modes = makeModesTemplate()
    let search = CPSearchTemplate()
    search.delegate = self
    search.tabTitle = "搜索"
    search.tabImage = UIImage(systemName: "magnifyingglass")

    let nowPlaying = CPNowPlayingTemplate.shared
    nowPlaying.tabTitle = "正在播放"
    nowPlaying.tabImage = UIImage(systemName: "play.circle")

    let root = CPTabBarTemplate(
      templates: [library, modes, search, nowPlaying]
    )
    interfaceController.setRootTemplate(root, animated: false)
  }

  private func makeLibraryTemplate(
    counts: [String: Int] = [:]
  ) -> CPListTemplate {
    let template = CPListTemplate(
      title: "音乐库",
      sections: [
        CPListSection(items: [
          collectionItem(
            title: "最近播放",
            detail: countText(counts["recent"]),
            source: "recent"
          ),
          collectionItem(
            title: "我的收藏",
            detail: countText(counts["favorites"]),
            source: "favorites"
          ),
          collectionItem(
            title: "当前队列",
            detail: countText(counts["queue"]),
            source: "queue"
          ),
        ]),
      ]
    )
    template.tabTitle = "音乐库"
    template.tabImage = UIImage(systemName: "music.note.list")
    return template
  }

  private func collectionItem(
    title: String,
    detail: String,
    source: String
  ) -> CPListItem {
    let item = CPListItem(text: title, detailText: detail)
    item.handler = { [weak self] _, completion in
      self?.openCollection(title: title, source: source, completion: completion)
        ?? completion()
    }
    return item
  }

  private func makeModesTemplate() -> CPListTemplate {
    let loading = CPListItem(text: "正在加载听歌场景…", detailText: nil)
    let template = CPListTemplate(
      title: "听歌场景",
      sections: [CPListSection(items: [loading])]
    )
    template.tabTitle = "听歌场景"
    template.tabImage = UIImage(systemName: "sparkles")

    CarPlayBridge.shared.invoke("getModes") { [weak template] result, error in
      DispatchQueue.main.async {
        guard let template else { return }
        guard error == nil, let modes = result as? [[String: Any]] else {
          template.updateSections([
            CPListSection(items: [
              CPListItem(text: "听歌场景暂时不可用", detailText: "请稍后重试"),
            ]),
          ])
          return
        }
        let items = modes.prefix(CPListTemplate.maximumItemCount).map { [weak self] mode -> CPListItem in
          let name = mode["name"] as? String ?? "听歌场景"
          let sceneModeId = mode["sceneModeId"] as? Int ?? -1
          let item = CPListItem(text: name, detailText: "点按后开始播放")
          item.handler = { _, completion in
            self?.playMode(name: name, sceneModeId: sceneModeId, completion: completion)
              ?? completion()
          }
          return item
        }
        template.updateSections([CPListSection(items: items)])
      }
    }
    return template
  }

  private func refreshLibrary() {
    CarPlayBridge.shared.invoke("getLibrary") { [weak self] result, _ in
      guard let self, let library = result as? [String: Any] else { return }
      let counts = [
        "recent": (library["recent"] as? [Any])?.count ?? 0,
        "favorites": (library["favorites"] as? [Any])?.count ?? 0,
        "queue": (library["queue"] as? [Any])?.count ?? 0,
      ]
      DispatchQueue.main.async {
        guard let root = self.interfaceController?.rootTemplate as? CPTabBarTemplate else {
          return
        }
        var templates = root.templates
        guard !templates.isEmpty else { return }
        let selectedIndex = templates.firstIndex {
          $0 === root.selectedTemplate
        } ?? 0
        templates[0] = self.makeLibraryTemplate(counts: counts)
        root.updateTemplates(templates)
        if #available(iOS 17.0, *) {
          root.selectTemplate(at: selectedIndex)
        }
      }
    }
  }

  private func openCollection(
    title: String,
    source: String,
    completion: @escaping () -> Void
  ) {
    let loading = CPListTemplate(
      title: title,
      sections: [
        CPListSection(items: [
          CPListItem(text: "正在加载…", detailText: nil),
        ]),
      ]
    )
    interfaceController?.pushTemplate(loading, animated: true)
    completion()

    CarPlayBridge.shared.invoke("getSongs", arguments: ["source": source]) {
      [weak self, weak loading] result, error in
      DispatchQueue.main.async {
        guard let self, let loading else { return }
        guard error == nil, let songs = result as? [[String: Any]] else {
          loading.updateSections([
            CPListSection(items: [
              CPListItem(text: "加载失败", detailText: "请返回后重试"),
            ]),
          ])
          return
        }
        guard !songs.isEmpty else {
          loading.updateSections([
            CPListSection(items: [
              CPListItem(text: "这里还没有歌曲", detailText: nil),
            ]),
          ])
          return
        }
        loading.updateSections([
          CPListSection(items: self.songItems(songs, source: source)),
        ])
      }
    }
  }

  private func songItems(
    _ songs: [[String: Any]],
    source: String
  ) -> [CPListItem] {
    songs.prefix(CPListTemplate.maximumItemCount).enumerated().map { index, song in
      let name = song["name"] as? String ?? "未知歌曲"
      let singer = song["singer"] as? String ?? "未知歌手"
      let album = song["album"] as? String ?? ""
      let detail = album.isEmpty ? singer : "\(singer) · \(album)"
      let item = CPListItem(text: name, detailText: detail)
      item.handler = { [weak self] _, completion in
        self?.playSong(source: source, index: index, completion: completion)
          ?? completion()
      }
      return item
    }
  }

  private func playSong(
    source: String,
    index: Int,
    completion: @escaping () -> Void
  ) {
    CarPlayBridge.shared.invoke(
      "playSong",
      arguments: ["source": source, "index": index]
    ) { [weak self] _, error in
      DispatchQueue.main.async {
        completion()
        if let error {
          self?.showError(error.localizedDescription)
        } else {
          self?.showNowPlaying()
          self?.refreshLibrary()
        }
      }
    }
  }

  private func playMode(
    name: String,
    sceneModeId: Int,
    completion: @escaping () -> Void
  ) {
    CarPlayBridge.shared.invoke(
      "playMode",
      arguments: ["sceneModeId": sceneModeId]
    ) { [weak self] result, error in
      DispatchQueue.main.async {
        completion()
        if let error {
          self?.showError(error.localizedDescription)
        } else if (result as? Bool) == true {
          self?.showNowPlaying()
          self?.refreshLibrary()
        } else {
          self?.showError("“\(name)”暂时没有可播放歌曲")
        }
      }
    }
  }

  private func showNowPlaying() {
    guard let root = interfaceController?.rootTemplate as? CPTabBarTemplate else { return }
    if #available(iOS 17.0, *),
       let index = root.templates.firstIndex(where: {
         $0 === CPNowPlayingTemplate.shared
       }) {
      root.selectTemplate(at: index)
    }
  }

  private func showError(_ message: String) {
    let action = CPAlertAction(title: "知道了", style: .default) { _ in }
    let alert = CPAlertTemplate(titleVariants: [message], actions: [action])
    interfaceController?.presentTemplate(alert, animated: true)
  }

  private func countText(_ count: Int?) -> String {
    guard let count else { return "正在同步…" }
    return count == 0 ? "暂无歌曲" : "\(count) 首歌曲"
  }
}

extension CarPlaySceneDelegate: CPSearchTemplateDelegate {
  func searchTemplate(
    _ searchTemplate: CPSearchTemplate,
    updatedSearchText searchText: String,
    completionHandler: @escaping ([CPListItem]) -> Void
  ) {
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    searchGeneration += 1
    let generation = searchGeneration
    guard !query.isEmpty else {
      searchResults = []
      completionHandler([])
      return
    }
    CarPlayBridge.shared.invoke("search", arguments: ["query": query]) {
      [weak self] result, _ in
      DispatchQueue.main.async {
        guard let self, generation == self.searchGeneration,
              let songs = result as? [[String: Any]] else {
          completionHandler([])
          return
        }
        self.searchResults = Array(songs.prefix(CPListTemplate.maximumItemCount))
        let items = self.searchResults.enumerated().map { index, song in
          let name = song["name"] as? String ?? "未知歌曲"
          let singer = song["singer"] as? String ?? "未知歌手"
          let item = CPListItem(text: name, detailText: singer)
          item.userInfo = index
          return item
        }
        completionHandler(items)
      }
    }
  }

  func searchTemplate(
    _ searchTemplate: CPSearchTemplate,
    selectedResult item: CPListItem,
    completionHandler: @escaping () -> Void
  ) {
    guard let index = item.userInfo as? Int, searchResults.indices.contains(index) else {
      completionHandler()
      return
    }
    CarPlayBridge.shared.invoke(
      "playSearchResults",
      arguments: ["songs": searchResults, "index": index]
    ) { [weak self] _, error in
      DispatchQueue.main.async {
        completionHandler()
        if let error {
          self?.showError(error.localizedDescription)
        } else {
          self?.showNowPlaying()
          self?.refreshLibrary()
        }
      }
    }
  }
}
