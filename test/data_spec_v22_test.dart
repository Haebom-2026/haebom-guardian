// 공통 데이터 규격 v2.2 (docs/DATA_SPEC_CHANGES.md) 확인:
// elderLabel/guardianLabel 분리, level·category·reason 선택 필드, 승인 action 4개, 막힘 알림 우선순위.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guardian_app/app/routes.dart';
import 'package:guardian_app/models/approval_request.dart';
import 'package:guardian_app/models/notification_item.dart';
import 'package:guardian_app/models/sensitive_app.dart';
import 'package:guardian_app/models/sensitivity.dart';
import 'package:guardian_app/repositories/mock_backend.dart';
import 'package:guardian_app/repositories/server/server_repository.dart';
import 'package:guardian_app/services/notification_service.dart';
import 'package:guardian_app/utils/formatters.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers.dart';

DateTime _now() => DateTime(2026, 11, 25, 12);

NotificationItem _n(NotificationType type,
        {SensitivityLevel? level, SensitivityCategory? category, String? reason, String app = '토스'}) =>
    NotificationItem(
      id: 'n1',
      elderId: 'e',
      guardianIds: const ['g'],
      appName: app,
      packageName: 'p',
      type: type,
      createdAt: _now(),
      level: level,
      category: category,
      reason: reason,
    );

void main() {
  group('Firestore 문서 읽기 (새 필드가 없어도 동작)', () {
    final base = {
      'elderId': 'e',
      'guardianIds': ['g'],
      'appName': '토스',
      'packageName': 'viva.republica.toss',
      'type': 'sensitive_entry',
      'createdAt': Timestamp.fromDate(_now()),
    };

    test('기존 알림 문서: level·category·reason 없음 → null, 위험도는 type 기준', () {
      final n = FirestoreMappers.notification('n1', base, _now);
      expect(n.level, isNull);
      expect(n.category, isNull);
      expect(n.reason, isNull);
      expect(n.risk, RiskTone.normal);
      final sos = FirestoreMappers.notification('n2', {...base, 'type': 'sos'}, _now);
      expect(sos.risk, RiskTone.danger);
      final stuck = FirestoreMappers.notification('n3', {...base, 'type': 'stuck'}, _now);
      expect(stuck.risk, RiskTone.caution);
    });

    test('새 필드가 있으면 읽고, 모르는 값·잘못된 형식은 무시한다', () {
      final n = FirestoreMappers.notification(
          'n1', {...base, 'level': 'L2', 'category': 'finance', 'reason': '송금 화면'}, _now);
      expect(n.level, SensitivityLevel.l2);
      expect(n.category, SensitivityCategory.finance);
      expect(n.reason, '송금 화면');
      expect(n.risk, RiskTone.caution);

      final odd = FirestoreMappers.notification('n2', {...base, 'level': 'L9', 'category': 42, 'reason': 3}, _now);
      expect(odd.level, isNull);
      expect(odd.category, isNull);
      expect(odd.reason, isNull);
    });

    test('scam은 어떤 type이든 위험, L3도 위험', () {
      final scam = FirestoreMappers.notification('n1', {...base, 'category': 'scam'}, _now);
      expect(scam.risk, RiskTone.danger);
      final l3 = FirestoreMappers.notification('n2', {...base, 'level': 'l3'}, _now);
      expect(l3.risk, RiskTone.danger);
    });

    test('승인 문서 category: 없으면 null, 있으면 읽음', () {
      final a = {
        'elderId': 'e',
        'guardianIds': ['g'],
        'appName': '정부24',
        'packageName': 'kr.go.minwon.m',
        'action': 'guide_identity',
        'status': 'pending',
        'createdAt': Timestamp.fromDate(_now()),
      };
      expect(FirestoreMappers.approval('a1', a, _now).category, isNull);
      expect(FirestoreMappers.approval('a1', {...a, 'category': 'identity'}, _now).category,
          SensitivityCategory.identity);
    });

    test('links: 옛 relationship은 elderLabel로, 새 문서는 두 호칭 모두 읽는다', () {
      final old = FirestoreMappers.link({'elderId': 'e', 'guardianId': 'g', 'elderName': '김순자', 'relationship': '어머니'});
      expect(old.elderLabel, '어머니');
      expect(old.guardianLabel, '');
      expect(old.displayName, '어머니');
      final v22 = FirestoreMappers.link(
          {'elderId': 'e', 'guardianId': 'g', 'elderName': '김순자', 'elderLabel': '엄마', 'guardianLabel': '딸'});
      expect(v22.elderLabel, '엄마');
      expect(v22.guardianLabel, '딸');
    });
  });

  group('문구', () {
    test('민감 앱 알림은 "사용하려고 합니다" + 받침에 맞는 조사', () {
      expect(notificationMessage(_n(NotificationType.sensitiveEntry), '어머니'), '어머니가 토스를 사용하려고 합니다.');
      expect(notificationMessage(_n(NotificationType.sensitiveEntry, app: 'KB스타뱅킹'), '아버지'),
          '아버지가 KB스타뱅킹을 사용하려고 합니다.');
      expect(notificationMessage(_n(NotificationType.sensitiveEntry, app: '정부24'), '할머니'),
          '할머니가 정부24를 사용하려고 합니다.');
      expect(withObjectParticle('홈택스'), '홈택스를');
      expect(withObjectParticle('국민연금'), '국민연금을');
    });

    test('사기 의심은 type과 관계없이 사기 의심 문구와 라벨', () {
      final scam = _n(NotificationType.sos, category: SensitivityCategory.scam, level: SensitivityLevel.l3);
      expect(notificationMessage(scam, '어머니'), '어머니가 사기 의심 상황일 수 있습니다. 바로 연락해 확인해 주세요.');
      expect(notificationLabel(scam), '사기 의심 알림');
    });

    test('L2 이상이면 라벨에 단계, 없으면 기존 라벨', () {
      expect(notificationLabel(_n(NotificationType.sensitiveEntry)), '앱 이용 알림');
      expect(notificationLabel(_n(NotificationType.sensitiveEntry, level: SensitivityLevel.l1)), '앱 이용 알림');
      expect(notificationLabel(_n(NotificationType.sensitiveEntry, level: SensitivityLevel.l2)), '앱 이용 알림 · 주의');
    });

    test('승인 action 4개 추가 문구, 모르는 action은 기본 문구', () {
      expect(ApprovalActions.label('guide_money_move'), '송금·이체 화면 안내');
      expect(ApprovalActions.label('guide_identity'), '본인인증·신분증 제출 안내');
      expect(ApprovalActions.label('guide_install'), '앱 설치·권한 허용 안내');
      expect(ApprovalActions.label('guide_privacy_send'), '개인정보·신분증 사진 보내기 안내');
      expect(ApprovalActions.label('guide_new_future_action'), '도우미 안내 진행');
      expect(ApprovalActions.all, hasLength(6));
    });

    test('만료·취소 상태 이름', () {
      expect(ApprovalStatus.expired.label, '응답 시간 지남');
      expect(ApprovalStatus.cancelled.label, '요청 취소됨');
    });
  });

  group('알림 채널 (우선순위)', () {
    test('막힘 → 도움 필요(높음), SOS·사기 의심·L3 → 긴급, 그 밖은 일반', () {
      expect(NotificationService.channelFor(_n(NotificationType.stuck)), AlertChannel.help);
      expect(NotificationService.channelFor(_n(NotificationType.sos)), AlertChannel.sos);
      expect(NotificationService.channelFor(_n(NotificationType.sensitiveEntry)), AlertChannel.activity);
      expect(
          NotificationService.channelFor(
              _n(NotificationType.sensitiveEntry, category: SensitivityCategory.scam)),
          AlertChannel.sos);
      expect(NotificationService.channelFor(_n(NotificationType.sensitiveEntry, level: SensitivityLevel.l3)),
          AlertChannel.sos);
    });

    test('Mock: 막힘 알림이 도움 필요 채널로 표시된다', () async {
      final env = TestEnv();
      addTearDown(env.deps.dispose);
      env.deps.notifications.start();
      await Future<void>.delayed(Duration.zero);
      env.backend.createStuck(MockBackend.momId, SensitiveApp.gov24);
      await Future<void>.delayed(Duration.zero);
      expect(env.notifier.shown.single.channel, AlertChannel.help);
      expect(env.notifier.shown.single.title, '해봄 가족 · 도움 필요');
    });
  });

  group('Mock 서버', () {
    test('민감 앱 알림에 level·category·reason, 사기 의심 SOS에 scam·L3', () {
      final b = MockBackend(clock: _now);
      final (_, n) =
          b.reportSensitiveEntry(elderId: MockBackend.momId, app: SensitiveApp.gov24, choice: ConsentChoice.yes);
      expect(n!.level, SensitivityLevel.l1);
      expect(n.category, SensitivityCategory.public);
      expect(n.reason, '정부24 열기');

      final sos = b.createSos(MockBackend.momId, category: SensitivityCategory.scam, reason: '기관 사칭 송금 요청')!;
      expect(sos.isScam, isTrue);
      expect(sos.level, SensitivityLevel.l3);
      expect(b.createSos(MockBackend.momId)!.category, isNull, reason: '일반 SOS는 새 필드 없음');
    });

    test('연결 시 두 호칭을 함께 저장한다', () {
      final b = MockBackend(clock: _now);
      final code = b.issueConnectCode(MockBackend.grandmaId);
      final l = b.connectWithCode(MockBackend.meId, code, elderLabel: '할머니', guardianLabel: '손녀');
      expect(l.elderLabel, '할머니');
      expect(l.guardianLabel, '손녀');
      expect(l.toMap()['guardianLabel'], '손녀');
    });
  });

  testWidgets('가족 연결: 가족이 나를 부르는 호칭을 골라야 연결할 수 있다', (tester) async {
    tester.view.physicalSize = const Size(412, 915) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final env = TestEnv();
    addTearDown(env.deps.dispose);
    await tester.pumpWidget(env.app);
    await tester.pumpAndSettle();
    env.deps.navigatorKey.currentState!.pushNamed(AppRoutes.connectFamily);
    await tester.pumpAndSettle();

    final code = env.backend.issueConnectCode(MockBackend.grandmaId);
    await tester.enterText(find.byKey(const Key('connect_code_field')), code);
    await tester.tap(find.byKey(const Key('elder_label_할머니')));
    await tester.pump();
    FilledButton submit() => tester.widget<FilledButton>(find.byKey(const Key('connect_submit')));
    expect(submit().onPressed, isNull, reason: '두 번째 호칭을 고르기 전에는 비활성');

    await tester.ensureVisible(find.byKey(const Key('guardian_label_손자')));
    await tester.tap(find.byKey(const Key('guardian_label_손자')));
    await tester.pump();
    expect(submit().onPressed, isNotNull);
    await tester.ensureVisible(find.byKey(const Key('connect_submit')));
    await tester.tap(find.byKey(const Key('connect_submit')));
    await tester.pumpAndSettle();

    final link = env.backend.linksForGuardian(MockBackend.meId).firstWhere((l) => l.elderId == MockBackend.grandmaId);
    expect(link.elderLabel, '할머니');
    expect(link.guardianLabel, '손자');
  });

  testWidgets('사기 의심 알림은 목록에 사기 의심 라벨과 이유를 보여 준다', (tester) async {
    tester.view.physicalSize = const Size(412, 915) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final env = TestEnv();
    addTearDown(env.deps.dispose);
    await tester.pumpWidget(env.app);
    await tester.pumpAndSettle();
    env.backend.createSos(MockBackend.momId, category: SensitivityCategory.scam, reason: '기관 사칭 송금 요청');
    await tester.pumpAndSettle();
    expect(find.textContaining('사기 의심 알림'), findsWidgets); // "사기 의심 알림 · 방금 전"
    expect(find.text('이유: 기관 사칭 송금 요청'), findsWidgets);
  });
}
