# 작업 기록 · 이어서 하기 (해봄 가족 보호자 앱)

> 마지막 업데이트: 2026-11-26 오후 (GitHub 저장소로 이동, 자동 재연결·프로필 재시도, 통일 규격 정리)
> 새 세션을 시작하면 이 파일부터 읽는다. 프로젝트 원칙은 `CLAUDE.md`, 연동 규격은 `docs/GUARDIAN_INTEGRATION.md`(v2.1), 서버 담당자에게 받을 정보는 `docs/SERVER_REQUIREMENTS.md`.

---

## 1. 한 줄 요약
보호자 앱 전체 기능(Mock) + **팀원 검토(`INTEGRATION_REVIEW.md`) 합의 반영** + **실제 서버 연동용 코드(Firebase Auth·Firestore 구독·서버 API·FCM 수신)** 까지 구현했다. 실제 연결은 **팀원 Firebase 프로젝트에 보호자 앱 등록 + 서버 완성** 후에 한다. 역할: 고령자 앱·서버(FCM 발송)는 팀원, 보호자 앱(FCM 수신)은 나. 첫 커밋(`10d6efa`) 이후 변경은 커밋 안 함.

## 2. 현재 상태

### 11-26: 새 저장소 이동 · 실제 서버 연동 준비
- **위치 변경**: `~/Desktop/해봄/haebom_guardian` ← GitHub `Haebom-2026/haebom-guardian`, 브랜치 `feature/guardian-app`. 옛 `바이브 코딩/guardian_app`과 내용 동일 확인 후 복사(`config/firebase.json`은 사용자가 직접 복사)
- **GitHub 단계별 올리기 (7단계 중 3단계까지 push)**: 1 프로젝트 설정 `7e14f88` · 2 데이터 모델 `6062fa7` · 3 Mock 서버·저장소 `4ea1c4a` / 남음: 4 화면·알림 · 5 서버 연동 · 6 테스트 · 7 문서. **사용자가 "올려"라고 할 때만** push. PR은 7단계 뒤 (gh CLI 없음 → 웹에서 생성). 앱은 5단계부터 빌드됨
- **사용자 결정**: 고령자 ↔ 보호자 **다대다 유지**, 엔드포인트·DB 구조·UI 변경 없음. 보호자 화면은 연결된 어르신이 1명이면 필터 숨김(이미 구현)
- **구현 (11-26)**
  - Firestore 구독 자동 재연결: `lib/repositories/server/resilient_stream.dart`, links·가족별 알림·승인 모두 적용. `GuardianStore` 오류를 구독별로 관리(다른 구독 데이터로 오류가 지워져 무한 로딩되던 회귀를 테스트가 잡아 수정)
  - 보호자 프로필 등록 재시도: `lib/services/profile_registrar.dart` (15초→최대 5분, 앱 복귀 시 즉시, 성공 시 FCM 재등록)
  - API 재시도: 401 → 토큰 갱신 1회, 403 `profile-required` → 프로필 등록 후 1회 (같은 Idempotency-Key). 503 재시도는 안 함(이유: `ALIGNMENT_CHECKLIST.md` 2장)
- **검증**: `flutter analyze` 0건, `flutter test` **144개 통과**(새 `test/reconnect_retry_test.dart` 20개). 기기: Android 에뮬레이터 app_flow·settings·server_emulator 통과(server_emulator 첫 실행 1회 실패 후 4회 연속 통과 — 11-25와 같은 현상, 첫 실패 로그 미확보), **Fold3** app_flow·server_emulator 통과
- **통일 규격 정리**: `docs/ALIGNMENT_CHECKLIST.md` (결정 필요 4개: 서버 담당·서버 방식·readBy 직접 쓰기·호칭 필드)
- 실제 서버 연결은 `GO_LIVE_CHECKLIST.md` 3장(서버 주소 넣는 법) → 4장 순서
- **UI/UX 개편 (11-26 저녁, 사용자 확정안)** — 비즈니스 로직·API·Firebase·DB·권한·알림 수신/재시도 변경 없음. 1차 개편(홈 바로 승인·색 막대 카드·잎사귀 아이콘)은 "조잡하다"는 피드백으로 대체됨
  - 사용자 결정: "부모님의 작은 성취"는 **제외**(완료 데이터를 수집하지 않음 — 앱 이용 알림은 "사용하려고 한다", 승인 완료는 "안내 계속 허락"일 뿐). 하단 탭은 **홈·알림·승인·가족 유지**, 설정 위치 유지
  - 디자인 규칙 `lib/app/theme.dart`: `Space`(좌우 20·섹션 24·카드 간격 12·안쪽 16·모서리 14·버튼 56), `HaebomTokens`(라이트·다크 의미별 색, 브랜드 노랑 #FFD34E·녹색 #245D45·주의 #FFF1E5/#A34114·긴급 #FDECEA/#B3362A). 글자색 조합 모두 4.5:1 이상 계산 확인, 노랑은 글자색으로 쓰지 않음
  - 홈 순서: 로고·설정 → 가족(1명이면 "어머니 (김순자)", 여러 명이면 칩) → **도움이 필요한 일**(확인 전 SOS → 도움 필요 → 승인 대기, 각 "확인하기"/"요청 확인하기" → 기존 상세. 홈에서 바로 승인·거절 없음) → **확인하지 않은 알림**(일반 알림만, 최대 3) → **최근 소식**(확인한 알림·처리된 승인 최대 3) → 알림 기록/승인 기록 버튼. 같은 항목이 두 곳에 나오지 않음. 없으면 "지금 확인할 요청이 없어요 / 새로운 승인 요청이 오면 알려드릴게요."
  - 알림 탭: 날짜별(오늘·어제·날짜) 목록, 카드 없이 구분선, 확인 전 = 굵은 제목 + 녹색 점(낭독 "확인 전"). 승인 탭: 탭 없이 "응답이 필요한 요청"(주황 상자) 위, 회색 띠 아래 "지난 요청"(아이콘 + 상태 글자). 가족 탭: 이름 아바타, 해제는 ⋯ 메뉴(확인 창 유지), "가족 연결" 버튼. 설정: 알림 받기 / 잠금 화면 / 연결 상태 / 정보 / 개발자 섹션
  - 앱 아이콘: 녹색 #245D45 + 노란 햇살 (Android 적응형·테마·iOS 전 크기), 알림 작은 아이콘 흰 햇살 `@drawable/ic_stat_haebom` + FCM 기본 아이콘·색 메타데이터. 앱 안 로고 `BrandMark`도 같은 모양
  - 검증: analyze 0건, `flutter test` **157개 통과**(레이아웃 5개 화면 × 글자 1.0/1.5/**2.0**배, 접근성 터치 48×48·버튼 라벨·글자 명암비 라이트/다크). 기기: 에뮬레이터 app_flow·settings·server_emulator, Fold3 app_flow·server_emulator 통과. 에뮬레이터 라이트·다크 캡처 확인
  - 미검증: iPhone 실기기 화면, 실제 서버 데이터로 본 화면

### 11-25 밤: 고령자 앱 `해봄_개발지침서.md` 비교 → 공통 데이터 규격 v2.2 반영 (`docs/DATA_SPEC_CHANGES.md`)
- 가족 호칭 `elderLabel`(보호자가 부르는 호칭) / `guardianLabel`(어르신이 부르는 호칭, 고령자 앱 안내용) 분리. 연결 화면에서 둘 다 선택. 옛 `relationship`은 elderLabel로 읽음
- 알림 `level`·`category`·`reason`, 승인 `category` (선택 필드, 없어도 동작). 위험도 색: 일반 그린 / L2·막힘 주황 / L3·SOS·사기 의심 빨강, 사기 의심 라벨·문구, 이유·분류 표시
- 승인 action 4개 문구, 막힘 알림 `help_alerts`(최상) 채널, 사기 의심 → `sos_alerts`
- 문구: "토스를 사용하려고 합니다", 상태 "응답 시간 지남"/"요청 취소됨", 만료·취소 안내. 승인 버튼 문구는 유지
- 개발자 화면: "사기 의심 SOS (L3)", "송금 화면 요청" 버튼
- `flutter test` **124개 통과**(새 `test/data_spec_v22_test.dart` 16개). `server_emulator_test`·`app_flow_test` Android 에뮬레이터 통과 (server_emulator_test는 첫 실행 1회 실패 후 3회 연속 통과, 첫 실패 원인 미확인)
- 미합의: 서버 구현 주체·방식(지침서는 보호자 앱 담당 + Firebase Functions라고 적었으나 협의 안 됨), 전화 걸기(전화번호 저장 방식), readBy 직접 쓰기

### 구현 완료 (자동 테스트로 검증)
- 홈 / 알림 / 승인 / 가족 / 설정 / 개발자 테스트 화면
- Mock 서버(`MockBackend`): 민감 앱 알림(**10분** 중복 방지), 승인 상태 전이, 여러 보호자 동시 응답, 연결 코드(10분·일회용·5회 실패 잠금·**재발급 시 이전 코드 무효화**), 보호자·**고령자 양쪽 연결 해제**, **SOS 앱 정보(선택)**
- **"확인했어요" 버튼**: 상세를 열기만 해서는 확인 안 됨. 목록 표시는 "확인 전"/"모두 확인(확인 창)"
- 등본 시나리오 6단계: 이용 알림 → 메뉴 안내 → **본인 인증 단계 승인 요청(보호자 응답 대기, 거절·만료 시 중단, 만료 시 SOS 문자 제안)** → 직접 인증 → **고령자 동의 후** 도움 필요 알림 → 완료
- 로컬 알림 채널 3개, 알림 탭 → 상세 이동, 잠금 화면 최소 문구, 설정 기기 저장
- **실제 서버 모드** (`--dart-define-from-file=config/firebase.json`, 기본은 Mock)
  - `lib/app/backend_config.dart`: Firebase 값을 빌드 값으로 받음 (google-services.json 없이 초기화), 값 없으면 안내 화면
  - `lib/repositories/server/server_repository.dart`: links → 가족별 notifications/approvals 실시간 구독, readBy 직접 쓰기
  - `lib/repositories/server/guardian_server_api.dart`: Bearer ID 토큰, Idempotency-Key(UUID v4), 오류 reason → 오류 코드, 경로는 `ServerEndpoints` 한곳
  - `lib/repositories/server/server_url.dart`: 서버 주소 = 고정값 또는 Firestore `config/server.baseUrl`
  - `lib/services/push_service.dart`: FCM 권한·토큰·서버 등록·갱신·재시도, 포그라운드 메시지 표시, 알림 탭(백그라운드·종료 상태) → 상세
  - `NotificationService`: **로컬 알림 ↔ 원격 푸시 중복 방지** (문서 ID 단위 1회, 원격 푸시 활성 시 앱이 앞에 있을 때만 저장소 기반 알림, 오래된 문서 무시)
  - 설정 화면 "원격 알림" 상태 (사용 중 / 서버 연결 대기 / 사용할 수 없음 / 권한 꺼짐)
  - AndroidManifest: FCM 기본 채널 `family_activity`
- 승인 버튼 **"계속해도 돼요" / "잠깐 멈춰요"** (세로 배치, 확인 창·결과 문구도 변경, 내부 값 approved/rejected 유지)
- 리뷰 수정(11-25 저녁): 서버가 읽기를 거부하면 홈 무한 로딩 대신 안내 / 한 가족 쿼리 실패해도 나머지 목록 유지 / 디버그 빌드에서 FCM 토큰 표시·복사(설정 화면, 로그인 실패 화면) / data 없는 FCM 메시지(콘솔 테스트)도 앱이 앞에 있을 때 제목·본문으로 표시
- `flutter analyze` 0건, `flutter test` **108개 통과**, `integration_test/app_flow_test` Android 에뮬레이터 통과(11-25 저녁)

### 실행 검증 결과
| 환경 | 결과 |
|---|---|
| **서버 모드 (Firestore 에뮬레이터)** `integration_test/server_emulator_test.dart` | ✅ **iOS 시뮬레이터 · Android 에뮬레이터 · 실제 Fold3** 모두 통과 (11-25 밤): links 실시간 수신 → 일반·도움 필요·SOS 수신 → 로컬 알림(채널·최소 문구) → 중복 방지 → 탭 경로로 상세 이동 → "확인했어요" readBy 기록 → 승인("계속해도 돼요") → 가족 연결 → 연결 해제 시 목록 제거. 승인·연결 API는 테스트용 흉내 구현 |
| Fold3 Mock | ✅ (11-25 밤) `app_flow_test` 통과, 최신 Mock 빌드 설치·실행 |
| Android 에뮬레이터 (API 37) | ✅ (11-24) 로컬 알림·승인 흐름 / ✅ (11-25) Firebase 패키지 포함 Mock 모드 시작, 서버 모드 설정 값 없음 → 안내 화면 |
| 실제 Galaxy Z Fold3 | ✅ (11-24) 전체 흐름 / ✅ (11-25 밤) 위 자동 테스트 2종 / ❓ 새 문구·버튼 화면 수동 확인 |
| iOS 시뮬레이터 빌드 | ✅ (11-25) Firebase 패키지 포함 `flutter build ios --simulator` 성공 (SPM) |
| 실제 iPhone 14 Pro | ✅ (11-25 밤) 최신 Mock 빌드 설치, **사용자 수동 확인 "된다"**: 앱 실행 중 알림 표시·승인·상세 흐름 / 서버 모드 에뮬레이터 실기기 검증은 맥 방화벽(java) 때문에 안 함 — iOS 시뮬레이터로 대신 통과 |
| 실제 Firebase·서버·FCM 원격 푸시 | ❌ 미검증 (프로젝트 앱 등록·서버 필요) |

## 3. 내린 결정 (왜 이렇게 했는지)
| 결정 | 이유 |
|---|---|
| 역할 분담: 서버·FCM 발송은 팀원, 보호자 앱은 FCM 수신만 (11-25) | 사용자 결정. 맥북 Node 서버 계획(`docs/archive/SERVER_PLAN_mac_server_2026-11-25.md`)은 취소 |
| 등본 시나리오에 **승인 요청 다시 추가** (11-25) | 팀원 검토 #5: 고령자 앱이 정부24 본인 인증 단계에서 이미 승인을 요청함, 공모전 시연 포함 합의 (11-24의 "승인 제거" 결정을 뒤집음) |
| 도움 필요는 고령자 동의 후에만 | 팀원 검토 #10: "예일 때만 전송" 원칙, 45초 자동 전송은 오탐 |
| "확인했어요" 버튼으로만 readBy 기록 | 팀원 검토 #9: 연 것만으로는 확인이라 하기 어려움 |
| Firebase 값을 `--dart-define-from-file`로 주입, 설정 파일은 Git 제외 | 공유 프로젝트에 앱 등록 전에도 빌드 가능, 프로젝트를 바꿔도 코드 수정 없음 |
| 알림·승인 구독을 **가족(elderId)별 쿼리**로 | 보안 규칙의 `exists(links/{elderId}_{uid})` 검사를 쿼리가 통과하려면 elderId가 고정돼야 함 |
| FCM은 기존 **등록 토큰**(`getToken`, deprecated) 사용 | firebase_messaging 17의 새 방식(Installation ID direct-send)은 서버 발송 방식과 맞춰야 함 → 서버 담당자 확인 전까지 Admin SDK 표준 방식 |
| **iPhone은 원격 푸시 없이 앱 실행 중 실시간 수신 + 로컬 알림** (11-25 사용자 확정: 시연은 앱을 켜 놓고 진행) | APNs 키는 Apple 유료 계정 필요. Push Notifications capability를 추가하면 무료 서명이 깨져서 추가하지 않음 |
| 이용 알림도 팝업(중요도 high) | 사용자 요청. 기존 설치본은 재설치해야 채널 반영 |
| 등본 시나리오 중복 방지 선택 창 | 연달아 실행 시 1단계 생략 혼란 (규칙은 10분 그대로) |
| Android `compileSdk = 37`, import `material_ui` | 의존성·Flutter 3.50 |

## 4. 다음에 할 일

### ✅ 11-25 밤: `copilot-demo-c9a74`에 보호자 앱 등록 완료 (Firebase CLI, 사용자 계정 로그인)
- Android `com.yju.haebom.guardian_app` → 앱 ID `1:291903535200:android:5e39142024e7c69ef0ab05` ("해봄 가족 Android")
- iOS `com.yju.haebom.guardianApp` → 앱 ID `1:291903535200:ios:b286019a64a89e42f0ab05` ("해봄 가족 iOS")
- 기존 앱(고령자 쪽이 등록): 부모 `com.example.copilot.parent`, 보호자 `com.example.copilot.guardian`, guardian_app `kr.ac.yju.guardian.guardian_app`/`…guardianApp` — 건드리지 않음
- `config/firebase.json` 생성(Git 제외, 권한 600). 실행: `flutter run --dart-define-from-file=config/firebase.json -d <기기>`
- Android 에뮬레이터 서버 모드 실행 결과: **익명 로그인 성공**(이미 켜져 있음), Firestore 읽기는 **PERMISSION_DENIED**(현재 규칙) → 홈에 안내 표시(정상), **FCM 토큰 발급 성공**, 프로필 등록은 서버 주소 없음으로 실패(정상)
- ✅ **실제 FCM 원격 푸시 수신 확인 (Android 에뮬레이터, 11-25 12:32~12:43, Firebase 콘솔 메시지)**
  - 앱 화면이 열려 있을 때: 앱이 로컬 알림으로 표시 (채널 family_activity)
  - 백그라운드(홈 화면): 상단 팝업 알림 표시
  - 종료 상태(`am kill`, 강제 중지 아님): 알림 표시 → 누르면 앱 실행(콘솔 메시지라 문서 ID 없음 → 홈)
  - ⚠️ 첫 메시지는 테스트가 아니라 캠페인으로 **게시**됨(상태 "완료"). 대상 앱 확인 필요 — 해봄 가족 Android만이면 영향 없음, 다른 앱이 포함됐으면 팀원에게 알림
- 다음: 폴드3에서 같은 확인(무선 연결 불안정 → USB 권장), 서버 담당자 보안 규칙 배포 후 실제 데이터 확인

### ▶ 실제 연결 최종 준비 → `docs/GO_LIVE_CHECKLIST.md` (누가·무엇을·순서, 설정 파일, 연결 후 확인 순서)
- [x] iPhone 최신 버전 설치·Mock 수동 확인 (11-25 밤, 사용자 확인). 처음엔 Mac이 USB로 인식 못 함 → 케이블 다시 연결 후 해결

### 검증 방법 (서버 없이 실제 Firestore SDK로) → `tool/firebase_emulator/README.md`
- 에뮬레이터: `cd tool/firebase_emulator && npx -y firebase-tools emulators:start --project demo-haebom` (JAVA_HOME 필요)
- 실기기 Android는 `adb reverse tcp:8080 tcp:8080`(+9099) 후 주소 `127.0.0.1`
- iOS SDK는 API 키 형식을 검사하므로 가짜 키도 `AIza…`(39자) 형식이어야 함 (처음에 이것 때문에 앱이 시작하자마자 꺼졌음)

### 바로 할 수 있는 것 (서버 없이)
- [ ] 폴드3·iPhone에 11-25 버전 설치 후 수동 확인 (확인했어요 버튼, 등본 시나리오 승인 단계, 고령자 쪽 해제)
- [ ] 앱 아이콘 (FCM 알림 작은 아이콘도 현재 앱 아이콘 → Android에서 흰 사각형으로 보일 수 있음)
- [ ] 보호자 이름 입력 (프로필 생성 시 지금은 "보호자" 고정)

### ▶ 서버 없이 FCM 수신 테스트 → `docs/FIREBASE_CONSOLE_GUIDE.md`
- [ ] 소유자 동의 → 사용자가 콘솔에서 보호자 Android 앱 등록 → `google-services.json` 위치를 Claude에게 → Claude가 `config/firebase.json` 작성 → 폴드3에 서버 모드 설치 → 로그의 FCM 토큰으로 콘솔 "테스트 메시지 전송" → 앞/백그라운드/잠금/종료 상태 수신 확인 → 캠페인 초안 삭제

### 서버 담당자·프로젝트 소유자에게 받을 것 → `docs/SERVER_REQUIREMENTS.md`
- [ ] Firebase 프로젝트 ID·Sender ID, 보호자 Android·iOS **앱 등록**(소유자 동의) 후 API 키·앱 ID → `config/firebase.json`
- [ ] 서버 API 확정본(REST/Callable, 경로, 서버 주소 전달, 오류 형식), FCM payload·발송 대상(토큰/FID)
- [ ] 보안 규칙이 보호자 앱 쿼리를 허용하는지
- [ ] 콘솔 확인 목록(요금제·권한·익명 로그인·FCM API 등)은 사용자가 직접 확인 (같은 문서 5장)

### 받은 뒤
1. `config/firebase.json` 작성 → `flutter run --dart-define-from-file=config/firebase.json -d <기기>`
2. 설정 → "원격 알림: 사용 중" 확인 → 서버 테스트 발송 → Android **앱 종료·잠금 화면** 수신, 탭 → 상세
3. 승인·연결·해제 실제 서버로 확인 → iPhone 데이터 연동 확인

### 사용자가 할 것
- [ ] 팀원에게 `INTEGRATION_CHANGES.md`(0장 v2.1) + `SERVER_REQUIREMENTS.md` 전달
- [x] Firebase 프로젝트: **`copilot-demo-c9a74` 공동 사용** (2026-11-25 사용자 결정) → 소유자에게 보호자 앱 등록 동의 받기
- [ ] (시뮬레이터가 필요할 때만) Xcode 재설치
- [ ] `flutter doctor --android-licenses`

### iPhone 수동 확인 (11-24에서 이어짐)
1. 케이블 연결·잠금 해제 → `xcrun devicectl list devices`
2. `flutter run -d 00008120-000C615C0A28C01E --debug`
3. 알림 권한, 4개 탭 레이아웃, 등본 시나리오(홈 화면으로 나가서 알림 확인, 승인 단계에서 승인), 알림 탭 이동, "확인했어요", 잠금 화면 최소 문구, 설정 유지

### 하지 말 것 (요청 전까지)
공유 Firebase 프로젝트 설정·데이터·규칙 변경, 앱 등록(소유자 동의 전), Blaze·결제 카드, 별도 서버 구축, `git push`

## 5. 환경 · 바로 실행하는 명령

```bash
export PATH="$HOME/development/flutter/bin:$HOME/Library/Android/sdk/platform-tools:$HOME/Library/Android/sdk/emulator:$PATH"
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"     # Android 빌드
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer                     # xcode-select 미설정이라 필요
cd ~/Desktop/해봄/haebom_guardian

flutter analyze && flutter test
flutter build apk --debug
```

- Flutter 3.50.1 / Dart 3.14.0 (`~/development/flutter`), Xcode 27.2(불완전), Android SDK platform 37.0
- `~/.zshrc`에는 아직 PATH를 추가하지 않았다

### Android 에뮬레이터
```bash
emulator -avd Medium_Phone_API_37.0 &
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell monkey -p com.yju.haebom.guardian_app -c android.intent.category.LAUNCHER 1
```

### 실제 Android 폰 (무선 디버깅)
- Mac과 폰이 같은 Wi-Fi에 있어야 한다(`192.168.0.x`). Mac은 192.168.0.15, 폰은 192.168.0.7이었다
- **이미 페어링되어 있다.** 폰의 무선 디버깅 화면에 나온 최신 `IP:포트`로 연결만 하면 된다. 포트는 무선 디버깅을 켤 때마다 바뀐다
  ```bash
  adb connect 192.168.0.7:<포트>
  adb -s 192.168.0.7:<포트> install -r build/app/outputs/flutter-apk/app-debug.apk
  ```
- 페어링이 풀렸다면, 폰에서 "페어링 코드로 기기 페어링" 화면을 연 채로 `adb mdns services`를 실행해 `_adb-tls-pairing` 포트를 찾고 `adb pair <IP:포트> <코드>`
- `No route to host`가 나오면 `adb kill-server && adb start-server` (macOS 로컬 네트워크 권한 문제였다)
- 알림 권한 재설정: `adb shell pm grant com.yju.haebom.guardian_app android.permission.POST_NOTIFICATIONS`

### 실제 폰 자동 조작 시 주의 (Fold3)
- 화면이 2개라서 캡처할 때 디스플레이 지정이 필요하다: `adb exec-out screencap -p -d 4630947232161729154`, 터치는 `adb shell input -d 0 tap X Y`
- **고령자 앱(팀원 앱)의 화면 위 안내창**(파란 마이크·빨간 SOS·하단 안내 패널)이 아래쪽 메뉴(설정 → 개발자 테스트 모드)를 가린다. 하단 패널의 "✕ 그만하기"(약 1562, 2062)만 눌러서 닫았다. 그 앱의 다른 기능은 건드리지 않는다. Tab 키 포커스도 그 창으로 넘어가므로 Enter를 보내지 말 것
- 스크롤은 안내 패널 위쪽 영역에서: `adb shell input -d 0 swipe 500 1400 500 350 500`
- 삼성 팝업 스타일이 **"간략히"(edge_lighting=1)** 라 팝업이 아이콘처럼 작게 보인다. 크게 보려면 폰 설정 → 알림 → 알림 팝업 스타일 → "자세히"

### 실제 iPhone (케이블)
- 기기: iPhone14 (iPhone 14 Pro, UDID `00008120-000C615C0A28C01E`)
- 서명: Xcode Personal Team `T95YPRLR85`, 자동 서명. `ios/Runner.xcodeproj/project.pbxproj`에 `DEVELOPMENT_TEAM` 3줄 추가됨(Xcode가 `objectVersion` 54→60도 변경)
- **무료 계정이라 설치 후 7일이 지나면 앱이 안 열린다** → 다시 `flutter run`
- 페어링이 `UserDeniedPairing`으로 실패하면: 아이폰 잠금 해제 → Finder 왼쪽 목록의 iPhone 클릭 → "신뢰" → 아이폰에서 신뢰·암호 → `xcrun devicectl manage pair --device <UDID>`. (사용자는 개인 폰이라 "위치 및 개인정보 보호 재설정"은 원하지 않음 — 권하지 말 것)
- Xcode에서 프로젝트를 열면 `ios/RunnerTests/RunnerTests.swift`에 빈 줄이 추가되는 일이 있다 → `git checkout ios/RunnerTests/RunnerTests.swift`
- 처음 실행 시 "신뢰하지 않는 개발자" → 아이폰 설정 → 일반 → VPN 및 기기 관리 → 개발자 앱 → 신뢰

### iOS 시뮬레이터 (화면 없이)
```bash
xcrun simctl boot 799AF53B-EFE9-4AA7-A3EB-4986CD280B06    # iPhone 18 Pro
flutter build ios --simulator --debug
xcrun simctl install booted build/ios/iphonesimulator/Runner.app
xcrun simctl launch booted com.yju.haebom.guardianApp
flutter test integration_test -d 799AF53B-EFE9-4AA7-A3EB-4986CD280B06
```
CocoaPods 없이 Swift Package Manager로 빌드된다.

## 6. 앱 안에서 테스트하는 방법
**⚙︎ 설정 → 맨 아래 개발자 → 개발자 테스트 모드** (디버그 빌드에서만 보임)

| 섹션 | 내용 |
|---|---|
| 대상 고령자 | 어머니(김순자)·아버지(이정호)는 연결된 가족, 박말순은 미연결 (연결 코드 테스트용) |
| ⓪ 등본 발급 따라하기 | "알림에 상세 내용 표시" 켜기 → 시작 → 약 8초 뒤 **승인 요청** 알림 → 승인하면 이어서 도움 필요 알림 (총 알림 2개 + 승인 1개). 10분 안에 다시 시작하면 선택 창 |
| ① 민감 앱 진입 | 정부24·KB스타뱅킹·카카오뱅크·토스 / 예·아니요·닫기·중복 |
| ② 승인 요청 | 생성(팝업 알림) → 알림 누르면 상세 → 승인/거절 → "고령자 앱 수신 결과"에서 확인, 만료시키기·고령자가 취소·여러 보호자 동시 응답 |
| ③ 가족 연결 코드 | 발급(이전 코드 무효화) / 만료된 코드 발급 / 고령자가 나와 연결 해제 / 코드 입력 화면 |
| ④ 읽음 상태 · ⑤ SOS·도움 필요 · ⑥ 초기화 | |

Mock 데이터는 메모리에만 있다. 앱을 완전히 종료하면 초기 상태로 돌아간다.

## 7. 주요 파일
| 파일 | 역할 |
|---|---|
| `lib/repositories/guardian_repository.dart` | UI가 의존하는 인터페이스와 오류 코드 (나중에 FirebaseRepository로 교체) |
| `lib/repositories/mock_backend.dart` | 서버 규칙 시뮬레이션 (중복·권한·상태 전이·연결 코드) |
| `lib/services/notification_service.dart` | 로컬 알림 채널, 문구, 클릭 시 이동 |
| `lib/screens/developer/developer_screen.dart` | 개발자 테스트 화면 |
| `lib/screens/developer/gov24_scenario.dart` | 등본 발급 시나리오 |
| `lib/utils/formatters.dart` | 알림·승인 문구 (`approvalAlertDetail` 등) |
| `test/` | 단위·위젯 테스트 63개 (`helpers.dart`의 TestEnv·FakeClock·FakeNotifier) |
| `integration_test/app_flow_test.dart` | 기기 위 통합 테스트 |
| `lib/app/backend_config.dart` | Mock/서버 모드, Firebase 값 (`config/firebase.example.json`) |
| `lib/repositories/server/` | 실제 서버용 저장소(Firestore)·서버 API·서버 주소 |
| `lib/services/push_service.dart` | FCM 수신 |
| `docs/SERVER_REQUIREMENTS.md` | 서버 담당자에게 받을 정보, Firebase 프로젝트 확인 목록 |
| `../INTEGRATION_REVIEW.md` (바탕화면 `바이브 코딩/`) | 고령자 앱 담당자의 규격 검토 (11-25) |
| `docs/INTEGRATION.md` | 고령자 앱 연동 규격 (✅ 확정 / 💡 제안) |
