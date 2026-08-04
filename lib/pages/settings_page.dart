import 'package:flutter/material.dart';
import '../services/settings_service.dart';
import '../services/theme_service.dart';
import '../theme/app_design_tokens.dart';
import '../widgets/glass_panel.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _settings = SettingsService();
  Color _accent = AppDesignTokens.lyricWhite;
  Color _bgHint = AppDesignTokens.inkBlack;

  @override
  void initState() {
    super.initState();
    _onThemeChange();
    ThemeService.accentColor.addListener(_onThemeChange);
    ThemeService.bgHint.addListener(_onThemeChange);
  }

  void _onThemeChange() {
    if (mounted) {
      setState(() {
        _accent = AppDesignTokens.readableAccent(ThemeService.accentColor.value);
        _bgHint = ThemeService.bgHint.value;
      });
    }
  }

  @override
  void dispose() {
    ThemeService.accentColor.removeListener(_onThemeChange);
    ThemeService.bgHint.removeListener(_onThemeChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: MusicScaffoldBackground(
        bgHint: _bgHint,
        accent: _accent,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
                child: Row(
                  children: [
                    IconOrbButton(icon: Icons.arrow_back_rounded, accent: _accent, size: 42, onTap: () => Navigator.pop(context)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('设置', style: AppDesignTokens.title(size: 25)),
                          const SizedBox(height: 4),
                          Text('让播放质量跟上你的夜晚', style: AppDesignTokens.caption(color: _accent)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                  children: [
                    GlassPanel(
                      accent: _accent,
                      radius: 28,
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('音质选择', style: AppDesignTokens.title(size: 20)),
                          const SizedBox(height: 6),
                          Text('质量越高，缓存越慢，占用空间也越多。', style: AppDesignTokens.body(size: 13, color: AppDesignTokens.quietGrey)),
                          const SizedBox(height: 16),
                          ...AudioQuality.values.map(_buildQualityTile),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQualityTile(AudioQuality q) {
    final isSelected = _settings.quality == q;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () async {
          await _settings.setQuality(q);
          setState(() {});
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: isSelected ? _accent.withOpacity(0.16) : AppDesignTokens.glassBlack.withOpacity(0.44),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: isSelected ? _accent.withOpacity(0.50) : AppDesignTokens.mistLine),
          ),
          child: Row(
            children: [
              Icon(isSelected ? Icons.check_circle_rounded : Icons.circle_outlined, color: isSelected ? _accent : AppDesignTokens.dimGrey, size: 21),
              const SizedBox(width: 12),
              Expanded(child: Text(q.label, style: AppDesignTokens.body(color: isSelected ? AppDesignTokens.lyricWhite : AppDesignTokens.quietGrey, weight: isSelected ? FontWeight.w700 : FontWeight.w500))),
            ],
          ),
        ),
      ),
    );
  }
}
