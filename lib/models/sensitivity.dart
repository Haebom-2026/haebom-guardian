/// 민감도 단계(level)와 분류(category). 개발지침서 4장 · DATA_SPEC_CHANGES.md v2.2.
///
/// 고령자 앱이 판단해 서버를 거쳐 notifications·approvals 문서에 실어 보내는 **선택 필드**다.
/// 기존 문서에는 없을 수 있으므로 모두 null을 허용하고, 모르는 값도 null로 처리한다.
library;

enum SensitivityLevel {
  l0('L0', '일반'),
  l1('L1', '알림'),
  l2('L2', '주의'),
  l3('L3', '위험');

  const SensitivityLevel(this.code, this.label);
  final String code;
  final String label;

  static SensitivityLevel? fromCode(Object? code) {
    if (code is! String) return null;
    final c = code.trim().toUpperCase();
    for (final l in values) {
      if (l.code == c) return l;
    }
    return null;
  }
}

enum SensitivityCategory {
  finance('finance', '금융'),
  identity('identity', '본인인증'),
  public('public', '공공 서비스'),
  device('device', '기기·보안'),
  privacy('privacy', '개인정보'),
  scam('scam', '사기 의심'),
  none('none', '기타');

  const SensitivityCategory(this.code, this.label);
  final String code;
  final String label;

  static SensitivityCategory? fromCode(Object? code) {
    if (code is! String) return null;
    final c = code.trim().toLowerCase();
    for (final v in values) {
      if (v.code == c) return v;
    }
    return null;
  }
}

/// 보호자 앱 화면에서 쓰는 위험도 표시 단계 (색상 + 아이콘 + 글자로 구분).
enum RiskTone {
  /// 일반 (그린)
  normal,

  /// 주의 (주황): L2, 막힘
  caution,

  /// 위험 (빨강): L3, 사기 의심, SOS
  danger,
}
