import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// 어떤 저장소로 실행할지 결정한다.
///
/// - 기본값은 `mock`: 지금까지와 같이 앱 안의 [MockBackend]로 동작한다 (자동 테스트·데모용).
/// - `server`: 팀원의 공통 Firebase 프로젝트 + 공통 서버에 연결한다.
///
/// 값은 빌드할 때 `--dart-define-from-file=config/firebase.json`으로 넣는다.
/// (`config/firebase.example.json` 참고. 실제 값 파일은 Git에 올리지 않는다.)
/// 기존 Firebase 프로젝트에 보호자 앱을 등록한 뒤 받은 값을 넣는다 — 팀원 합의 후.
class BackendConfig {
  const BackendConfig({
    required this.mode,
    required this.projectId,
    required this.messagingSenderId,
    required this.androidApiKey,
    required this.androidAppId,
    required this.iosApiKey,
    required this.iosAppId,
    required this.iosBundleId,
    required this.storageBucket,
    required this.serverBaseUrl,
    required this.serverConfigDoc,
    this.emulatorHost = '',
  });

  factory BackendConfig.fromEnvironment() => const BackendConfig(
        mode: String.fromEnvironment('BACKEND', defaultValue: 'mock'),
        projectId: String.fromEnvironment('FIREBASE_PROJECT_ID'),
        messagingSenderId: String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID'),
        androidApiKey: String.fromEnvironment('FIREBASE_ANDROID_API_KEY'),
        androidAppId: String.fromEnvironment('FIREBASE_ANDROID_APP_ID'),
        iosApiKey: String.fromEnvironment('FIREBASE_IOS_API_KEY'),
        iosAppId: String.fromEnvironment('FIREBASE_IOS_APP_ID'),
        iosBundleId: String.fromEnvironment('FIREBASE_IOS_BUNDLE_ID', defaultValue: 'com.yju.haebom.guardianApp'),
        storageBucket: String.fromEnvironment('FIREBASE_STORAGE_BUCKET'),
        serverBaseUrl: String.fromEnvironment('SERVER_BASE_URL'),
        serverConfigDoc: String.fromEnvironment('SERVER_CONFIG_DOC', defaultValue: 'config/server'),
        emulatorHost: String.fromEnvironment('FIREBASE_EMULATOR_HOST'),
      );

  /// `mock` | `server`
  final String mode;
  final String projectId;
  final String messagingSenderId;
  final String androidApiKey;
  final String androidAppId;
  final String iosApiKey;
  final String iosAppId;
  final String iosBundleId;
  final String storageBucket;

  /// 공통 서버 주소를 고정해서 쓸 때 (예: `https://example.trycloudflare.com`). 비우면 [serverConfigDoc]에서 읽는다.
  final String serverBaseUrl;

  /// 서버 주소(`baseUrl` 필드)를 담은 Firestore 문서 경로. 💡 서버 담당자와 합의 필요.
  final String serverConfigDoc;

  /// Firebase 로컬 에뮬레이터 주소 (검증용, 디버그 빌드에서만 사용). `tool/firebase_emulator/README.md`
  final String emulatorHost;

  bool get useServer => mode == 'server';
  bool get useEmulator => kDebugMode && emulatorHost.isNotEmpty;

  /// 현재 플랫폼에 필요한 Firebase 값이 모두 있는지
  bool get hasFirebaseOptions {
    if (projectId.isEmpty || messagingSenderId.isEmpty) return false;
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => iosApiKey.isNotEmpty && iosAppId.isNotEmpty,
      _ => androidApiKey.isNotEmpty && androidAppId.isNotEmpty,
    };
  }

  /// 빠진 값 목록 (실행 시 안내용)
  List<String> get missingKeys => [
        if (projectId.isEmpty) 'FIREBASE_PROJECT_ID',
        if (messagingSenderId.isEmpty) 'FIREBASE_MESSAGING_SENDER_ID',
        if (defaultTargetPlatform == TargetPlatform.iOS) ...[
          if (iosApiKey.isEmpty) 'FIREBASE_IOS_API_KEY',
          if (iosAppId.isEmpty) 'FIREBASE_IOS_APP_ID',
        ] else ...[
          if (androidApiKey.isEmpty) 'FIREBASE_ANDROID_API_KEY',
          if (androidAppId.isEmpty) 'FIREBASE_ANDROID_APP_ID',
        ],
      ];

  /// google-services.json / GoogleService-Info.plist 없이 Dart에서 Firebase를 초기화하기 위한 값
  FirebaseOptions get firebaseOptions => switch (defaultTargetPlatform) {
        TargetPlatform.iOS => FirebaseOptions(
            apiKey: iosApiKey,
            appId: iosAppId,
            messagingSenderId: messagingSenderId,
            projectId: projectId,
            iosBundleId: iosBundleId,
            storageBucket: storageBucket.isEmpty ? null : storageBucket,
          ),
        _ => FirebaseOptions(
            apiKey: androidApiKey,
            appId: androidAppId,
            messagingSenderId: messagingSenderId,
            projectId: projectId,
            storageBucket: storageBucket.isEmpty ? null : storageBucket,
          ),
      };
}
