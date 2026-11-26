import 'package:flutter/widgets.dart';

import '../controllers/guardian_store.dart';
import '../controllers/settings_controller.dart';
import '../repositories/guardian_repository.dart';
import '../repositories/mock_backend.dart';
import '../repositories/mock_repository.dart';
import '../services/notification_service.dart';
import '../services/push_service.dart';

/// 앱 전역 의존성 묶음. 저장소 구현(Mock ↔ Firebase) 교체 지점은 여기 하나뿐이다.
class AppDependencies {
  AppDependencies({
    required this.repository,
    required this.notifier,
    this.mockBackend,
    SettingsStorage? settingsStorage,
  })  : store = GuardianStore(repository),
        settings = SettingsController(storage: settingsStorage) {
    notifications = NotificationService(notifier: notifier, store: store, settings: settings);
  }

  /// Mock 서버를 사용하는 기본 구성.
  factory AppDependencies.mock({
    MockBackend? backend,
    LocalNotifier? notifier,
    SettingsStorage? settingsStorage,
    String guardianId = MockBackend.meId,
  }) {
    final b = backend ?? MockBackend();
    return AppDependencies(
      repository: MockGuardianRepository(b, guardianId: guardianId),
      notifier: notifier ?? NoopLocalNotifier(),
      mockBackend: b,
      settingsStorage: settingsStorage,
    );
  }

  final GuardianRepository repository;
  final LocalNotifier notifier;
  final GuardianStore store;
  final SettingsController settings;
  late final NotificationService notifications;

  /// Mock 모드에서만 존재. 개발자 테스트 화면이 "고령자 앱 + 서버"를 흉내 낼 때 사용.
  final MockBackend? mockBackend;

  /// 서버 모드에서만 존재. FCM 원격 푸시 수신 상태.
  PushService? push;

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  /// 하단 탭 인덱스 (0 홈, 1 알림, 2 승인, 3 가족)
  final ValueNotifier<int> tabIndex = ValueNotifier<int>(0);

  void dispose() {
    push?.dispose();
    notifications.dispose();
    store.dispose();
    settings.dispose();
    tabIndex.dispose();
  }
}

/// 위젯 트리에서 [AppDependencies]를 꺼내 쓰기 위한 InheritedWidget.
class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.deps, required super.child});

  final AppDependencies deps;

  static AppDependencies of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope가 위젯 트리에 없습니다.');
    return scope!.deps;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => deps != oldWidget.deps;
}
