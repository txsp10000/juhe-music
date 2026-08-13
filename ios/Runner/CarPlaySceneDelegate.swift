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
    CarPlayDiagnosticLog.write("BRIDGE configure pending=\(pendingInvocations.count)")
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
      CarPlayDiagnosticLog.write("BRIDGE queue method=\(method)")
      pendingInvocations.append(
        PendingInvocation(
          method: method,
          arguments: arguments,
          completion: completion
        )
      )
      return
    }
    CarPlayDiagnosticLog.write("BRIDGE invoke method=\(method)")
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

@objc final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
  private var interfaceController: CPInterfaceController?
  private var rootTemplate: CPListTemplate?
  private var searchResults: [[String: Any]] = []
  private var searchGeneration = 0
  private var rootDidAppear = false
  private var libraryRefreshStarted = false
  private var rootRetryScheduled = false

  override init() {
    super.init()
    CarPlayDiagnosticLog.write("SCENE_DELEGATE initialized")
  }

  func sceneWillEnterForeground(_ scene: UIScene) {
    CarPlayDiagnosticLog.write("SCENE willEnterForeground")
  }

  func sceneDidBecomeActive(_ scene: UIScene) {
    CarPlayDiagnosticLog.write("SCENE didBecomeActive root=\(interfaceController?.rootTemplate != nil)")
    guard rootTemplate == nil, let interfaceController else { return }
    CarPlayDiagnosticLog.write("SET_ROOT scheduling after_scene_active")
    DispatchQueue.main.async { [weak self, weak interfaceController] in
      guard let self, let interfaceController, self.rootTemplate == nil else { return }
      self.installRootTemplate(on: interfaceController)
    }
  }

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didConnect interfaceController: CPInterfaceController
  ) {
    CarPlayDiagnosticLog.write("DID_CONNECT interfaceController received")
    self.interfaceController = interfaceController
    interfaceController.delegate = self
  }

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didDisconnectInterfaceController interfaceController: CPInterfaceController
  ) {
    CarPlayDiagnosticLog.write("DID_DISCONNECT")
    interfaceController.delegate = nil
    self.interfaceController = nil
    rootTemplate = nil
    rootDidAppear = false
    libraryRefreshStarted = false
    rootRetryScheduled = false
    searchResults = []
    searchGeneration += 1
  }

  private func installRootTemplate(on interfaceController: CPInterfaceController) {
    let root = CPListTemplate(
      title: "音乐",
      sections: [CPListSection(items: [
        CPListItem(text: "CarPlay 已连接", detailText: "正在载入音乐库"),
      ])]
    )
    rootTemplate = root
    CarPlayDiagnosticLog.write("SET_ROOT begin after_scene_active type=CPListTemplate sections=1 items=1")
    interfaceController.setRootTemplate(root, animated: true) { success, error in
      if let error {
        CarPlayDiagnosticLog.write("SET_ROOT completion failed error=\(error.localizedDescription)")
        return
      }
      CarPlayDiagnosticLog.write("SET_ROOT completion success=\(success)")
    }
    CarPlayDiagnosticLog.write("SET_ROOT dispatched installed=\(interfaceController.rootTemplate === root)")
    scheduleRootRetry(on: interfaceController)
  }

  private func scheduleRootRetry(on interfaceController: CPInterfaceController) {
    guard !rootRetryScheduled else { return }
    rootRetryScheduled = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self, weak interfaceController] in
      guard let self, let interfaceController, !self.rootDidAppear else { return }
      CarPlayDiagnosticLog.write("SET_ROOT retry begin reason=no_template_appearance")
      let retryRoot = CPListTemplate(
        title: "音乐",
        sections: [CPListSection(items: [
          CPListItem(text: "音乐已连接", detailText: "请选择音乐开始播放"),
        ])]
      )
      self.rootTemplate = retryRoot
      interfaceController.setRootTemplate(retryRoot, animated: false) { success, error in
        if let error {
          CarPlayDiagnosticLog.write("SET_ROOT retry failed error=\(error.localizedDescription)")
        } else {
          CarPlayDiagnosticLog.write("SET_ROOT retry completion success=\(success)")
        }
      }
      CarPlayDiagnosticLog.write("SET_ROOT retry dispatched installed=\(interfaceController.rootTemplate === retryRoot)")
    }
  }

  private func makeRootSections(counts: [String: Int] = [:]) -> [CPListSection] {
    let modes = CPListItem(
      text: "听歌场景",
      detailText: "按场景发现音乐"
    )
    modes.handler = { [weak self] _, completion in
      self?.openModes()
      completion()
    }

    let search = CPListItem(
      text: "搜索歌曲",
      detailText: "按歌曲名或歌手搜索"
    )
    search.handler = { [weak self] _, completion in
      guard let self else {
        completion()
        return
      }
      let search = CPSearchTemplate()
      search.delegate = self
      self.interfaceController?.pushTemplate(search, animated: true)
      completion()
    }

    let nowPlaying = CPListItem(
      text: "打开正在播放",
      detailText: "查看歌曲与播放控制"
    )
    nowPlaying.handler = { [weak self] _, completion in
      self?.showNowPlaying()
      completion()
    }

    return [CPListSection(items: [
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
      modes,
      search,
      nowPlaying,
    ])]
  }

  private func startLibraryRefreshAfterRootAppears() {
    guard rootDidAppear, !libraryRefreshStarted else { return }
    guard let root = rootTemplate,
          let installedRoot = interfaceController?.rootTemplate,
          installedRoot === root else {
      CarPlayDiagnosticLog.write("REFRESH_LIBRARY skipped root_not_attached")
      return
    }
    libraryRefreshStarted = true
    CarPlayDiagnosticLog.write("REFRESH_LIBRARY begin after_root_appeared")
    root.updateSections(makeRootSections())
    CarPlayDiagnosticLog.write("REFRESH_LIBRARY static_sections_applied")
    refreshLibrary()
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

  private func openModes() {
    let loading = CPListItem(text: "正在加载听歌场景…", detailText: nil)
    let template = CPListTemplate(
      title: "听歌场景",
      sections: [CPListSection(items: [loading])]
    )
    interfaceController?.pushTemplate(template, animated: true)

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
        guard let root = self.rootTemplate,
              let installedRoot = self.interfaceController?.rootTemplate,
              installedRoot === root else {
          return
        }
        root.updateSections(self.makeRootSections(counts: counts))
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
    interfaceController?.pushTemplate(CPNowPlayingTemplate.shared, animated: true)
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

extension CarPlaySceneDelegate: CPInterfaceControllerDelegate {
  func templateWillAppear(_ aTemplate: CPTemplate, animated: Bool) {
    CarPlayDiagnosticLog.write(
      "TEMPLATE willAppear type=\(String(describing: type(of: aTemplate))) animated=\(animated)"
    )
  }

  func templateDidAppear(_ aTemplate: CPTemplate, animated: Bool) {
    let isRoot = aTemplate === rootTemplate
    CarPlayDiagnosticLog.write(
      "TEMPLATE didAppear type=\(String(describing: type(of: aTemplate))) root=\(isRoot)"
    )
    guard isRoot else { return }
    rootDidAppear = true
    startLibraryRefreshAfterRootAppears()
  }

  func templateWillDisappear(_ aTemplate: CPTemplate, animated: Bool) {
    CarPlayDiagnosticLog.write(
      "TEMPLATE willDisappear type=\(String(describing: type(of: aTemplate)))"
    )
  }

  func templateDidDisappear(_ aTemplate: CPTemplate, animated: Bool) {
    CarPlayDiagnosticLog.write(
      "TEMPLATE didDisappear type=\(String(describing: type(of: aTemplate)))"
    )
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
