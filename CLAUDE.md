# CLAUDE.md — 해봄 가족 (보호자 앱)

> **새 세션 시작 시 `docs/PROGRESS.md`(진행 상황·다음 할 일·기기 연결 방법)를 먼저 읽는다.** 작업을 마치면 그 파일을 갱신한다.

## 목적
고령자 스마트폰 AI 도우미 **해봄**의 보호자 앱(Flutter, Android+iOS). 바이브코딩 공모전 출품작이지만 실제 보호자가 쓸 수 있는 품질을 목표로 한다.
철학: 대신 조작해 주는 AI가 아니라 고령자가 **스스로** 해내도록 돕고, 필요한 순간에만 가족이 돕는다.

## 역할 분담 (2026-11-25 확정)
- 고령자 앱(Kotlin, Android): 다른 팀원 — **이 저장소에서 수정하지 않는다.**
- 공통 백엔드 서버 + FCM 발송: 다른 팀원(개발 중) — **이 저장소에서 서버·터널을 만들지 않는다.**
- 보호자 앱(Flutter, Android/iOS) + FCM 수신: 이 저장소.
- Firebase 프로젝트: 고령자 앱이 쓰는 **`copilot-demo-c9a74`를 공동 사용**(2026-11-25 사용자 결정, 새 프로젝트 만들지 않음). 앱 등록·규칙 변경은 소유자 동의 후, 규칙 배포는 서버 담당자.
- 두 앱은 공통 서버와 Firebase를 통해서만 통신한다. 서버에 기대하는 사항은 `docs/SERVER_REQUIREMENTS.md`.

## 현재 단계
1. Mock 데이터로 전체 기능 구현 ✅
2. Android 에뮬레이터·실제 Android 폰 검증 ✅ / iPhone 설치·실행 ✅, 화면 수동 확인 남음
3. 실제 연동 (진행 중): 보호자 앱 쪽 Firebase Auth·Firestore 구독·서버 API 클라이언트·FCM 수신 **구현 완료(가짜 객체 테스트)**. 실제 프로젝트 연결은 팀원의 Firebase 프로젝트 앱 등록·서버 완성 후

## 반드시 지킬 것
- 공유받은 Firebase 프로젝트(`copilot-demo-c9a74` 포함)의 설정·데이터·보안 규칙을 변경하지 않는다. 보호자 앱 등록도 소유자 동의 후. Blaze 가입·결제 카드 등록 금지, 별도 서버 구축 금지, `git push` 금지 (요청 전까지).
- Firebase 설정 값은 `config/firebase.json`(Git 제외)에 두고 `--dart-define-from-file`로 넣는다. `google-services.json`·`GoogleService-Info.plist`·서비스 계정 키는 커밋하지 않는다.
- Mock 모드가 기본값이다. `MockBackend`·`MockGuardianRepository`·기존 자동 테스트를 삭제하지 않는다.
- 통신 규격(`docs/GUARDIAN_INTEGRATION.md` v2.1 + `docs/DATA_SPEC_CHANGES.md` v2.2, 상세 `docs/INTEGRATION.md`)을 임의로 바꾸지 않는다. 문서와 코드가 다르면 차이를 보고한다. 합의 안 된 내용은 "💡 제안"으로 표시.
- UI는 `GuardianRepository` 인터페이스에만 의존한다. 서버 규칙(권한·중복·상태 전이)은 `MockBackend`에(실제로는 공통 서버). 실제 서버용 구현은 `lib/repositories/server/`.
- 수신 보호자(`guardianIds`)는 서버가 links 기준으로 결정한다. 클라이언트가 지정하지 않는다.
- 구현 완료와 실행 검증 완료를 구분해 보고한다. 테스트 결과·수치를 지어내지 않는다.

## 개인정보·표현 원칙
- 고령자가 "예"를 선택했을 때만 민감 앱 이용 알림 생성. 아니요/닫기는 문서 자체를 만들지 않는다 (consent 필드 없음).
- 비밀번호·계좌번호·주민번호·화면 캡처·거래 내용은 수집하지 않는다.
- "이용 사실"만 알린다. 개인정보 입력을 감지했다고 표현하지 않는다.
- 승인은 "거래 승인"이 아니라 **도우미 진행 승인**이다. 실제 금융 거래를 승인·차단하지 않는다.
- 잠금화면 알림은 기본적으로 최소 문구("새 가족 알림이 도착했습니다.").
- 로컬 알림 동작을 원격 푸시가 된다고 표현하지 않는다. iPhone은 APNs(유료 계정) 없이는 원격 푸시를 받지 못한다.
- 보호자의 "확인"은 상세 화면의 **"확인했어요" 버튼**을 눌렀을 때만 기록한다(열기만 해서는 기록하지 않음).
- 위치·접속 상태 등 알 수 없는 정보를 임의로 표시하지 않는다.

## 디자인
화이트·아이보리·차분한 그린, 그라데이션·과한 장식 지양, 한국어 UI, SafeArea, 가로 오버플로 없음, 글자 크기 확대·다크 모드 대응. 디자인 토큰은 `lib/app/theme.dart`.

## 개발 명령
```bash
export PATH="$HOME/development/flutter/bin:$PATH"
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"   # Android 빌드
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer                   # xcode-select 미설정 시
flutter analyze && flutter test
flutter test integration_test -d <device-id>
flutter run --dart-define-from-file=config/firebase.json   # 실제 서버 모드 (config/firebase.example.json 참고)
```
- `package:flutter/material.dart` 대신 **`package:material_ui/material_ui.dart`** 를 import한다 (Flutter 3.50에서 분리됨).
- Android `compileSdk = 37` (androidx.core 1.19 요구사항).
- 위젯 테스트는 `test/helpers.dart`의 `TestEnv`(FakeClock, FakeNotifier)를 사용한다.
