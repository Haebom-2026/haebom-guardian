/// notifications/{id} 문서 모델.
///
/// 고령자가 "예"를 선택한 경우에만 서버가 생성한다. (consent 필드 없음)
library;

import 'sensitivity.dart';

enum NotificationType {
  /// 민감 앱 진입 (고령자 동의 후 생성)
  sensitiveEntry('sensitive_entry'),

  /// SOS 도움 요청
  sos('sos'),

  /// 앱 사용 중 도움이 필요해 보이는 상황
  stuck('stuck');

  const NotificationType(this.code);
  final String code;

  static NotificationType fromCode(String code) => NotificationType.values
      .firstWhere((t) => t.code == code, orElse: () => NotificationType.sensitiveEntry);
}

class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.elderId,
    required this.guardianIds,
    required this.appName,
    required this.packageName,
    required this.type,
    required this.createdAt,
    this.readBy = const {},
    this.level,
    this.category,
    this.reason,
  });

  final String id;
  final String elderId;

  /// 서버가 links 컬렉션을 기준으로 결정한 수신 보호자 UID 목록.
  final List<String> guardianIds;
  final String appName;
  final String packageName;
  final NotificationType type;
  final DateTime createdAt;

  /// 보호자 UID → 읽은 시각. 보호자별로 독립 관리한다.
  final Map<String, DateTime> readBy;

  /// 민감도 단계 (선택 필드 · v2.2). 기존 문서에는 없다.
  final SensitivityLevel? level;

  /// 분류 (선택 필드 · v2.2). `scam`이면 어떤 type이든 가장 위험하게 표시한다.
  final SensitivityCategory? category;

  /// 고령자 앱이 정한 짧은 이유 (예: "은행 앱 열기"). 선택 필드 · v2.2.
  final String? reason;

  bool isReadBy(String guardianId) => readBy.containsKey(guardianId);

  bool get isScam => category == SensitivityCategory.scam;

  /// 화면 표시용 위험도. 새 필드가 없으면 type만으로 판단한다(기존 동작과 같음).
  RiskTone get risk {
    if (isScam || level == SensitivityLevel.l3 || type == NotificationType.sos) return RiskTone.danger;
    if (level == SensitivityLevel.l2 || type == NotificationType.stuck) return RiskTone.caution;
    return RiskTone.normal;
  }

  /// 표시할 이유. 비어 있으면 null.
  String? get reasonText {
    final r = reason?.trim();
    return r == null || r.isEmpty ? null : r;
  }

  NotificationItem copyWith({Map<String, DateTime>? readBy}) => NotificationItem(
        id: id,
        elderId: elderId,
        guardianIds: guardianIds,
        appName: appName,
        packageName: packageName,
        type: type,
        createdAt: createdAt,
        readBy: readBy ?? this.readBy,
        level: level,
        category: category,
        reason: reason,
      );

  /// Firestore 문서 형태 (FirebaseRepository 구현 시 Timestamp 변환 필요).
  Map<String, Object?> toMap() => {
        'elderId': elderId,
        'guardianIds': guardianIds,
        'appName': appName,
        'packageName': packageName,
        'type': type.code,
        'createdAt': createdAt.toIso8601String(),
        'readBy': readBy.map((k, v) => MapEntry(k, v.toIso8601String())),
        if (level != null) 'level': level!.code,
        if (category != null) 'category': category!.code,
        if (reason != null) 'reason': reason,
      };
}
