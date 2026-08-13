import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/carplay_diagnostics_service.dart';
import '../services/theme_service.dart';
import '../theme/app_design_tokens.dart';
import '../widgets/glass_panel.dart';

class CarPlayDiagnosticsPage extends StatefulWidget {
  const CarPlayDiagnosticsPage({super.key});

  @override
  State<CarPlayDiagnosticsPage> createState() => _CarPlayDiagnosticsPageState();
}

class _CarPlayDiagnosticsPageState extends State<CarPlayDiagnosticsPage> {
  String _contents = '正在读取...';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final contents = await CarPlayDiagnosticsService.read();
      if (mounted) {
        setState(() => _contents = contents);
      }
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() => _contents = '读取失败：${error.message ?? error.code}');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _clear() async {
    await CarPlayDiagnosticsService.clear();
    await _refresh();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _contents));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('诊断记录已复制')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent =
        AppDesignTokens.readableAccent(ThemeService.accentColor.value);
    final background = ThemeService.bgHint.value;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: MusicScaffoldBackground(
        bgHint: background,
        accent: accent,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
                child: Row(
                  children: [
                    IconOrbButton(
                      icon: Icons.arrow_back_rounded,
                      accent: accent,
                      size: 42,
                      onTap: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('CarPlay 诊断',
                          style: AppDesignTokens.title(size: 23)),
                    ),
                    IconButton(
                      tooltip: '刷新',
                      onPressed: _loading ? null : _refresh,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                    IconButton(
                      tooltip: '复制',
                      onPressed: _copy,
                      icon: const Icon(Icons.copy_rounded),
                    ),
                    IconButton(
                      tooltip: '清空',
                      onPressed: _clear,
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '文件 > 我的 iPhone > 音乐 > CarPlay-Diagnostics.txt',
                        style: AppDesignTokens.caption(
                          color:
                              AppDesignTokens.warmWhite.withValues(alpha: 0.78),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: GlassPanel(
                          accent: accent,
                          radius: 12,
                          padding: const EdgeInsets.all(14),
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: SingleChildScrollView(
                                  child: SelectableText(
                                    _contents,
                                    style: const TextStyle(
                                      color: AppDesignTokens.warmWhite,
                                      fontSize: 12,
                                      height: 1.5,
                                      fontFamily: 'monospace',
                                      letterSpacing: 0,
                                    ),
                                  ),
                                ),
                              ),
                              if (_loading)
                                const Align(
                                  alignment: Alignment.topCenter,
                                  child: LinearProgressIndicator(minHeight: 2),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
