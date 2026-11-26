import 'package:material_ui/material_ui.dart';

import '../models/approval_request.dart';
import '../models/sensitivity.dart';

/// 해봄 가족 디자인 토큰: 화이트 · 아이보리 · 차분한 그린
class HaebomColors {
  static const green = Color(0xFF3E7B57);
  static const greenDark = Color(0xFF8CC7A1);
  static const sprout = Color(0xFF7FB069);
  static const ivory = Color(0xFFFAF8F1);
  static const ivoryDeep = Color(0xFFF1EDE1);
  static const ink = Color(0xFF1F2A24);
  static const darkBg = Color(0xFF121613);
  static const darkSurface = Color(0xFF1B211D);

  static const sos = Color(0xFFC2412D);
}

/// 알림 위험도별 색상 (일반: 그린 / 주의: 주황 / 위험: 빨강). 아이콘·글자와 함께 쓴다.
class RiskStyle {
  static Color color(RiskTone tone, ThemeData t) {
    final dark = t.brightness == Brightness.dark;
    return switch (tone) {
      RiskTone.normal => t.colorScheme.primary,
      RiskTone.caution => dark ? const Color(0xFFE9B949) : const Color(0xFFA86B00),
      RiskTone.danger => dark ? const Color(0xFFF08A7E) : HaebomColors.sos,
    };
  }
}

/// 승인 상태별 색상/아이콘 (색상 + 아이콘 + 글자 세 가지로 구분해 색약 사용자도 식별 가능)
class StatusStyle {
  const StatusStyle(this.color, this.icon);
  final Color color;
  final IconData icon;

  static StatusStyle of(ApprovalStatus s, Brightness b) {
    final dark = b == Brightness.dark;
    return switch (s) {
      ApprovalStatus.pending =>
        StatusStyle(dark ? const Color(0xFFE9B949) : const Color(0xFFA86B00), Icons.hourglass_top_rounded),
      ApprovalStatus.approved =>
        StatusStyle(dark ? HaebomColors.greenDark : const Color(0xFF2E7048), Icons.check_circle_rounded),
      ApprovalStatus.rejected =>
        StatusStyle(dark ? const Color(0xFFF08A7E) : const Color(0xFFB3362A), Icons.cancel_rounded),
      ApprovalStatus.expired =>
        StatusStyle(dark ? const Color(0xFFA3A8A5) : const Color(0xFF6B716D), Icons.timer_off_rounded),
      ApprovalStatus.cancelled =>
        StatusStyle(dark ? const Color(0xFF9DB0C7) : const Color(0xFF52627A), Icons.undo_rounded),
    };
  }
}

ThemeData _base(ColorScheme scheme, Color scaffold) {
  final radius = BorderRadius.circular(16);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scaffold,
    visualDensity: VisualDensity.standard,
    appBarTheme: AppBarTheme(
      backgroundColor: scaffold,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.primaryContainer,
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontSize: 13,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      side: BorderSide(color: scheme.outlineVariant),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.5), space: 1),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

ThemeData buildLightTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: HaebomColors.green,
    brightness: Brightness.light,
  ).copyWith(
    primary: HaebomColors.green,
    surface: Colors.white,
    onSurface: HaebomColors.ink,
    surfaceContainerLow: HaebomColors.ivoryDeep,
  );
  return _base(scheme, HaebomColors.ivory);
}

ThemeData buildDarkTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: HaebomColors.green,
    brightness: Brightness.dark,
  ).copyWith(
    primary: HaebomColors.greenDark,
    surface: HaebomColors.darkSurface,
    surfaceContainerLow: const Color(0xFF232A25),
  );
  return _base(scheme, HaebomColors.darkBg);
}
