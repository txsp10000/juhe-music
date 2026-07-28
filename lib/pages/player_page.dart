import 'dart:ui';
import 'package:flutter/material.dart';
import '../services/player_service.dart';
import '../services/favorites_service.dart';
import '../services/cover_cache_service.dart';
import '../models/song.dart';
import '../utils/toast.dart';
import 'playlist_page.dart';
import 'search_result_page.dart';
import '../services/settings_service.dart';
import 'dart:typed_data';

/// LRC 歌词行
class _LrcLine {
  final int timeMs;
  final String text;
  const _LrcLine(this.timeMs, this.text);
}

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage>
    with SingleTickerProviderStateMixin {
  final _player = PlayerService();
  bool _isFavorite = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  List<_LrcLine> _parsedLrc = [];
  bool _isDragging = false;
  double _dragValue = 0.0;
  double? _downloadProgress;
  String _coverUrl = '';
  Uint8List? _coverBytes;

  late AnimationController _coverAnim;
  late Animation<double> _coverScale;
  late Animation<double> _coverOpacity;

  // ─── Design tokens ───
  static const _bg = Color(0xFF07080C);
  static const _accent = Color(0xFF5A78F0);
  static const _textPrimary = Color(0xFFEDEDF2);
  static const _textSecondary = Color(0xFF7C7F8C);
  static const _textTertiary = Color(0xFF4E515E);

  @override
  void initState() {
    super.initState();
    _coverAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _coverScale = CurvedAnimation(
      parent: _coverAnim,
      curve: Curves.easeOutCubic,
    ).drive(Tween(begin: 0.85, end: 1.0));
    _coverOpacity = CurvedAnimation(
      parent: _coverAnim,
      curve: Curves.easeOut,
    ).drive(Tween(begin: 0.0, end: 1.0));
    _coverAnim.forward();

    _player.addProgressListener(_onProgressUpdate);
    _player.addSongChangeListener(_onSongChange);
    _player.addDownloadProgressListener(_onDownloadProgress);
    _player.onPlayStateChanged = (_) => mounted ? setState(() {}) : null;
    _syncState();
    _checkFavorite();
  }

  void _onProgressUpdate(Duration pos, Duration? dur) {
    if (!mounted) return;
    setState(() {
      _position = pos;
      _duration = dur ?? Duration.zero;
    });
    final song = _player.currentSong;
    if (song != null && _coverBytes == null && song.cover.isNotEmpty && song.cover != _coverUrl) {
      _loadCover(song);
    }
  }

  void _onSongChange(Song s) {
    if (!mounted) return;
    _parsedLrc = _parseLrc(s.lyric);
    if (s.cover.isEmpty || s.cover != _coverUrl) {
      _coverBytes = null;
      _coverUrl = '';
    }
    _coverAnim.reset();
    _coverAnim.forward();
    setState(() {});
    _checkFavorite();
    _loadCover(s);
  }

  void _onDownloadProgress(double? progress) {
    if (mounted) setState(() => _downloadProgress = progress);
  }

  @override
  void dispose() {
    _player.removeProgressListener(_onProgressUpdate);
    _player.removeSongChangeListener(_onSongChange);
    _player.removeDownloadProgressListener(_onDownloadProgress);
    _coverAnim.dispose();
    super.dispose();
  }

  void _syncState() {
    if (_player.duration != null) _duration = _player.duration!;
    _position = _player.position;
    final song = _player.currentSong;
    if (song != null && _parsedLrc.isEmpty) {
      _parsedLrc = _parseLrc(song.lyric);
    }
    if (song != null) _loadCover(song);
  }

  Future<void> _loadCover(Song song) async {
    if (song.cover.isEmpty) return;
    if (song.cover == _coverUrl && _coverBytes != null) return;
    final url = song.cover;
    _coverUrl = url;
    _coverBytes = null;
    final picId = song.picId.isNotEmpty ? song.picId : song.id;
    final coverCache = CoverCacheService();
    final cached = await coverCache.load(picId);
    if (cached != null && mounted && _coverUrl == url) {
      setState(() => _coverBytes = cached);
      return;
    }
    if (url.startsWith('file://')) return;
    final downloaded = await coverCache.download(picId, url);
    if (downloaded != null && mounted && _coverUrl == url) {
      setState(() => _coverBytes = downloaded);
    } else {
      if (_coverUrl == url) _coverUrl = '';
    }
  }

  Future<void> _checkFavorite() async {
    final song = _player.currentSong;
    if (song == null) return;
    _isFavorite = await FavoritesService.isFavorite(song);
    if (mounted) setState(() {});
  }

  void _toggleFavorite() async {
    final song = _player.currentSong;
    if (song == null) return;
    if (_isFavorite) {
      await FavoritesService.remove(song);
      _isFavorite = false;
      if (mounted) _showToast('已取消收藏');
    } else {
      await FavoritesService.save(song);
      _isFavorite = true;
      if (mounted) _showToast('已加入收藏');
    }
    if (mounted) setState(() {});
  }

  void _showToast(String msg) => Toast.show(context, msg);

  String _fmt(Duration d) {
    final s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  void _showSearchSameSheet() {
    final song = _player.currentSong;
    if (song == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111318),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32, height: 4,
              decoration: BoxDecoration(
                color: _textTertiary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text('搜索同名',
                style: TextStyle(color: _textPrimary, fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            _sheetRow(Icons.music_note, '歌曲: ${song.name}', () {
              Navigator.pop(ctx);
              Navigator.push(context, MaterialPageRoute(
                  builder: (_) => SearchResultPage(keyword: song.name, fromPlayer: true)));
            }),
            const SizedBox(height: 4),
            _sheetRow(Icons.person, '歌手: ${song.singer}', () {
              Navigator.pop(ctx);
              Navigator.push(context, MaterialPageRoute(
                  builder: (_) => SearchResultPage(keyword: song.singer, fromPlayer: true)));
            }),
          ],
        ),
      ),
    );
  }

  Widget _sheetRow(IconData icon, String text, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF16181E),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, color: _accent, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: const TextStyle(color: _textPrimary, fontSize: 15))),
            const Icon(Icons.chevron_right, color: _textTertiary, size: 20),
          ],
        ),
      ),
    );
  }

  String _currentBrLabel() {
    switch (_player.currentPlayingBr) {
      case 128: return '128 kbps';
      case 192: return '192 kbps';
      case 320: return '320 kbps';
      case 740: return '16bit 无损';
      case 999: return '24bit 无损';
      default: return '${_player.currentPlayingBr}kbps';
    }
  }

  String _qualityLabel() {
    switch (SettingsService().quality) {
      case AudioQuality.low128: return '128k';
      case AudioQuality.medium192: return '192k';
      case AudioQuality.high320: return '320k';
      case AudioQuality.lossless740: return '16bit';
      case AudioQuality.lossless999: return '24bit';
    }
  }

  void _showQualityPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111318),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 32, height: 4,
              decoration: BoxDecoration(color: _textTertiary, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            const Text('音质选择',
                style: TextStyle(color: _textPrimary, fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            ...AudioQuality.values.map((q) {
              final selected = SettingsService().quality == q;
              return GestureDetector(
                onTap: () async {
                  final oldBr = SettingsService().quality.br;
                  await SettingsService().setQuality(q);
                  Navigator.pop(ctx);
                  if (mounted) setState(() {});
                  if (q.br > oldBr) _player.redownloadCurrentAtNewQuality();
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: selected ? _accent.withOpacity(0.12) : const Color(0xFF16181E),
                    borderRadius: BorderRadius.circular(10),
                    border: selected ? Border.all(color: _accent.withOpacity(0.3)) : null,
                  ),
                  child: Row(
                    children: [
                      Text(q.label,
                          style: TextStyle(
                              color: selected ? _accent : _textPrimary,
                              fontSize: 15,
                              fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
                      const Spacer(),
                      if (selected)
                        const Icon(Icons.check, color: _accent, size: 20),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ─── LRC ───

  List<_LrcLine> _parseLrc(String? lyric) {
    if (lyric == null || lyric.isEmpty) return [];
    final lines = <_LrcLine>[];
    final regex = RegExp(r'\[(\d{2}):(\d{2})(?:\.(\d{1,3}))?\](.*)');
    for (final line in lyric.split('\n')) {
      final match = regex.firstMatch(line.trim());
      if (match != null) {
        final min = int.parse(match.group(1)!);
        final sec = int.parse(match.group(2)!);
        var msStr = match.group(3);
        var ms = 0;
        if (msStr != null) {
          ms = int.parse(msStr);
          if (msStr.length == 1) ms *= 100;
          else if (msStr.length == 2) ms *= 10;
        }
        final text = match.group(4)?.trim() ?? '';
        if (text.isNotEmpty) lines.add(_LrcLine((min * 60 + sec) * 1000 + ms, text));
      }
    }
    lines.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    return lines;
  }

  int _currentLrcIndex() {
    if (_parsedLrc.isEmpty) return -1;
    final posMs = _position.inMilliseconds;
    int left = 0, right = _parsedLrc.length - 1, idx = -1;
    while (left <= right) {
      int mid = (left + right) ~/ 2;
      if (_parsedLrc[mid].timeMs <= posMs) {
        idx = mid;
        left = mid + 1;
      } else {
        right = mid - 1;
      }
    }
    return idx;
  }

  String _firstLyric(String? lyric) {
    if (lyric == null || lyric.isEmpty) return '';
    return lyric.split('\n')
        .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '')
        .replaceAll(RegExp(r'\[.*?\]'), '')
        .trim();
  }

  // ─── Build ───

  @override
  Widget build(BuildContext context) {
    final song = _player.currentSong;
    if (song == null) return const Scaffold(body: SizedBox());

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          // ── Background: blurred cover art ──
          if (_coverBytes != null)
            Positioned.fill(
              child: Image.memory(
                _coverBytes!,
                fit: BoxFit.cover,
                color: _bg.withOpacity(0.82),
                colorBlendMode: BlendMode.darken,
              ),
            ),
          // Gradient overlay for legibility
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    _bg.withOpacity(0.3),
                    _bg.withOpacity(0.7),
                  ],
                ),
              ),
            ),
          ),

          // ── Content ──
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(song),
                Expanded(child: _buildCenterContent()),
                _buildDownloadProgress(),
                _buildTimeBar(),
                _buildControls(),
                _buildBottomActions(),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(Song song) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.keyboard_arrow_down, color: _textSecondary, size: 28),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(song.name, style: const TextStyle(
                    color: _textPrimary, fontSize: 16, fontWeight: FontWeight.w600,
                  ), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text('${song.singer} · ${_currentBrLabel()}', style: const TextStyle(
                    color: _textSecondary, fontSize: 12,
                  ), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const PlaylistPage(fromPlayer: true))),
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.queue_music, color: _textSecondary, size: 24),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterContent() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // ── Cover art ──
        ScaleTransition(
          scale: _coverScale,
          child: FadeTransition(
            opacity: _coverOpacity,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: _accent.withOpacity(0.18),
                    blurRadius: 40,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: _coverBytes != null
                  ? Image.memory(_coverBytes!, fit: BoxFit.cover)
                  : Container(
                      color: const Color(0xFF16181E),
                      child: const Icon(Icons.music_note, color: _accent, size: 64),
                    ),
            ),
          ),
        ),

        const SizedBox(height: 32),

        // ── Lyrics ──
        if (_parsedLrc.isNotEmpty)
          _buildLyrics()
        else if (_player.currentSong?.lyric != null && _player.currentSong!.lyric.isNotEmpty)
          Text(
            _firstLyric(_player.currentSong!.lyric),
            style: const TextStyle(color: _textSecondary, fontSize: 16),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }

  Widget _buildLyrics() {
    final currentIdx = _currentLrcIndex();
    final lines = <Widget>[];

    // Previous lines
    for (var i = currentIdx - 2; i < currentIdx; i++) {
      if (i >= 0) {
        lines.add(Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(_parsedLrc[i].text,
              style: const TextStyle(color: _textTertiary, fontSize: 15, height: 1.4),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ));
      }
    }
    // Current line
    if (currentIdx >= 0) {
      lines.add(Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 300),
          style: const TextStyle(
              color: _accent, fontSize: 20, fontWeight: FontWeight.w600, height: 1.4),
          child: Text(_parsedLrc[currentIdx].text,
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ));
    }
    // Upcoming lines
    for (var i = currentIdx + 1; i <= currentIdx + 3; i++) {
      if (i < _parsedLrc.length) {
        lines.add(Padding(
          padding: EdgeInsets.only(bottom: i < currentIdx + 3 ? 6 : 0),
          child: Text(_parsedLrc[i].text,
              style: const TextStyle(color: _textTertiary, fontSize: 15, height: 1.4),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ));
      }
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOut,
      child: Container(
        key: ValueKey(currentIdx),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        constraints: const BoxConstraints(maxHeight: 180),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: lines,
          ),
        ),
      ),
    );
  }

  Widget _buildDownloadProgress() {
    if (_downloadProgress == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 14, height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: _accent),
          ),
          const SizedBox(width: 8),
          const Text('缓存中', style: TextStyle(color: _textSecondary, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildTimeBar() {
    final max = _duration.inMilliseconds.toDouble();
    final current = _isDragging
        ? _dragValue
        : _position.inMilliseconds.toDouble().clamp(0.0, max);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: _accent,
              inactiveTrackColor: const Color(0xFF252836),
              thumbColor: _accent,
              overlayColor: _accent.withOpacity(0.15),
            ),
            child: Slider(
              min: 0,
              max: max > 0 ? max : 1,
              value: max > 0 ? current.clamp(0.0, max) : 0,
              onChangeStart: (v) { _isDragging = true; _dragValue = v; },
              onChanged: (v) => setState(() => _dragValue = v),
              onChangeEnd: (v) {
                _isDragging = false;
                _player.seek(Duration(milliseconds: v.toInt()));
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _fmt(_isDragging
                      ? Duration(milliseconds: _dragValue.toInt())
                      : _position),
                  style: const TextStyle(color: _textTertiary, fontSize: 11, letterSpacing: 0.5),
                ),
                Text(_fmt(_duration),
                    style: const TextStyle(color: _textTertiary, fontSize: 11, letterSpacing: 0.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    final isPlaying = _player.isPlaying;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(width: 36),
          GestureDetector(
            onTap: () => _player.prev(),
            child: const Icon(Icons.skip_previous, color: _textPrimary, size: 38),
          ),
          const SizedBox(width: 40),
          GestureDetector(
            onTap: () => _player.togglePlayPause(),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
              child: Container(
                key: ValueKey(isPlaying),
                width: 64, height: 64,
                decoration: BoxDecoration(
                  color: _accent,
                  borderRadius: BorderRadius.circular(32),
                ),
                child: Icon(
                  isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white, size: 34,
                ),
              ),
            ),
          ),
          const SizedBox(width: 40),
          GestureDetector(
            onTap: () => _player.next(),
            child: const Icon(Icons.skip_next, color: _textPrimary, size: 38),
          ),
          const SizedBox(width: 36),
        ],
      ),
    );
  }

  Widget _buildBottomActions() {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _actionBtn(
            icon: _isFavorite ? Icons.favorite : Icons.favorite_border,
            label: _isFavorite ? '已收藏' : '收藏',
            color: _isFavorite ? const Color(0xFFFF5E5E) : _textSecondary,
            onTap: _toggleFavorite,
          ),
          _actionBtn(
            icon: Icons.search,
            label: '搜索同名',
            color: _textSecondary,
            onTap: _showSearchSameSheet,
          ),
          _actionBtn(
            icon: Icons.high_quality,
            label: _qualityLabel(),
            color: _textSecondary,
            onTap: _showQualityPicker,
          ),
        ],
      ),
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(color: color, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
