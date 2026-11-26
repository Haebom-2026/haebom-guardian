import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 설정 값을 기기에 저장하는 저장소. 테스트에서는 [MemorySettingsStorage]를 쓴다.
abstract class SettingsStorage {
  Future<Map<String, bool>> load();
  Future<void> save(String key, bool value);
}

/// 메모리에만 저장 (테스트·기본값).
class MemorySettingsStorage implements SettingsStorage {
  MemorySettingsStorage([Map<String, bool>? initial]) : values = {...?initial};
  final Map<String, bool> values;

  @override
  Future<Map<String, bool>> load() async => Map.of(values);

  @override
  Future<void> save(String key, bool value) async => values[key] = value;
}

/// 기기 저장소(Android SharedPreferences / iOS NSUserDefaults).
/// 앱 데이터 삭제·재설치 시 초기화된다.
class DeviceSettingsStorage implements SettingsStorage {
  static const _prefix = 'settings.';
  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  @override
  Future<Map<String, bool>> load() async {
    final result = <String, bool>{};
    for (final key in SettingsController.keys) {
      final v = await _prefs.getBool('$_prefix$key');
      if (v != null) result[key] = v;
    }
    return result;
  }

  @override
  Future<void> save(String key, bool value) => _prefs.setBool('$_prefix$key', value);
}

/// 보호자 앱 알림 설정.
///
/// [load]로 기기에 저장된 값을 불러오고, 값이 바뀔 때마다 [SettingsStorage]에 저장한다.
/// 실제 연동 후 여러 기기 간 동기화가 필요하면 users/{uid} 설정 문서로 옮긴다.
class SettingsController extends ChangeNotifier {
  SettingsController({SettingsStorage? storage}) : _storage = storage ?? MemorySettingsStorage();

  final SettingsStorage _storage;

  static const kActivity = 'activityAlerts';
  static const kApproval = 'approvalAlerts';
  static const kSos = 'sosAlerts';
  static const kBrief = 'briefNotifications';
  static const keys = [kActivity, kApproval, kSos, kBrief];

  bool _activityAlerts = true;
  bool _approvalAlerts = true;
  bool _sosAlerts = true;
  bool _briefNotifications = false;

  /// 민감 앱 이용/도움 필요 알림
  bool get activityAlerts => _activityAlerts;
  bool get approvalAlerts => _approvalAlerts;
  bool get sosAlerts => _sosAlerts;

  /// 간략하게 보기. 기본값은 꺼짐 → 기기 알림에 "어머니가 정부24를 사용하려고 합니다"처럼 자세히 표시
  /// (잠금 화면에서는 알림을 '비공개'로 띄워 휴대폰 설정에 따라 내용을 숨긴다).
  /// 켜면 잠금이 풀려 있어도 "새 가족 알림이 도착했습니다" 같은 최소 문구만 표시.
  bool get briefNotifications => _briefNotifications;

  /// 기기 알림에 자세한 문구를 쓸지 ([briefNotifications]의 반대)
  bool get showDetailsInNotification => !_briefNotifications;

  set activityAlerts(bool v) => _set(kActivity, v, () => _activityAlerts = v);
  set approvalAlerts(bool v) => _set(kApproval, v, () => _approvalAlerts = v);
  set sosAlerts(bool v) => _set(kSos, v, () => _sosAlerts = v);
  set briefNotifications(bool v) => _set(kBrief, v, () => _briefNotifications = v);

  /// 저장된 값을 불러온다. 읽기에 실패하면 기본값을 유지한다.
  Future<void> load() async {
    final Map<String, bool> saved;
    try {
      saved = await _storage.load();
    } catch (e) {
      debugPrint('설정 불러오기 실패, 기본값 사용: $e');
      return;
    }
    _activityAlerts = saved[kActivity] ?? _activityAlerts;
    _approvalAlerts = saved[kApproval] ?? _approvalAlerts;
    _sosAlerts = saved[kSos] ?? _sosAlerts;
    _briefNotifications = saved[kBrief] ?? _briefNotifications;
    notifyListeners();
  }

  void _set(String key, bool value, VoidCallback apply) {
    apply();
    notifyListeners();
    _storage.save(key, value).catchError((Object e) => debugPrint('설정 저장 실패($key): $e'));
  }
}
