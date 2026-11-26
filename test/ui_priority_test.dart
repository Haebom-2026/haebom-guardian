// 11-26 UI 개편 (사용자 확정안): 홈 = 가족 → 도움이 필요한 일(SOS → 도움 필요 → 승인 대기) → 확인하지 않은 알림 → 최근 소식(오늘·어제, 최대 3)
// 같은 항목이 두 곳에 나오지 않고, 홈에서는 바로 승인·거절하지 않는다.
import 'package:flutter_test/flutter_test.dart';
import 'package:guardian_app/models/approval_request.dart';
import 'package:guardian_app/models/sensitive_app.dart';
import 'package:guardian_app/repositories/mock_backend.dart';
import 'package:guardian_app/widgets/common.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers.dart';

Future<TestEnv> pumpPhone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(412, 915) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final env = TestEnv();
  await tester.pumpWidget(env.app);
  await tester.pumpAndSettle();
  addTearDown(env.deps.dispose);
  return env;
}

Future<void> openTab(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
  await tester.pumpAndSettle();
}

ApprovalRequest pendingOf(TestEnv env) =>
    env.backend.allApprovals.firstWhere((a) => a.effectiveStatus(env.backend.now()) == ApprovalStatus.pending);

double topOf(WidgetTester tester, Finder f) => tester.getTopLeft(f).dy;

/// 화면 아래로 밀려난 ListView 항목까지 스크롤 (홈 첫 문구·숫자 카드 아래에 있는 섹션 확인용)
Future<void> reveal(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 150, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('홈: 승인 대기는 "요청 확인하기"로 상세에 가서 결정한다 (홈에서 바로 승인·거절 버튼 없음)', (tester) async {
    final env = await pumpPhone(tester);
    final a = pendingOf(env);
    expect(find.text('계속해도 돼요'), findsNothing);
    expect(find.text('잠깐 멈춰요'), findsNothing);
    await tester.tap(find.byKey(ValueKey('help_open_${a.id}')));
    await tester.pumpAndSettle();
    expect(find.text('승인 요청 상세'), findsOneWidget);
    expect(find.byKey(const Key('approve_button')), findsOneWidget);
    expect(env.backend.elderInbox, isEmpty, reason: '상세로 이동만 하고 응답은 보내지 않음');
  });

  testWidgets('홈: 도움이 필요한 일은 SOS → 도움 필요 → 승인 대기 순서, 확인한 SOS는 사라진다', (tester) async {
    final env = await pumpPhone(tester);
    final a = pendingOf(env);
    final stuck = env.backend.createStuck(MockBackend.dadId, SensitiveApp.gov24)!;
    final sos = env.backend.createSos(MockBackend.momId, app: SensitiveApp.toss)!;
    await tester.pumpAndSettle();
    final ySos = topOf(tester, find.byKey(ValueKey('help_${sos.id}')));
    final yStuck = topOf(tester, find.byKey(ValueKey('help_${stuck.id}')));
    final yApproval = topOf(tester, find.byKey(ValueKey('help_${a.id}')));
    expect(ySos < yStuck && yStuck < yApproval, isTrue);
    expect((tester.widget<Text>(find.byKey(const ValueKey('help_count')))).data, '3');

    // SOS·도움 필요는 "확인하지 않은 알림"에 다시 세지 않는다 (중복 없음)
    await reveal(tester, find.byKey(const ValueKey('unread_count')));
    expect((tester.widget<Text>(find.byKey(const ValueKey('unread_count')))).data, '2');

    await tester.ensureVisible(find.byKey(ValueKey('help_open_${sos.id}'), skipOffstage: false));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('help_open_${sos.id}')));
    await tester.pumpAndSettle();
    expect(find.text('알림 상세'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('notification_confirm')));
    await tester.tap(find.byKey(const Key('notification_confirm')));
    await tester.pumpAndSettle();
    env.deps.navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('help_${sos.id}')), findsNothing);
    expect(find.byKey(ValueKey('help_${stuck.id}')), findsOneWidget);
  });

  testWidgets('홈: 최근 소식은 최대 3건, 확인 전 알림·승인 대기는 넣지 않는다', (tester) async {
    final env = await pumpPhone(tester);
    final a = pendingOf(env);
    await reveal(tester, find.text('최근 소식'));
    final recentTop = topOf(tester, find.text('최근 소식'));
    // 최근 소식 영역(제목 아래)에 있는 줄 수
    int rowsBelow(Type type) =>
        find.byType(type).evaluate().where((e) => tester.getTopLeft(find.byWidget(e.widget)).dy > recentTop).length;
    expect(rowsBelow(NotificationTile) + rowsBelow(ApprovalCard), lessThanOrEqualTo(3));
    expect(find.byType(ApprovalCard).evaluate().where((e) => (e.widget as ApprovalCard).request.id == a.id), isEmpty);
    for (final e in find.byType(NotificationTile).evaluate()) {
      final n = (e.widget as NotificationTile).item;
      if (tester.getTopLeft(find.byWidget(e.widget)).dy > recentTop) {
        expect(env.deps.store.isUnread(n), isFalse, reason: '확인 전 알림은 위 섹션에만');
      }
    }
  });

  testWidgets('홈: 숫자는 첫 문구 한 곳에만 (숫자 카드 없음), 오늘 알림 수는 그 아래 한 줄', (tester) async {
    final env = await pumpPhone(tester);
    final today = env.deps.store.notifications.where((n) => n.createdAt.day == env.clock.now().day).length;
    expect(find.text(today == 0 ? '오늘 온 알림은 없어요' : '오늘 알림 $today건'), findsOneWidget);
    expect(find.text('확인 전'), findsNothing, reason: '섹션과 숫자가 달라 보이던 숫자 카드는 없앴다');
  });

  testWidgets('홈: 최근 소식은 오늘·어제 것만 (그보다 오래된 소식은 알림·승인 기록에서 본다)', (tester) async {
    tester.view.physicalSize = const Size(412, 915) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final env = TestEnv();
    env.clock.advance(const Duration(days: 3)); // 기본 데이터가 모두 사흘 전 일이 된다
    await tester.pumpWidget(env.app);
    await tester.pumpAndSettle();
    addTearDown(env.deps.dispose);
    await reveal(tester, find.text('오늘과 어제 처리한 소식이 없어요.'));
    expect(find.textContaining('최근 소식 '), findsNothing, reason: '더 보기 링크도 없음');
    expect(find.byKey(const Key('home_all_notifications')), findsOneWidget);
  });

  testWidgets('승인 탭: 응답이 필요한 요청이 먼저, 지난 요청은 분리되어 상태를 글자로 보여 준다', (tester) async {
    final env = await pumpPhone(tester);
    await openTab(tester, '승인');
    final a = pendingOf(env);
    expect(find.text('응답이 필요한 요청'), findsOneWidget);
    expect(find.byKey(ValueKey('pending_${a.id}')), findsOneWidget);
    expect(topOf(tester, find.text('응답이 필요한 요청')) < topOf(tester, find.text('지난 요청')), isTrue);
    await tester.scrollUntilVisible(find.text('요청 취소됨'), 200, scrollable: find.byType(Scrollable).first);
    for (final label in ['승인 완료', '거절', '응답 시간 지남', '요청 취소됨']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
  });

  testWidgets('필터: 연결된 어르신이 1명이면 가족 칩이 사라지고 상단에 그분 이름이 보인다', (tester) async {
    final env = await pumpPhone(tester);
    expect(find.widgetWithText(ChoiceChip, '전체 가족'), findsOneWidget);
    env.backend.disconnectByElder(MockBackend.dadId, MockBackend.meId);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ChoiceChip, '전체 가족'), findsNothing);
    expect(find.text('어머니 (김순자)'), findsOneWidget);
    await openTab(tester, '알림');
    expect(find.widgetWithText(ChoiceChip, '전체'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '어머니'), findsNothing);
  });

  for (final dark in [false, true]) {
    testWidgets('접근성: 터치 영역 48×48 · 버튼 라벨 · 글자 명암비 (${dark ? '다크' : '라이트'})', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = dark ? Brightness.dark : Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final handle = tester.ensureSemantics();
      final env = await pumpPhone(tester);
      env.backend.createSos(MockBackend.momId, app: SensitiveApp.toss);
      env.backend.createStuck(MockBackend.dadId, SensitiveApp.gov24);
      await tester.pumpAndSettle();
      Future<void> check(String where) async {
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline), reason: where);
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline), reason: where);
        await expectLater(tester, meetsGuideline(textContrastGuideline), reason: where);
      }

      for (final tab in ['홈', '알림', '승인', '가족']) {
        await openTab(tester, tab);
        await check('$tab 탭');
      }
      final nav = env.deps.navigatorKey.currentState!;
      nav.pushNamed('/approval', arguments: pendingOf(env).id);
      await tester.pumpAndSettle();
      await check('승인 상세');
      nav.pop();
      await tester.pumpAndSettle();
      nav.pushNamed('/settings');
      await tester.pumpAndSettle();
      await check('설정');
      handle.dispose();
    });
  }

  test('아바타 글자: 이름(뒤 두 글자) → 실명 → 호칭 첫 글자', () {
    expect(avatarText('김순자'), '순자');
    expect(avatarText('이정호', fallback: '아버지'), '정호');
    expect(avatarText('민수'), '민수');
    expect(avatarText('', fallback: '할머니'), '할');
    expect(avatarText(''), '?');
  });
}
