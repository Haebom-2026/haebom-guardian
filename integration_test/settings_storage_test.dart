import 'package:flutter_test/flutter_test.dart';
import 'package:guardian_app/controllers/settings_controller.dart';
import 'package:integration_test/integration_test.dart';

/// 실제 기기 저장소(SharedPreferences / NSUserDefaults)에 설정이 저장·복원되는지 확인한다.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('설정이 기기 저장소에 저장되고 새 컨트롤러가 다시 불러온다', (tester) async {
    final storage = DeviceSettingsStorage();
    final original = await storage.load();

    final a = SettingsController(storage: storage)..showDetailsInNotification = true;
    a.sosAlerts = false;
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final b = SettingsController(storage: DeviceSettingsStorage());
    await b.load();
    expect(b.showDetailsInNotification, isTrue);
    expect(b.sosAlerts, isFalse);

    // 원래 값으로 되돌린다 (없던 키는 기본값으로)
    await storage.save(SettingsController.kShowDetails, original[SettingsController.kShowDetails] ?? false);
    await storage.save(SettingsController.kSos, original[SettingsController.kSos] ?? true);
  });
}
