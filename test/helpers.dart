import 'package:guardian_app/app/app.dart';
import 'package:guardian_app/app/dependencies.dart';
import 'package:guardian_app/repositories/mock_backend.dart';
import 'package:guardian_app/services/notification_service.dart';
import 'package:material_ui/material_ui.dart';

/// 테스트용 고정 시계 (2026-11-24 14:00 기준)
class FakeClock {
  FakeClock([DateTime? start]) : value = start ?? DateTime(2026, 11, 24, 14);
  DateTime value;
  DateTime now() => value;
  void advance(Duration d) => value = value.add(d);
}

/// 로컬 알림 호출을 기록하는 가짜 구현
class FakeNotifier implements LocalNotifier {
  final List<LocalAlert> shown = [];
  bool granted = true;
  void Function(AlertTarget)? onTap;

  @override
  Future<void> initialize(void Function(AlertTarget target) onTap) async => this.onTap = onTap;
  @override
  Future<bool> requestPermission() async => granted;
  @override
  Future<bool> isPermissionGranted() async => granted;
  int settingsOpened = 0;
  @override
  Future<void> openSettings() async => settingsOpened++;
  @override
  Future<void> show(LocalAlert alert) async => shown.add(alert);
  @override
  Future<AlertTarget?> launchTarget() async => null;
}

class TestEnv {
  TestEnv({bool seed = true}) {
    clock = FakeClock();
    backend = MockBackend(clock: clock.now, seed: seed);
    notifier = FakeNotifier();
    deps = AppDependencies.mock(backend: backend, notifier: notifier);
  }

  late final FakeClock clock;
  late final MockBackend backend;
  late final FakeNotifier notifier;
  late final AppDependencies deps;

  Widget get app => HaebomFamilyApp(deps: deps);
}
