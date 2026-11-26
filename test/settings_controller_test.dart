import 'package:flutter_test/flutter_test.dart';
import 'package:guardian_app/controllers/settings_controller.dart';

class _FailingStorage implements SettingsStorage {
  @override
  Future<Map<String, bool>> load() async => throw Exception('disk error');
  @override
  Future<void> save(String key, bool value) async => throw Exception('disk error');
}

void main() {
  test('기본값: 간략하게 보기는 꺼짐(자세히 표시), 알림은 모두 켜짐', () async {
    final s = SettingsController(storage: MemorySettingsStorage());
    await s.load();
    expect(s.briefNotifications, isFalse);
    expect(s.showDetailsInNotification, isTrue);
    expect(s.activityAlerts && s.approvalAlerts && s.sosAlerts, isTrue);
  });

  test('바꾼 값은 저장소에 기록되고, 새 컨트롤러가 다시 불러온다 (앱 재시작)', () async {
    final storage = MemorySettingsStorage();
    final first = SettingsController(storage: storage)
      ..briefNotifications = true
      ..activityAlerts = false;
    await Future<void>.delayed(Duration.zero);
    expect(storage.values, {
      SettingsController.kBrief: true,
      SettingsController.kActivity: false,
    });
    first.dispose();

    final restarted = SettingsController(storage: storage);
    await restarted.load();
    expect(restarted.briefNotifications, isTrue);
    expect(restarted.activityAlerts, isFalse);
    expect(restarted.approvalAlerts, isTrue);
  });

  test('저장소 오류가 나도 기본값으로 동작하고 설정 변경은 반영된다', () async {
    final s = SettingsController(storage: _FailingStorage());
    await s.load();
    expect(s.briefNotifications, isFalse);
    s.briefNotifications = true;
    await Future<void>.delayed(Duration.zero);
    expect(s.briefNotifications, isTrue);
  });
}
