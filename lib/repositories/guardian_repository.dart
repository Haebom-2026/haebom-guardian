import '../models/approval_request.dart';
import '../models/family_link.dart';
import '../models/notification_item.dart';

/// 서버/저장소 오류 코드. 실제 연동 시 Cloud Functions 오류 응답의 code 값과 1:1 대응한다.
enum RepositoryErrorCode {
  notFound('not-found'),
  permissionDenied('permission-denied'),
  alreadyResponded('already-responded'),
  approvalExpired('approval-expired'),
  approvalCancelled('approval-cancelled'),
  invalidCode('invalid-code'),
  codeExpired('code-expired'),
  codeUsed('code-used'),
  alreadyLinked('already-linked'),
  tooManyAttempts('too-many-attempts'),
  invalidArgument('invalid-argument'),
  unavailable('unavailable');

  const RepositoryErrorCode(this.wire);

  /// 통신 규격상의 문자열 코드
  final String wire;
}

class RepositoryException implements Exception {
  const RepositoryException(this.code, [this.detail]);

  final RepositoryErrorCode code;
  final String? detail;

  /// 보호자에게 보여줄 한국어 안내 문구.
  String get userMessage => switch (code) {
        RepositoryErrorCode.notFound => '요청한 내용을 찾을 수 없습니다. 이미 삭제되었거나 연결이 해제되었을 수 있습니다.',
        RepositoryErrorCode.permissionDenied => '이 내용에 접근할 권한이 없습니다.',
        RepositoryErrorCode.alreadyResponded => '이미 다른 보호자가 응답한 요청입니다.',
        RepositoryErrorCode.approvalExpired => '응답 가능 시간이 지나 요청이 만료되었습니다.',
        RepositoryErrorCode.approvalCancelled => '가족이 요청을 취소했습니다.',
        RepositoryErrorCode.invalidCode => '연결 코드가 올바르지 않습니다. 숫자 6자리를 다시 확인해 주세요.',
        RepositoryErrorCode.codeExpired => '연결 코드의 유효시간(10분)이 지났습니다. 가족에게 새 코드를 요청해 주세요.',
        RepositoryErrorCode.codeUsed => '이미 사용된 연결 코드입니다. 가족에게 새 코드를 요청해 주세요.',
        RepositoryErrorCode.alreadyLinked => '이미 연결된 가족입니다.',
        RepositoryErrorCode.tooManyAttempts => '연결 코드 입력을 여러 번 실패했습니다. 잠시 후 다시 시도해 주세요.',
        RepositoryErrorCode.invalidArgument => '입력값을 다시 확인해 주세요.',
        RepositoryErrorCode.unavailable => '네트워크 연결을 확인한 뒤 다시 시도해 주세요.',
      };

  @override
  String toString() => 'RepositoryException(${code.wire}${detail == null ? '' : ': $detail'})';
}

/// 보호자 앱이 사용하는 데이터 접근 계층.
///
/// 현재는 [MockGuardianRepository]가 구현하며,
/// 추후 FirebaseRepository(Firestore + Cloud Functions)로 교체한다.
/// UI는 이 인터페이스에만 의존한다.
abstract class GuardianRepository {
  /// 로그인한 보호자 UID (실제 연동 시 Firebase Auth UID)
  String get currentGuardianId;

  /// 서버 기준 현재 시각 (남은 시간 계산용).
  DateTime now();

  /// 현재 보호자와 연결된 가족 목록 (실시간)
  Stream<List<FamilyLink>> watchLinks();

  /// 현재 보호자에게 공개된 알림 목록, 최신순 (실시간)
  Stream<List<NotificationItem>> watchNotifications();

  /// 현재 보호자가 응답 대상인 승인 요청 목록, 최신순 (실시간)
  Stream<List<ApprovalRequest>> watchApprovals();

  /// 단건 조회. 없거나 권한이 없으면 [RepositoryException].
  Future<NotificationItem> getNotification(String id);
  Future<ApprovalRequest> getApproval(String id);

  /// 현재 보호자 기준 읽음 처리 (readBy.{guardianUid})
  Future<void> markNotificationRead(String id);
  Future<void> markAllNotificationsRead({String? elderId});

  /// 승인/거절. 서버 트랜잭션에서 최초의 유효한 응답만 처리된다.
  Future<ApprovalRequest> respondToApproval(String id, {required bool approve});

  /// 6자리 연결 코드로 가족 연결. 서버가 코드 검증 및 횟수 제한을 처리한다.
  /// [elderLabel]: 내가 어르신을 부르는 호칭(어머니) · [guardianLabel]: 어르신이 나를 부르는 호칭(딸)
  Future<FamilyLink> connectWithCode(String code, {required String elderLabel, String guardianLabel = ''});

  /// 가족 연결 해제
  Future<void> disconnect(String elderId);
}
