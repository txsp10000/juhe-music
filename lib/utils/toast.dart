import 'package:flutter/material.dart';
import '../services/theme_service.dart';
import '../theme/app_design_tokens.dart';

class Toast {
  static void show(BuildContext context, String message) {
    final overlay = Overlay.of(context);
    final accent = AppDesignTokens.readableAccent(ThemeService.accentColor.value);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned.fill(
        child: IgnorePointer(
          child: SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 92),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.66), borderRadius: BorderRadius.circular(999)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 7, height: 7, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
                      const SizedBox(width: 10),
                      Flexible(child: Text(message, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppDesignTokens.body(size: 14, weight: FontWeight.w800).copyWith(decoration: TextDecoration.none))),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    Future.delayed(const Duration(milliseconds: 1600), () => entry.remove());
  }
}
