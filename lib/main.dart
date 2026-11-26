import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'app/app.dart';
import 'app/backend_config.dart';
import 'app/dependencies.dart';
import 'app/routes.dart';
import 'app/theme.dart';
import 'controllers/settings_controller.dart';
import 'repositories/mock_backend.dart';
import 'repositories/server/guardian_server_api.dart';
import 'repositories/server/server_repository.dart';
import 'repositories/server/server_url.dart';
import 'services/notification_service.dart';
import 'services/profile_registrar.dart';
import 'services/push_service.dart';

/// 실행 방법
/// - Mock (기본): `flutter run`
/// - 실제 서버: `flutter run --dart-define-from-file=config/firebase.json` (BACKEND=server 포함)
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = BackendConfig.fromEnvironment();
  if (config.useServer) return _runWithServer(config);
  return _runWithMock();
}

/// 앱 안의 Mock 서버로 실행 (자동 테스트·데모용, 지금까지와 동일)
Future<void> _runWithMock() async {
  final backend = MockBackend()..startExpiryTicker();
  final deps = AppDependencies.mock(
    backend: backend,
    notifier: PluginLocalNotifier(),
    settingsStorage: DeviceSettingsStorage(),
  );
  await deps.settings.load();

  await deps.notifier.initialize(
    (target) => AppRoutes.openTarget(deps.navigatorKey.currentState, target),
  );
  deps.notifications.start();

  runApp(HaebomFamilyApp(deps: deps));

  // 첫 화면이 그려진 뒤 권한 요청 및 "알림으로 앱이 실행된 경우" 처리
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await deps.notifications.requestPermission();
    final launch = await deps.notifier.launchTarget();
    if (launch != null) AppRoutes.openTarget(deps.navigatorKey.currentState, launch);
  });
}

/// 팀원의 공통 Firebase 프로젝트 + 공통 서버로 실행
Future<void> _runWithServer(BackendConfig config) async {
  if (!config.hasFirebaseOptions) {
    return runApp(_StartupErrorApp(
      title: 'Firebase 설정 값이 없습니다',
      message: '빠진 값: ${config.missingKeys.join(', ')}\n\n'
          'config/firebase.example.json을 참고해 config/firebase.json을 만든 뒤\n'
          'flutter run --dart-define-from-file=config/firebase.json 으로 실행하세요.',
    ));
  }

  try {
    await Firebase.initializeApp(options: config.firebaseOptions);
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    if (config.useEmulator) {
      // 공유 프로젝트 대신 맥북의 Firebase 로컬 에뮬레이터에 연결 (검증용)
      // 주소를 명시적으로 넣으므로 Android의 localhost → 10.0.2.2 자동 변환은 끈다
      // (실제 기기에서 adb reverse로 127.0.0.1을 쓸 수 있게)
      FirebaseFirestore.instance.useFirestoreEmulator(config.emulatorHost, 8080, automaticHostMapping: false);
      await FirebaseAuth.instance.useAuthEmulator(config.emulatorHost, 9099, automaticHostMapping: false);
    }
  } catch (e) {
    return runApp(_StartupErrorApp(
      title: 'Firebase를 시작하지 못했습니다',
      message: 'config/firebase.json의 값(프로젝트 ID, API 키, 앱 ID)을 확인해 주세요.\n\n$e',
    ));
  }

  final User user;
  try {
    final auth = FirebaseAuth.instance;
    user = auth.currentUser ?? (await auth.signInAnonymously()).user!;
  } catch (e) {
    // 로그인이 안 돼도(예: 익명 로그인 미사용) FCM 수신 시험은 할 수 있도록 토큰을 보여 준다.
    // 알림 채널을 먼저 만들어 두어야 백그라운드 FCM 알림이 '가족 앱 이용 알림' 채널로 표시된다.
    final notifier = PluginLocalNotifier();
    await notifier.initialize((_) {});
    return runApp(_StartupErrorApp(
      title: '로그인하지 못했습니다',
      message: '네트워크 연결과 Firebase 콘솔의 익명 로그인 사용 여부를 확인해 주세요.\n'
          '로그인 없이도 아래 토큰으로 FCM 테스트 메시지는 받을 수 있습니다.\n\n$e',
      fcmToken: kDebugMode ? _debugFcmToken(notifier) : null,
    ));
  }

  final firestore = FirebaseFirestore.instance;
  final serverUrl = ServerUrlResolver(
    fixedUrl: config.serverBaseUrl,
    firestore: firestore,
    configDoc: config.serverConfigDoc,
  )..start();
  final api = HttpGuardianServerApi(
    baseUrl: serverUrl.current,
    idToken: () async => FirebaseAuth.instance.currentUser?.getIdToken(),
    refreshIdToken: () async => FirebaseAuth.instance.currentUser?.getIdToken(true),
  );

  final deps = AppDependencies(
    repository: ServerGuardianRepository(firestore: firestore, guardianId: user.uid, api: api),
    notifier: PluginLocalNotifier(),
    settingsStorage: DeviceSettingsStorage(),
  );
  await deps.settings.load();
  // 원격 푸시 사용 중에는 앱이 화면 앞에 있을 때만 저장소 기반 로컬 알림을 띄운다 (중복 방지)
  deps.notifications.isForeground =
      () => WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  void open(AlertTarget t) => AppRoutes.openTarget(deps.navigatorKey.currentState, t);
  await deps.notifier.initialize(open);
  deps.notifications.start();

  final push = PushService(
    messaging: FirebasePushMessaging(),
    api: api,
    notifications: deps.notifications,
    deviceId: DeviceIdStore().get,
    onOpen: open,
  );
  deps.push = push;
  // 서버 규격상 기기 등록 전에 보호자 프로필이 필요하다. 서버가 꺼져 있어도 앱은 계속 동작하고,
  // 등록될 때까지 점점 긴 간격으로 다시 시도한다. 성공하면 실패했던 FCM 토큰 등록도 다시 해 본다.
  final profile = ProfileRegistrar(register: api.ensureGuardianProfile, onRegistered: push.retry);
  // 앱이 다시 앞으로 오면 프로필·FCM 토큰 등록이 실패했던 경우 바로 다시 시도한다
  AppLifecycleListener(onResume: () {
    unawaited(profile.retryNow());
    unawaited(push.retry());
  });

  runApp(HaebomFamilyApp(deps: deps));

  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await deps.notifications.requestPermission();
    final launch = await deps.notifier.launchTarget();
    if (launch != null) open(launch);
    await profile.start();
    await push.start();
  });
}

/// 디버그 빌드 진단용: 알림 권한을 요청하고 FCM 등록 토큰을 얻는다
Future<String?> _debugFcmToken(PluginLocalNotifier notifier) async {
  await notifier.requestPermission();
  final m = FirebasePushMessaging();
  if (!await m.requestPermission()) return null;
  final token = await m.getToken();
  debugPrint('FCM 등록 토큰 (테스트용): $token');
  return token;
}

class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp({required this.title, required this.message, this.fcmToken});
  final String title;
  final String message;
  final Future<String?>? fcmToken;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildLightTheme(),
        darkTheme: buildDarkTheme(),
        home: Scaffold(
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Icon(Icons.cloud_off_rounded, size: 48),
                const SizedBox(height: 16),
                Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                SelectableText(message),
                if (fcmToken != null) ...[
                  const SizedBox(height: 24),
                  const Text('FCM 등록 토큰 (테스트용)', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  FutureBuilder<String?>(
                    future: fcmToken,
                    builder: (context, snap) {
                      if (snap.connectionState != ConnectionState.done) return const LinearProgressIndicator();
                      final token = snap.data;
                      if (token == null) return Text('토큰을 받지 못했습니다. ${snap.error ?? '알림 권한을 확인해 주세요.'}');
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText(token, style: const TextStyle(fontSize: 12)),
                          TextButton.icon(
                            onPressed: () => Clipboard.setData(ClipboardData(text: token)),
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            label: const Text('토큰 복사'),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      );
}
