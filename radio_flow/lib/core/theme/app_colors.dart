import 'package:flutter/material.dart';

/// Jetons sémantiques de Radio Flow (source : design-system/radio-flow/MASTER.md).
/// Les widgets lisent ces valeurs via `Theme.of(context).extension<AppColors>()`,
/// jamais de couleur en dur.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.card,
    required this.muted,
    required this.mutedForeground,
    required this.foreground,
    required this.border,
    required this.divider,
    required this.success,
    required this.onSuccess,
    required this.warning,
    required this.danger,
  });

  final Color background;
  final Color card;
  final Color muted;
  final Color mutedForeground;
  final Color foreground;
  final Color border;
  final Color divider;
  final Color success;
  final Color onSuccess;
  final Color warning;
  final Color danger;

  static const dark = AppColors(
    background: Color(0xFF0F172A),
    card: Color(0xFF1B2336),
    muted: Color(0xFF272F42),
    mutedForeground: Color(0xFF94A3B8),
    foreground: Color(0xFFF8FAFC),
    border: Color(0xFF8494AB),
    divider: Color(0xFF334155),
    success: Color(0xFF22C55E),
    onSuccess: Color(0xFF0F172A),
    warning: Color(0xFFF59E0B),
    danger: Color(0xFFF87171),
  );

  static const light = AppColors(
    background: Color(0xFFF8FAFC),
    card: Color(0xFFFFFFFF),
    muted: Color(0xFFE2E8F0),
    mutedForeground: Color(0xFF475569),
    foreground: Color(0xFF0F172A),
    border: Color(0xFF64748B),
    divider: Color(0xFFCBD5E1),
    success: Color(0xFF166534),
    onSuccess: Color(0xFFFFFFFF),
    warning: Color(0xFF92400E),
    danger: Color(0xFFB91C1C),
  );

  @override
  AppColors copyWith({
    Color? background,
    Color? card,
    Color? muted,
    Color? mutedForeground,
    Color? foreground,
    Color? border,
    Color? divider,
    Color? success,
    Color? onSuccess,
    Color? warning,
    Color? danger,
  }) {
    return AppColors(
      background: background ?? this.background,
      card: card ?? this.card,
      muted: muted ?? this.muted,
      mutedForeground: mutedForeground ?? this.mutedForeground,
      foreground: foreground ?? this.foreground,
      border: border ?? this.border,
      divider: divider ?? this.divider,
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      background: Color.lerp(background, other.background, t)!,
      card: Color.lerp(card, other.card, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      mutedForeground: Color.lerp(mutedForeground, other.mutedForeground, t)!,
      foreground: Color.lerp(foreground, other.foreground, t)!,
      border: Color.lerp(border, other.border, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}

extension AppColorsContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}
