enum Platform {
  qsvip('qsvip', '汽水VIP', '', null, ['flac24bit', 'flac', '320k', '128k']),
  wy('wy', '网易云', 'netease', 'netease', ['24bit', 'flac', '320k', '192k', '128k']),
  tx('tx', 'QQ音乐', 'tencent', 'qq', ['24bit', 'flac', '320k', '192k', '128k']),
  kw('kw', '酷我', 'kuwo', 'kuwo', ['24bit', 'flac', '320k', '192k', '128k']),
  kg('kg', '酷狗', 'kugou', null, ['24bit', 'flac', '320k', '192k', '128k']),
  mg('mg', '咪咕', 'migu', null, ['24bit', 'flac', '320k', '192k', '128k']);

  final String code;
  final String displayName;
  final String xinghaiSource;
  final String? xinghaiBackupSource;
  final List<String> qualities;

  const Platform(this.code, this.displayName, this.xinghaiSource,
      this.xinghaiBackupSource, this.qualities);

  static Platform? fromCode(String code) {
    try {
      return Platform.values.firstWhere((p) => p.code == code);
    } catch (_) {
      return null;
    }
  }

  static List<Platform> get searchablePlatforms =>
      [Platform.qsvip, Platform.wy, Platform.tx, Platform.kw, Platform.kg, Platform.mg];

  static List<Platform> get urlPlatforms =>
      [Platform.wy, Platform.tx, Platform.kw, Platform.kg, Platform.mg];
}

class QualityBr {
  static const xinghaiBr = {
    '128k': '128', '192k': '192', '320k': '320',
    'flac': '740', 'flac24bit': '999', '24bit': '999',
  };

  static const suyinQQBr = {
    '128k': 7, '320k': 5, '192k': 5,
    'flac': 4, 'hires': 3, 'atmos': 2, 'master': 1, '24bit': 1,
  };

  static const kwBr = {'flac': 1, '320k': 5, '128k': 7, '24bit': 1};

  static const displayBitrate = {
    'flac24bit': '24bit/192kHz',
    '24bit': '24bit/192kHz',
    'flac': 'FLAC 无损',
    '320k': '320kbps',
    '192k': '192kbps',
    '128k': '128kbps',
  };
}
