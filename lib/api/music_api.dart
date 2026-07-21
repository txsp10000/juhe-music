import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/song.dart';
import '../models/platform.dart';
import '../models/search_result.dart';

class MusicApi {
  static const _xinghaiMain =
      'https://music-api.gdstudio.xyz/api.php?use_xbridge3=true&loader_name=forest&need_sec_link=1&sec_link_scene=im&theme=light';
  static const _xinghaiMainBase = 'https://music-api.gdstudio.xyz/api.php';
  static const _xinghaiBackup = 'https://music-dl.sayqz.com/api/';
  static const _suyinQQ = 'https://oiapi.net/api/QQ_Music';
  static const _suyinQQKey = 'oiapi-ef6133b7-ac2f-dc7d-878c-d3e207a82575';
  static const _suyin163 = 'https://oiapi.net/api/Music_163';
  static const _suyinKuwo = 'https://oiapi.net/api/Kuwo';
  static const _suyinMigu = 'https://api.xcvts.cn/api/music/migu';
  static const _qishuiHttps = 'https://api.vsaa.cn/api/music.qishui.vip';
  static const _qishuiHttp = 'http://api.vsaa.cn/api/music.qishui.vip';
  static const _qishuiProxy = 'https://proxy.qishui.vsaa.cn/qishui/proxy';

  static const _changqing = {
    'tx': 'http://175.27.166.236/kgqq/qq.php?type=mp3&id=%s&level=%s',
    'wy': 'http://175.27.166.236/wy/wy.php?type=mp3&id=%s&level=%s',
    'kw': 'https://musicapi.haitangw.net/music/kw.php?type=mp3&id=%s&level=%s',
    'kg': 'https://music.haitangw.cc/kgqq/kg.php?type=mp3&id=%s&level=%s',
    'mg': 'https://music.haitangw.cc/musicapi/mg.php?type=mp3&id=%s&level=%s',
  };
  static const _nianxin = {
    'tx': 'https://music.nxinxz.com/kgqq/tx.php?id=%s&level=%s&type=mp3',
    'wy': 'http://music.nxinxz.com/wy.php?id=%s&level=%s&type=mp3',
    'kw': 'http://music.nxinxz.com/kw.php?id=%s&level=%s&type=mp3',
    'kg': 'https://music.nxinxz.com/kgqq/kg.php?id=%s&level=%s&type=mp3',
    'mg': 'http://music.nxinxz.com/mg.php?id=%s&level=%s&type=mp3',
  };

  static final _client = http.Client();
  static String _urlEnc(String s) => Uri.encodeComponent(s);

  static Future<String> _httpGet(String url) async {
    final resp = await _client.get(Uri.parse(url),
        headers: {'User-Agent': 'LX-Music-Mobile', 'Accept': 'application/json'});
    if (resp.statusCode >= 400) throw Exception('HTTP ${resp.statusCode}');
    return resp.body;
  }

  static Future<String> _httpPost(String url, String body) async {
    final resp = await _client.post(Uri.parse(url),
        headers: {'Content-Type': 'application/json'}, body: body);
    if (resp.statusCode >= 400) throw Exception('HTTP ${resp.statusCode}');
    return resp.body;
  }

  static Future<String> _httpGetWithFallback(Map<String, String> params,
      {int timeout = 15000}) async {
    final query = params.entries
        .map((e) => '${_urlEnc(e.key)}=${_urlEnc(e.value)}')
        .join('&');
    final urls = ['$_qishuiHttps?$query', '$_qishuiHttp?$query'];
    for (final u in urls) {
      try {
        final resp =
            await _client.get(Uri.parse(u)).timeout(Duration(milliseconds: timeout));
        if (resp.statusCode >= 400) throw Exception('HTTP ${resp.statusCode}');
        return resp.body;
      } catch (_) {}
    }
    throw Exception('汽水VIP请求失败');
  }

  static Future<List<Song>> qishuiSearch(String keyword,
      {int page = 1, int pageSize = 30}) async {
    final body = await _httpGetWithFallback({
      'act': 'search',
      'keywords': keyword,
      'page': page.toString(),
      'pagesize': pageSize.toString(),
      'type': 'music',
    });
    final json = jsonDecode(body);
    final data = json['data'];
    if (data == null) return [];
    final lists = data['lists'] ?? [];
    return (lists as List).map((el) {
      return Song(
        id: el['vid'] ?? el['id'] ?? '',
        songmid: el['vid'] ?? el['id'] ?? '',
        hash: el['vid'] ?? el['id'] ?? '',
        name: el['name'] ?? '未知歌曲',
        singer: el['artists'] ?? '未知歌手',
        album: el['album'] ?? '',
        cover: el['cover'] ?? el['pic'] ?? '',
        duration: (el['duration'] ?? 0) ~/ 1000,
        source: 'qsvip',
      );
    }).toList();
  }

  static Future<String> qishuiGetUrl(Song song,
      {String quality = 'flac'}) async {
    final q = quality.toLowerCase() == '128k'
        ? 'low'
        : quality.toLowerCase() == '320k'
            ? 'standard'
            : 'lossless';
    final body = await _httpGetWithFallback(
        {'act': 'song', 'id': song.id, 'quality': q},
        timeout: 20000);
    final json = jsonDecode(body);
    final dataArr = json['data'];
    if (dataArr == null || dataArr.isEmpty) throw Exception('qishui: 无data');
    final data = dataArr[0];
    final url = data['url'];
    if (url == null) throw Exception('qishui: 无URL');
    final ekey = data['ekey'];
    if (ekey != null && ekey.isNotEmpty) {
      final filename = data['filename'] ?? 'KMusic';
      final ext = data['fileExtension'] ?? 'aac';
      final proxyBody = await _httpPost(_qishuiProxy,
          jsonEncode({'url': url, 'key': ekey, 'filename': filename, 'ext': ext}));
      final proxyJson = jsonDecode(proxyBody);
      if (proxyJson['code'] == 200) {
        return proxyJson['url'] ?? (throw Exception('代理返回无URL'));
      }
      throw Exception('汽水VIP代理解密失败');
    }
    return url;
  }

  static Future<String> qishuiGetLyric(Song song) async {
    try {
      final body = await _httpGetWithFallback({'act': 'song', 'id': song.id},
          timeout: 15000);
      final json = jsonDecode(body);
      final dataArr = json['data'];
      if (dataArr == null || dataArr.isEmpty) return '';
      return dataArr[0]['lyric'] ?? '';
    } catch (_) {
      return '';
    }
  }

  static String _extractLrc(String raw) {
    try {
      final el = jsonDecode(raw);
      if (el is Map) return el['lrc'] ?? el['lyric'] ?? '';
      if (el is String) return el;
    } catch (_) {}
    return '';
  }

  static Future<String> getLyric(Platform platform, Song song) async {
    try {
      if (platform == Platform.qsvip) return await qishuiGetLyric(song);
      final id = song.getHashOrMid();
      final source = platform.xinghaiSource;
      try {
        final url = '$_xinghaiMain&types=lrc&source=$source&id=${_urlEnc(id)}';
        final lrc = _extractLrc(await _httpGet(url));
        if (lrc.isNotEmpty) return lrc;
      } catch (_) {}
      final backupSrc = platform.xinghaiBackupSource;
      if (backupSrc != null) {
        try {
          final url =
              '$_xinghaiBackup?source=${_urlEnc(backupSrc)}&id=${_urlEnc(id)}&type=lrc';
          final lrc = _extractLrc(await _httpGet(url));
          if (lrc.isNotEmpty) return lrc;
        } catch (_) {}
      }
    } catch (_) {}
    return '';
  }

  static Future<SearchResult> searchByPlatform(Platform platform, String keyword,
      {int page = 1, int limit = 30}) async {
    final encoded = Uri.encodeComponent(keyword);
    final sources =
        platform == Platform.qsvip ? ['tencent'] : [platform.xinghaiSource];
    for (final src in sources) {
      final url =
          '$_xinghaiMain&types=search&source=$src&name=$encoded&count=$limit&pages=$page';
      try {
        final body = await _httpGet(url);
        final el = jsonDecode(body);
        if (el is! List) {
          final obj = el as Map<String, dynamic>;
          throw Exception(obj['detail'] ?? obj['msg'] ?? '未知错误');
        }
        final list = (el as List).map((item) {
          if (item is! Map<String, dynamic>) return null;
          final songId = item['url_id'] ?? item['id'] ?? '';
          if (songId.isEmpty) return null;
          String singer;
          final artistEl = item['artist'];
          if (artistEl == null) {
            singer = '未知歌手';
          } else if (artistEl is List) {
            singer = artistEl.join('/');
          } else {
            singer = artistEl.toString();
          }
          return Song(
            id: songId.toString(),
            songmid: songId.toString(),
            name: item['name'] ?? '未知',
            singer: singer,
            album: item['album'] ?? '',
            source: platform.code,
          );
        }).whereType<Song>().toList();
        return SearchResult(
            list: list, total: list.length, page: page, source: platform.code);
      } catch (_) {}
    }
    throw Exception('搜索失败');
  }

  static String _selectQuality(String requested, List<String> supported) {
    final q = requested.toLowerCase();
    if (q == '24bit') return '24bit';
    if (supported.contains(q)) return q;
    const order = ['flac24bit', 'flac', '320k', '192k', '128k'];
    final idx = order.indexOf(q);
    final start = idx < 0 ? order.length - 1 : idx;
    for (var i = start; i < order.length; i++) {
      if (supported.contains(order[i])) return order[i];
    }
    for (var i = order.length - 1; i >= 0; i--) {
      if (supported.contains(order[i])) return order[i];
    }
    return supported.isNotEmpty ? supported.first : '128k';
  }

  static String _qualityToNetease(String quality) {
    final q = quality.toLowerCase();
    if (q == 'flac' ||
        q == 'flac24bit' ||
        q == 'hires' ||
        q == 'master' ||
        q == 'atmos') return 'lossless';
    if (q == '320k' || q == '192k') return 'exhigh';
    return 'standard';
  }

  static List<String> _buildSearchKeywords(Song song) {
    String normalize(String s) => s
        .replaceAll(RegExp(r'\(\s*Live\s*\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\([^)]*\)'), '')
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'[^\w\u4e00-\u9fa5]'), '')
        .trim()
        .toLowerCase();
    final list = <String>[];
    if (song.name.isNotEmpty && song.album.isNotEmpty) {
      final kw = normalize(song.name + song.album);
      if (kw.isNotEmpty) list.add(kw);
    }
    if (song.name.isNotEmpty && song.singer.isNotEmpty) {
      final kw = normalize(song.name + song.singer);
      if (kw.isNotEmpty) list.add(kw);
    }
    if (song.name.isNotEmpty) {
      final kw = normalize(song.name);
      if (kw.isNotEmpty) list.add(kw);
    }
    return list;
  }

  static Future<String> getMusicUrl(Platform platform, Song song,
      {String quality = 'flac'}) async {
    if (!Platform.urlPlatforms.contains(platform)) {
      throw Exception('不支持的播放平台: ${platform.code}');
    }
    final selectedQuality = _selectQuality(quality, platform.qualities);
    try {
      final source = platform.xinghaiSource;
      final id = song.getHashOrMid();
      final br = QualityBr.xinghaiBr[selectedQuality] ?? '320';
      final url =
          '$_xinghaiMain&types=url&source=$source&id=${_urlEnc(id)}&br=$br';
      final bd = await _httpGet(url);
      final js = jsonDecode(bd);
      final mu = js['url'];
      if (mu != null && mu.startsWith('http')) return mu;
    } catch (_) {}
    try {
      if (platform == Platform.wy) return await _suyin163Get(song);
      if (platform == Platform.tx) return await _suyinQQGet(song, quality);
      if (platform == Platform.kw) return await _suyinKuwoGet(song, quality);
      if (platform == Platform.mg) return await _suyinMiguGet(song);
    } catch (_) {}
    final backupSrc = platform.xinghaiBackupSource;
    if (backupSrc != null) {
      try {
        final id = song.getHashOrMid();
        final u =
            '$_xinghaiBackup?source=${_urlEnc(backupSrc)}&id=${_urlEnc(id)}&type=url&br=${_urlEnc(selectedQuality)}';
        final resp = await _httpGet(u);
        final t = resp.trim();
        if (t.startsWith('http')) return t;
        final js = jsonDecode(resp);
        if (js is Map) {
          final u2 = js['url'];
          if (u2 != null) return u2;
        }
        if (js is String) return js;
      } catch (_) {}
    }
    try {
      return _buildTemplateUrl(platform.code, song, quality, _changqing);
    } catch (_) {}
    return _buildTemplateUrl(platform.code, song, quality, _nianxin);
  }

  static String _buildTemplateUrl(
      String code, Song song, String quality, Map<String, String> templates) {
    final template = templates[code];
    if (template == null) throw Exception('不支持的平台');
    final level = _qualityToNetease(quality);
    final songId = song.hash.isNotEmpty
        ? song.hash
        : (song.songmid.isNotEmpty ? song.songmid : song.id);
    return template
        .replaceFirst('%s', Uri.encodeComponent(songId))
        .replaceFirst('%s', Uri.encodeComponent(level))
        .replaceAll('{id}', Uri.encodeComponent(songId))
        .replaceAll('{level}', Uri.encodeComponent(level));
  }

  static Future<String> _suyin163Get(Song song) async {
    final id = song.songmid.isNotEmpty ? song.songmid : song.id;
    final body = await _httpGet('$_suyin163?id=$id');
    final json = jsonDecode(body);
    if (json['code'] != 0) throw Exception('code!=0');
    return (json['data'] as List)[0]['url'] ?? (throw Exception('无url'));
  }

  static Future<String> _suyinQQGet(Song song, String quality) async {
    final qqId = song.songmid.isNotEmpty ? song.songmid : song.id;
    final selectedQ = quality.toLowerCase() == 'flac24bit'
        ? 'hires'
        : (quality.toLowerCase() == '192k' ? '320k' : quality.toLowerCase());
    final startBr = QualityBr.suyinQQBr[selectedQ] ?? 7;
    final brList = [startBr, 4, 5, 7].toSet().toList()..sort();
    for (final br in brList) {
      try {
        final params = <String, String>{
          'key': _suyinQQKey,
          'type': 'json',
          'br': br.toString(),
          'n': '1',
        };
        if (RegExp(r'^\d+$').hasMatch(qqId)) {
          params['songid'] = qqId;
        } else {
          params['mid'] = qqId;
        }
        final q =
            params.entries.map((e) => '${e.key}=${_urlEnc(e.value)}').join('&');
        final body = await _httpGet('$_suyinQQ?$q');
        final json = jsonDecode(body);
        final music = json['music'];
        if (music != null && music.isNotEmpty) return music;
        final msg = json['message'] ?? '';
        final m = RegExp(r'音频链接[：:](.+?)(?:\n|$)').firstMatch(msg);
        if (m != null) return m.group(1)!.trim();
      } catch (_) {}
    }
    throw Exception('溯音QQ全部失败');
  }

  static Future<String> _suyinKuwoGet(Song song, String quality) async {
    final selectedQ = _selectQuality(quality, ['flac', '320k', '128k']);
    final br = QualityBr.kwBr[selectedQ] ?? 1;
    final keywords = _buildSearchKeywords(song);
    for (final kw in keywords) {
      try {
        final body =
            await _httpGet('$_suyinKuwo?msg=${_urlEnc(kw)}&n=1&br=$br');
        final json = jsonDecode(body);
        final dataUrl = json['data']?['url'];
        if (dataUrl != null && dataUrl.isNotEmpty) return dataUrl;
        final msg = json['message'] ?? '';
        final m = RegExp(r'音乐链接[：:](\S+)').firstMatch(msg);
        if (m != null) return m.group(1)!;
      } catch (_) {}
    }
    throw Exception('溯音酷我失败');
  }

  static Future<String> _suyinMiguGet(Song song) async {
    final keywords = _buildSearchKeywords(song);
    for (final kw in keywords) {
      try {
        final body = await _httpGet(
            '$_suyinMigu?gm=${_urlEnc(kw)}&n=1&num=1&type=json');
        final json = jsonDecode(body);
        if (json['code'] == 200) {
          final mi = json['musicInfo'];
          if (mi != null && mi.isNotEmpty) return mi;
        }
      } catch (_) {}
    }
    throw Exception('溯音咪咕失败');
  }
}
