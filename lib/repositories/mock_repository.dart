import 'dart:async';

import '../models/approval_request.dart';
import '../models/family_link.dart';
import '../models/notification_item.dart';
import 'guardian_repository.dart';
import 'mock_backend.dart';

/// [MockBackend]를 서버로 사용하는 보호자 저장소.
///
/// 실제 FirebaseRepository처럼 비동기 Future/Stream으로만 동작하므로
/// UI 코드는 교체 시 변경할 필요가 없다.
class MockGuardianRepository implements GuardianRepository {
  MockGuardianRepository(this.backend, {this.guardianId = MockBackend.meId, this.latency = Duration.zero});

  final MockBackend backend;
  final String guardianId;

  /// 네트워크 지연 흉내 (테스트에서는 0)
  final Duration latency;

  @override
  String get currentGuardianId => guardianId;

  @override
  DateTime now() => backend.now();

  Stream<T> _watch<T>(T Function() read) => Stream<T>.multi((controller) {
        controller.add(read()); // Firestore처럼 구독 즉시 현재 값을 전달
        final sub = backend.changes.listen((_) => controller.add(read()));
        controller.onCancel = sub.cancel;
      });

  Future<T> _call<T>(T Function() body) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    return body();
  }

  @override
  Stream<List<FamilyLink>> watchLinks() => _watch(() => backend.linksForGuardian(guardianId));

  @override
  Stream<List<NotificationItem>> watchNotifications() =>
      _watch(() => backend.notificationsFor(guardianId));

  @override
  Stream<List<ApprovalRequest>> watchApprovals() => _watch(() => backend.approvalsFor(guardianId));

  @override
  Future<NotificationItem> getNotification(String id) =>
      _call(() => backend.notificationFor(guardianId, id));

  @override
  Future<ApprovalRequest> getApproval(String id) => _call(() => backend.approvalFor(guardianId, id));

  @override
  Future<void> markNotificationRead(String id) => _call(() => backend.markRead(guardianId, id));

  @override
  Future<void> markAllNotificationsRead({String? elderId}) =>
      _call(() => backend.markAllRead(guardianId, elderId: elderId));

  @override
  Future<ApprovalRequest> respondToApproval(String id, {required bool approve}) =>
      _call(() => backend.respond(guardianId, id, approve: approve));

  @override
  Future<FamilyLink> connectWithCode(String code, {required String elderLabel, String guardianLabel = ''}) =>
      _call(() => backend.connectWithCode(guardianId, code, elderLabel: elderLabel, guardianLabel: guardianLabel));

  @override
  Future<void> disconnect(String elderId) => _call(() => backend.disconnect(guardianId, elderId));

  /// Mock은 실시간으로 반영되므로 할 일 없음
  @override
  Future<void> refresh() async {}
}
