// 알림 권한 안내: 권한 창 전에 이유를 설명하고(첫 실행 한 번), 꺼져 있으면 홈 맨 위에서 계속 알려 준다.
import 'package:flutter_test/flutter_test.dart';
import 'package:guardian_app/screens/onboarding/notification_permission.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers.dart';

Future<TestEnv> pumpApp(WidgetTester tester, {required bool granted}) async {
  tester.view.physicalSize = const Size(412, 915) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final env = TestEnv();
  env.notifier.granted = granted;
  await tester.pumpWidget(env.app);
  await tester.pumpAndSettle();
  addTearDown(env.deps.dispose);
  return env;
}

void main() {
  testWidgets('첫 실행: 알림이 꺼져 있으면 이유를 먼저 설명하고, "알림 받기"를 눌러야 권한 창을 띄운다', (tester) async {
    final env = await pumpApp(tester, granted: false);
    final done = showNotificationIntroIfNeeded(env.deps);
    await tester.pumpAndSettle();
    expect(find.text('가족이 도움을 청하면\n바로 알려 드릴게요'), findsOneWidget);
    expect(find.text('SOS · 사기 의심'), findsOneWidget);
    expect(find.textContaining('비밀번호·화면 내용·위치는 받지 않아요'), findsOneWidget);

    env.notifier.granted = true; // 시스템 권한 창에서 "허용"
    await tester.tap(find.byKey(const Key('notification_intro_allow')));
    await tester.pumpAndSettle();
    await done;
    expect(find.byKey(const Key('notification_intro_allow')), findsNothing);
    expect(env.deps.notifications.permission.value, isTrue);
    expect(env.deps.settings.notificationIntroDone, isTrue);
    expect(find.byKey(const Key('notification_off_banner')), findsNothing);
  });

  testWidgets('안내는 한 번만: "나중에 할게요" 뒤에는 다시 띄우지 않고 홈 맨 위에 "알림이 꺼져 있어요"를 보여 준다', (tester) async {
    final env = await pumpApp(tester, granted: false);
    final done = showNotificationIntroIfNeeded(env.deps);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notification_intro_later')));
    await tester.pumpAndSettle();
    await done;
    expect(find.byKey(const Key('notification_off_banner')), findsOneWidget);
    expect(find.text('알림이 꺼져 있어요'), findsOneWidget);

    await showNotificationIntroIfNeeded(env.deps);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notification_intro_allow')), findsNothing, reason: '두 번째부터는 안내 화면 없음');
  });

  testWidgets('이미 알림이 허용돼 있으면 안내 화면도, 홈 경고도 없다', (tester) async {
    final env = await pumpApp(tester, granted: true);
    await showNotificationIntroIfNeeded(env.deps);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notification_intro_allow')), findsNothing);
    expect(find.byKey(const Key('notification_off_banner')), findsNothing);
  });

  testWidgets('홈 "켜기": 권한 창을 더 띄울 수 없으면 휴대폰 설정을 열고, 켜고 돌아오면 경고가 사라진다', (tester) async {
    final env = await pumpApp(tester, granted: false);
    expect(find.byKey(const Key('notification_off_banner')), findsOneWidget);

    await tester.tap(find.byKey(const Key('notification_off_turn_on')));
    await tester.pumpAndSettle();
    expect(env.notifier.settingsOpened, 1);

    env.notifier.granted = true; // 휴대폰 설정에서 켬
    await env.deps.notifications.refreshPermission(); // 앱 복귀 시 하는 확인
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notification_off_banner')), findsNothing);
  });
}
