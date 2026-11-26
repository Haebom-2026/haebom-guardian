# Firebase 로컬 에뮬레이터 (보호자 앱 실제 Firestore 연동 검증용)

공유 Firebase 프로젝트·서버를 **전혀 건드리지 않고**, 맥북 안에서 Firestore·Auth를 흉내 낸다.
프로젝트 ID는 `demo-haebom`(`demo-`로 시작하면 실제 프로젝트에 연결되지 않음). 보안 규칙 파일이 없으므로 모든 읽기·쓰기가 허용된다(검증 전용).

```bash
cd tool/firebase_emulator
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
npx -y firebase-tools emulators:start --project demo-haebom
```

## 기기별 주소 (`FIREBASE_EMULATOR_HOST`)
| 기기 | 주소 | 비고 |
|---|---|---|
| iOS 시뮬레이터 | `localhost` | |
| Android 에뮬레이터 | `10.0.2.2` | |
| 실제 Android 폰 (무선·USB 디버깅) | `127.0.0.1` | 먼저 `adb -s <기기> reverse tcp:8080 tcp:8080 && adb -s <기기> reverse tcp:9099 tcp:9099` (맥 방화벽을 바꾸지 않아도 됨) |
| 실제 iPhone | 맥의 Wi-Fi IP | 맥 방화벽이 켜져 있으면 막힘 → 시스템 설정 → 네트워크 → 방화벽 → 옵션에서 `java` 들어오는 연결 허용이 필요 (사용자 결정) |

앱은 주소를 그대로 쓴다(`automaticHostMapping: false`). FlutterFire의 Android 자동 변환(127.0.0.1 → 10.0.2.2)은 실제 기기에서 틀린 주소가 되기 때문이다.

## 실행
- 자동 검증: `flutter test integration_test/server_emulator_test.dart -d <기기> --dart-define=FIREBASE_EMULATOR_HOST=<주소>`
  - 연결 → 일반·도움 필요·SOS 수신 → 로컬 알림 → 중복 방지 → 상세 이동·"확인했어요" → 승인 → 가족 연결 → 연결 해제
  - 무선 디버깅에서 `WebSocketChannelException`이 나면 테스트 도구 연결이 끊긴 것이므로 `adb -s <기기> forward --remove-all` 후 다시 실행
- 앱 수동 실행: `flutter run --dart-define-from-file=config/firebase.emulator.json --dart-define=FIREBASE_EMULATOR_HOST=<주소>`
- 에뮬레이터의 fake API 키(`AIza…0000`)는 형식만 맞춘 가짜 값이다 (iOS SDK가 형식을 검사함).
