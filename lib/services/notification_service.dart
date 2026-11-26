import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../controllers/guardian_store.dart';
import '../controllers/settings_controller.dart';
import '../models/approval_request.dart';
import '../models/notification_item.dart';
import '../models/sensitivity.dart';
import '../utils/formatters.dart';

/// 알림을 눌렀을 때 이동할 대상. payload 문자열 형식: `notification:{id}` 또는 `approval:{id}`
/// 향후 FCM data payload의 {kind, id} 와 동일한 의미를 가진다.
class AlertTarget {
  const AlertTarget(this.kind, this.id);
  final String kind;
  final String id;

  static const notification = 'notification';
  static const approval = 'approval';

  String encode() => '$kind:$id';

  static AlertTarget? decode(String? payload) {
    if (payload == null) return null;
    final i = payload.indexOf(':');
    if (i <= 0 || i == payload.length - 1) return null;
    final kind = payload.substring(0, i);
    if (kind != notification && kind != approval) return null;
    return AlertTarget(kind, payload.substring(i + 1));
  }
}

/// Android 알림 채널. help(도움 필요)는 SOS 다음으로 높은 우선순위 (개발지침서 8.3).
enum AlertChannel { activity, approval, sos, help }

class LocalAlert {
  const LocalAlert({
    required this.id,
    required this.channel,
    required this.title,
    required this.body,
    required this.target,
  });
  final int id;
  final AlertChannel channel;
  final String title;
  final String body;

  /// 눌렀을 때 이동할 상세 화면. null이면 앱만 연다.
  final AlertTarget? target;
}

/// 운영체제 로컬 알림 추상화. (테스트에서는 가짜 구현 사용)
///
/// 주의: 로컬 알림은 "이 기기에서 이 앱이 직접" 띄우는 알림이다.
/// 다른 스마트폰(고령자 폰)에서 보낸 원격 알림은 FCM/APNs 연동 후에만 가능하다.
abstract class LocalNotifier {
  Future<void> initialize(void Function(AlertTarget target) onTap);
  Future<bool> requestPermission();

  /// 권한 창을 띄우지 않고 지금 알림이 허용되어 있는지만 확인한다
  Future<bool> isPermissionGranted();

  /// 휴대폰 설정의 이 앱 알림 화면을 연다 (권한 창을 더 띄울 수 없을 때)
  Future<void> openSettings();
  Future<void> show(LocalAlert alert);

  /// 앱이 종료된 상태에서 알림을 눌러 실행된 경우의 대상
  Future<AlertTarget?> launchTarget();
}

class NoopLocalNotifier implements LocalNotifier {
  @override
  Future<void> initialize(void Function(AlertTarget target) onTap) async {}
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<bool> isPermissionGranted() async => false;
  @override
  Future<void> openSettings() async {}
  @override
  Future<void> show(LocalAlert alert) async {}
  @override
  Future<AlertTarget?> launchTarget() async => null;
}

/// flutter_local_notifications 기반 구현 (Android / iOS)
class PluginLocalNotifier implements LocalNotifier {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  static const _channels = {
    AlertChannel.activity: AndroidNotificationChannel(
      'family_activity',
      '가족 앱 이용 알림',
      description: '가족이 동의한 민감 서비스 이용 알림',
      // 화면 상단 팝업(헤드업)으로 표시. 기존 설치본은 채널 중요도가 고정되므로 재설치해야 반영된다.
      importance: Importance.high,
    ),
    AlertChannel.approval: AndroidNotificationChannel(
      'approval_requests',
      '도우미 진행 승인 요청',
      description: '응답 시간이 정해진 승인 요청 알림',
      importance: Importance.high,
    ),
    AlertChannel.sos: AndroidNotificationChannel(
      'sos_alerts',
      'SOS 알림',
      description: '가족의 긴급 도움 요청, 사기 의심 상황',
      importance: Importance.max,
    ),
    AlertChannel.help: AndroidNotificationChannel(
      'help_alerts',
      '도움 필요 알림',
      description: '가족이 앱 사용 중 막혀 도움이 필요할 수 있는 상황',
      importance: Importance.max,
    ),
  };

  @override
  Future<void> initialize(void Function(AlertTarget target) onTap) async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_stat_haebom') /* 흰 잎사귀 실루엣 (상태 표시줄용) */,
        // 권한은 앱 시작 후 requestPermission()에서 명시적으로 요청한다.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        final target = AlertTarget.decode(response.payload);
        if (target != null) onTap(target);
      },
    );
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    for (final c in _channels.values) {
      await android?.createNotificationChannel(c);
    }
  }

  @override
  Future<bool> requestPermission() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? false;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      return await ios?.requestPermissions(alert: true, badge: true, sound: true) ?? false;
    }
    return false;
  }

  @override
  Future<bool> isPermissionGranted() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return await android?.areNotificationsEnabled() ?? false;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      return (await ios?.checkPermissions())?.isEnabled ?? false;
    }
    return false;
  }

  static const _settingsChannel = MethodChannel('haebom/settings');

  @override
  Future<void> openSettings() async {
    try {
      await _settingsChannel.invokeMethod<void>('openNotificationSettings');
    } on PlatformException catch (e) {
      debugPrint('알림 설정 화면 열기 실패: $e');
    } on MissingPluginException {
      // 테스트·지원하지 않는 플랫폼
    }
  }

  @override
  Future<void> show(LocalAlert alert) async {
    final c = _channels[alert.channel]!;
    await _plugin.show(
      id: alert.id,
      title: alert.title,
      body: alert.body,
      payload: alert.target?.encode(),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          c.id,
          c.name,
          channelDescription: c.description,
          importance: c.importance,
          priority: Priority.high,
          // 잠금 화면에서는 내용 숨김
          visibility: NotificationVisibility.private,
          category: alert.channel == AlertChannel.sos ? AndroidNotificationCategory.alarm : null,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBanner: true,
          presentList: true,
          presentSound: true,
          threadIdentifier: 'haebom_family',
        ),
      ),
    );
  }

  @override
  Future<AlertTarget?> launchTarget() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return null;
    return AlertTarget.decode(details?.notificationResponse?.payload);
  }
}

/// 저장소에 새로 들어온 알림/승인 요청을 감지해 로컬 알림으로 표시한다.
///
/// Mock 단계에서는 앱 프로세스가 살아 있는 동안 이 경로만 사용한다.
///
/// 원격 푸시(FCM)와 함께 쓸 때의 **중복 표시 방지** 규칙:
/// - 같은 문서(알림·승인)는 경로와 상관없이 한 번만 띄운다 (`_seen*`, 로컬 알림 id도 문서 ID 기반으로 같음).
/// - [remotePushActive]가 켜지면(이 기기 FCM 토큰이 서버에 등록됨) 저장소 변경 기반 알림은
///   **앱이 화면 앞에 있을 때만** 띄운다. 백그라운드·종료 상태는 시스템이 FCM 알림을 표시한다.
/// - 앱이 다시 앞으로 왔을 때 밀려 들어온 오래된 문서([staleAfter]보다 오래됨)는 띄우지 않는다
///   (이미 FCM 알림으로 받았기 때문).
/// - iPhone(APNs 없음)처럼 원격 푸시가 없으면 지금처럼 저장소 변경 기반 알림을 계속 쓴다.
class NotificationService {
  NotificationService({
    required this.notifier,
    required this.store,
    required this.settings,
    bool Function()? isForeground,
    this.staleAfter = const Duration(seconds: 60),
  }) : isForeground = isForeground ?? (() => true);

  final LocalNotifier notifier;
  final GuardianStore store;
  final SettingsController settings;

  /// 앱이 화면 앞에 있는지 (main에서 앱 생명주기로 갱신)
  bool Function() isForeground;

  /// 원격 푸시 사용 중일 때, 이보다 오래된 문서는 저장소 경로로 다시 띄우지 않는다
  final Duration staleAfter;

  /// 이 기기가 FCM 원격 푸시를 받을 수 있는 상태(토큰이 서버에 등록됨)
  bool remotePushActive = false;

  final Set<String> _seenNotifications = {};
  final Set<String> _seenApprovals = {};
  bool _primed = false;
  bool _permissionGranted = false;
  bool get permissionGranted => _permissionGranted;

  /// 알림 권한 상태 (null: 아직 확인 전). 홈의 "알림이 꺼져 있어요" 안내가 듣는다.
  final ValueNotifier<bool?> permission = ValueNotifier(null);

  /// 기존 데이터는 알림으로 띄우지 않기 위해 첫 로딩 시점의 id를 기록한다.
  void start() {
    store.addListener(_onStoreChanged);
    _onStoreChanged();
  }

  Future<bool> requestPermission() async {
    _permissionGranted = await notifier.requestPermission();
    permission.value = _permissionGranted;
    return _permissionGranted;
  }

  /// 권한 창 없이 지금 상태만 다시 읽는다 (앱 복귀 시: 휴대폰 설정에서 바꿨을 수 있음)
  Future<bool> refreshPermission() async {
    _permissionGranted = await notifier.isPermissionGranted();
    permission.value = _permissionGranted;
    return _permissionGranted;
  }

  /// 알림 켜기: 권한 창을 다시 띄울 수 있으면 띄우고, 이미 막혔으면 휴대폰 설정 화면을 연다.
  /// 설정 화면을 열었으면 true (돌아왔을 때 [refreshPermission]으로 다시 확인).
  Future<bool> turnOn() async {
    if (await requestPermission()) return false;
    await notifier.openSettings();
    return true;
  }

  void _onStoreChanged() {
    if (!store.isLoaded) return;
    if (!_primed) {
      _seenNotifications.addAll(store.notifications.map((n) => n.id));
      _seenApprovals.addAll(store.approvals.map((a) => a.id));
      _primed = true;
      return;
    }
    for (final n in store.notifications) {
      if (_seenNotifications.add(n.id) && _alertFromStore(n.createdAt)) _alertNotification(n);
    }
    for (final a in store.approvals) {
      if (_seenApprovals.add(a.id) && a.status == ApprovalStatus.pending && _alertFromStore(a.createdAt)) {
        _alertApproval(a);
      }
    }
  }

  bool _alertFromStore(DateTime createdAt) {
    if (!remotePushActive) return true;
    if (!isForeground()) return false;
    return store.now().difference(createdAt) <= staleAfter;
  }

  /// 앱이 앞에 있을 때 FCM 메시지를 받은 경우 (Android는 포그라운드에서 FCM 알림을 자동 표시하지 않음).
  /// 저장소 경로와 같은 중복 방지 집합을 쓰므로, 둘 중 먼저 온 쪽만 표시된다.
  void showRemote(AlertTarget target, {String? type}) {
    if (target.kind == AlertTarget.notification) {
      if (_seenNotifications.contains(target.id)) return;
      final n = store.notifications.where((x) => x.id == target.id).firstOrNull;
      if (n != null) {
        _seenNotifications.add(n.id);
        return _alertNotification(n);
      }
      // 아직 목록에 없음(서버에서 다시 조회 중) → 목록에 들어오면 저장소 경로가 자세한 문구로 띄운다.
      // [remoteFallbackDelay] 안에 들어오지 않으면 최소 문구로라도 띄운다.
      Timer(remoteFallbackDelay, () {
        if (_disposed) return;
        final late = store.notifications.where((x) => x.id == target.id).firstOrNull;
        if (!_seenNotifications.add(target.id)) return;
        if (late != null) return _alertNotification(late);
        _showMinimalRemote(target, type);
      });
    } else if (target.kind == AlertTarget.approval) {
      _showRemoteApproval(target);
    }
  }

  /// FCM 뒤 목록이 들어오기를 기다리는 최대 시간
  Duration remoteFallbackDelay = const Duration(seconds: 6);
  bool _disposed = false;

  void _showMinimalRemote(AlertTarget target, String? type) {
    final t = NotificationType.fromCode(type ?? '');
    final channel = channelForType(t);
    if (!_enabled(channel)) return;
    notifier.show(
      LocalAlert(
        id: idFor(target.id),
        channel: channel,
        title: titleFor(channel),
        body: minimalBody(t),
        target: target,
      ),
    );
  }

  void _showRemoteApproval(AlertTarget target) {
    if (!_seenApprovals.add(target.id)) return;
    final a = store.approvals.where((x) => x.id == target.id).firstOrNull;
    if (a != null) return _alertApproval(a);
    if (!settings.approvalAlerts) return;
    notifier.show(
      LocalAlert(
        id: idFor(target.id),
        channel: AlertChannel.approval,
        title: '해봄 가족 · 승인 요청',
        body: '확인이 필요한 요청이 도착했습니다.',
        target: target,
      ),
    );
  }

  final Set<String> _seenUntargeted = {};

  /// 상세 화면 대상이 없는 원격 메시지(예: 콘솔 테스트 메시지)를 앱이 앞에 있을 때 표시한다.
  void showUntargeted(String key, {String? title, String? body}) {
    if (!settings.activityAlerts || !_seenUntargeted.add(key)) return;
    notifier.show(
      LocalAlert(
        id: idFor('untargeted:$key'),
        channel: AlertChannel.activity,
        title: title ?? '해봄 가족',
        body: body ?? '새 가족 알림이 도착했습니다.',
        target: null,
      ),
    );
  }

  /// 잠금 화면용 최소 문구 (FCM 서버 payload와 같은 문구)
  static String minimalBody(NotificationType t) => switch (t) {
    NotificationType.sos => '가족이 도움을 요청했습니다. 앱에서 확인해 주세요.',
    NotificationType.stuck => '가족에게 도움이 필요할 수 있습니다. 앱에서 확인해 주세요.',
    NotificationType.sensitiveEntry => '새 가족 알림이 도착했습니다.',
  };

  /// 문서 ID → 로컬 알림 id. 같은 문서는 항상 같은 id라 다시 표시돼도 알림창에 하나만 남는다.
  /// (String.hashCode는 실행마다 달라질 수 있어 고정 해시를 쓴다)
  static int idFor(String docId) {
    var h = 0x811c9dc5;
    for (final c in docId.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0x7fffffff;
    }
    return h;
  }

  /// 알림 종류 → 채널. SOS·사기 의심·L3는 긴급, 막힘은 도움 필요(높음), 나머지는 일반.
  static AlertChannel channelFor(NotificationItem n) =>
      n.isScam || n.level == SensitivityLevel.l3 ? AlertChannel.sos : channelForType(n.type);

  static AlertChannel channelForType(NotificationType t) => switch (t) {
    NotificationType.sos => AlertChannel.sos,
    NotificationType.stuck => AlertChannel.help,
    NotificationType.sensitiveEntry => AlertChannel.activity,
  };

  static String titleFor(AlertChannel c) => switch (c) {
    AlertChannel.sos => '해봄 가족 · 긴급',
    AlertChannel.help => '해봄 가족 · 도움 필요',
    AlertChannel.approval => '해봄 가족 · 승인 요청',
    AlertChannel.activity => '해봄 가족',
  };

  /// 설정 스위치: 긴급(SOS·사기 의심)은 SOS 알림, 막힘·앱 이용은 앱 이용 알림을 따른다.
  bool _enabled(AlertChannel c) => switch (c) {
    AlertChannel.sos => settings.sosAlerts,
    AlertChannel.approval => settings.approvalAlerts,
    AlertChannel.help || AlertChannel.activity => settings.activityAlerts,
  };

  void _alertNotification(NotificationItem n) {
    final channel = channelFor(n);
    if (!_enabled(channel)) return;
    final detail = notificationMessage(n, store.nameOf(n.elderId));
    final minimal = minimalBody(n.type);
    notifier.show(
      LocalAlert(
        id: idFor(n.id),
        channel: channel,
        title: titleFor(channel),
        body: settings.showDetailsInNotification ? detail : minimal,
        target: AlertTarget(AlertTarget.notification, n.id),
      ),
    );
  }

  void _alertApproval(ApprovalRequest a) {
    if (!settings.approvalAlerts) return;
    final who = store.nameOf(a.elderId);
    notifier.show(
      LocalAlert(
        id: idFor(a.id),
        channel: AlertChannel.approval,
        title: '해봄 가족 · 승인 요청',
        body: settings.showDetailsInNotification ? approvalAlertDetail(a, who) : '확인이 필요한 요청이 도착했습니다.',
        target: AlertTarget(AlertTarget.approval, a.id),
      ),
    );
  }

  void dispose() {
    _disposed = true;
    store.removeListener(_onStoreChanged);
  }
}
