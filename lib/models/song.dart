class Song {
  final String id;
  final String name;
  final String singer;
  final String album;
  final String source;
  final String picId;
  final String lyricId;
  final int duration;
  String cover;   // 封面URL，异步获取后填入
  String lyric;   // 歌词，异步获取后填入

  Song({
    required this.id,
    required this.name,
    required this.singer,
    this.album = '',
    this.source = 'netease',
    this.picId = '',
    this.lyricId = '',
    this.duration = 0,
    this.cover = '',
    this.lyric = '',
  });

  factory Song.fromApiJson(Map<String, dynamic> json) {
    String parseSinger(dynamic artist) {
      if (artist == null) return '未知歌手';
      if (artist is List) return artist.join(' / ');
      return artist.toString();
    }

    final dur = json['interval'] ?? json['time'] ?? json['duration'] ?? 0;
    return Song(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? '未知歌曲',
      singer: parseSinger(json['artist']),
      album: json['album'] ?? '',
      source: json['source'] ?? 'netease',
      picId: json['pic_id']?.toString() ?? '',
      lyricId: json['lyric_id']?.toString() ?? '',
      duration: dur is int ? dur : int.tryParse(dur.toString()) ?? 0,
    );
  }

  /// 从本地存储的 JSON 反序列化（toJson 的逆操作）
  factory Song.fromJson(Map<String, dynamic> json) {
    return Song(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? '',
      singer: json['singer'] ?? '',
      album: json['album'] ?? '',
      source: json['source'] ?? 'netease',
      picId: json['pic_id']?.toString() ?? '',
      lyricId: json['lyric_id']?.toString() ?? '',
      duration: json['duration'] is int ? json['duration'] : int.tryParse(json['duration']?.toString() ?? '') ?? 0,
      cover: json['cover'] ?? '',
      lyric: json['lyric'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'singer': singer,
    'album': album,
    'source': source,
    'pic_id': picId,
    'lyric_id': lyricId,
    'duration': duration,
    'cover': cover,
    'lyric': lyric,
  };
}
