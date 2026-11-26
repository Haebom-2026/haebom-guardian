# 해봄 가족 (Haebom Family) — 보호자 앱

> 오늘도, 스스로 해봄.
> 대신 해주는 AI가 아니라, 스스로 해낼 수 있도록 돕는 AI.

고령자 스마트폰 AI 도우미 **해봄**의 보호자용 앱입니다. 가족이 동의한 민감 서비스 이용 알림을 받고, 해봄 도우미의 진행 승인 요청에 응답하며, 6자리 코드로 가족을 연결합니다.

- 플랫폼: Android · iOS (Flutter)
- 현재 단계: 기본은 **Mock 데이터로 동작**. 서버 연동(Firebase 로그인·FCM 수신·서버 API)은 구현 완료, 실제 서버 연결 대기 중
- 고령자 앱(Kotlin)은 별도 저장소/팀원 담당이며 이 프로젝트 범위가 아닙니다.
- 연동 규격: [docs/INTEGRATION.md](docs/INTEGRATION.md)

## 주요 기능

| 탭 | 기능 |
|---|---|
| 홈 | 연결된 가족, 가족 선택, 오늘 알림·읽지 않음·승인 대기 수, 승인 요청, 최근 활동. 우측 상단 ⚙︎ → 설정 |
| 알림 | 전체/읽지 않음 필터, 가족별 필터, 앱 이용/도움 필요/SOS 구분, 상세·읽음 처리, 모두 읽음 |
| 승인 | 승인 대기/완료/거절/시간 만료/요청 취소, 남은 시간, 확인 팝업 후 승인·거절, 중복 응답 방지 |
| 가족 | 연결된 가족 목록, 6자리 코드로 연결, 연결 해제, 코드 오류/만료/재사용 처리 |
| 설정 | 알림 종류별 on/off, 잠금화면 상세 표시(기본 꺼짐), 개인정보 보호 안내, 버전, 개발자 테스트 모드(디버그 빌드 전용) |

## 개발 환경 설정 (macOS, Apple Silicon)

이 컴퓨터에서 확인된 버전 (2026-11-26):
Flutter 3.50.1 / Dart 3.14.0 / Xcode 27.2 / Android SDK (platform android-37.0, build-tools 36.0.0) / Android Studio 내장 JBR

1. **Flutter SDK** — `~/development/flutter` (git clone, stable 채널)
   ```bash
   # ~/.zshrc 에 추가
   export PATH="$HOME/development/flutter/bin:$PATH"
   export ANDROID_HOME="$HOME/Library/Android/sdk"
   export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"
   export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
   ```
2. **Android** — Android Studio 설치 후 SDK Manager에서 *Android SDK Command-line Tools (latest)* 설치, 라이선스 동의:
   ```bash
   flutter doctor --android-licenses
   ```
3. **iOS** — Xcode 설치 후 (관리자 권한 필요):
   ```bash
   sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
   sudo xcodebuild -runFirstLaunch
   ```
   위 명령 전에는 터미널에서 `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` 로 대신할 수 있습니다.
   Flutter 3.50은 Swift Package Manager를 사용하므로 CocoaPods 없이 빌드됩니다(현재 플러그인 기준 확인).
4. **VS Code** — Flutter, Dart 확장 설치.
5. 확인: `flutter doctor -v`

## 실행

```bash
cd haebom_guardian
flutter pub get

# Android 에뮬레이터
emulator -avd Medium_Phone_API_37.0 &
flutter run -d emulator-5554

# iOS 시뮬레이터
xcrun simctl boot "iPhone 18 Pro" && open -a Simulator
flutter run -d "iPhone 18 Pro"
```

첫 실행 시 알림 권한을 **허용**해야 로컬 알림이 표시됩니다.

### 개발자 테스트 모드
설정 → 개발자 → **개발자 테스트 모드** (디버그 빌드에서만 보임).
고령자 앱과 서버 동작을 Mock으로 흉내 냅니다: 민감 앱 진입(예/아니요/닫기/중복), 승인 요청 생성·만료·취소·동시 응답, 고령자 앱 수신 결과, 연결 코드 발급(정상/만료), 보호자별 읽음 상태, SOS/도움 필요, 데이터 초기화.

> 여기서 만든 알림은 **이 기기의 로컬 알림**입니다. 다른 휴대폰에서 보내는 원격 푸시(FCM/APNs)는 Firebase 연동 후에만 가능합니다.

## 테스트

```bash
flutter analyze
flutter test                                   # 단위·위젯 테스트 (157개)
flutter test integration_test -d <device-id>   # 실기기/시뮬레이터 통합 테스트
```

## 구조

```
lib/
  main.dart                 앱 진입, Mock 서버·로컬 알림 초기화
  app/                      dependencies(DI) · routes · theme
  models/                   notifications / approvals / links / 민감 앱 카탈로그
  repositories/
    guardian_repository.dart  UI가 의존하는 인터페이스 (+ 오류 코드)
    mock_backend.dart         Firebase(Firestore+Functions) 역할의 서버 규칙 시뮬레이션
    mock_repository.dart      보호자 1인 관점의 구현 (추후 FirebaseRepository로 교체)
  controllers/              GuardianStore(스트림 → UI 상태), SettingsController
  services/                 notification_service (flutter_local_notifications)
  screens/                  home · notifications · approvals · family · settings · developer
  widgets/                  공통 카드·배지·확인 팝업
test/                       단위·위젯 테스트
integration_test/           기기 위 통합 테스트
docs/INTEGRATION.md         고령자 앱 연동 규격
```

## 현재 제한 사항
- 기본(Mock) 모드에서는 데이터가 앱 메모리에만 있어 재시작하면 초기화됩니다. 실제 서버 모드는 `--dart-define-from-file=config/firebase.json`으로 실행합니다.
- 실제 서버와의 연결은 서버 완성 후 검증 예정입니다.
- iPhone은 원격 푸시(APNs)를 쓰지 않아 앱이 켜져 있을 때만 알림을 받습니다.
