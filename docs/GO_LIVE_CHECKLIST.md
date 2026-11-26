# 실제 연결 최종 준비 — 팀원 Firebase 프로젝트 + 공통 서버

> 작성일: 2026-11-25 · 보호자 앱 담당
> 보호자 앱 쪽 코드는 준비 완료. **아래 값과 서버 쪽 준비만 있으면 코드 수정 없이 설정 파일로 연결한다.**
> 자세한 근거: 서버 요청 사항 `docs/SERVER_REQUIREMENTS.md` · 콘솔 작업 `docs/FIREBASE_CONSOLE_GUIDE.md` · 규격 `docs/GUARDIAN_INTEGRATION.md`(v2.1)

## 1. 지금 준비된 것 (보호자 앱)
| 항목 | 상태 | 근거 |
|---|---|---|
| Mock 모드 전체 기능 (기본값) | ✅ | `flutter test` 108개, Fold3 `app_flow_test` |
| 서버 모드: Firebase 초기화(설정 파일), 익명 로그인, 가족별 Firestore 실시간 구독, "확인했어요" readBy | ✅ | Firestore 에뮬레이터 기기 테스트 — iOS 시뮬레이터·Android 에뮬레이터·**실제 Fold3** 통과 |
| 서버 API 클라이언트 (승인·거절, 연결·해제, 기기 등록, 오류 reason) | ✅ 구현 / ❓ 실제 서버 미검증 | 가짜 HTTP 테스트 |
| Android FCM 원격 푸시 수신 (백그라운드·잠금·종료, 탭 → 상세) | ✅ 구현 / ❓ 실제 푸시 미검증 | 가짜 FCM 테스트 |
| iPhone: 앱 실행 중 실시간 수신 + 로컬 알림 (원격 푸시 없음 — 사용자 확정) | ✅ 구현 / ✅ iOS 시뮬레이터 에뮬레이터 테스트 / ❓ 실기기 | |
| 로컬 알림 ↔ 원격 푸시 중복 방지 | ✅ | 단위 + 기기 테스트 |
| 설정 값 없음·로그인 실패·서버 읽기 거부 시 안내 화면 | ✅ | 에뮬레이터 화면 확인, 위젯 테스트 |

## 2. 연결 순서 (누가 · 무엇을)
| # | 누가 | 할 일 | 끝나면 |
|---|---|---|---|
| 1 | ✅ 결정됨 | **`copilot-demo-c9a74` 공동 사용** (2026-11-25 사용자 결정). 남은 것: 소유자에게 보호자 앱 등록 동의, 규칙 교체 전 옛 학습용 앱·`families` 경로가 더 필요 없는지 확인, 요금제(Blaze 여부) 공유 | – |
| 2 | 나 (콘솔) | 보호자 **Android 앱 등록** `com.yju.haebom.guardian_app`, (선택) **iOS 앱 등록** `com.yju.haebom.guardianApp` → 설정 파일 위치를 Claude에게 | `FIREBASE_CONSOLE_GUIDE.md` 1~3단계 |
| 3 | Claude | `config/firebase.json` 작성 (Git 제외) | |
| 4 | 나 + Claude | **서버 없이 FCM 테스트**: 폴드3 서버 모드 설치 → 토큰 → 콘솔 테스트 메시지 → 앞/백그라운드/잠금/종료 수신 확인 → 캠페인 초안 삭제 | Android 원격 푸시 확인 |
| 5 | 서버 담당 | `SERVER_REQUIREMENTS.md` 답변: API 방식·경로·**서버 주소 전달 방식**·오류 형식, FCM 발송 대상(**등록 토큰** vs Installation ID)·payload | Claude가 `ServerEndpoints`/설정만 조정 |
| 6 | 서버 담당 | **보안 규칙** 배포 (보호자 쿼리 허용: links `guardianId == 나`, 가족별 `elderId == X && guardianIds array-contains 나`, `readBy.{나}`만 쓰기, `config/server` 읽기). 소유자·고령자 앱 담당 확인 후 | 보호자 앱 홈에 실제 가족 표시 |
| 7 | 서버 담당 | **익명 로그인** 사용 설정 (소유자 동의) — 1차 시연 로그인 방식 | 보호자 앱 로그인 성공 |
| 8 | 고령자 앱 담당 | Firestore 직접 쓰기 → 서버 호출로 교체, 가족 연결 코드 화면 | 실제 알림 생성 |
| 9 | 모두 | 통합 시나리오 (`GUARDIAN_INTEGRATION.md` 13장) | 시연 준비 완료 |

## 3. 보호자 앱 설정 파일 (`config/firebase.json`, Git 제외)
```json
{
  "BACKEND": "server",
  "FIREBASE_PROJECT_ID": "<프로젝트 ID>",
  "FIREBASE_MESSAGING_SENDER_ID": "<프로젝트 번호>",
  "FIREBASE_ANDROID_API_KEY": "<google-services.json api_key.current_key>",
  "FIREBASE_ANDROID_APP_ID": "<google-services.json client.client_info.mobilesdk_app_id>",
  "FIREBASE_IOS_API_KEY": "<GoogleService-Info.plist API_KEY>",
  "FIREBASE_IOS_APP_ID": "<GoogleService-Info.plist GOOGLE_APP_ID>",
  "FIREBASE_IOS_BUNDLE_ID": "com.yju.haebom.guardianApp",
  "SERVER_BASE_URL": "<서버 주소 고정이면 입력, config/server 문서를 쓰면 비움>",
  "SERVER_CONFIG_DOC": "config/server"
}
```
실행: `flutter run --dart-define-from-file=config/firebase.json -d <기기>` (iPhone은 디버그 실행·Mac 연결 상태, 무료 서명 7일)

### 서버 주소 넣는 방법 (둘 중 하나, 코드 수정 없음)
| 방법 | 언제 | 하는 일 |
|---|---|---|
| ① 빌드 값 | 주소가 고정(AWS 등)일 때 | `config/firebase.json`의 `SERVER_BASE_URL`에 `https://<서버>` (끝의 `/`·`/v1` 없이) → 다시 빌드 |
| ② Firestore 문서 | 주소가 자주 바뀔 때(터널 등) | `SERVER_BASE_URL`은 비우고, 서버 담당이 `config/server` 문서에 `{ "baseUrl": "https://<서버>" }` 저장 (보안 규칙에서 읽기 허용 필요). 앱 재빌드 불필요 |

서버가 살아 있는지 먼저 확인: `curl https://<서버>/v1/healthz` (보호자 앱은 이 API를 부르지 않는다)

### 서버가 늦게 켜지거나 잠깐 끊겨도 앱은 다시 실행하지 않아도 된다 (11-26 구현)
- **Firestore 구독**: 권한 거부·서버 오류로 끊기면 1·2·4·8·16·30초 간격으로 다시 구독 (`lib/repositories/server/resilient_stream.dart`). 보안 규칙을 배포하면 최대 30초 안에 홈에 가족이 나타난다.
- **보호자 프로필(#2)**: 시작 때 실패하면 15초부터 두 배씩(최대 5분) 다시 시도, 앱이 다시 앞으로 오면 바로 시도 (`lib/services/profile_registrar.dart`). 성공하면 실패했던 FCM 토큰 등록도 다시 한다.
- **API**: 401 → 토큰 새로 받아 1번, 403 `profile-required` → 프로필 등록 후 1번 다시 보냄. 503·네트워크 오류는 다시 보내지 않음 (`docs/ALIGNMENT_CHECKLIST.md` 2장)

## 4. 연결 후 확인 순서
1. 앱 시작 → 로그인 성공 (실패하면 "로그인하지 못했습니다" + FCM 토큰 화면 → 익명 로그인 설정 확인)
2. 홈: "가족 정보를 불러오지 못했습니다"가 나오면 **보안 규칙**이 아직 보호자 쿼리를 막는 것 → 서버 담당자에게 `ALIGNMENT_CHECKLIST.md` 3장 쿼리 전달. 규칙 배포 후 앱을 그대로 두면 최대 30초 안에 자동으로 다시 불러온다
3. 설정 → 원격 알림 = **사용 중** (Android). "서버 연결 대기"면 서버 주소·기기 등록 API 확인
4. 고령자 앱(또는 서버 담당자의 테스트 호출)으로 알림 생성 → Android: 앱 종료·잠금 상태에서 푸시, 탭 → 상세 / iPhone: 앱을 켠 상태에서 로컬 알림
5. "확인했어요" → Firestore `readBy.{내 uid}` 기록
6. 승인 요청 → "계속해도 돼요"/"잠깐 멈춰요" → 고령자 앱 반영
7. 연결 코드로 가족 연결 / 양쪽 해제

## 5. 되돌리기
- Mock으로 돌아가기: `--dart-define-from-file` 없이 `flutter run` (기본 Mock)
- 프로젝트를 바꾸면 `config/firebase.json` 값만 교체
- 보호자 앱이 프로젝트에 만든 변경은 **앱 등록뿐** (콘솔 테스트 캠페인 초안은 삭제)

## 6. 알려진 제약
- iPhone 원격 푸시(앱 종료·잠금 화면)는 Apple 유료 계정 + APNs 키가 필요 → 시연은 보호자 앱을 켜 놓고 진행
- 익명 로그인은 앱 삭제 시 uid가 바뀌어 연결이 끊김 → 시연 전 재설치 금지
- 무료 iOS 서명은 7일마다 재설치
- 보호자 이름은 아직 "보호자"로 고정 (프로필 생성 시)
- FCM은 기존 등록 토큰 방식(deprecated API) 사용 — 서버가 Installation ID 방식을 쓰면 `FirebasePushMessaging`만 교체
