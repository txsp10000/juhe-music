class Song {
  final String id;
  final String name;
  final String singer;
  final String album;
  final String source;
  final String picId;
  final String lyricId;
  final int duration;
  String cover;
  String lyric;

  Song({
    required this.id,
    required this.name,
    required this.singer,
    this.album = '',
    this.source = 'soda',
    this.picId = '',
    this.lyricId = '',
    this.duration = 0,
    this.cover = '',
    this.lyric = '',
  });

  factory Song.fromApiJson(Map<String, dynamic> json) {
    final entity = json['entity'];
    final nestedTrack = entity is Map ? entity['track'] : null;
    if (nestedTrack is Map) {
      return Song.fromApiJson(Map<String, dynamic>.from(nestedTrack));
    }
    final trackWrapper = entity is Map ? entity['track_wrapper'] : null;
    final wrappedTrack = trackWrapper is Map ? trackWrapper['track'] : null;
    if (wrappedTrack is Map) {
      return Song.fromApiJson(Map<String, dynamic>.from(wrappedTrack));
    }

    String parseSinger(dynamic artist) {
      if (artist == null) return '未知歌手';
      if (artist is List) return artist.join(' / ');
      return artist.toString();
    }

    String firstString(List<dynamic> values) {
      for (final value in values) {
        final text = value?.toString() ?? '';
        if (text.isNotEmpty && text != 'null') return text;
      }
      return '';
    }

    final albumJson = json['album'];
    final albumName = albumJson is Map
        ? albumJson['name']?.toString() ?? ''
        : albumJson?.toString() ?? '';
    final dur = json['interval'] ??
        json['time'] ??
        json['duration_ms'] ??
        json['duration'] ??
        0;
    final artists = json['artists'];
    final artist = artists is List
        ? artists
            .map((value) => value is Map ? value['name'] : value)
            .where((value) => value != null)
            .join(' / ')
        : json['artist'];
    final urlCover = json['url_cover'] ??
        json['cover_info'] ??
        (albumJson is Map ? albumJson['url_cover'] : null);
    final sodaCover = buildSodaImageUrl(urlCover, size: 720);
    return Song(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? '未知歌曲',
      singer: parseSinger(artist),
      album: albumName,
      source: json['source'] ?? 'soda',
      picId: firstString([
        if (artists is List) json['id'],
        json['pic_id'],
        json['picId'],
        json['pic'],
        if (albumJson is Map) albumJson['pic_str'],
        if (albumJson is Map) albumJson['pic'],
        if (albumJson is Map) albumJson['id'],
        json['id'],
      ]),
      lyricId: firstString([json['lyric_id'], json['lyricId'], json['id']]),
      duration: dur is num
          ? (dur > 10000 ? dur ~/ 1000 : dur.toInt())
          : int.tryParse(dur.toString()) ?? 0,
      cover: firstString([
        json['cover'],
        json['coverUrl'],
        json['cover_url'],
        json['pic_url'],
        if (albumJson is Map) albumJson['picUrl'],
        sodaCover,
      ]),
    );
  }

  factory Song.fromJson(Map<String, dynamic> json) {
    return Song(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? '',
      singer: json['singer'] ?? '',
      album: json['album'] ?? '',
      source: json['source'] ?? 'soda',
      picId: json['pic_id']?.toString() ?? '',
      lyricId: json['lyric_id']?.toString() ?? '',
      duration: json['duration'] is int
          ? json['duration']
          : int.tryParse(json['duration']?.toString() ?? '') ?? 0,
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

String buildSodaImageUrl(dynamic value, {int size = 720}) {
  if (value is String) return value;
  if (value is! Map) return '';
  final urls = value['urls'];
  final base =
      urls is List && urls.isNotEmpty ? urls.first?.toString() ?? '' : '';
  final uri = value['uri']?.toString() ?? '';
  final template = value['template_prefix']?.toString() ?? '';
  if (base.isEmpty) return '';
  if (uri.isEmpty) return base;
  final separator = base.endsWith('/') ? '' : '/';
  final suffix =
      template.isEmpty ? '~noop.image' : '~$template-resize:$size:$size.image';
  return '$base$separator$uri$suffix';
}
