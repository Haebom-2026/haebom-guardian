import 'package:flutter_test/flutter_test.dart';
import 'package:guardian_app/repositories/mock_repository.dart';
import 'package:guardian_app/repositories/guardian_repository.dart';
import 'package:guardian_app/models/family_link.dart';
import 'package:guardian_app/app/dependencies.dart';
import 'package:guardian_app/app/app.dart';
import 'package:guardian_app/app/routes.dart';
import 'package:guardian_app/models/approval_request.dart';
import 'package:guardian_app/models/sensitive_app.dart';
import 'package:guardian_app/repositories/mock_backend.dart';
import 'package:guardian_app/services/notification_service.dart';
import 'package:guardian_app/widgets/common.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers.dart';

String countValue(WidgetTester tester, String key) => (tester.widget<Text>(find.byKey(ValueKey(key)))).data!;

Future<TestEnv> pumpApp(WidgetTester tester, {bool phoneSize = true}) async {
  if (phoneSize) {
    tester.view.physicalSize = const Size(412, 915) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }
  final env = TestEnv();
  await tester.pumpWidget(env.app);
  await tester.pumpAndSettle();
  addTearDown(env.deps.dispose);
  return env;
}

/// 지연 생성되는 ListView 항목까지 스크롤한 뒤 탭
Future<void> tapVisible(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 150, scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> openTab(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('홈: 도움이 필요한 일·확인하지 않은 알림 수가 표시되고 실시간으로 갱신된다', (tester) async {
    final env = await pumpApp(tester);
    expect(find.text('해봄 가족'), findsOneWidget);
    expect(find.text('도움이 필요한 일'), findsOneWidget);
    expect(countValue(tester, 'help_count'), '1', reason: '승인 대기 1');
    expect(countValue(tester, 'unread_count'), '2');
    expect(find.text('요청 확인하기'), findsOneWidget, reason: '홈에서는 바로 승인하지 않고 상세로 이동');

    env.backend.reportSensitiveEntry(elderId: MockBackend.momId, app: SensitiveApp.toss, choice: ConsentChoice.yes);
    env.backend.requestApproval(elderId: MockBackend.dadId, app: SensitiveApp.bank);
    await tester.pumpAndSettle();
    expect(countValue(tester, 'help_count'), '2');
    expect(countValue(tester, 'unread_count'), '3');
    expect(find.text('어머니가 토스를 사용하려고 합니다.'), findsWidgets);
  });

  testWidgets('홈: 가족 선택 시 해당 가족 기준으로 바뀐다', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, '아버지'));
    await tester.pumpAndSettle();
    expect(countValue(tester, 'unread_count'), '1');
    expect(find.byKey(const ValueKey('help_count')), findsNothing);
    expect(find.text('지금 확인할 요청이 없어요'), findsOneWidget);
    expect(find.text('아버지 (이정호)'), findsOneWidget, reason: '누구의 정보인지 상단에 표시');
  });

  testWidgets('홈: 아니요 선택은 홈에 아무것도 추가하지 않는다', (tester) async {
    final env = await pumpApp(tester);
    final rowsBefore = find.byType(NotificationTile).evaluate().length;
    env.backend.reportSensitiveEntry(elderId: MockBackend.momId, app: SensitiveApp.kakaoBank, choice: ConsentChoice.no);
    env.backend.reportSensitiveEntry(
      elderId: MockBackend.momId,
      app: SensitiveApp.kakaoBank,
      choice: ConsentChoice.dismissed,
    );
    await tester.pumpAndSettle();
    expect(countValue(tester, 'unread_count'), '2');
    expect(find.byType(NotificationTile).evaluate().length, rowsBefore);
    expect(find.text('어머니가 카카오뱅크를 사용하려고 합니다.'), findsNothing);
  });

  testWidgets('알림 상세: 열기만 해서는 확인되지 않고, "확인했어요"를 눌러야 확인 전 수가 줄어든다', (tester) async {
    final env = await pumpApp(tester);
    await tapVisible(tester, find.text('아버지가 카카오뱅크를 사용하려고 합니다.'));
    expect(find.text('알림 상세'), findsOneWidget);
    expect(find.text('카카오뱅크'), findsOneWidget);
    expect(find.textContaining('입력한 개인정보'), findsOneWidget);
    expect(env.deps.store.unreadCount(), 2, reason: '상세를 연 것만으로는 확인 처리하지 않는다');
    await tapVisible(tester, find.byKey(const Key('notification_confirm')));
    expect(find.byKey(const Key('notification_confirmed')), findsOneWidget);
    expect(find.byKey(const Key('notification_confirm')), findsNothing);
    env.deps.navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(env.deps.store.unreadCount(), 1);
    // 하단 탭 '알림' 배지도 1로 갱신
    expect(find.descendant(of: find.byType(NavigationBar), matching: find.text('1')), findsWidgets);
  });

  testWidgets('알림 화면: 확인 전 필터와 모두 확인(확인 창)', (tester) async {
    await pumpApp(tester);
    await openTab(tester, '알림');
    expect(find.text('어머니가 정부24를 사용하려고 합니다.'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, '확인 전 2'));
    await tester.pumpAndSettle();
    expect(find.text('어머니가 정부24를 사용하려고 합니다.'), findsNothing, reason: '이미 확인한 알림은 숨김');
    expect(find.text('아버지가 카카오뱅크를 사용하려고 합니다.'), findsOneWidget);
    await tester.tap(find.text('모두 확인'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm_dialog_ok')));
    await tester.pumpAndSettle();
    expect(find.text('확인 전 알림이 없습니다'), findsOneWidget);
  });

  testWidgets('승인 상세 이동 → 확인 팝업 → 승인 완료, 결과가 고령자 앱에 전달된다', (tester) async {
    final env = await pumpApp(tester);
    await openTab(tester, '승인');
    await tester.tap(find.text('어머니 · 정부24'));
    await tester.pumpAndSettle();
    expect(find.text('승인 요청 상세'), findsOneWidget);
    expect(find.text('정부24 본인인증 단계 안내'), findsOneWidget);
    expect(find.text('남은 시간'), findsOneWidget);
    expect(find.text('계속해도 돼요'), findsOneWidget);
    expect(find.text('잠깐 멈춰요'), findsOneWidget);

    await tester.tap(find.byKey(const Key('approve_button')));
    await tester.pumpAndSettle();
    expect(find.text('도우미 안내를 계속해도 될까요?'), findsOneWidget);
    // 팝업에서 취소하면 아무것도 바뀌지 않음
    await tester.tap(find.byKey(const Key('confirm_dialog_cancel')));
    await tester.pumpAndSettle();
    expect(env.backend.elderInbox, isEmpty);

    await tester.tap(find.byKey(const Key('approve_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm_dialog_ok')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('approve_button')), findsNothing, reason: '응답 후 버튼 숨김 (중복 응답 방지)');
    expect(find.text('승인 완료'), findsWidgets);
    expect(env.backend.elderInbox.first.status, ApprovalStatus.approved);
    expect(env.backend.elderInbox.first.respondedBy, MockBackend.meId);
  });

  testWidgets('승인 상세: "잠깐 멈춰요" → 확인 창 → rejected로 고령자 앱에 전달, 결과 안내 표시', (tester) async {
    final env = await pumpApp(tester);
    await openTab(tester, '승인');
    await tester.tap(find.text('어머니 · 정부24'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reject_button')));
    await tester.pumpAndSettle();
    expect(find.text('도우미 안내를 잠깐 멈출까요?'), findsOneWidget);
    expect(find.textContaining('가족이 잠깐 멈추자고 했어요'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm_dialog_ok')));
    await tester.pumpAndSettle();
    expect(env.backend.elderInbox.first.status, ApprovalStatus.rejected, reason: '내부 값은 그대로 rejected');
    expect(find.textContaining('"잠깐 멈춰요"로 응답해'), findsOneWidget);
    expect(find.byKey(const Key('reject_button')), findsNothing);
  });

  testWidgets('승인 상세: 다른 보호자가 먼저 응답하면 즉시 반영되고 버튼이 사라진다', (tester) async {
    final env = await pumpApp(tester);
    final a = env.backend.approvalsFor(MockBackend.meId).firstWhere((x) => x.status == ApprovalStatus.pending);
    env.deps.navigatorKey.currentState!.pushNamed(AppRoutes.approvalDetail, arguments: a.id);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('approve_button')), findsOneWidget);

    env.backend.respond(MockBackend.siblingId, a.id, approve: false);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('approve_button')), findsNothing);
    expect(find.text('다른 보호자'), findsOneWidget);
    expect(find.textContaining('"잠깐 멈춰요"로 응답해'), findsOneWidget);
  });

  testWidgets('승인 상세: 확인 팝업이 떠 있는 동안 만료되면 승인이 거부된다', (tester) async {
    final env = await pumpApp(tester);
    final a = env.backend.approvalsFor(MockBackend.meId).firstWhere((x) => x.status == ApprovalStatus.pending);
    env.deps.navigatorKey.currentState!.pushNamed(AppRoutes.approvalDetail, arguments: a.id);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('approve_button')));
    await tester.pumpAndSettle();
    env.clock.advance(const Duration(minutes: 10));
    await tester.tap(find.byKey(const Key('confirm_dialog_ok')));
    await tester.pumpAndSettle();
    expect(find.text('응답 가능 시간이 지나 요청이 만료되었습니다.'), findsOneWidget); // 스낵바
    expect(env.backend.approvalFor(MockBackend.meId, a.id).status, ApprovalStatus.expired);
  });

  testWidgets('로컬 알림 탭 → 승인 상세 화면으로 이동, 없는 문서는 안내 화면', (tester) async {
    final env = await pumpApp(tester);
    final a = env.backend.requestApproval(elderId: MockBackend.dadId, app: SensitiveApp.bank)!;
    await tester.pumpAndSettle();
    AppRoutes.openTarget(env.deps.navigatorKey.currentState, AlertTarget(AlertTarget.approval, a.id));
    await tester.pumpAndSettle();
    expect(find.text('승인 요청 상세'), findsOneWidget);
    expect(find.text('은행 앱 이용 안내'), findsOneWidget);

    AppRoutes.openTarget(env.deps.navigatorKey.currentState, const AlertTarget(AlertTarget.notification, 'deleted'));
    await tester.pumpAndSettle();
    expect(find.text('알림을 열 수 없습니다'), findsOneWidget);
  });

  testWidgets('가족 연결: 잘못된 코드, 만료 코드, 사용된 코드 오류 후 정상 연결', (tester) async {
    final env = await pumpApp(tester);
    await openTab(tester, '가족');
    expect(find.text('연결된 가족 2명'), findsOneWidget);

    Future<void> submit(String code) async {
      await tester.enterText(find.byKey(const Key('connect_code_field')), code);
      await tester.pump();
      await tester.tap(find.byKey(const Key('connect_submit')));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('가족 연결'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '할머니'));
    await tester.ensureVisible(find.byKey(const Key('guardian_label_손녀')));
    await tester.tap(find.byKey(const Key('guardian_label_손녀')));

    await submit('000000');
    expect(find.textContaining('연결 코드가 올바르지 않습니다'), findsOneWidget);

    await submit(env.backend.issueExpiredConnectCode(MockBackend.grandmaId));
    expect(find.textContaining('유효시간(10분)이 지났습니다'), findsOneWidget);

    final used = env.backend.issueConnectCode(MockBackend.grandmaId);
    env.backend.connectWithCode(MockBackend.siblingId, used, elderLabel: '할머니');
    await submit(used);
    expect(find.textContaining('이미 사용된 연결 코드'), findsOneWidget);

    await submit(env.backend.issueConnectCode(MockBackend.grandmaId));
    expect(find.text('연결된 가족 3명'), findsOneWidget);
    expect(find.textContaining('박말순'), findsWidgets); // 목록 "박말순 · 연결 시각" + 연결 완료 안내
  });

  testWidgets('가족 연결 해제: 메뉴(⋯) → 연결 해제 → 확인 후 목록과 알림에서 사라진다', (tester) async {
    await pumpApp(tester);
    await openTab(tester, '가족');
    // 되돌리기 어려운 동작이라 바로 보이는 버튼이 아니라 메뉴 안에 있다
    expect(find.text('연결 해제'), findsNothing);
    await tester.tap(find.byTooltip('아버지 메뉴'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('연결 해제'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm_dialog_ok')));
    await tester.pumpAndSettle();
    expect(find.text('연결된 가족 1명'), findsOneWidget);
    await openTab(tester, '홈');
    expect(find.text('아버지가 카카오뱅크를 사용하려고 합니다.'), findsNothing);
  });

  testWidgets('설정 → 개발자 테스트: 예/아니요 시나리오', (tester) async {
    final env = await pumpApp(tester);
    await tester.tap(find.byTooltip('설정'));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('developer_entry')));
    expect(find.text('개발자 테스트'), findsOneWidget);

    final before = env.backend.allNotifications.length;
    await tapVisible(tester, find.text('아니요 선택')); // 글자 확대 등으로 화면 밖에 있을 수 있음
    expect(env.backend.allNotifications.length, before);
    expect(env.backend.notificationsFor(MockBackend.meId).length, before);

    await tapVisible(tester, find.text('예 선택')); // 글자 확대 등으로 화면 밖에 있을 수 있음
    expect(env.backend.allNotifications.length, before + 1);

    await tapVisible(tester, find.text('같은 앱 다시 전송(중복)')); // 글자 확대 등으로 화면 밖에 있을 수 있음
    expect(env.backend.allNotifications.length, before + 1);
    // 실행 기록에 결과 문구가 남는다
    await tester.scrollUntilVisible(find.textContaining('중복 알림'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('중복 알림'), findsOneWidget);
    await tester.scrollUntilVisible(find.textContaining('동의하지 않아'), 100, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('동의하지 않아'), findsOneWidget);
  });

  testWidgets('개발자 테스트: 10분 안에 등본 시나리오를 다시 시작하면 선택 창 → 초기화 후 시작하면 알림 2개 + 승인 요청 1개', (tester) async {
    final env = await pumpApp(tester);
    final seeded = env.backend.allNotifications.length;
    await tester.tap(find.byTooltip('설정'));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('developer_entry')));

    // 정부24 접속 알림을 먼저 만들어 두면 중복 방지 대상이 된다
    await tapVisible(tester, find.text('예 선택')); // 글자 확대 등으로 화면 밖에 있을 수 있음
    // 시나리오 시작 버튼은 맨 위(⓪)에 있으므로 다시 위로
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
    await tester.pumpAndSettle();
    expect(env.backend.allNotifications.length, seeded + 1);

    await tapVisible(tester, find.byKey(const Key('scenario_start')));
    expect(find.text('정부24 알림이 이미 있어요'), findsOneWidget);

    // 취소하면 아무것도 시작하지 않는다
    await tester.tap(find.byKey(const Key('scenario_cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scenario_stop')), findsNothing);
    expect(env.backend.allNotifications.length, seeded + 1);

    await tapVisible(tester, find.byKey(const Key('scenario_start')));
    await tester.tap(find.byKey(const Key('scenario_reset_start')));
    await tester.pump();
    final seededApprovalIds = env.backend.allApprovals.map((a) => a.id).toSet();
    // 3단계에서 승인 요청이 생기고 보호자 응답을 기다린다
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    final created = env.backend.allApprovals.where((a) => !seededApprovalIds.contains(a.id)).toList();
    expect(created, hasLength(1));
    final requested = created.single;
    expect(requested.action, ApprovalActions.gov24Auth);
    expect(requested.status, ApprovalStatus.pending);
    env.backend.respond(MockBackend.meId, requested.id, approve: true);
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pumpAndSettle();
    expect(env.backend.allNotifications.length, seeded + 2);
    expect(find.byKey(const Key('scenario_stop')), findsNothing, reason: '시나리오 종료');
  });

  testWidgets('서버가 읽기를 거부하면 무한 로딩 대신 안내를 보여 준다', (tester) async {
    final backend = MockBackend();
    final deps = AppDependencies(repository: _DeniedRepository(backend), notifier: FakeNotifier());
    addTearDown(deps.dispose);
    await tester.pumpWidget(HaebomFamilyApp(deps: deps));
    await tester.pumpAndSettle();
    expect(find.text('가족 정보를 불러오지 못했습니다'), findsOneWidget);
    expect(find.textContaining('접근을 허용하지 않았습니다'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  group('모바일 화면 크기별 레이아웃 (오버플로 없음)', () {
    const sizes = {
      '소형 320x568': Size(320, 568),
      '일반 360x780': Size(360, 780),
      '대형 430x932': Size(430, 932),
      '태블릿 820x1180': Size(820, 1180),
      '가로 780x360': Size(780, 360),
    };
    for (final entry in sizes.entries) {
      for (final scale in [1.0, 1.5, 2.0]) {
        testWidgets('${entry.key} 글자 크기 x$scale', (tester) async {
          tester.view.physicalSize = entry.value * 3;
          tester.view.devicePixelRatio = 3;
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.view.reset);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

          final env = await pumpApp(tester);
          for (final tab in ['알림', '승인', '가족', '홈']) {
            await openTab(tester, tab);
            expect(tester.takeException(), isNull, reason: '$tab 탭');
          }
          final nav = env.deps.navigatorKey.currentState!;
          final a = env.backend.approvalsFor(MockBackend.meId).first;
          final n = env.backend.notificationsFor(MockBackend.meId).first;
          for (final (route, arg) in [
            (AppRoutes.approvalDetail, a.id),
            (AppRoutes.notificationDetail, n.id),
            (AppRoutes.settings, null),
            (AppRoutes.connectFamily, null),
            (AppRoutes.developer, null),
          ]) {
            nav.pushNamed(route, arguments: arg);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: route);
            nav.pop();
            await tester.pumpAndSettle();
          }
        });
      }
    }
  });
}

/// 보안 규칙이 아직 준비되지 않은 서버처럼 links 구독이 거부되는 저장소
class _DeniedRepository extends MockGuardianRepository {
  _DeniedRepository(super.backend);
  @override
  Stream<List<FamilyLink>> watchLinks() =>
      Stream.error(const RepositoryException(RepositoryErrorCode.permissionDenied));
}
