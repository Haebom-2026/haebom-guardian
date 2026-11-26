import 'package:flutter_test/flutter_test.dart';
import 'package:guardian_app/models/sensitive_app.dart';
import 'package:guardian_app/repositories/mock_backend.dart';
import 'package:guardian_app/services/notification_service.dart';

import 'helpers.dart';

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  late TestEnv env;

  setUp(() async {
    env = TestEnv();
    env.deps.notifications.start();
    await flush();
  });

  tearDown(() => env.deps.dispose());

  test('기존 데이터는 로컬 알림으로 띄우지 않는다', () {
    expect(env.notifier.shown, isEmpty);
  });

  test('간략하게 보기를 켜면 최소 문구로 로컬 알림을 표시한다', () async {
    env.deps.settings.briefNotifications = true;
    final (_, n) = env.backend
        .reportSensitiveEntry(elderId: MockBackend.momId, app: SensitiveApp.gov24, choice: ConsentChoice.yes);
    await flush();
    expect(env.notifier.shown, hasLength(1));
    final alert = env.notifier.shown.single;
    expect(alert.body, isNot(contains('정부24')));
    expect(alert.target!.kind, AlertTarget.notification);
    expect(alert.target!.id, n!.id);
    expect(alert.channel, AlertChannel.activity);
  });

  test('기본은 자세히: 누가 어떤 서비스를 쓰는지 포함한다 (잠금 화면은 비공개 알림으로 보호)', () async {
    env.backend.reportSensitiveEntry(elderId: MockBackend.momId, app: SensitiveApp.gov24, choice: ConsentChoice.yes);
    await flush();
    expect(env.notifier.shown.single.body, '어머니가 정부24를 사용하려고 합니다.');
  });

  test('아니요 선택 시 로컬 알림도 표시되지 않는다', () async {
    env.backend.reportSensitiveEntry(elderId: MockBackend.momId, app: SensitiveApp.gov24, choice: ConsentChoice.no);
    env.backend.reportSensitiveEntry(
        elderId: MockBackend.momId, app: SensitiveApp.gov24, choice: ConsentChoice.dismissed);
    await flush();
    expect(env.notifier.shown, isEmpty);
  });

  test('승인 요청은 승인 채널로, SOS는 SOS 채널로 표시된다', () async {
    final a = env.backend.requestApproval(elderId: MockBackend.dadId, app: SensitiveApp.bank)!;
    env.backend.createSos(MockBackend.dadId);
    await flush();
    expect(env.notifier.shown.map((s) => s.channel), containsAll([AlertChannel.approval, AlertChannel.sos]));
    final approvalAlert = env.notifier.shown.firstWhere((s) => s.channel == AlertChannel.approval);
    expect(approvalAlert.target!.encode(), 'approval:${a.id}');
  });

  test('알림 종류별 설정을 끄면 표시하지 않는다', () async {
    env.deps.settings.activityAlerts = false;
    env.deps.settings.approvalAlerts = false;
    env.backend.reportSensitiveEntry(elderId: MockBackend.momId, app: SensitiveApp.toss, choice: ConsentChoice.yes);
    env.backend.requestApproval(elderId: MockBackend.momId, app: SensitiveApp.toss);
    await flush();
    expect(env.notifier.shown, isEmpty);
  });

  test('payload 인코딩/디코딩', () {
    expect(AlertTarget.decode('approval:a_1')!.id, 'a_1');
    expect(AlertTarget.decode('notification:n_1')!.kind, AlertTarget.notification);
    expect(AlertTarget.decode('unknown:x'), isNull);
    expect(AlertTarget.decode('approval:'), isNull);
    expect(AlertTarget.decode(null), isNull);
  });
}
