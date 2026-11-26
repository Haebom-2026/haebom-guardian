import 'package:flutter_test/flutter_test.dart';
import 'package:guardian_app/models/approval_request.dart';
import 'package:guardian_app/models/notification_item.dart';
import 'package:guardian_app/repositories/mock_backend.dart';
import 'package:guardian_app/screens/developer/gov24_scenario.dart';
import 'package:guardian_app/utils/formatters.dart';

import 'helpers.dart';

void main() {
  late TestEnv env;
  late List<String> logs;
  late Set<String> seededNotifications;
  late int seededApprovals;
  late Set<String> seededApprovalIds;

  Gov24ResidentCopyScenario scenario({String elderId = MockBackend.momId}) => Gov24ResidentCopyScenario(
      backend: env.backend,
      elderId: elderId,
      log: logs.add,
      stepDelay: Duration.zero,
      pollInterval: const Duration(milliseconds: 1));

  /// 시나리오가 새로 만든 승인 요청이 생길 때까지 기다린 뒤 반환
  Future<ApprovalRequest> waitForRequest() async {
    for (var i = 0; i < 500; i++) {
      final created = env.backend.allApprovals.where((a) => !seededApprovalIds.contains(a.id));
      if (created.isNotEmpty) return created.single;
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    throw StateError('승인 요청이 만들어지지 않음');
  }

  /// 시나리오가 새로 만든 알림의 종류
  List<NotificationType> newTypes() => env.backend
      .notificationsFor(MockBackend.meId)
      .where((n) => !seededNotifications.contains(n.id))
      .map((n) => n.type)
      .toList();

  setUp(() {
    env = TestEnv();
    logs = [];
    seededNotifications = env.backend.allNotifications.map((n) => n.id).toSet();
    seededApprovals = env.backend.allApprovals.length;
    seededApprovalIds = env.backend.allApprovals.map((a) => a.id).toSet();
  });

  test('등본 시나리오: 이용 알림 → 승인 요청 → 보호자 승인 → (고령자 동의) 도움 필요 알림 → 완료', () async {
    final run = scenario().run();
    final req = await waitForRequest();
    expect(req.appName, '정부24');
    expect(req.guardianIds, unorderedEquals([MockBackend.meId, MockBackend.siblingId]));
    expect(newTypes(), [NotificationType.sensitiveEntry], reason: '승인 전에는 도움 필요 알림이 없다');
    env.backend.respond(MockBackend.meId, req.id, approve: true);
    await run;

    expect(newTypes(), unorderedEquals([NotificationType.sensitiveEntry, NotificationType.stuck]));
    expect(
      env.backend.allNotifications.where((n) => !seededNotifications.contains(n.id)).map((n) => n.appName),
      everyElement('정부24'),
    );
    expect(env.backend.allApprovals.length, seededApprovals + 1);
    expect(env.backend.elderInbox.first.status, ApprovalStatus.approved);
    expect(logs.any((l) => l.contains('가족에게 연락할까요?')), isTrue, reason: '도움 필요는 고령자 동의 후 전송');
    expect(logs.last, contains('[등본 6/6]'));
  });

  test('보호자가 거절하면 안내를 중단하고 도움 필요 알림을 보내지 않는다', () async {
    final run = scenario().run();
    final req = await waitForRequest();
    env.backend.respond(MockBackend.siblingId, req.id, approve: false);
    await run;
    expect(newTypes(), [NotificationType.sensitiveEntry]);
    expect(logs.last, contains('보호자가 거절함'));
  });

  test('응답 없이 5분이 지나면 만료 → 안내 중단 + SOS 문자 제안', () async {
    final run = scenario().run();
    await waitForRequest();
    env.clock.advance(MockBackend.approvalTtl);
    await run;
    expect(newTypes(), [NotificationType.sensitiveEntry]);
    expect(env.backend.allApprovals.firstWhere((a) => !seededApprovalIds.contains(a.id)).status,
        ApprovalStatus.expired);
    expect(logs.last, contains('SOS 문자'));
  });

  test('승인 대기 중에 중단하면 승인 요청을 취소한다', () async {
    final s = scenario();
    final run = s.run();
    final req = await waitForRequest();
    expect(s.pendingApprovalId, req.id);
    s.cancel();
    await run;
    expect(env.backend.allApprovals.firstWhere((a) => a.id == req.id).status, ApprovalStatus.cancelled);
    expect(newTypes(), [NotificationType.sensitiveEntry]);
    expect(s.pendingApprovalId, isNull);
  });

  test('중단하면 이후 단계(도움 필요 알림)를 보내지 않음', () async {
    final s = Gov24ResidentCopyScenario(
      backend: env.backend,
      elderId: MockBackend.momId,
      log: logs.add,
      stepDelay: const Duration(milliseconds: 20),
    );
    final run = s.run();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    s.cancel();
    await run;
    expect(newTypes(), [NotificationType.sensitiveEntry]);
    expect(logs.any((l) => l.contains('사용자가 중단함')), isTrue);
    expect(s.running, isFalse);
  });

  test('연결된 보호자가 없는 고령자는 알림 없이 바로 종료', () async {
    final before = env.backend.allNotifications.length;
    await scenario(elderId: MockBackend.grandmaId).run();
    expect(env.backend.allNotifications.length, before);
    expect(logs.any((l) => l.contains('시나리오 중단')), isTrue);
  });

  test('승인 알림 상세 문구: 안내 이름에 앱 이름이 있으면 반복하지 않음', () {
    final now = DateTime(2026, 11, 24, 14);
    ApprovalRequest req(String appName, String action) => ApprovalRequest(
          id: 'x',
          elderId: MockBackend.momId,
          guardianIds: const [MockBackend.meId],
          appName: appName,
          packageName: 'p',
          action: action,
          status: ApprovalStatus.pending,
          createdAt: now,
          expiresAt: now.add(const Duration(minutes: 5)),
        );
    expect(approvalAlertDetail(req('정부24', ApprovalActions.gov24Auth), '어머니'),
        "어머니가 '정부24 본인인증 단계 안내' 진행 승인을 요청했습니다.");
    expect(approvalAlertDetail(req('KB스타뱅킹', ApprovalActions.bankOpen), '어머니'),
        "어머니가 KB스타뱅킹 '은행 앱 이용 안내' 진행 승인을 요청했습니다.");
  });
}
