import Flutter
import MediaPlayer
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
    completion: @escaping (Any?, Error?) -> Void = { _, _ in }
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
        completion(
          nil,
          NSError(
            domain: "com.music.carplay",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: error.message ?? "操作失败"]
          )
        )
      } else {
        completion(result, nil)
      }
    }
  }
}

@objc(CarPlaySceneDelegate)
final class CarPlaySceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?

  override init() {
    super.init()
    CarPlayDiagnosticLog.write("PRIVATE_SCENE delegate_initialized")
  }

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    CarPlayDiagnosticLog.write(
      "PRIVATE_SCENE willConnect role=\(session.role.rawValue) type=\(String(describing: type(of: scene)))"
    )
    guard let windowScene = scene as? UIWindowScene else {
      CarPlayDiagnosticLog.write("PRIVATE_SCENE failed reason=not_window_scene")
      return
    }

    let window = UIWindow(windowScene: windowScene)
    window.backgroundColor = UIColor(red: 0.035, green: 0.043, blue: 0.055, alpha: 1)
    window.rootViewController = CarPlayHomeViewController()
    self.window = window
    window.makeKeyAndVisible()
    CarPlayDiagnosticLog.write("PRIVATE_SCENE window_visible bounds=\(window.bounds)")
  }

  func sceneDidBecomeActive(_ scene: UIScene) {
    CarPlayDiagnosticLog.write("PRIVATE_SCENE didBecomeActive visible=\(window?.isHidden == false)")
  }

  func sceneDidDisconnect(_ scene: UIScene) {
    CarPlayDiagnosticLog.write("PRIVATE_SCENE didDisconnect")
    window = nil
  }
}

private struct CarPlayCollection {
  let title: String
  let subtitle: String
  let source: String
  let symbol: String
  let tint: UIColor
}

private final class CarPlayHomeViewController: UIViewController {
  private let collections = [
    CarPlayCollection(
      title: "最近播放",
      subtitle: "继续最近听过的音乐",
      source: "recent",
      symbol: "clock.fill",
      tint: UIColor(red: 0.20, green: 0.72, blue: 0.96, alpha: 1)
    ),
    CarPlayCollection(
      title: "我的收藏",
      subtitle: "已收藏的歌曲",
      source: "favorites",
      symbol: "heart.fill",
      tint: UIColor(red: 0.96, green: 0.31, blue: 0.40, alpha: 1)
    ),
    CarPlayCollection(
      title: "当前队列",
      subtitle: "查看正在播放的队列",
      source: "queue",
      symbol: "text.line.first.and.arrowtriangle.forward",
      tint: UIColor(red: 0.31, green: 0.79, blue: 0.55, alpha: 1)
    ),
    CarPlayCollection(
      title: "听歌场景",
      subtitle: "按心情发现音乐",
      source: "modes",
      symbol: "sparkles",
      tint: UIColor(red: 0.93, green: 0.66, blue: 0.25, alpha: 1)
    ),
  ]

  private let titleLabel = UILabel()
  private let statusLabel = UILabel()
  private let grid = UIStackView()
  private let nowPlayingBar = CarPlayNowPlayingBar()

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = UIColor(red: 0.035, green: 0.043, blue: 0.055, alpha: 1)
    buildLayout()
    refreshStatus()
    CarPlayDiagnosticLog.write("PRIVATE_UI home_view_did_load")
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    refreshStatus()
    CarPlayDiagnosticLog.write("PRIVATE_UI home_view_did_appear")
  }

  private func buildLayout() {
    titleLabel.text = "音乐"
    titleLabel.font = .systemFont(ofSize: 34, weight: .bold)
    titleLabel.textColor = .white

    statusLabel.text = "正在连接音乐库"
    statusLabel.font = .systemFont(ofSize: 15, weight: .medium)
    statusLabel.textColor = UIColor.white.withAlphaComponent(0.62)

    let heading = UIStackView(arrangedSubviews: [titleLabel, statusLabel])
    heading.axis = .vertical
    heading.spacing = 3

    grid.axis = .vertical
    grid.spacing = 12
    for pairStart in stride(from: 0, to: collections.count, by: 2) {
      let row = UIStackView()
      row.axis = .horizontal
      row.spacing = 12
      row.distribution = .fillEqually
      for index in pairStart..<min(pairStart + 2, collections.count) {
        let button = CarPlayCollectionButton(collection: collections[index])
        button.tag = index
        button.addTarget(self, action: #selector(openCollection(_:)), for: .touchUpInside)
        row.addArrangedSubview(button)
      }
      grid.addArrangedSubview(row)
    }

    nowPlayingBar.onControl = { action in
      CarPlayBridge.shared.invoke(action) { [weak self] _, error in
        DispatchQueue.main.async {
          if let error {
            self?.showError(error.localizedDescription)
          } else {
            self?.nowPlayingBar.refresh()
          }
        }
      }
    }

    [heading, grid, nowPlayingBar].forEach {
      $0.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview($0)
    }

    NSLayoutConstraint.activate([
      heading.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 18),
      heading.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 28),
      heading.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -28),

      grid.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 18),
      grid.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
      grid.trailingAnchor.constraint(equalTo: heading.trailingAnchor),

      nowPlayingBar.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
      nowPlayingBar.trailingAnchor.constraint(equalTo: heading.trailingAnchor),
      nowPlayingBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -14),
      nowPlayingBar.heightAnchor.constraint(equalToConstant: 78),
      grid.bottomAnchor.constraint(lessThanOrEqualTo: nowPlayingBar.topAnchor, constant: -16),
    ])
  }

  private func refreshStatus() {
    CarPlayBridge.shared.invoke("getLibrary") { [weak self] result, error in
      DispatchQueue.main.async {
        guard let self else { return }
        if let error {
          self.statusLabel.text = "音乐库暂不可用：\(error.localizedDescription)"
          return
        }
        let library = result as? [String: Any]
        let count = ["recent", "favorites", "queue"].reduce(0) { partial, key in
          partial + ((library?[key] as? [Any])?.count ?? 0)
        }
        self.statusLabel.text = count > 0 ? "音乐库已连接" : "选择一个分类开始播放"
        self.nowPlayingBar.refresh()
      }
    }
  }

  @objc private func openCollection(_ sender: UIButton) {
    guard collections.indices.contains(sender.tag) else { return }
    let collection = collections[sender.tag]
    let controller: UIViewController
    if collection.source == "modes" {
      controller = CarPlayModeListViewController()
    } else {
      controller = CarPlaySongListViewController(
        title: collection.title,
        source: collection.source
      )
    }
    controller.modalPresentationStyle = .fullScreen
    present(controller, animated: true)
  }

  private func showError(_ message: String) {
    let alert = UIAlertController(title: "无法完成操作", message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "知道了", style: .default))
    present(alert, animated: true)
  }
}

private final class CarPlayCollectionButton: UIControl {
  init(collection: CarPlayCollection) {
    super.init(frame: .zero)
    backgroundColor = UIColor.white.withAlphaComponent(0.075)
    layer.cornerRadius = 8

    let icon = UIImageView(image: UIImage(systemName: collection.symbol))
    icon.tintColor = collection.tint
    icon.contentMode = .scaleAspectFit

    let title = UILabel()
    title.text = collection.title
    title.textColor = .white
    title.font = .systemFont(ofSize: 21, weight: .semibold)

    let subtitle = UILabel()
    subtitle.text = collection.subtitle
    subtitle.textColor = UIColor.white.withAlphaComponent(0.55)
    subtitle.font = .systemFont(ofSize: 13, weight: .regular)

    let labels = UIStackView(arrangedSubviews: [title, subtitle])
    labels.axis = .vertical
    labels.spacing = 3

    [icon, labels].forEach {
      $0.isUserInteractionEnabled = false
      $0.translatesAutoresizingMaskIntoConstraints = false
      addSubview($0)
    }

    NSLayoutConstraint.activate([
      heightAnchor.constraint(equalToConstant: 78),
      icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
      icon.centerYAnchor.constraint(equalTo: centerYAnchor),
      icon.widthAnchor.constraint(equalToConstant: 30),
      icon.heightAnchor.constraint(equalToConstant: 30),
      labels.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 14),
      labels.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
      labels.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var isHighlighted: Bool {
    didSet { alpha = isHighlighted ? 0.62 : 1 }
  }
}

private final class CarPlayNowPlayingBar: UIView {
  var onControl: ((String) -> Void)?

  private let titleLabel = UILabel()
  private let artistLabel = UILabel()
  private let playButton = UIButton(type: .system)

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = UIColor.white.withAlphaComponent(0.09)
    layer.cornerRadius = 8

    titleLabel.text = "暂无播放"
    titleLabel.textColor = .white
    titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
    titleLabel.lineBreakMode = .byTruncatingTail

    artistLabel.text = "选择歌曲开始播放"
    artistLabel.textColor = UIColor.white.withAlphaComponent(0.56)
    artistLabel.font = .systemFont(ofSize: 13)
    artistLabel.lineBreakMode = .byTruncatingTail

    let labels = UIStackView(arrangedSubviews: [titleLabel, artistLabel])
    labels.axis = .vertical
    labels.spacing = 3

    let previous = controlButton(symbol: "backward.fill", action: #selector(previousTapped))
    playButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
    playButton.tintColor = .white
    playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
    let next = controlButton(symbol: "forward.fill", action: #selector(nextTapped))
    let controls = UIStackView(arrangedSubviews: [previous, playButton, next])
    controls.axis = .horizontal
    controls.spacing = 16
    controls.distribution = .fillEqually

    [labels, controls].forEach {
      $0.translatesAutoresizingMaskIntoConstraints = false
      addSubview($0)
    }
    NSLayoutConstraint.activate([
      labels.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
      labels.centerYAnchor.constraint(equalTo: centerYAnchor),
      labels.trailingAnchor.constraint(lessThanOrEqualTo: controls.leadingAnchor, constant: -12),
      controls.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
      controls.centerYAnchor.constraint(equalTo: centerYAnchor),
      controls.widthAnchor.constraint(equalToConstant: 150),
      controls.heightAnchor.constraint(equalToConstant: 48),
    ])
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func refresh() {
    let info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
    titleLabel.text = info[MPMediaItemPropertyTitle] as? String ?? "暂无播放"
    artistLabel.text = info[MPMediaItemPropertyArtist] as? String ?? "选择歌曲开始播放"
    let rate = (info[MPNowPlayingInfoPropertyPlaybackRate] as? NSNumber)?.doubleValue ?? 0
    playButton.setImage(UIImage(systemName: rate > 0 ? "pause.fill" : "play.fill"), for: .normal)
  }

  private func controlButton(symbol: String, action: Selector) -> UIButton {
    let button = UIButton(type: .system)
    button.setImage(UIImage(systemName: symbol), for: .normal)
    button.tintColor = .white
    button.addTarget(self, action: action, for: .touchUpInside)
    return button
  }

  @objc private func previousTapped() { onControl?("previous") }
  @objc private func playTapped() { onControl?("togglePlayPause") }
  @objc private func nextTapped() { onControl?("next") }
}

private class CarPlayBaseListViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
  let tableView = UITableView(frame: .zero, style: .plain)
  private let heading: String

  init(title: String) {
    heading = title
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = UIColor(red: 0.035, green: 0.043, blue: 0.055, alpha: 1)

    let back = UIButton(type: .system)
    back.setImage(UIImage(systemName: "chevron.left"), for: .normal)
    back.tintColor = .white
    back.addTarget(self, action: #selector(close), for: .touchUpInside)

    let title = UILabel()
    title.text = heading
    title.textColor = .white
    title.font = .systemFont(ofSize: 28, weight: .bold)

    let header = UIStackView(arrangedSubviews: [back, title])
    header.axis = .horizontal
    header.spacing = 14
    back.widthAnchor.constraint(equalToConstant: 44).isActive = true

    tableView.backgroundColor = .clear
    tableView.separatorColor = UIColor.white.withAlphaComponent(0.12)
    tableView.dataSource = self
    tableView.delegate = self
    tableView.rowHeight = 66
    tableView.tableFooterView = UIView()

    [header, tableView].forEach {
      $0.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview($0)
    }
    NSLayoutConstraint.activate([
      header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
      header.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 18),
      header.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -18),
      header.heightAnchor.constraint(equalToConstant: 48),
      tableView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
      tableView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
      tableView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
      tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
  }

  @objc private func close() { dismiss(animated: true) }

  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 0 }

  func tableView(
    _ tableView: UITableView,
    cellForRowAt indexPath: IndexPath
  ) -> UITableViewCell {
    UITableViewCell(style: .subtitle, reuseIdentifier: nil)
  }

  func configureCell(_ cell: UITableViewCell, title: String, detail: String) {
    cell.backgroundColor = .clear
    cell.textLabel?.text = title
    cell.textLabel?.textColor = .white
    cell.textLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
    cell.detailTextLabel?.text = detail
    cell.detailTextLabel?.textColor = UIColor.white.withAlphaComponent(0.52)
    cell.detailTextLabel?.font = .systemFont(ofSize: 13)
    cell.accessoryType = .disclosureIndicator
    cell.tintColor = UIColor.white.withAlphaComponent(0.45)
  }
}

private final class CarPlaySongListViewController: CarPlayBaseListViewController {
  private let source: String
  private var songs: [[String: Any]] = []
  private var message = "正在载入音乐…"

  init(title: String, source: String) {
    self.source = source
    super.init(title: title)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    CarPlayBridge.shared.invoke("getSongs", arguments: ["source": source]) { [weak self] result, error in
      DispatchQueue.main.async {
        guard let self else { return }
        if let error {
          self.message = "加载失败：\(error.localizedDescription)"
        } else {
          self.songs = result as? [[String: Any]] ?? []
          self.message = self.songs.isEmpty ? "这里还没有歌曲" : ""
        }
        self.tableView.reloadData()
      }
    }
  }

  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    max(1, songs.count)
  }

  override func tableView(
    _ tableView: UITableView,
    cellForRowAt indexPath: IndexPath
  ) -> UITableViewCell {
    let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
    guard songs.indices.contains(indexPath.row) else {
      configureCell(cell, title: message, detail: "")
      cell.accessoryType = .none
      cell.selectionStyle = .none
      return cell
    }
    let song = songs[indexPath.row]
    configureCell(
      cell,
      title: song["name"] as? String ?? "未知歌曲",
      detail: song["singer"] as? String ?? "未知歌手"
    )
    return cell
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    guard songs.indices.contains(indexPath.row) else { return }
    CarPlayBridge.shared.invoke(
      "playSong",
      arguments: ["source": source, "index": indexPath.row]
    ) { [weak self] _, error in
      DispatchQueue.main.async {
        if let error {
          let alert = UIAlertController(
            title: "播放失败",
            message: error.localizedDescription,
            preferredStyle: .alert
          )
          alert.addAction(UIAlertAction(title: "知道了", style: .default))
          self?.present(alert, animated: true)
        } else {
          self?.dismiss(animated: true)
        }
      }
    }
  }
}

private final class CarPlayModeListViewController: CarPlayBaseListViewController {
  private var modes: [[String: Any]] = []
  private var message = "正在载入听歌场景…"

  init() {
    super.init(title: "听歌场景")
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    CarPlayBridge.shared.invoke("getModes") { [weak self] result, error in
      DispatchQueue.main.async {
        guard let self else { return }
        if let error {
          self.message = "加载失败：\(error.localizedDescription)"
        } else {
          self.modes = result as? [[String: Any]] ?? []
          self.message = self.modes.isEmpty ? "暂无可用场景" : ""
        }
        self.tableView.reloadData()
      }
    }
  }

  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    max(1, modes.count)
  }

  override func tableView(
    _ tableView: UITableView,
    cellForRowAt indexPath: IndexPath
  ) -> UITableViewCell {
    let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
    guard modes.indices.contains(indexPath.row) else {
      configureCell(cell, title: message, detail: "")
      cell.accessoryType = .none
      cell.selectionStyle = .none
      return cell
    }
    configureCell(
      cell,
      title: modes[indexPath.row]["name"] as? String ?? "听歌场景",
      detail: "点按后开始播放"
    )
    return cell
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    guard modes.indices.contains(indexPath.row),
          let sceneModeId = modes[indexPath.row]["sceneModeId"] as? Int else { return }
    CarPlayBridge.shared.invoke("playMode", arguments: ["sceneModeId": sceneModeId]) {
      [weak self] result, error in
      DispatchQueue.main.async {
        guard error == nil, (result as? Bool) == true else {
          let alert = UIAlertController(
            title: "播放失败",
            message: error?.localizedDescription ?? "这个场景暂时没有可播放歌曲",
            preferredStyle: .alert
          )
          alert.addAction(UIAlertAction(title: "知道了", style: .default))
          self?.present(alert, animated: true)
          return
        }
        self?.dismiss(animated: true)
      }
    }
  }
}
