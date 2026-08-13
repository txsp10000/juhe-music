import 'package:flutter/material.dart';
import '../services/theme_service.dart';
import '../theme/app_design_tokens.dart';
import '../widgets/glass_panel.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
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
        _accent =
            AppDesignTokens.readableAccent(ThemeService.accentColor.value);
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
                    IconOrbButton(
                        icon: Icons.arrow_back_rounded,
                        accent: _accent,
                        size: 42,
                        onTap: () => Navigator.pop(context)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('设置', style: AppDesignTokens.title(size: 25)),
                          const SizedBox(height: 4),
                          Text('让播放质量跟上你的夜晚',
                              style: AppDesignTokens.caption(
                                  color: AppDesignTokens.lyricWhite
                                      .withValues(alpha: 0.72))),
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
                      child: Text('播放时会自动选择该歌曲可用的最高音质。',
                          style: AppDesignTokens.body(
                              size: 14, color: AppDesignTokens.quietGrey)),
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
}
