class Song {
  final String id;
  final String name;
  final String singer;
  final String album;
  final String source;
  final String cover;
  final int duration; // seconds
  final String hash;
  final String songmid;
  String quality;
  String bitrate;
  String lyric;

  Song({
    required this.id,
    required this.name,
    required this.singer,
    this.album = '',
    this.source = 'qsvip',
    this.cover = '',
    this.duration = 0,
    this.hash = '',
    this.songmid = '',
    this.quality = 'flac',
    this.bitrate = '',
    this.lyric = '',
  });

  String getHashOrMid() {
    if (hash.isNotEmpty) return hash;
    if (songmid.isNotEmpty) return songmid;
    return id;
  }

  factory Song.fromJson(Map<String, dynamic> json) {
    return Song(
      id: json['id'] ?? '',
      name: json['name'] ?? '未知歌曲',
      singer: json['singer'] ?? json['artists'] ?? '未知歌手',
      album: json['album'] ?? '',
      source: json['source'] ?? 'qsvip',
      cover: json['cover'] ?? '',
      duration: json['duration'] ?? 0,
      hash: json['hash'] ?? '',
      songmid: json['songmid'] ?? '',
      quality: json['quality'] ?? 'flac',
      bitrate: json['bitrate'] ?? '',
      lyric: json['lyric'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'singer': singer,
    'album': album,
    'source': source,
    'cover': cover,
    'duration': duration,
    'hash': hash,
    'songmid': songmid,
    'quality': quality,
    'bitrate': bitrate,
    'lyric': lyric,
  };
}
