import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Icône + libellé qui se raccourcit au lieu de déborder (grands textes, écrans étroits).
class IconLabel extends StatelessWidget {
  const IconLabel({
    super.key,
    required this.icon,
    required this.label,
    this.color,
    this.style,
    this.iconSize = 16,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final Color? color;
  final TextStyle? style;
  final double iconSize;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: Icon(icon, size: iconSize, color: color),
        ),
        const SizedBox(width: Space.xs),
        Flexible(
          child: Text(
            label,
            style: (style ?? Theme.of(context).textTheme.bodySmall)?.copyWith(
              color: color,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ),
        ?trailing,
      ],
    );
  }
}
