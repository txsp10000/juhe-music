import 'package:flutter/material.dart';

import '../tv_layout_metrics.dart';
import 'tv_pill_button.dart';

class TvTopBar extends StatelessWidget {
  final List<String> categories;
  final String selectedCategory;
  final VoidCallback onSearch;
  final ValueChanged<String> onCategorySelected;
  final Widget? leading;
  final Widget? trailing;

  const TvTopBar({
    super.key,
    required this.categories,
    required this.selectedCategory,
    required this.onSearch,
    required this.onCategorySelected,
    this.leading,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final metrics = TvLayoutMetrics.of(context);
    return Row(
      children: [
        if (leading != null) leading!,
        if (leading != null) SizedBox(width: metrics.value(20, minimum: 10)),
        Expanded(
          child: Wrap(
            spacing: metrics.value(16, minimum: 8),
            runSpacing: metrics.value(12, minimum: 8),
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TvPillButton(
                label: '搜索',
                icon: Icons.search_rounded,
                onTap: onSearch,
              ),
              for (final category in categories)
                TvPillButton(
                  label: category,
                  selected: category == selectedCategory,
                  onTap: () => onCategorySelected(category),
                ),
            ],
          ),
        ),
        if (trailing != null) ...[
          SizedBox(width: metrics.value(20, minimum: 10)),
          trailing!,
        ],
      ],
    );
  }
}
