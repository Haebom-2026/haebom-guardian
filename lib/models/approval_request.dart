/// approvals/{id} 문서 모델. 일반 알림(notifications)과 별도로 관리한다.
library;

import 'sensitivity.dart';

enum ApprovalStatus {
  pending('pending', '승인 대기'),
  approved('approved', '승인 완료'),
  rejected('rejected', '거절'),
  expired('expired', '응답 시간 지남'),
  cancelled('cancelled', '요청 취소됨');

  const ApprovalStatus(this.code, this.label);
  final String code;
  final String label;

  bool get isFinal => this != ApprovalStatus.pending;

  static ApprovalStatus fromCode(String code) => ApprovalStatus.values
      .firstWhere((s) => s.code == code, orElse: () => ApprovalStatus.pending);
}

class ApprovalRequest {
  const ApprovalRequest({
    required this.id,
    required this.elderId,
    required this.guardianIds,
    required this.appName,
    required this.packageName,
    required this.action,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    this.respondedAt,
    this.respondedBy,
    this.category,
  });

  final String id;
  final String elderId;
  final List<String> guardianIds;
  final String appName;
  final String packageName;

  /// 내부 코드 (예: guide_gov24_auth). UI 문구는 [ApprovalActions]에서 변환.
  final String action;
  final ApprovalStatus status;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? respondedAt;
  final String? respondedBy;

  /// 분류 (선택 필드 · v2.2). 기존 문서에는 없다.
  final SensitivityCategory? category;

  /// 서버가 아직 만료 처리를 하지 않았더라도 만료 시각이 지났으면 만료로 본다.
  ApprovalStatus effectiveStatus(DateTime now) =>
      status == ApprovalStatus.pending && !now.isBefore(expiresAt)
          ? ApprovalStatus.expired
          : status;

  Duration remaining(DateTime now) {
    final d = expiresAt.difference(now);
    return d.isNegative ? Duration.zero : d;
  }

  ApprovalRequest copyWith({
    ApprovalStatus? status,
    DateTime? expiresAt,
    DateTime? respondedAt,
    String? respondedBy,
  }) =>
      ApprovalRequest(
        id: id,
        elderId: elderId,
        guardianIds: guardianIds,
        appName: appName,
        packageName: packageName,
        action: action,
        status: status ?? this.status,
        createdAt: createdAt,
        expiresAt: expiresAt ?? this.expiresAt,
        respondedAt: respondedAt ?? this.respondedAt,
        respondedBy: respondedBy ?? this.respondedBy,
        category: category,
      );

  Map<String, Object?> toMap() => {
        'elderId': elderId,
        'guardianIds': guardianIds,
        'appName': appName,
        'packageName': packageName,
        'action': action,
        'status': status.code,
        'createdAt': createdAt.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
        'respondedAt': respondedAt?.toIso8601String(),
        'respondedBy': respondedBy,
        if (category != null) 'category': category!.code,
      };
}

/// action 코드 → 보호자에게 보여줄 한국어 문구.
/// 실제 금융 거래/인증 승인이 아니라 "AI 도우미 안내를 계속할지"에 대한 승인이다.
class ApprovalActions {
  static const gov24Auth = 'guide_gov24_auth';
  static const bankOpen = 'guide_bank_open';
  static const moneyMove = 'guide_money_move';
  static const identity = 'guide_identity';
  static const install = 'guide_install';
  static const privacySend = 'guide_privacy_send';

  /// 고령자 앱은 쓰지 않는 옛 코드. 기존 데이터 표시용으로만 남긴다.
  static const unknownApp = 'guide_unknown_app';

  static const Map<String, String> _labels = {
    gov24Auth: '정부24 본인인증 단계 안내',
    bankOpen: '은행 앱 이용 안내',
    moneyMove: '송금·이체 화면 안내',
    identity: '본인인증·신분증 제출 안내',
    install: '앱 설치·권한 허용 안내',
    privacySend: '개인정보·신분증 사진 보내기 안내',
    unknownApp: '처음 사용하는 앱 이용 안내',
  };

  static String label(String action) => _labels[action] ?? '도우미 안내 진행';

  /// 고령자 앱이 보내는 action (개발자 화면 선택지)
  static List<String> get all => [gov24Auth, bankOpen, moneyMove, identity, install, privacySend];
}
