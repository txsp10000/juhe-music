import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/cover_cache_service.dart';

class CachedCoverImage extends StatefulWidget {
  final String cacheKey;
  final String url;
  final BoxFit fit;
  final Widget fallback;

  const CachedCoverImage({
    super.key,
    required this.cacheKey,
    required this.url,
    required this.fallback,
    this.fit = BoxFit.cover,
  });

  @override
  State<CachedCoverImage> createState() => _CachedCoverImageState();
}

class _CachedCoverImageState extends State<CachedCoverImage> {
  Uint8List? _bytes;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant CachedCoverImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cacheKey != widget.cacheKey || oldWidget.url != widget.url) {
      _bytes = null;
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final cache = CoverCacheService();
    final bytes = await cache.resolve(widget.cacheKey, widget.url);
    if (!mounted || generation != _loadGeneration) return;
    if (bytes != null) setState(() => _bytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    return bytes == null
        ? widget.fallback
        : Image.memory(bytes, fit: widget.fit);
  }
}
