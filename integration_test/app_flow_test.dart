// 실제 기기/시뮬레이터에서 실행하는 통합 테스트.
//
//   flutter test integration_test -d <device-id>
//
// - 실제 플랫폼 플러그인(PluginLocalNotifier)으로 알림 초기화·표시 경로를 실행한다.
// - OS 알림 센터에서 알림을 "손가락으로 누르는" 동작은 자동화할 수 없으므로,
//   플러그인의 탭 콜백이 호출하는 것과 동일한 AppRoutes.openTarget 경로로 상세 이동을 검증한다.
// - 권한 팝업이 테스트를 멈추지 않도록 권한 요청은 호출하지 않는다.
import 'package:flutter_test/flutter_test.dart';
import 'package:guardian_app/app/app.dart';
import 'package:guardian_app/app/dependencies.dart';
import 'package:guardian_app/app/routes.dart';
import 'package:guardian_app/models/sensitive_app.dart';
import 'package:guardian_app/repositories/mock_backend.dart';
import 'package:guardian_app/services/notification_service.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('실기기: 4개 탭 · 민감 앱 알림 · 승인 처리 흐름', (tester) async {
    final backend = MockBackend();
    final deps = AppDependencies.mock(backend: backend, notifier: PluginLocalNotifier());
    await deps.notifier.initialize(
      (t) => AppRoutes.openTarget(deps.navigatorKey.currentState, t),
    );
    deps.notifications.start();

    await tester.pumpWidget(HaebomFamilyApp(deps: deps));
    await tester.pumpAndSettle();
    expect(find.text('해봄 가족'), findsWidgets);

    Future<void> tab(String label) async {
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
      await tester.pumpAndSettle();
    }

    await tab('알림');
    expect(find.text('어머니가 정부24를 사용하려고 합니다.'), findsWidgets);
    await tab('승인');
    expect(find.text('도우미 진행 승인'), findsOneWidget);
    await tab('가족');
    expect(find.text('연결된 가족 2명'), findsOneWidget);
    await tab('홈');

    // 고령자가 "아니요" → 알림 미생성, "예" → 알림 생성
    final before = backend.notificationsFor(MockBackend.meId).length;
    backend.reportSensitiveEntry(
        elderId: MockBackend.dadId, app: SensitiveApp.toss, choice: ConsentChoice.no);
    await tester.pumpAndSettle();
    expect(backend.notificationsFor(MockBackend.meId).length, before);

    final (_, n) = backend.reportSensitiveEntry(
        elderId: MockBackend.dadId, app: SensitiveApp.toss, choice: ConsentChoice.yes);
    await tester.pumpAndSettle();
    expect(n, isNotNull);
    expect(backend.notificationsFor(MockBackend.meId).length, before + 1);

    // 알림 탭과 같은 경로로 상세 이동
    AppRoutes.openTarget(deps.navigatorKey.currentState, AlertTarget(AlertTarget.notification, n!.id));
    await tester.pumpAndSettle();
    expect(find.text('알림 상세'), findsOneWidget);
    expect(find.text('아버지가 토스를 사용하려고 합니다.'), findsOneWidget);
    deps.navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();

    // 승인 요청 → 상세 → 승인 → 확인 팝업 → 승인 완료
    final a = backend.requestApproval(elderId: MockBackend.dadId, app: SensitiveApp.kakaoBank)!;
    await tester.pumpAndSettle();
    AppRoutes.openTarget(deps.navigatorKey.currentState, AlertTarget(AlertTarget.approval, a.id));
    await tester.pumpAndSettle();
    expect(find.text('승인 요청 상세'), findsOneWidget);
    await tester.tap(find.byKey(const Key('approve_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm_dialog_ok')));
    await tester.pumpAndSettle();
    expect(find.text('승인 완료'), findsWidgets);
    expect(find.byKey(const Key('approve_button')), findsNothing);

    backend.dispose();
  });
}
