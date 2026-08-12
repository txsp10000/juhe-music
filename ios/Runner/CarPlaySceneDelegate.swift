import CarPlay
import UIKit

/// CarPlay entry point for the music app. CarPlay renders templates, not the
/// Flutter view hierarchy, so this delegate always installs a native root
/// template as soon as the head unit connects.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
  private weak var interfaceController: CPInterfaceController?

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didConnect interfaceController: CPInterfaceController
  ) {
    self.interfaceController = interfaceController

    let library = CPListTemplate(
      title: "音乐库",
      sections: [
        CPListSection(items: [
          CPListItem(text: "最近播放", detailText: "继续播放上次的音乐", handler: openList),
          CPListItem(text: "我的收藏", detailText: "收藏的歌曲和专辑", handler: openList),
          CPListItem(text: "本地音乐", detailText: "设备上的音乐", handler: openList)
        ])
      ]
    )
    library.tabTitle = "音乐库"
    library.tabImage = UIImage(systemName: "music.note.list")

    let playlists = CPListTemplate(
      title: "歌单",
      sections: [
        CPListSection(items: [
          CPListItem(text: "我喜欢的音乐", detailText: "我的收藏", handler: openList),
          CPListItem(text: "最近添加", detailText: "新加入的歌曲", handler: openList)
        ])
      ]
    )
    playlists.tabTitle = "歌单"
    playlists.tabImage = UIImage(systemName: "rectangle.stack")

    // The shared template gives the head unit a functional now-playing view
    // and integrates with the system transport controls.
    let nowPlaying = CPNowPlayingTemplate.shared
    nowPlaying.tabTitle = "正在播放"
    nowPlaying.tabImage = UIImage(systemName: "play.circle")

    let rootTemplate = CPTabBarTemplate(templates: [library, playlists, nowPlaying])
    interfaceController.setRootTemplate(rootTemplate, animated: false)
  }

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didDisconnectInterfaceController interfaceController: CPInterfaceController
  ) {
    self.interfaceController = nil
  }

  private func openList(_ item: CPListItem, completion: @escaping () -> Void) {
    let songs = [
      CPListItem(text: "全部播放", detailText: "开始播放此列表", handler: playList),
      CPListItem(text: "播放列表为空时也能安全显示", detailText: "稍后可由 Flutter 同步真实歌曲")
    ]
    let template = CPListTemplate(title: item.text, sections: [CPListSection(items: songs)])
    interfaceController?.pushTemplate(template, animated: true)
    completion()
  }

  private func playList(_ item: CPListItem, completion: @escaping () -> Void) {
    // Playback remains owned by the existing Flutter/audio-service layer.
    // The completion callback is required by CarPlay to end the selection UI.
    completion()
  }
}
