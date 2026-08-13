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
  private var content: UIStackView?
  private var heading: UIStackView?
  private var contentTopConstraint: NSLayoutConstraint?
  private var contentBottomConstraint: NSLayoutConstraint?
  private var contentLeadingConstraint: NSLayoutConstraint?
  private var contentTrailingConstraint: NSLayoutConstraint?
  private var headingHeightConstraint: NSLayoutConstraint?
  private var nowPlayingHeightConstraint: NSLayoutConstraint?
  private var lastLayoutSize = CGSize.zero
  private var nowPlayingTimer: Timer?

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
    startNowPlayingUpdates()
    CarPlayDiagnosticLog.write("PRIVATE_UI home_view_did_appear")
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    nowPlayingTimer?.invalidate()
    nowPlayingTimer = nil
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    let safeSize = view.safeAreaLayoutGuide.layoutFrame.size
    guard safeSize.width > 0, safeSize.height > 0, safeSize != lastLayoutSize else { return }
    lastLayoutSize = safeSize
    applyAdaptiveLayout(for: safeSize)
    CarPlayDiagnosticLog.write(
      "PRIVATE_UI layout bounds=\(view.bounds) safe=\(view.safeAreaInsets) scale=\(view.window?.screen.scale ?? 0)"
    )
  }

  private func applyAdaptiveLayout(for size: CGSize) {
    guard let content, let heading else { return }
    let heightScale = min(max(size.height / 240, 0.72), 2.0)
    let horizontalInset = min(max(size.width * 0.025, 8), 32)
    let verticalInset = min(max(size.height * 0.025, 2), 12)
    let headingHeight = min(max(size.height * 0.12, 20), 48)
    let nowPlayingHeight = min(max(size.height * 0.25, 42), 96)

    contentTopConstraint?.constant = verticalInset
    contentBottomConstraint?.constant = -verticalInset
    contentLeadingConstraint?.constant = horizontalInset
    contentTrailingConstraint?.constant = -horizontalInset
    headingHeightConstraint?.constant = headingHeight
    nowPlayingHeightConstraint?.constant = nowPlayingHeight

    content.setCustomSpacing(min(max(size.height * 0.025, 3), 12), after: heading)
    content.setCustomSpacing(min(max(size.height * 0.03, 4), 14), after: grid)
    grid.spacing = min(max(size.height * 0.018, 3), 10)
    grid.arrangedSubviews.compactMap { $0 as? UIStackView }.forEach { row in
      row.spacing = min(max(size.width * 0.01, 4), 16)
    }

    titleLabel.font = .systemFont(ofSize: 20 * heightScale, weight: .bold)
    statusLabel.font = .systemFont(ofSize: 11 * heightScale, weight: .medium)
  }

  private func buildLayout() {
    titleLabel.text = "音乐"
    titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
    titleLabel.textColor = .white

    statusLabel.text = "正在连接音乐库"
    statusLabel.font = .systemFont(ofSize: 11, weight: .medium)
    statusLabel.textColor = UIColor.white.withAlphaComponent(0.62)
    statusLabel.textAlignment = .right
    statusLabel.lineBreakMode = .byTruncatingTail

    let heading = UIStackView(arrangedSubviews: [titleLabel, statusLabel])
    heading.axis = .horizontal
    heading.alignment = .center
    heading.spacing = 12
    self.heading = heading

    grid.axis = .vertical
    grid.distribution = .fillEqually
    for pairStart in stride(from: 0, to: collections.count, by: 2) {
      let row = UIStackView()
      row.axis = .horizontal
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
            self?.refreshNowPlaying()
          }
        }
      }
    }
    nowPlayingBar.onOpen = { [weak self] in
      guard let self, self.presentedViewController == nil else { return }
      let controller = CarPlayNowPlayingViewController()
      controller.modalPresentationStyle = .fullScreen
      self.present(controller, animated: false)
    }
    nowPlayingBar.onFavorite = { [weak self] in
      CarPlayBridge.shared.invoke("toggleFavorite") { result, error in
        DispatchQueue.main.async {
          if let error {
            self?.showError(error.localizedDescription)
          } else if let favorite = result as? Bool {
            self?.nowPlayingBar.setFavorite(favorite)
          }
        }
      }
    }

    let content = UIStackView(arrangedSubviews: [heading, grid, nowPlayingBar])
    content.axis = .vertical
    content.spacing = 0
    content.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(content)
    self.content = content

    let top = content.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
    let bottom = content.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
    let leading = content.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor)
    let trailing = content.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)
    let headingHeight = heading.heightAnchor.constraint(equalToConstant: 24)
    let nowPlayingHeight = nowPlayingBar.heightAnchor.constraint(equalToConstant: 52)
    contentTopConstraint = top
    contentBottomConstraint = bottom
    contentLeadingConstraint = leading
    contentTrailingConstraint = trailing
    headingHeightConstraint = headingHeight
    nowPlayingHeightConstraint = nowPlayingHeight

    NSLayoutConstraint.activate([
      top, bottom, leading, trailing, headingHeight, nowPlayingHeight,
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
        self.refreshNowPlaying()
      }
    }
  }

  private func startNowPlayingUpdates() {
    nowPlayingTimer?.invalidate()
    refreshNowPlaying()
    nowPlayingTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
      self?.refreshNowPlaying()
    }
  }

  private func refreshNowPlaying() {
    CarPlayBridge.shared.invoke("getNowPlaying") { [weak self] result, _ in
      DispatchQueue.main.async {
        guard let state = result as? [String: Any] else { return }
        self?.nowPlayingBar.apply(state)
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
  private let icon: UIImageView
  private let titleLabel: UILabel
  private let subtitleLabel: UILabel
  private var iconLeadingConstraint: NSLayoutConstraint!
  private var iconWidthConstraint: NSLayoutConstraint!
  private var iconHeightConstraint: NSLayoutConstraint!
  private var labelsLeadingConstraint: NSLayoutConstraint!
  private var labelsTrailingConstraint: NSLayoutConstraint!
  private var lastHeight: CGFloat = 0

  init(collection: CarPlayCollection) {
    icon = UIImageView(image: UIImage(systemName: collection.symbol))
    titleLabel = UILabel()
    subtitleLabel = UILabel()
    super.init(frame: .zero)
    backgroundColor = UIColor.white.withAlphaComponent(0.075)
    layer.cornerRadius = 8

    icon.tintColor = collection.tint
    icon.contentMode = .scaleAspectFit

    titleLabel.text = collection.title
    titleLabel.textColor = .white
    titleLabel.lineBreakMode = .byTruncatingTail

    subtitleLabel.text = collection.subtitle
    subtitleLabel.textColor = UIColor.white.withAlphaComponent(0.55)
    subtitleLabel.lineBreakMode = .byTruncatingTail

    let labels = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
    labels.axis = .vertical
    labels.spacing = 1

    [icon, labels].forEach {
      $0.isUserInteractionEnabled = false
      $0.translatesAutoresizingMaskIntoConstraints = false
      addSubview($0)
    }

    iconLeadingConstraint = icon.leadingAnchor.constraint(equalTo: leadingAnchor)
    iconWidthConstraint = icon.widthAnchor.constraint(equalToConstant: 18)
    iconHeightConstraint = icon.heightAnchor.constraint(equalToConstant: 18)
    labelsLeadingConstraint = labels.leadingAnchor.constraint(equalTo: icon.trailingAnchor)
    labelsTrailingConstraint = labels.trailingAnchor.constraint(equalTo: trailingAnchor)
    NSLayoutConstraint.activate([
      iconLeadingConstraint,
      icon.centerYAnchor.constraint(equalTo: centerYAnchor),
      iconWidthConstraint, iconHeightConstraint,
      labelsLeadingConstraint, labelsTrailingConstraint,
      labels.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    guard bounds.height > 0, bounds.height != lastHeight else { return }
    lastHeight = bounds.height
    let scale = min(max(bounds.height / 40, 0.72), 2.0)
    let inset = min(max(bounds.height * 0.25, 7), 20)
    let iconSize = min(max(bounds.height * 0.45, 14), 36)
    iconLeadingConstraint.constant = inset
    iconWidthConstraint.constant = iconSize
    iconHeightConstraint.constant = iconSize
    labelsLeadingConstraint.constant = min(max(bounds.height * 0.2, 6), 16)
    labelsTrailingConstraint.constant = -inset
    titleLabel.font = .systemFont(ofSize: 14 * scale, weight: .semibold)
    subtitleLabel.font = .systemFont(ofSize: 9 * scale, weight: .regular)
  }

  override var isHighlighted: Bool {
    didSet { alpha = isHighlighted ? 0.62 : 1 }
  }
}

private final class CarPlayNowPlayingBar: UIView, UIGestureRecognizerDelegate {
  var onControl: ((String) -> Void)?
  var onOpen: (() -> Void)?
  var onFavorite: (() -> Void)?

  private let titleLabel = UILabel()
  private let artistLabel = UILabel()
  private let favoriteButton = UIButton(type: .system)
  private let playButton = UIButton(type: .system)
  private var labelsLeadingConstraint: NSLayoutConstraint!
  private var labelsTrailingConstraint: NSLayoutConstraint!
  private var controlsTrailingConstraint: NSLayoutConstraint!
  private var controlsWidthConstraint: NSLayoutConstraint!
  private var controlsHeightConstraint: NSLayoutConstraint!
  private var favoriteWidthConstraint: NSLayoutConstraint!
  private var favoriteHeightConstraint: NSLayoutConstraint!
  private var controls: UIStackView!
  private var lastSize = CGSize.zero

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = UIColor.white.withAlphaComponent(0.09)
    layer.cornerRadius = 8

    titleLabel.text = "暂无播放"
    titleLabel.textColor = .white
    titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
    titleLabel.lineBreakMode = .byTruncatingTail

    artistLabel.text = "选择歌曲开始播放"
    artistLabel.textColor = UIColor.white.withAlphaComponent(0.56)
    artistLabel.font = .systemFont(ofSize: 9)
    artistLabel.lineBreakMode = .byTruncatingTail

    favoriteButton.setImage(UIImage(systemName: "heart"), for: .normal)
    favoriteButton.tintColor = .white
    favoriteButton.addTarget(self, action: #selector(favoriteTapped), for: .touchUpInside)

    let labels = UIStackView(arrangedSubviews: [titleLabel, artistLabel])
    labels.axis = .vertical
    labels.spacing = 1

    let previous = controlButton(symbol: "backward.fill", action: #selector(previousTapped))
    playButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
    playButton.tintColor = .white
    playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
    let next = controlButton(symbol: "forward.fill", action: #selector(nextTapped))
    controls = UIStackView(arrangedSubviews: [previous, playButton, next])
    controls.axis = .horizontal
    controls.spacing = 8
    controls.distribution = .fillEqually

    let tap = UITapGestureRecognizer(target: self, action: #selector(openTapped))
    tap.delegate = self
    addGestureRecognizer(tap)

    [labels, favoriteButton, controls].forEach {
      $0.translatesAutoresizingMaskIntoConstraints = false
      addSubview($0)
    }
    labelsLeadingConstraint = labels.leadingAnchor.constraint(equalTo: leadingAnchor)
    labelsTrailingConstraint = labels.trailingAnchor.constraint(lessThanOrEqualTo: favoriteButton.leadingAnchor)
    controlsTrailingConstraint = controls.trailingAnchor.constraint(equalTo: trailingAnchor)
    controlsWidthConstraint = controls.widthAnchor.constraint(equalToConstant: 108)
    controlsHeightConstraint = controls.heightAnchor.constraint(equalToConstant: 36)
    favoriteWidthConstraint = favoriteButton.widthAnchor.constraint(equalToConstant: 36)
    favoriteHeightConstraint = favoriteButton.heightAnchor.constraint(equalToConstant: 36)
    NSLayoutConstraint.activate([
      labelsLeadingConstraint,
      labels.centerYAnchor.constraint(equalTo: centerYAnchor),
      labelsTrailingConstraint,
      favoriteButton.trailingAnchor.constraint(equalTo: controls.leadingAnchor, constant: -4),
      favoriteButton.centerYAnchor.constraint(equalTo: centerYAnchor),
      favoriteWidthConstraint, favoriteHeightConstraint,
      controlsTrailingConstraint,
      controls.centerYAnchor.constraint(equalTo: centerYAnchor),
      controlsWidthConstraint, controlsHeightConstraint,
    ])
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    guard bounds.width > 0, bounds.height > 0, bounds.size != lastSize else { return }
    lastSize = bounds.size
    let scale = min(max(bounds.height / 52, 0.72), 2.0)
    let horizontalInset = min(max(bounds.height * 0.22, 8), 24)
    labelsLeadingConstraint.constant = horizontalInset
    labelsTrailingConstraint.constant = -min(max(bounds.height * 0.15, 5), 16)
    controlsTrailingConstraint.constant = -horizontalInset
    controlsWidthConstraint.constant = min(max(bounds.width * 0.22, 90), 240)
    controlsHeightConstraint.constant = min(max(bounds.height * 0.7, 30), 72)
    favoriteWidthConstraint.constant = controlsHeightConstraint.constant
    favoriteHeightConstraint.constant = controlsHeightConstraint.constant
    controls.spacing = min(max(bounds.height * 0.15, 5), 16)
    titleLabel.font = .systemFont(ofSize: 14 * scale, weight: .semibold)
    artistLabel.font = .systemFont(ofSize: 9 * scale)
  }

  func refresh() {
    let info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
    titleLabel.text = info[MPMediaItemPropertyTitle] as? String ?? "暂无播放"
    artistLabel.text = info[MPMediaItemPropertyArtist] as? String ?? "选择歌曲开始播放"
    let rate = (info[MPNowPlayingInfoPropertyPlaybackRate] as? NSNumber)?.doubleValue ?? 0
    playButton.setImage(UIImage(systemName: rate > 0 ? "pause.fill" : "play.fill"), for: .normal)
  }

  func apply(_ state: [String: Any]) {
    guard state["hasSong"] as? Bool == true else {
      titleLabel.text = "暂无播放"
      artistLabel.text = "选择歌曲开始播放"
      playButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
      setFavorite(false)
      return
    }
    titleLabel.text = state["name"] as? String ?? "暂无播放"
    artistLabel.text = state["singer"] as? String ?? ""
    let playing = state["playing"] as? Bool ?? false
    playButton.setImage(UIImage(systemName: playing ? "pause.fill" : "play.fill"), for: .normal)
    setFavorite(state["favorite"] as? Bool ?? false)
  }

  func setFavorite(_ favorite: Bool) {
    favoriteButton.setImage(UIImage(systemName: favorite ? "heart.fill" : "heart"), for: .normal)
    favoriteButton.tintColor = favorite
      ? UIColor(red: 0.96, green: 0.31, blue: 0.40, alpha: 1)
      : .white
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
  @objc private func favoriteTapped() { onFavorite?() }
  @objc private func openTapped() { onOpen?() }

  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldReceive touch: UITouch
  ) -> Bool {
    var touchedView: UIView? = touch.view
    while let view = touchedView, view !== self {
      if view is UIControl { return false }
      touchedView = view.superview
    }
    return true
  }
}

private struct CarPlayLyricSyllable {
  let startMs: Int
  let durationMs: Int
  let text: String
}

private struct CarPlayLyricLine {
  let startMs: Int
  let durationMs: Int
  let text: String
  let syllables: [CarPlayLyricSyllable]
}

private final class CarPlayKaraokeView: UIView {
  private let inactiveLabel = UILabel()
  private let activeLabel = UILabel()
  private let activeContainer = UIView()
  private var progress: CGFloat = 0

  override init(frame: CGRect) {
    super.init(frame: frame)
    clipsToBounds = true
    activeContainer.clipsToBounds = true
    [inactiveLabel, activeLabel].forEach { label in
      label.textAlignment = .center
      label.numberOfLines = 2
      label.lineBreakMode = .byTruncatingTail
    }
    inactiveLabel.textColor = UIColor.white.withAlphaComponent(0.32)
    activeLabel.textColor = .white
    addSubview(inactiveLabel)
    addSubview(activeContainer)
    activeContainer.addSubview(activeLabel)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    inactiveLabel.frame = bounds
    activeContainer.frame = CGRect(
      x: 0,
      y: 0,
      width: bounds.width * progress,
      height: bounds.height
    )
    activeLabel.frame = bounds
  }

  func update(text: String, progress: Double, fontSize: CGFloat) {
    inactiveLabel.text = text
    activeLabel.text = text
    let font = UIFont.systemFont(ofSize: fontSize, weight: .bold)
    inactiveLabel.font = font
    activeLabel.font = font
    self.progress = CGFloat(min(max(progress, 0), 1))
    setNeedsLayout()
  }
}

private final class CarPlayNowPlayingViewController: UIViewController {
  private static let visualDelayMs = 450
  private let backButton = UIButton(type: .system)
  private let artworkView = UIImageView()
  private let playbackPanel = UIView()
  private let titleLabel = UILabel()
  private let artistLabel = UILabel()
  private let favoriteButton = UIButton(type: .system)
  private let previousLyricLabel = UILabel()
  private let karaokeView = CarPlayKaraokeView()
  private let nextLyricLabel = UILabel()
  private let progressView = UIProgressView(progressViewStyle: .default)
  private let elapsedLabel = UILabel()
  private let durationLabel = UILabel()
  private let previousButton = UIButton(type: .system)
  private let playButton = UIButton(type: .system)
  private let nextButton = UIButton(type: .system)
  private var pollTimer: Timer?
  private var displayLink: CADisplayLink?
  private var snapshotPositionMs = 0
  private var snapshotDurationMs = 0
  private var snapshotDate = Date()
  private var snapshotPlaying = false
  private var currentLine: CarPlayLyricLine?
  private var currentSongId = ""
  private var displayedArtwork: MPMediaItemArtwork?
  private var requestInFlight = false

  override func viewDidLoad() {
    super.viewDidLoad()
    buildView()
    CarPlayDiagnosticLog.write("PRIVATE_UI now_playing_view_did_load")
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    refreshSnapshot()
    pollTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
      self?.refreshSnapshot()
    }
    let displayLink = CADisplayLink(target: self, selector: #selector(updatePlaybackFrame))
    displayLink.add(to: .main, forMode: .common)
    self.displayLink = displayLink
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    pollTimer?.invalidate()
    pollTimer = nil
    displayLink?.invalidate()
    displayLink = nil
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    let safe = view.safeAreaLayoutGuide.layoutFrame
    guard safe.width > 0, safe.height > 0 else { return }
    let insetX = min(max(safe.width * 0.025, 8), 32)
    let insetY = min(max(safe.height * 0.025, 3), 14)
    let gap = min(max(safe.width * 0.018, 8), 28)
    let contentHeight = max(safe.height - insetY * 2, 80)
    let artworkSide = min(contentHeight, max(safe.width * 0.34, 84))
    artworkView.frame = CGRect(
      x: safe.minX + insetX,
      y: safe.minY + insetY + max((contentHeight - artworkSide) / 2, 0),
      width: artworkSide,
      height: artworkSide
    )
    artworkView.layer.cornerRadius = min(max(artworkSide * 0.06, 5), 14)
    let backSide = min(max(artworkSide * 0.18, 34), 58)
    backButton.frame = CGRect(x: artworkView.frame.minX + 5, y: artworkView.frame.minY + 5, width: backSide, height: backSide)
    backButton.backgroundColor = UIColor.black.withAlphaComponent(0.42)
    backButton.layer.cornerRadius = 8

    let panelX = artworkView.frame.maxX + gap
    let panelWidth = max(safe.maxX - insetX - panelX, 80)
    playbackPanel.frame = CGRect(x: panelX, y: safe.minY + insetY, width: panelWidth, height: contentHeight)
    playbackPanel.layer.cornerRadius = 8
    let panelInset = min(max(contentHeight * 0.06, 8), 22)
    let innerX = panelX + panelInset
    let innerWidth = max(panelWidth - panelInset * 2, 40)
    let infoHeight = contentHeight * 0.19
    let favoriteSide = min(max(infoHeight * 0.72, 30), 56)
    titleLabel.frame = CGRect(x: innerX, y: playbackPanel.frame.minY + panelInset * 0.45, width: innerWidth - favoriteSide - 8, height: infoHeight * 0.58)
    artistLabel.frame = CGRect(x: innerX, y: titleLabel.frame.maxY, width: titleLabel.frame.width, height: infoHeight * 0.34)
    favoriteButton.frame = CGRect(x: playbackPanel.frame.maxX - panelInset - favoriteSide, y: playbackPanel.frame.minY + panelInset * 0.55, width: favoriteSide, height: favoriteSide)

    let controlsHeight = contentHeight * 0.24
    let progressHeight = min(max(contentHeight * 0.09, 14), 28)
    let lyricsTop = playbackPanel.frame.minY + panelInset * 0.45 + infoHeight
    let lyricsBottom = playbackPanel.frame.maxY - panelInset - controlsHeight - progressHeight
    let lyricsHeight = max(lyricsBottom - lyricsTop, 34)
    let sideLineHeight = lyricsHeight * 0.22
    previousLyricLabel.frame = CGRect(x: innerX, y: lyricsTop, width: innerWidth, height: sideLineHeight)
    karaokeView.frame = CGRect(x: innerX, y: previousLyricLabel.frame.maxY, width: innerWidth, height: lyricsHeight - sideLineHeight * 2)
    nextLyricLabel.frame = CGRect(x: innerX, y: karaokeView.frame.maxY, width: innerWidth, height: sideLineHeight)

    let progressY = lyricsBottom + max(progressHeight * 0.08, 1)
    let timeWidth = min(max(innerWidth * 0.12, 38), 66)
    elapsedLabel.frame = CGRect(x: innerX, y: progressY, width: timeWidth, height: progressHeight)
    durationLabel.frame = CGRect(x: playbackPanel.frame.maxX - panelInset - timeWidth, y: progressY, width: timeWidth, height: progressHeight)
    progressView.frame = CGRect(
      x: elapsedLabel.frame.maxX + 6,
      y: progressY + progressHeight * 0.5,
      width: max(durationLabel.frame.minX - elapsedLabel.frame.maxX - 12, 20),
      height: 4
    )
    let buttonSide = min(max(controlsHeight * 0.72, 32), 64)
    let buttonGap = min(max(innerWidth * 0.06, 10), 30)
    let buttonsWidth = buttonSide * 3 + buttonGap * 2
    let buttonsX = playbackPanel.frame.midX - buttonsWidth / 2
    let buttonsY = playbackPanel.frame.maxY - panelInset - buttonSide
    previousButton.frame = CGRect(x: buttonsX, y: buttonsY, width: buttonSide, height: buttonSide)
    playButton.frame = CGRect(x: previousButton.frame.maxX + buttonGap, y: buttonsY, width: buttonSide, height: buttonSide)
    nextButton.frame = CGRect(x: playButton.frame.maxX + buttonGap, y: buttonsY, width: buttonSide, height: buttonSide)

    let heightScale = min(max(safe.height / 240, 0.72), 2)
    titleLabel.font = .systemFont(ofSize: 17 * heightScale, weight: .bold)
    artistLabel.font = .systemFont(ofSize: 10 * heightScale, weight: .medium)
    previousLyricLabel.font = .systemFont(ofSize: 10 * heightScale, weight: .medium)
    nextLyricLabel.font = previousLyricLabel.font
    elapsedLabel.font = .monospacedDigitSystemFont(ofSize: 8 * heightScale, weight: .medium)
    durationLabel.font = elapsedLabel.font
    updatePlaybackFrame()
    CarPlayDiagnosticLog.write("PRIVATE_UI now_playing_layout safe=\(safe.size) artwork=\(artworkSide)")
  }

  private func buildView() {
    view.backgroundColor = UIColor(red: 0.035, green: 0.043, blue: 0.055, alpha: 1)
    playbackPanel.backgroundColor = UIColor.white.withAlphaComponent(0.075)
    artworkView.contentMode = .scaleAspectFill
    artworkView.clipsToBounds = true
    artworkView.backgroundColor = UIColor.white.withAlphaComponent(0.08)

    backButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
    backButton.tintColor = .white
    backButton.addTarget(self, action: #selector(close), for: .touchUpInside)
    favoriteButton.setImage(UIImage(systemName: "heart"), for: .normal)
    favoriteButton.tintColor = .white
    favoriteButton.addTarget(self, action: #selector(favoriteTapped), for: .touchUpInside)
    configureLabel(titleLabel, color: .white, alignment: .left)
    configureLabel(artistLabel, color: UIColor.white.withAlphaComponent(0.58), alignment: .left)
    configureLabel(previousLyricLabel, color: UIColor.white.withAlphaComponent(0.30), alignment: .center)
    configureLabel(nextLyricLabel, color: UIColor.white.withAlphaComponent(0.30), alignment: .center)
    previousLyricLabel.numberOfLines = 1
    nextLyricLabel.numberOfLines = 1

    elapsedLabel.textColor = UIColor.white.withAlphaComponent(0.56)
    durationLabel.textColor = UIColor.white.withAlphaComponent(0.56)
    durationLabel.textAlignment = .right
    progressView.trackTintColor = UIColor.white.withAlphaComponent(0.18)
    progressView.progressTintColor = .white
    configureControl(previousButton, symbol: "backward.fill", action: #selector(previousTapped))
    configureControl(playButton, symbol: "play.fill", action: #selector(playTapped))
    configureControl(nextButton, symbol: "forward.fill", action: #selector(nextTapped))

    [artworkView, playbackPanel, backButton, titleLabel, artistLabel, favoriteButton,
     previousLyricLabel, karaokeView, nextLyricLabel, progressView, elapsedLabel, durationLabel,
     previousButton, playButton, nextButton].forEach { view.addSubview($0) }
    showEmptyState()
  }

  private func configureLabel(_ label: UILabel, color: UIColor, alignment: NSTextAlignment) {
    label.textColor = color
    label.textAlignment = alignment
    label.lineBreakMode = .byTruncatingTail
  }

  private func configureControl(_ button: UIButton, symbol: String, action: Selector) {
    button.setImage(UIImage(systemName: symbol), for: .normal)
    button.tintColor = .white
    button.backgroundColor = UIColor.white.withAlphaComponent(0.10)
    button.layer.cornerRadius = 8
    button.addTarget(self, action: action, for: .touchUpInside)
  }

  private func refreshSnapshot() {
    guard !requestInFlight else { return }
    requestInFlight = true
    CarPlayBridge.shared.invoke("getNowPlaying") { [weak self] result, error in
      DispatchQueue.main.async {
        guard let self else { return }
        self.requestInFlight = false
        guard error == nil, let state = result as? [String: Any] else { return }
        self.applySnapshot(state)
      }
    }
  }

  private func applySnapshot(_ state: [String: Any]) {
    guard state["hasSong"] as? Bool == true else {
      showEmptyState()
      return
    }
    let songId = state["id"] as? String ?? ""
    if songId != currentSongId {
      currentSongId = songId
      displayedArtwork = nil
    }
    refreshArtwork()
    titleLabel.text = state["name"] as? String ?? "正在播放"
    artistLabel.text = state["singer"] as? String ?? ""
    previousLyricLabel.text = state["previousLyric"] as? String ?? ""
    nextLyricLabel.text = state["nextLyric"] as? String ?? ""
    snapshotPositionMs = (state["positionMs"] as? NSNumber)?.intValue ?? 0
    snapshotDurationMs = (state["durationMs"] as? NSNumber)?.intValue ?? 0
    snapshotPlaying = state["playing"] as? Bool ?? false
    snapshotDate = Date()
    playButton.setImage(UIImage(systemName: snapshotPlaying ? "pause.fill" : "play.fill"), for: .normal)
    setFavorite(state["favorite"] as? Bool ?? false)

    if let rawLine = state["currentLyric"] as? [String: Any] {
      let rawSyllables = rawLine["syllables"] as? [[String: Any]] ?? []
      currentLine = CarPlayLyricLine(
        startMs: (rawLine["startMs"] as? NSNumber)?.intValue ?? 0,
        durationMs: (rawLine["durationMs"] as? NSNumber)?.intValue ?? 0,
        text: rawLine["text"] as? String ?? "",
        syllables: rawSyllables.map { item in
          CarPlayLyricSyllable(
            startMs: (item["startMs"] as? NSNumber)?.intValue ?? 0,
            durationMs: (item["durationMs"] as? NSNumber)?.intValue ?? 0,
            text: item["text"] as? String ?? ""
          )
        }
      )
    } else {
      currentLine = nil
    }
    updatePlaybackFrame()
  }

  private func showEmptyState() {
    titleLabel.text = "暂无播放"
    artistLabel.text = "请先选择一首歌曲"
    previousLyricLabel.text = ""
    nextLyricLabel.text = ""
    currentLine = nil
    snapshotPositionMs = 0
    snapshotDurationMs = 0
    snapshotPlaying = false
    setFavorite(false)
    karaokeView.update(text: "歌词将在这里显示", progress: 0, fontSize: 20)
    updatePlaybackFrame()
  }

  private func refreshArtwork() {
    guard let artwork = MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork]
      as? MPMediaItemArtwork else {
      if displayedArtwork == nil {
        artworkView.image = nil
      }
      return
    }
    guard artwork !== displayedArtwork else { return }
    displayedArtwork = artwork
    let image = artwork.image(at: CGSize(width: 720, height: 720))
    artworkView.image = image
  }

  @objc private func updatePlaybackFrame() {
    let elapsedSinceSnapshot = snapshotPlaying ? Date().timeIntervalSince(snapshotDate) * 1000 : 0
    let positionMs = min(snapshotPositionMs + Int(elapsedSinceSnapshot), max(snapshotDurationMs, snapshotPositionMs))
    let progress = snapshotDurationMs > 0 ? Float(positionMs) / Float(snapshotDurationMs) : 0
    progressView.setProgress(min(max(progress, 0), 1), animated: false)
    elapsedLabel.text = formatTime(positionMs)
    durationLabel.text = formatTime(snapshotDurationMs)

    let safeHeight = view.safeAreaLayoutGuide.layoutFrame.height
    let lyricFontSize = 18 * min(max(safeHeight / 240, 0.72), 2)
    if let line = currentLine {
      karaokeView.update(
        text: line.text,
        progress: lyricProgress(line, at: max(positionMs - Self.visualDelayMs, 0)),
        fontSize: lyricFontSize
      )
    } else {
      karaokeView.update(text: "纯音乐，请欣赏", progress: 0, fontSize: lyricFontSize)
    }
  }

  private func lyricProgress(_ line: CarPlayLyricLine, at positionMs: Int) -> Double {
    guard !line.syllables.isEmpty, positionMs >= line.startMs else { return 0 }
    if line.syllables.count == 1, line.syllables[0].durationMs == 0 { return 1 }
    let weights = line.syllables.map { max($0.text.count, 0) }
    let totalWeight = weights.reduce(0, +)
    guard totalWeight > 0 else { return 0 }
    var completedWeight = 0
    for (index, syllable) in line.syllables.enumerated() {
      if positionMs < syllable.startMs {
        return Double(completedWeight) / Double(totalWeight)
      }
      let endMs = syllable.startMs + syllable.durationMs
      if syllable.durationMs > 0, positionMs < endMs {
        let local = Double(positionMs - syllable.startMs) / Double(syllable.durationMs)
        return min(max((Double(completedWeight) + Double(weights[index]) * local) / Double(totalWeight), 0), 1)
      }
      completedWeight += weights[index]
    }
    return 1
  }

  private func formatTime(_ milliseconds: Int) -> String {
    let seconds = max(milliseconds, 0) / 1000
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
  }

  private func perform(_ action: String) {
    CarPlayBridge.shared.invoke(action) { [weak self] _, _ in
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { self?.refreshSnapshot() }
    }
  }

  private func setFavorite(_ favorite: Bool) {
    favoriteButton.setImage(UIImage(systemName: favorite ? "heart.fill" : "heart"), for: .normal)
    favoriteButton.tintColor = favorite
      ? UIColor(red: 0.96, green: 0.31, blue: 0.40, alpha: 1)
      : .white
  }

  @objc private func close() { dismiss(animated: false) }
  @objc private func favoriteTapped() {
    CarPlayBridge.shared.invoke("toggleFavorite") { [weak self] result, _ in
      DispatchQueue.main.async {
        if let favorite = result as? Bool { self?.setFavorite(favorite) }
        self?.refreshSnapshot()
      }
    }
  }
  @objc private func previousTapped() { perform("previous") }
  @objc private func playTapped() { perform("togglePlayPause") }
  @objc private func nextTapped() { perform("next") }
}

private class CarPlayBaseListViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
  let tableView = UITableView(frame: .zero, style: .plain)
  private let heading: String
  private let headingLabel = UILabel()
  private var headerTopConstraint: NSLayoutConstraint!
  private var headerLeadingConstraint: NSLayoutConstraint!
  private var headerTrailingConstraint: NSLayoutConstraint!
  private var headerHeightConstraint: NSLayoutConstraint!
  private var tableLeadingConstraint: NSLayoutConstraint!
  private var tableTrailingConstraint: NSLayoutConstraint!
  private var backWidthConstraint: NSLayoutConstraint!
  private var lastLayoutSize = CGSize.zero

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

    headingLabel.text = heading
    headingLabel.textColor = .white
    headingLabel.font = .systemFont(ofSize: 18, weight: .bold)

    let header = UIStackView(arrangedSubviews: [back, headingLabel])
    header.axis = .horizontal
    header.spacing = 14
    backWidthConstraint = back.widthAnchor.constraint(equalToConstant: 44)
    backWidthConstraint.isActive = true

    tableView.backgroundColor = .clear
    tableView.separatorColor = UIColor.white.withAlphaComponent(0.12)
    tableView.dataSource = self
    tableView.delegate = self
    tableView.rowHeight = UITableView.automaticDimension
    tableView.estimatedRowHeight = 44
    tableView.tableFooterView = UIView()

    [header, tableView].forEach {
      $0.translatesAutoresizingMaskIntoConstraints = false
      view.addSubview($0)
    }
    headerTopConstraint = header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
    headerLeadingConstraint = header.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor)
    headerTrailingConstraint = header.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)
    headerHeightConstraint = header.heightAnchor.constraint(equalToConstant: 32)
    tableLeadingConstraint = tableView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor)
    tableTrailingConstraint = tableView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)
    NSLayoutConstraint.activate([
      headerTopConstraint, headerLeadingConstraint, headerTrailingConstraint, headerHeightConstraint,
      tableView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 2),
      tableLeadingConstraint, tableTrailingConstraint,
      tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
    ])
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    let size = view.safeAreaLayoutGuide.layoutFrame.size
    guard size.width > 0, size.height > 0, size != lastLayoutSize else { return }
    lastLayoutSize = size
    let scale = min(max(size.height / 240, 0.72), 2.0)
    let horizontalInset = min(max(size.width * 0.02, 6), 28)
    let headerHeight = min(max(size.height * 0.16, 28), 64)
    headerTopConstraint.constant = min(max(size.height * 0.015, 2), 10)
    headerLeadingConstraint.constant = horizontalInset
    headerTrailingConstraint.constant = -horizontalInset
    headerHeightConstraint.constant = headerHeight
    tableLeadingConstraint.constant = horizontalInset
    tableTrailingConstraint.constant = -horizontalInset
    backWidthConstraint.constant = headerHeight
    headingLabel.font = .systemFont(ofSize: 18 * scale, weight: .bold)
    tableView.rowHeight = min(max(size.height * 0.19, 38), 84)
    tableView.reloadData()
    CarPlayDiagnosticLog.write("PRIVATE_UI list_layout size=\(size) row=\(tableView.rowHeight)")
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
    let scale = min(max(view.safeAreaLayoutGuide.layoutFrame.height / 240, 0.72), 2.0)
    cell.backgroundColor = .clear
    cell.textLabel?.text = title
    cell.textLabel?.textColor = .white
    cell.textLabel?.font = .systemFont(ofSize: 14 * scale, weight: .semibold)
    cell.detailTextLabel?.text = detail
    cell.detailTextLabel?.textColor = UIColor.white.withAlphaComponent(0.52)
    cell.detailTextLabel?.font = .systemFont(ofSize: 9 * scale)
    cell.accessoryType = .disclosureIndicator
    cell.tintColor = UIColor.white.withAlphaComponent(0.45)
  }
}

private final class CarPlaySongListViewController: CarPlayBaseListViewController {
  private let source: String
  private var songs: [[String: Any]] = []
  private var message = "正在载入音乐…"
  private var loadingMore = false
  private var canLoadMore = true

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

  func tableView(
    _ tableView: UITableView,
    willDisplay cell: UITableViewCell,
    forRowAt indexPath: IndexPath
  ) {
    guard source == "queue",
          canLoadMore,
          !loadingMore,
          !songs.isEmpty,
          indexPath.row >= songs.count - 2 else { return }
    loadingMore = true
    CarPlayDiagnosticLog.write("PRIVATE_UI queue_load_more start count=\(songs.count)")
    CarPlayBridge.shared.invoke("loadMoreQueue") { [weak self] result, error in
      DispatchQueue.main.async {
        guard let self else { return }
        self.loadingMore = false
        guard error == nil, let payload = result as? [String: Any] else { return }
        self.canLoadMore = payload["canLoadMore"] as? Bool ?? false
        let updatedSongs = payload["songs"] as? [[String: Any]] ?? []
        guard updatedSongs.count != self.songs.count else { return }
        self.songs = updatedSongs
        self.tableView.reloadData()
        CarPlayDiagnosticLog.write("PRIVATE_UI queue_load_more complete count=\(updatedSongs.count)")
      }
    }
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
