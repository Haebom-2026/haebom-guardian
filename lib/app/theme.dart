import 'package:material_ui/material_ui.dart';

import '../models/approval_request.dart';
import '../models/sensitivity.dart';

/// 해봄 가족 디자인 규칙 (11-26 햇살 톤 개편 — Claude Design 시안 기준)
///
/// - 바탕은 따뜻한 아이보리, 카드는 흰색 + 옅은 따뜻한 그림자.
/// - 노랑(#FFCB3D)은 브랜드 포인트(로고·햇살·하단 탭 선택 표시)에만 쓴다. 흰 배경 위 글자색으로는 쓰지 않는다.
/// - 짙은 녹색(#245D45)은 주요 버튼과 긍정 상태에 쓴다.
/// - 주의(주황)·긴급(빨강)은 배경 + 글자 + 아이콘을 함께 써서 색만으로 구분하지 않는다.
/// - 글자색 조합은 모두 명암비 4.5:1 이상 (라이트·다크 모두 계산해 확인).
class Space {
  /// 화면 좌우 여백
  static const page = 20.0;

  /// 섹션 사이 간격
  static const section = 24.0;

  /// 카드 사이 간격
  static const gap = 12.0;

  /// 카드 안쪽 여백
  static const card = 16.0;

  /// 버튼·입력칸·안내 상자 모서리
  static const radius = 16.0;

  /// 카드 모서리
  static const cardRadius = 22.0;

  /// 주요 버튼 높이
  static const button = 56.0;
}

/// 의미별 색. 화면은 이 값만 쓴다 (라이트·다크 자동 전환).
@immutable
class HaebomTokens extends ThemeExtension<HaebomTokens> {
  const HaebomTokens({
    required this.brand,
    required this.primary,
    required this.onPrimary,
    required this.background,
    required this.subtle,
    required this.card,
    required this.text,
    required this.textSub,
    required this.divider,
    required this.cautionBg,
    required this.cautionText,
    required this.dangerBg,
    required this.dangerText,
    required this.positiveBg,
    required this.neutralText,
    required this.cancelledText,
  });

  /// 브랜드 노랑 (햇살)
  final Color brand;
  final Color primary;
  final Color onPrimary;
  final Color background;

  /// 보조 배경 (안내 상자·입력칸)
  final Color subtle;

  /// 카드 배경 (바탕 위에 떠 있는 흰 카드)
  final Color card;
  final Color text;
  final Color textSub;
  final Color divider;

  /// 주의: 승인 대기·도움 필요
  final Color cautionBg;
  final Color cautionText;

  /// 긴급: SOS·사기 의심
  final Color dangerBg;
  final Color dangerText;

  /// 선택된 칩·긍정 상태 배경
  final Color positiveBg;

  /// 응답 시간 지남
  final Color neutralText;

  /// 요청 취소됨
  final Color cancelledText;

  static const light = HaebomTokens(
    brand: Color(0xFFFFCB3D),
    primary: Color(0xFF245D45),
    onPrimary: Colors.white,
    background: Color(0xFFFBF7EE),
    subtle: Color(0xFFF4EEE2),
    card: Colors.white,
    text: Color(0xFF26221B),
    textSub: Color(0xFF6E675C),
    divider: Color(0xFFEFE8DA),
    cautionBg: Color(0xFFFFF2E8),
    cautionText: Color(0xFFA34114),
    dangerBg: Color(0xFFFDEEEC),
    dangerText: Color(0xFFB3362A),
    positiveBg: Color(0xFFEAF3EE),
    neutralText: Color(0xFF6E675C),
    cancelledText: Color(0xFF52627A),
  );

  static const dark = HaebomTokens(
    brand: Color(0xFFFFCB3D),
    primary: Color(0xFF8CC7A1),
    onPrimary: Color(0xFF0F2A1E),
    background: Color(0xFF15130F),
    subtle: Color(0xFF26221B),
    card: Color(0xFF201D17),
    text: Color(0xFFEEE9DF),
    textSub: Color(0xFFB5AC9D),
    divider: Color(0xFF332E25),
    cautionBg: Color(0xFF3A2618),
    cautionText: Color(0xFFF4B28A),
    dangerBg: Color(0xFF3A1F1C),
    dangerText: Color(0xFFF08A7E),
    positiveBg: Color(0xFF203A2C),
    neutralText: Color(0xFFB5AC9D),
    cancelledText: Color(0xFF9DB0C7),
  );

  static HaebomTokens of(BuildContext context) => Theme.of(context).extension<HaebomTokens>() ?? light;

  @override
  HaebomTokens copyWith() => this;

  @override
  HaebomTokens lerp(ThemeExtension<HaebomTokens>? other, double t) => t < 0.5 || other is! HaebomTokens ? this : other;
}

/// 알림 위험도별 색 (일반: 녹색 / 주의: 주황 / 긴급: 빨강). 아이콘·글자와 함께 쓴다.
class RiskStyle {
  static Color color(RiskTone tone, ThemeData t) {
    final k = t.extension<HaebomTokens>() ?? HaebomTokens.light;
    return switch (tone) {
      RiskTone.normal => k.primary,
      RiskTone.caution => k.cautionText,
      RiskTone.danger => k.dangerText,
    };
  }

  static Color background(RiskTone tone, ThemeData t) {
    final k = t.extension<HaebomTokens>() ?? HaebomTokens.light;
    return switch (tone) {
      RiskTone.normal => k.card,
      RiskTone.caution => k.cautionBg,
      RiskTone.danger => k.dangerBg,
    };
  }
}

/// 승인 상태별 색/아이콘 (색 + 아이콘 + 글자 세 가지로 구분)
class StatusStyle {
  const StatusStyle(this.color, this.icon);
  final Color color;
  final IconData icon;

  static StatusStyle of(ApprovalStatus s, Brightness b) {
    final k = b == Brightness.dark ? HaebomTokens.dark : HaebomTokens.light;
    return switch (s) {
      ApprovalStatus.pending => StatusStyle(k.cautionText, Icons.hourglass_top_rounded),
      ApprovalStatus.approved => StatusStyle(k.primary, Icons.check_circle_rounded),
      ApprovalStatus.rejected => StatusStyle(k.dangerText, Icons.pan_tool_rounded),
      ApprovalStatus.expired => StatusStyle(k.neutralText, Icons.timer_off_rounded),
      ApprovalStatus.cancelled => StatusStyle(k.cancelledText, Icons.undo_rounded),
    };
  }
}

ThemeData _build(HaebomTokens k, Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF245D45), brightness: brightness).copyWith(
    primary: k.primary,
    onPrimary: k.onPrimary,
    primaryContainer: k.positiveBg,
    onPrimaryContainer: k.text,
    secondaryContainer: brightness == Brightness.light ? const Color(0xFFFFF3CC) : const Color(0xFF3B3320),
    onSecondaryContainer: k.text,
    surface: k.background,
    onSurface: k.text,
    onSurfaceVariant: k.textSub,
    surfaceContainerLow: k.subtle,
    surfaceContainer: k.subtle,
    surfaceContainerHigh: k.subtle,
    outline: k.textSub,
    outlineVariant: k.divider,
    error: k.dangerText,
  );
  final radius = BorderRadius.circular(Space.radius);
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: brightness);
  final text = base.textTheme.apply(bodyColor: k.text, displayColor: k.text).copyWith(
        // 페이지 제목 24 · 섹션 제목 20 · 본문 16 · 보조 14
        headlineSmall: base.textTheme.headlineSmall?.copyWith(fontSize: 24, fontWeight: FontWeight.w800, color: k.text),
        titleLarge: base.textTheme.titleLarge?.copyWith(fontSize: 20, fontWeight: FontWeight.w700, color: k.text),
        titleMedium: base.textTheme.titleMedium?.copyWith(fontSize: 17, fontWeight: FontWeight.w700, color: k.text),
        titleSmall: base.textTheme.titleSmall?.copyWith(fontSize: 16, fontWeight: FontWeight.w700, color: k.text),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 16, height: 1.45, color: k.text),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: 14, height: 1.45, color: k.text),
        bodySmall: base.textTheme.bodySmall?.copyWith(fontSize: 14, height: 1.4, color: k.textSub),
        labelLarge: base.textTheme.labelLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
      );
  return base.copyWith(
    extensions: [k],
    scaffoldBackgroundColor: k.background,
    textTheme: text,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    appBarTheme: AppBarTheme(
      backgroundColor: k.background,
      foregroundColor: k.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      toolbarHeight: 64,
      titleSpacing: Space.page,
      titleTextStyle: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: k.text),
    ),
    cardTheme: CardThemeData(
      color: k.card,
      surfaceTintColor: Colors.transparent,
      shadowColor: brightness == Brightness.light ? const Color(0x406E5014) : Colors.transparent,
      elevation: brightness == Brightness.light ? 1.5 : 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Space.cardRadius)),
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.page),
      minVerticalPadding: 12,
      minTileHeight: 56,
      titleTextStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: k.text),
      subtitleTextStyle: TextStyle(fontSize: 14, height: 1.4, color: k.textSub),
      iconColor: k.textSub,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: k.primary,
        foregroundColor: k.onPrimary,
        minimumSize: const Size(64, Space.button),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: k.text,
        minimumSize: const Size(64, Space.button),
        side: BorderSide(color: k.textSub.withValues(alpha: 0.6)),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: k.primary,
        minimumSize: const Size(48, 48),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: k.subtle,
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: k.primary, width: 2)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: k.card,
      indicatorColor: brightness == Brightness.light ? const Color(0xFFFFE7A0) : const Color(0xFF4A3F1E),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 68,
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? k.text : k.textSub,
          )),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontSize: 13,
          color: s.contains(WidgetState.selected) ? k.text : k.textSub,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w500,
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: k.subtle,
      selectedColor: k.positiveBg,
      side: BorderSide.none,
      shape: const StadiumBorder(),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      labelStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: k.text),
      secondaryLabelStyle: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: k.primary),
    ),
    dividerTheme: DividerThemeData(color: k.divider, space: 1, thickness: 1),
    // 켜짐: 녹색 바탕 + 흰 손잡이 / 꺼짐: 연한 회갈색 바탕 + 흰 손잡이 (위치로도 구분)
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? k.onPrimary : k.card),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? k.primary : (brightness == Brightness.light ? const Color(0xFFD9D0BF) : k.divider),
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: k.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: k.card, surfaceTintColor: Colors.transparent),
    popupMenuTheme: PopupMenuThemeData(
      color: k.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: k.divider)),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    tabBarTheme: TabBarThemeData(
      labelColor: k.text,
      unselectedLabelColor: k.textSub,
      indicatorColor: k.primary,
      dividerColor: k.divider,
      labelStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    ),
  );
}

ThemeData buildLightTheme() => _build(HaebomTokens.light, Brightness.light);

ThemeData buildDarkTheme() => _build(HaebomTokens.dark, Brightness.dark);

/// 바탕 위에 떠 있는 흰 카드 (라이트: 옅은 따뜻한 그림자 / 다크: 그림자 없음)
BoxDecoration cardDecoration(BuildContext context, {Color? color}) {
  final k = HaebomTokens.of(context);
  final light = Theme.of(context).brightness == Brightness.light;
  return BoxDecoration(
    color: color ?? k.card,
    borderRadius: BorderRadius.circular(Space.cardRadius),
    boxShadow: light
        ? const [
            BoxShadow(color: Color(0x0A6E5014), blurRadius: 2, offset: Offset(0, 1)),
            BoxShadow(color: Color(0x0F6E5014), blurRadius: 24, offset: Offset(0, 8)),
          ]
        : null,
  );
}

/// 위험도별 아이콘 칸 배경 (연한 색)
Color riskTint(RiskTone tone, BuildContext context) {
  final k = HaebomTokens.of(context);
  return switch (tone) {
    RiskTone.normal => k.positiveBg,
    RiskTone.caution => k.cautionBg,
    RiskTone.danger => k.dangerBg,
  };
}
