import 'sensitivity.dart';

/// 민감 앱 카탈로그 (개발자 테스트 및 화면 표시용).
///
/// 패키지명은 고령자 앱의 감지 목록과 반드시 일치해야 하므로
/// 실제 연동 전 고령자 앱 담당자와 최종 확인이 필요하다. (docs/INTEGRATION.md 참고)
class SensitiveApp {
  const SensitiveApp({
    required this.appName,
    required this.packageName,
    required this.category,
    required this.defaultAction,
    this.sensitivity = SensitivityCategory.finance,
    this.entryReason = '',
  });

  final String appName;
  final String packageName;
  final String category;
  final String defaultAction;

  /// 고령자 앱이 보낼 분류·이유 예시 (개발자 테스트용, 개발지침서 4.3)
  final SensitivityCategory sensitivity;
  final String entryReason;

  static const gov24 = SensitiveApp(
    appName: '정부24',
    packageName: 'kr.go.minwon.m',
    category: '공공 서비스',
    defaultAction: 'guide_gov24_auth',
    sensitivity: SensitivityCategory.public,
    entryReason: '정부24 열기',
  );
  static const bank = SensitiveApp(
    appName: 'KB스타뱅킹',
    packageName: 'com.kbstar.kbbank',
    category: '은행',
    defaultAction: 'guide_bank_open',
    entryReason: '은행 앱 열기',
  );
  static const kakaoBank = SensitiveApp(
    appName: '카카오뱅크',
    packageName: 'com.kakaobank.channel',
    category: '은행',
    defaultAction: 'guide_bank_open',
    entryReason: '은행 앱 열기',
  );
  static const toss = SensitiveApp(
    appName: '토스',
    packageName: 'viva.republica.toss',
    category: '금융',
    defaultAction: 'guide_bank_open',
    entryReason: '금융 앱 열기',
  );

  static const all = [gov24, bank, kakaoBank, toss];
}

/// 고령자 앱 팝업("보호자에게 알림을 보내겠습니까?")에서의 선택.
enum ConsentChoice {
  yes('예'),
  no('아니요'),
  dismissed('닫기');

  const ConsentChoice(this.label);
  final String label;
}
