import 'dart:async';
import 'dart:math';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../repositories/server/guardian_server_api.dart';
import 'notification_service.dart';

/// FCM 메시지에서 보호자 앱이 쓰는 부분 (`data.kind`, `data.id`, `data.type`)
class PushMessage {
  const PushMessage(this.data, {this.messageId, this.title, this.body});
  final Map<String, String> data;

  /// FCM 메시지 ID, `notification` 영역의 제목·본문 (Firebase 콘솔 테스트 메시지처럼 data가 없을 때 표시용)
  final String? messageId;
  final String? title;
  final String? body;

  /// 알림을 눌렀을 때 이동할 상세 화면. 규격: `data.kind` = notification | approval, `data.id` = 문서 ID
  AlertTarget? get target {
    final kind = data['kind'];
    final id = data['id'];
    if (id == null || id.isEmpty) return null;
    if (kind != AlertTarget.notification && kind != AlertTarget.approval) return null;
    return AlertTarget(kind!, id);
  }

  String? get type => data['type'];

  /// 연결 생성·해제 알림 (`data.kind` = link, 화면에 띄우지 않는 data 메시지). S1 계약서 5장
  bool get isLinkChange => data['kind'] == 'link';
}

/// FirebaseMessaging 추상화 (테스트에서 가짜 구현 사용)
abstract class PushMessaging {
  Future<bool> requestPermission();
  Future<String?> getToken();
  Stream<String> get onTokenRefresh;
  Stream<PushMessage> get onForegroundMessage;
  Stream<PushMessage> get onMessageOpenedApp;
  Future<PushMessage?> initialMessage();
  Future<void> deleteToken();
}

/// firebase_messaging 17부터 `getToken`/`onTokenRefresh`/`deleteToken`은 deprecated이고
/// `register()`/`onRegistered`(Firebase Installation ID 기반 direct-send)가 새 방식이다.
/// 공통 서버가 Admin SDK의 일반적인 `send({ token })`(FCM 등록 토큰)으로 보낸다는 전제로 기존 토큰 방식을 쓴다.
/// 💡 서버가 FID direct-send를 쓰기로 하면 이 클래스만 바꾼다 (`docs/SERVER_REQUIREMENTS.md`).
// ignore_for_file: deprecated_member_use
class FirebasePushMessaging implements PushMessaging {
  FirebasePushMessaging([FirebaseMessaging? messaging]) : _m = messaging ?? FirebaseMessaging.instance;
  final FirebaseMessaging _m;

  static PushMessage _wrap(RemoteMessage m) => PushMessage(
        m.data.map((k, v) => MapEntry(k, v?.toString() ?? '')),
        messageId: m.messageId,
        title: m.notification?.title,
        body: m.notification?.body,
      );

  @override
  Future<bool> requestPermission() async {
    final s = await _m.requestPermission(alert: true, badge: true, sound: true);
    return s.authorizationStatus == AuthorizationStatus.authorized ||
        s.authorizationStatus == AuthorizationStatus.provisional;
  }

  /// iOS는 APNs 토큰이 있어야 FCM 토큰이 나온다. Apple 유료 계정 없이는 APNs가 없으므로 null.
  @override
  Future<String?> getToken() async {
    if (defaultTargetPlatform == TargetPlatform.iOS && await _m.getAPNSToken() == null) return null;
    return _m.getToken();
  }

  @override
  Stream<String> get onTokenRefresh => _m.onTokenRefresh;
  @override
  Stream<PushMessage> get onForegroundMessage => FirebaseMessaging.onMessage.map(_wrap);
  @override
  Stream<PushMessage> get onMessageOpenedApp => FirebaseMessaging.onMessageOpenedApp.map(_wrap);
  @override
  Future<PushMessage?> initialMessage() async {
    final m = await _m.getInitialMessage();
    return m == null ? null : _wrap(m);
  }

  @override
  Future<void> deleteToken() => _m.deleteToken();
}

/// 앱이 백그라운드·종료 상태일 때 받은 FCM 메시지 처리.
///
/// 서버가 `notification` 영역이 있는 메시지를 보내면 Android 시스템이 직접 알림을 표시하므로
/// 여기서 따로 띄우지 않는다(띄우면 중복). data 전용 메시지가 필요해지면 이곳에서 처리한다.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

/// 이 설치본을 구분하는 기기 ID (서버의 `users/{uid}/devices/{deviceId}`). 앱 삭제 시 새로 생성된다.
class DeviceIdStore {
  static const _key = 'push.deviceId';
  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  Future<String> get() async {
    final saved = await _prefs.getString(_key);
    if (saved != null && saved.isNotEmpty) return saved;
    final rng = Random.secure();
    final id = List.generate(16, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    await _prefs.setString(_key, id);
    return id;
  }
}

/// 원격 푸시 수신 상태 (설정 화면 표시용)
enum PushState {
  /// 아직 시작 전
  idle,

  /// 알림 권한 거부
  permissionDenied,

  /// FCM 토큰 없음 (iPhone: APNs 미설정 — Apple 유료 계정 필요)
  noToken,

  /// 토큰은 있으나 서버 등록 실패 (서버 꺼짐 등) — 로컬 알림으로 대체 중
  registerFailed,

  /// 서버에 등록됨 — 원격 푸시 수신 가능
  active,
}

/// FCM 토큰 발급·서버 등록, 포그라운드 메시지 표시, 알림 탭 이동을 담당한다.
class PushService extends ChangeNotifier {
  PushService({
    required this.messaging,
    required this.api,
    required this.notifications,
    required this.deviceId,
    required this.onOpen,
    this.onLinkChanged,
    this.onContentChanged,
    String? platform,
  }) : platform = platform ?? (defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android');

  final PushMessaging messaging;
  final GuardianServerApi api;
  final NotificationService notifications;
  final Future<String> Function() deviceId;
  final void Function(AlertTarget target) onOpen;

  /// FCM `kind: link`를 받았을 때 (가족 목록 다시 조회)
  final void Function()? onLinkChanged;

  /// FCM `kind: notification | approval`을 받았거나 눌렀을 때 (알림·승인 목록 다시 조회)
  final void Function()? onContentChanged;
  final String platform;

  PushState state = PushState.idle;
  String? lastError;

  /// 현재 FCM 등록 토큰 (디버그 빌드에서 Firebase 콘솔 테스트 메시지용으로 표시)
  String? token;
  final List<StreamSubscription<Object?>> _subs = [];

  void _set(PushState s, [String? error]) {
    state = s;
    lastError = error;
    // 서버에 등록된 경우에만 "원격 푸시 사용 중"으로 보고 로컬 알림 경로를 줄인다
    notifications.remotePushActive = s == PushState.active;
    notifyListeners();
  }

  Future<void> start() async {
    _subs.add(messaging.onForegroundMessage.listen((m) {
      if (m.isLinkChange) {
        onLinkChanged?.call();
        return;
      }
      final t = m.target;
      if (t != null) {
        onContentChanged?.call();
        notifications.showRemote(t, type: m.type);
      } else if (m.title != null || m.body != null) {
        // 규격의 data(kind·id)가 없는 메시지 (예: Firebase 콘솔 테스트 메시지): 제목·본문만 표시, 탭하면 앱 열기
        notifications.showUntargeted(m.messageId ?? '${m.title}|${m.body}', title: m.title, body: m.body);
      }
    }));
    _subs.add(messaging.onMessageOpenedApp.listen((m) {
      final t = m.target;
      if (t != null) {
        onContentChanged?.call();
        onOpen(t);
      }
    }));
    _subs.add(messaging.onTokenRefresh.listen(_register));

    final initial = await messaging.initialMessage();
    final t = initial?.target;
    if (t != null) onOpen(t);

    if (!await messaging.requestPermission()) return _set(PushState.permissionDenied);
    final String? token;
    try {
      token = await messaging.getToken();
    } catch (e) {
      return _set(PushState.noToken, '$e');
    }
    if (token == null) return _set(PushState.noToken, platform == 'ios' ? 'APNs 미설정' : null);
    this.token = token;
    if (kDebugMode) debugPrint('FCM 등록 토큰 (테스트용): $token');
    await _register(token);
  }

  /// 서버 등록 재시도 (설정 화면 버튼, 앱이 다시 앞으로 왔을 때)
  Future<void> retry() async {
    if (state == PushState.active || state == PushState.idle) return;
    final token = await messaging.getToken().catchError((Object _) => null);
    if (token != null) await _register(token);
  }

  Future<void> _register(String token) async {
    this.token = token;
    try {
      await api.registerDevice(deviceId: await deviceId(), fcmToken: token, platform: platform);
      _set(PushState.active);
    } catch (e) {
      _set(PushState.registerFailed, '$e');
    }
  }

  /// 로그아웃 시: 서버에서 이 기기 등록 해제 후 토큰 삭제
  Future<void> stop() async {
    try {
      await api.unregisterDevice(await deviceId());
    } catch (_) {}
    await messaging.deleteToken().catchError((Object _) {});
    _set(PushState.idle);
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}
