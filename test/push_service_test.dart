import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:guardian_app/models/sensitive_app.dart';
import 'package:guardian_app/repositories/guardian_repository.dart';
import 'package:guardian_app/repositories/mock_backend.dart';
import 'package:guardian_app/services/notification_service.dart';
import 'package:guardian_app/services/push_service.dart';

import 'helpers.dart';
import 'fake_server_api.dart';

class FakeMessaging implements PushMessaging {
  bool permission = true;
  String? token = 'fcm-token-1';
  PushMessage? initial;
  final foreground = StreamController<PushMessage>.broadcast();
  final opened = StreamController<PushMessage>.broadcast();
  final refresh = StreamController<String>.broadcast();
  bool deleted = false;

  @override
  Future<bool> requestPermission() async => permission;
  @override
  Future<String?> getToken() async => token;
  @override
  Stream<String> get onTokenRefresh => refresh.stream;
  @override
  Stream<PushMessage> get onForegroundMessage => foreground.stream;
  @override
  Stream<PushMessage> get onMessageOpenedApp => opened.stream;
  @override
  Future<PushMessage?> initialMessage() async => initial;
  @override
  Future<void> deleteToken() async => deleted = true;
}

void main() {
  late TestEnv env;
  late FakeMessaging messaging;
  late FakeServerApi api;
  late List<AlertTarget> opened;
  late PushService push;

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  setUp(() async {
    env = TestEnv();
    messaging = FakeMessaging();
    api = FakeServerApi();
    opened = [];
    push = PushService(
      messaging: messaging,
      api: api,
      notifications: env.deps.notifications,
      deviceId: () async => 'device-1',
      onOpen: opened.add,
      platform: 'android',
    );
    env.deps.notifications.start();
    await settle();
  });

  tearDown(() => env.deps.dispose());

  group('FCM 토큰', () {
    test('권한 허용 → 토큰을 서버에 등록 → 원격 푸시 사용 중', () async {
      await push.start();
      expect(api.calls, ['register:device-1:fcm-token-1:android']);
      expect(push.state, PushState.active);
      expect(env.deps.notifications.remotePushActive, isTrue);
      expect(push.token, 'fcm-token-1', reason: '디버그 빌드에서 콘솔 테스트용으로 복사할 수 있게 보관');
    });

    test('서버 등록이 실패해도 토큰은 보관한다 (서버 없이 콘솔 테스트 메시지 수신용)', () async {
      api.failWith = const RepositoryException(RepositoryErrorCode.unavailable);
      await push.start();
      expect(push.token, 'fcm-token-1');
      expect(push.state, PushState.registerFailed);
    });

    test('토큰이 바뀌면 다시 등록한다', () async {
      await push.start();
      messaging.refresh.add('fcm-token-2');
      await settle();
      expect(api.calls.last, 'register:device-1:fcm-token-2:android');
    });

    test('알림 권한 거부 → 등록하지 않고 로컬 알림 경로 유지', () async {
      messaging.permission = false;
      await push.start();
      expect(api.calls, isEmpty);
      expect(push.state, PushState.permissionDenied);
      expect(env.deps.notifications.remotePushActive, isFalse);
    });

    test('iPhone처럼 토큰이 없으면(APNs 미설정) 로컬 알림 경로 유지', () async {
      messaging.token = null;
      await push.start();
      expect(push.state, PushState.noToken);
      expect(env.deps.notifications.remotePushActive, isFalse);
    });

    test('서버가 꺼져 있으면 등록 실패 → 로컬 알림 유지, 다시 시도하면 등록', () async {
      api.failWith = const RepositoryException(RepositoryErrorCode.unavailable);
      await push.start();
      expect(push.state, PushState.registerFailed);
      expect(env.deps.notifications.remotePushActive, isFalse);
      api.failWith = null;
      await push.retry();
      expect(push.state, PushState.active);
    });

    test('로그아웃: 서버 등록 해제 후 토큰 삭제', () async {
      await push.start();
      await push.stop();
      expect(api.calls.last, 'unregister:device-1');
      expect(messaging.deleted, isTrue);
      expect(push.state, PushState.idle);
    });
  });

  group('알림 탭 → 상세 화면', () {
    test('백그라운드에서 알림을 눌러 앱이 열리면 해당 상세로 이동', () async {
      await push.start();
      messaging.opened.add(const PushMessage({'kind': 'approval', 'id': 'a1'}));
      await settle();
      expect(opened.single.encode(), 'approval:a1');
    });

    test('종료 상태에서 알림을 눌러 실행된 경우에도 이동', () async {
      messaging.initial = const PushMessage({'kind': 'notification', 'id': 'n9', 'type': 'sos'});
      await push.start();
      expect(opened.single.encode(), 'notification:n9');
    });

    test('data가 없는 메시지(콘솔 테스트 메시지)는 앱이 앞에 있을 때 제목·본문으로 한 번만 표시', () async {
      await push.start();
      const m = PushMessage({}, messageId: 'm1', title: '해봄 가족', body: '테스트 메시지');
      messaging.foreground.add(m);
      messaging.foreground.add(m);
      await settle();
      expect(env.notifier.shown, hasLength(1));
      expect(env.notifier.shown.single.body, '테스트 메시지');
      expect(env.notifier.shown.single.target, isNull, reason: '눌러도 앱만 열림');
    });

    test('규격에 없는 kind나 id 없는 메시지는 무시', () {
      expect(const PushMessage({'kind': 'other', 'id': 'x'}).target, isNull);
      expect(const PushMessage({'kind': 'notification'}).target, isNull);
    });
  });

  group('로컬 알림과 원격 푸시 중복 방지', () {
    test('포그라운드 FCM 메시지 → 로컬 알림 1개, 같은 문서가 Firestore로 와도 다시 띄우지 않음', () async {
      env.clock.advance(Duration.zero);
      await push.start();
      // FCM이 먼저 도착 (아직 Firestore에는 없음)
      messaging.foreground.add(const PushMessage({'kind': 'notification', 'id': 'n_push', 'type': 'stuck'}));
      await settle();
      expect(env.notifier.shown, hasLength(1));
      expect(env.notifier.shown.single.body, '가족에게 도움이 필요할 수 있습니다. 앱에서 확인해 주세요.');
      // 같은 메시지가 다시 와도 무시
      env.deps.notifications.showRemote(const AlertTarget('notification', 'n_push'), type: 'stuck');
      expect(env.notifier.shown, hasLength(1));
    });

    test('Firestore로 먼저 받아 표시한 문서는 FCM 포그라운드 메시지로 다시 띄우지 않음', () async {
      await push.start();
      final (_, n) = env.backend.reportSensitiveEntry(
          elderId: MockBackend.momId, app: SensitiveApp.toss, choice: ConsentChoice.yes);
      await settle();
      expect(env.notifier.shown, hasLength(1));
      messaging.foreground.add(PushMessage({'kind': 'notification', 'id': n!.id}));
      await settle();
      expect(env.notifier.shown, hasLength(1));
    });

    test('원격 푸시 사용 중 + 앱이 백그라운드 → 저장소 기반 로컬 알림을 띄우지 않음 (시스템이 FCM 알림 표시)', () async {
      var foreground = false;
      env.deps.notifications.isForeground = () => foreground;
      await push.start();
      env.backend.createSos(MockBackend.momId);
      await settle();
      expect(env.notifier.shown, isEmpty);
      // 다시 앞으로 와도, 백그라운드에서 받은 문서는 다시 띄우지 않음
      foreground = true;
      env.backend.createSos(MockBackend.dadId);
      await settle();
      expect(env.notifier.shown, hasLength(1), reason: '앞에 있을 때 새로 온 것만');
    });

    test('원격 푸시 사용 중이라도 오래된 문서(밀려 들어온 것)는 띄우지 않음', () async {
      await push.start();
      final n = env.backend.createSos(MockBackend.momId)!;
      // 같은 시각에 생성됐으므로 표시됨
      await settle();
      expect(env.notifier.shown.map((a) => a.id), [NotificationService.idFor(n.id)]);
      env.notifier.shown.clear();
      // 2분 전에 만들어진 문서가 늦게 도착
      env.backend.reportSensitiveEntry(elderId: MockBackend.dadId, app: SensitiveApp.toss, choice: ConsentChoice.yes);
      env.clock.advance(const Duration(minutes: 2));
      await settle();
      expect(env.notifier.shown, isEmpty);
    });

    test('원격 푸시를 못 받는 기기(iPhone 등)는 백그라운드에서도 지금처럼 로컬 알림', () async {
      messaging.token = null;
      env.deps.notifications.isForeground = () => false;
      await push.start();
      env.backend.createSos(MockBackend.momId);
      await settle();
      expect(env.notifier.shown, hasLength(1));
    });

    test('로컬 알림 id는 문서 ID로 고정 (실행마다 같음)', () {
      expect(NotificationService.idFor('abc'), NotificationService.idFor('abc'));
      expect(NotificationService.idFor('abc'), isNot(NotificationService.idFor('abd')));
      expect(NotificationService.idFor('abc'), greaterThanOrEqualTo(0));
    });
  });
}
