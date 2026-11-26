/// links/{elderId_guardianId} 문서 모델.
class FamilyLink {
  const FamilyLink({
    required this.elderId,
    required this.guardianId,
    required this.elderName,
    required this.elderLabel,
    this.guardianLabel = '',
    required this.connectedAt,
  });

  final String elderId;
  final String guardianId;
  final String elderName;

  /// 보호자가 어르신을 부르는 호칭 (예: 어머니). 보호자 앱 화면에 쓴다. 보호자마다 다를 수 있다.
  /// v2.2 전 문서의 `relationship` 값은 이 필드로 읽는다.
  final String elderLabel;

  /// 어르신이 보호자를 부르는 호칭 (예: 딸). 고령자 앱 안내("딸에게 알림을 보냈어요")에 쓴다.
  /// v2.2 전 문서에는 없으므로 빈 문자열일 수 있다.
  final String guardianLabel;
  final DateTime connectedAt;

  String get id => '${elderId}_$guardianId';

  /// 화면에 표시할 이름. 호칭이 없으면 이름을 사용한다.
  String get displayName => elderLabel.trim().isEmpty ? elderName : elderLabel;

  Map<String, Object?> toMap() => {
        'elderId': elderId,
        'guardianId': guardianId,
        'elderName': elderName,
        'elderLabel': elderLabel,
        'guardianLabel': guardianLabel,
        'connectedAt': connectedAt.toIso8601String(),
      };
}

/// connectCodes/{code} 문서 모델 (서버 전용, 보호자 앱은 직접 읽지 않음).
class ConnectCode {
  const ConnectCode({
    required this.code,
    required this.elderId,
    required this.expiresAt,
    this.used = false,
  });

  final String code;
  final String elderId;
  final DateTime expiresAt;
  final bool used;

  ConnectCode markUsed() =>
      ConnectCode(code: code, elderId: elderId, expiresAt: expiresAt, used: true);

  /// 새 코드 발급으로 무효화: 즉시 만료 처리
  ConnectCode expire(DateTime at) => ConnectCode(code: code, elderId: elderId, expiresAt: at, used: used);
}
