/// 真实歌单信息（所有数据硬编码，不需要 API 预加载）
class PlaylistInfo {
  final String name;
  final String id;
  final String coverUrl;
  const PlaylistInfo(this.name, this.id, {this.coverUrl = ''});
}

/// 歌单分类（名称和封面全部写死，点歌单时直接按 ID 去接口拉歌曲）
const playlistCategories = <String, List<PlaylistInfo>>{
  '榜单': [
    PlaylistInfo('热歌榜', '3778678',
        coverUrl:
            'https://p1.music.126.net/0SUEG8yDACfx0Bw2MYFv4Q==/109951170048519512.jpg'),
    PlaylistInfo('飙升榜', '19723756',
        coverUrl:
            'https://p1.music.126.net/rIi7Qzy2i2Y_1QD7cd0MYA==/109951170048506929.jpg'),
    PlaylistInfo('新歌榜', '3779629',
        coverUrl:
            'https://p1.music.126.net/5guhqPBTcIrrhLBotgaT6w==/109951170048511751.jpg'),
    PlaylistInfo('原创榜', '2884035',
        coverUrl:
            'https://p1.music.126.net/BaP9nrocNTL3gGThysv4eQ==/109951170091896587.jpg'),
    PlaylistInfo('抖音排行榜', '2250011882',
        coverUrl:
            'https://p1.music.126.net/8sRm2fQNh_KZeWmJ1sRhQQ==/109951165611408950.jpg'),
  ],
  '语种': [
    PlaylistInfo('欧美热歌榜', '2809513713',
        coverUrl:
            'https://p1.music.126.net/70_EO_Dc7NT_hhfvsapzcQ==/109951167430862162.jpg'),
    PlaylistInfo('韩语榜', '745956260',
        coverUrl:
            'https://p1.music.126.net/5oN9YaFznwNGXkmi8i2Ytw==/109951167430864741.jpg'),
    PlaylistInfo('日语榜', '5059644681',
        coverUrl:
            'https://p1.music.126.net/YFBFNI2F-4BveUpv6FKFuw==/109951167430864069.jpg'),
    PlaylistInfo('美国Billboard榜', '60198',
        coverUrl:
            'https://p1.music.126.net/rwRsVIJHQ68gglhA6TNEYA==/109951165611413732.jpg'),
    PlaylistInfo('UK排行榜周榜', '180106',
        coverUrl:
            'https://p1.music.126.net/fhAqiflLy3eU-ldmBQByrg==/109951165613082765.jpg'),
  ],
  '风格': [
    PlaylistInfo('电音榜', '1978921795',
        coverUrl:
            'https://p1.music.126.net/hXGObvXfsGtFjFvRhOYAkA==/109951170091888741.jpg'),
    PlaylistInfo('古典榜', '71384707',
        coverUrl:
            'https://p1.music.126.net/urByD_AmfBDBrs7fA9-O8A==/109951167976973225.jpg'),
    PlaylistInfo('ACG榜', '71385702',
        coverUrl:
            'https://p1.music.126.net/na1kEeCS1iZEkzOrs9r_9g==/109951167976973667.jpg'),
  ],
};
