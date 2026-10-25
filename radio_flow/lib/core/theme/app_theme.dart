import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Espacements (échelle dense du tableau de bord : 4 / 8 / 12 / 16 / 24).
abstract final class Space {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
}

abstract final class AppTheme {
  // Fira Sans (texte) / Fira Code (chiffres, durées) : à embarquer dans assets/fonts.
  static const _textFamily = 'FiraSans';
  static const monoFamily = 'FiraCode';

  static ThemeData get dark => _build(AppColors.dark, Brightness.dark);
  static ThemeData get light => _build(AppColors.light, Brightness.light);

  static ThemeData _build(AppColors c, Brightness brightness) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.success,
      onPrimary: c.onSuccess,
      secondary: c.muted,
      onSecondary: c.foreground,
      error: c.danger,
      onError: brightness == Brightness.dark
          ? const Color(0xFF000000)
          : const Color(0xFFFFFFFF),
      surface: c.card,
      onSurface: c.foreground,
      onSurfaceVariant: c.mutedForeground,
      outline: c.border,
      outlineVariant: c.divider,
      surfaceContainerHighest: c.muted,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.background,
      fontFamily: _textFamily,
      extensions: [c],
    );

    // Corps 16 px minimum, interligne 1,5.
    final text = base.textTheme
        .apply(bodyColor: c.foreground, displayColor: c.foreground)
        .copyWith(
          bodyLarge: base.textTheme.bodyLarge?.copyWith(
            fontSize: 16,
            height: 1.5,
          ),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(
            fontSize: 16,
            height: 1.5,
          ),
          bodySmall: base.textTheme.bodySmall?.copyWith(
            fontSize: 13,
            height: 1.4,
            color: c.mutedForeground,
          ),
          titleLarge: base.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          titleMedium: base.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        );

    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: c.border),
    );

    return base.copyWith(
      textTheme: text,
      visualDensity: VisualDensity.standard,
      // Zones tactiles de 48 dp minimum, aussi sur bureau.
      materialTapTargetSize: MaterialTapTargetSize.padded,
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      dividerTheme: DividerThemeData(color: c.divider, space: 1, thickness: 1),
      cardTheme: CardThemeData(
        color: c.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: c.divider),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.muted,
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: c.success, width: 2),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: c.danger),
        ),
        focusedErrorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: c.danger, width: 2),
        ),
        helperStyle: TextStyle(color: c.mutedForeground),
        errorStyle: TextStyle(color: c.danger),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 48),
          side: BorderSide(color: c.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.card,
        indicatorColor: c.success.withValues(alpha: 0.18),
        height: 64,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: c.foreground,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: c.card,
        indicatorColor: c.success.withValues(alpha: 0.18),
        selectedIconTheme: IconThemeData(color: c.success),
        unselectedIconTheme: IconThemeData(color: c.mutedForeground),
        selectedLabelTextStyle: TextStyle(
          color: c.foreground,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: TextStyle(color: c.mutedForeground),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
