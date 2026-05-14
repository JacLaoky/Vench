import 'package:flutter/material.dart';
import 'package:flutter_application_1/constants.dart';

class TagChip extends StatelessWidget {
  final String tag;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  const TagChip({
    super.key,
    required this.tag,
    this.selected = false,
    this.onTap,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final color = TagColors.forTag(tag);
    final isDark = AppColors.darkBg.computeLuminance() < 0.5;
    final bgAlpha   = selected ? 0.28 : (isDark ? 0.15 : 0.12);
    final bdrAlpha  = selected ? 0.75 : (isDark ? 0.35 : 0.50);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.fromLTRB(8, 3, onRemove != null ? 4 : 8, 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: bgAlpha),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: color.withValues(alpha: bdrAlpha),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tag,
                style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
            if (onRemove != null) ...[
              const SizedBox(width: 2),
              GestureDetector(
                onTap: onRemove,
                child: Icon(Icons.close_rounded, size: 12, color: color),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
