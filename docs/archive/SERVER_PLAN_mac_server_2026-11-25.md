# 해봄 공통 서버 구현 계획 (Node.js + Express + TypeScript, Firebase Spark)

> ⚠️ **보관본 — 사용하지 않음 (2026-11-25)**: 공통 서버와 FCM 발송은 서버 담당 팀원이 개발하기로 역할이 정해져, 보호자 앱 담당자가 맥북에 Node 서버·Cloudflare Tunnel을 만드는 이 계획은 취소되었다. 서버 담당자에게 필요한 정보는 `docs/SERVER_REQUIREMENTS.md`.

> 작성일: 2026-11-25 · 대상 규격: `docs/GUARDIAN_INTEGRATION.md` v2 (💡 고령자 앱 담당자 합의 전)
> 원칙: Blaze 가입·결제 카드 등록 없음 / 기존 고령자 앱 프로젝트(`copilot-demo-c9a74`) 변경 없음 / `MockBackend`·`MockGuardianRepository`·기존 자동 테스트 유지 / 승인·거절·가족 연결·도움 필요·SOS 모두 유지 / iPhone 코드 삭제 없음

---

## 1. 결정 사항 요약
| 항목 | 결정 |
|---|---|
| 서버 | Node.js 22 (설치됨 v22.19.0) + Express + TypeScript |
| Firebase | 해봄 공통 프로젝트 신규 생성(개인 Gmail), **Spark** — Auth(익명), Firestore(서울 `asia-northeast3`), FCM HTTP v1 |
| 서버 실행 | 맥북 `127.0.0.1:8787` + Cloudflare **Quick Tunnel** (계정·도메인 불필요, 무료) |
| 서버 주소 전달 | 서버가 시작할 때 터널 주소를 `config/server.baseUrl`에 기록 (Admin SDK만 쓰기 가능) |
| 테스트 | **Firebase Local Emulator Suite**(Auth·Firestore)로 실제 프로젝트 없이 자동 테스트. FCM은 가짜 발송기로 교체 |
| 코드 위치 | 💡 `guardian_app/server/` (같은 저장소, Flutter 빌드와 분리). 고령자 앱 담당자도 볼 수 있게 할지는 합의 |

### 1.1 현재 맥북 환경
| 도구 | 상태 | 조치 |
|---|---|---|
| Node.js / npm | ✅ v22.19.0 | – |
| Firebase CLI | ❌ | 서버 프로젝트의 개발 의존성(`firebase-tools`)으로 설치 → `npx firebase` 사용 (전역 설치 불필요) |
| cloudflared | ❌ (Homebrew도 없음) | GitHub 공식 릴리스의 macOS 바이너리를 `~/.local/bin`에 설치 |
| Java (에뮬레이터용) | ✅ Android Studio 내장 JBR | `JAVA_HOME` 지정 |

---

## 2. 서버 구조 (계획)
```
server/
├─ package.json            # express, firebase-admin, zod, helmet, express-rate-limit, pino
│                          # dev: typescript, tsx, vitest, supertest, firebase-tools, @firebase/rules-unit-testing
├─ tsconfig.json
├─ firebase.json           # 에뮬레이터 설정 (Auth 9099, Firestore 8080), 규칙·인덱스 경로
├─ .firebaserc             # 실제 프로젝트 ID (콘솔 생성 후)
├─ firestore.rules         # 보안 규칙 (GUARDIAN_INTEGRATION 3.3)
├─ firestore.indexes.json  # 승인 만료 조회용 복합 인덱스 (status + expiresAt)
├─ .env.example            # GOOGLE_APPLICATION_CREDENTIALS=~/.config/haebom/service-account.json 등 (실제 .env는 Git 제외)
├─ src/
│  ├─ index.ts             # 시작: 만료 정리 → 미발송 푸시 재처리 → 서버 시작 → 터널 주소 기록
│  ├─ app.ts               # Express 앱 (테스트에서 직접 사용)
│  ├─ config.ts            # 환경 변수 검증 (zod)
│  ├─ firebase.ts          # Admin SDK 초기화 (에뮬레이터/실제 자동 선택)
│  ├─ http/
│  │  ├─ auth.ts           # Bearer ID 토큰 검증 → req.uid, 역할 조회
│  │  ├─ errors.ts         # ApiError(reason) → HTTP 상태 + { error: { reason, message } }
│  │  ├─ idempotency.ts    # Idempotency-Key 처리
│  │  └─ rateLimit.ts      # IP(CF-Connecting-IP) 기준 제한
│  ├─ routes/              # users, devices, elder, guardian
│  ├─ domain/              # ★ MockBackend 규칙을 옮긴 곳 (순수 로직 + Firestore 트랜잭션)
│  │  ├─ links.ts          # 수신 보호자 결정, 연결 코드, 연결·해제
│  │  ├─ notifications.ts  # 민감 앱(dedupe), 도움 필요, SOS
│  │  └─ approvals.ts      # 생성·취소·응답·만료
│  ├─ push/
│  │  ├─ messenger.ts      # 발송 인터페이스: FcmMessenger(실제) / FakeMessenger(테스트)
│  │  ├─ payloads.ts       # 채널·문구 (보호자 앱 로컬 알림과 동일)
│  │  └─ worker.ts         # pushJobs 처리, 재시도, 무효 토큰 삭제
│  ├─ jobs/expiry.ts       # 승인 만료 (시작 시 + 30초마다)
│  └─ tunnel.ts            # cloudflared 실행 → 주소 파싱 → config/server 기록
├─ scripts/
│  └─ fake-elder.ts        # 고령자 앱이 완성되기 전 시연·테스트용: 익명 "고령자"로 로그인해 API 호출
└─ test/
   ├─ unit/                # 순수 규칙 (MockBackend 테스트를 옮김)
   ├─ api/                 # 에뮬레이터 + supertest로 엔드포인트 전체
   └─ rules/               # 보안 규칙 테스트
```

---

## 3. 단계별 구현 계획

각 단계는 **완료 조건(자동 테스트 또는 실행 확인)** 을 통과해야 다음으로 넘어간다. 1~8단계는 **실제 Firebase 프로젝트 없이 에뮬레이터로** 진행할 수 있어서 콘솔 작업과 팀원 합의를 기다리지 않고 시작할 수 있다.

| 단계 | 내용 | 완료 조건 |
|---|---|---|
| **S0 준비** | `server/` 생성, TypeScript·Express·firebase-admin 설치, `firebase-tools`(개발 의존성), cloudflared 바이너리 설치, `.gitignore`에 `.env`·`*service-account*.json`·`*-firebase-adminsdk-*.json` 추가 | `npm run build`, `npx firebase emulators:start` 실행됨 |
| **S1 뼈대·인증** | `GET /v1/healthz`, 오류 형식, 본문 10KB 제한, helmet, IP 속도 제한, **ID 토큰 검증 미들웨어**, `127.0.0.1`에만 바인딩 | 토큰 없음·위조·만료 → 401 `unauthenticated` 테스트 통과 |
| **S2 사용자·역할** | `POST/PATCH /v1/users/me`. 역할 최초 1회, 변경 시 409 `role-locked`, 프로필 없으면 403 `profile-required`. 역할별 라우트 보호 | 보호자가 고령자 API 호출 → 403, 역할 변경 → 409 테스트 |
| **S3 가족 연결** | 연결 코드 발급(암호학적 난수, 이전 미사용 코드 무효화 💡), `POST /v1/guardian/links` 트랜잭션, uid 5회·IP 10회 잠금, 양쪽 연결 해제 | `MockBackend` 연결 코드 테스트를 옮겨 모두 통과 (만료·사용됨·잘못됨·잠금·이미 연결) |
| **S4 알림** | `sensitive-entries`(dedupe 트랜잭션), `stuck`, `sos`, 수신자는 links에서 조회, `Idempotency-Key` | 같은 키 2회 → 문서 1개, N분 안 재진입 → `duplicate_suppressed`, 연결 보호자 없음 → `no_guardians`, 동시 요청 2개 → 문서 1개 |
| **S5 승인** | 생성·취소(본인만)·응답 트랜잭션, 만료 처리(시작 시 + 30초) | 동시 응답 2개 → 하나만 성공·하나 409, 만료 후 응답 → 409 `approval-expired`, **서버 재시작 시 밀린 만료 정리** 테스트 |
| **S6 푸시** | `PUT/DELETE /v1/devices`, `pushJobs`를 알림·승인 생성 트랜잭션에서 함께 생성, 워커 발송, 재시도(10초→30초→2분→5분, 최대 5회), 유효 기간, 무효 토큰 삭제, 재시작 시 재처리 | FakeMessenger로: 1회 발송만, 일시 오류 재시도, `UNREGISTERED` 토큰 삭제, 유효 기간 지나면 포기, 재시작 후 미발송 처리 |
| **S7 보안 규칙** | `firestore.rules`, `firestore.indexes.json` | 규칙 테스트: 연결된 보호자만 읽기, 해제 후 차단, `readBy` 자기 항목만, `users`·`config`·서버 전용 컬렉션 클라이언트 쓰기 거부 |
| **S8 터널·실행 스크립트** | `npm start` = 서버 + cloudflared Quick Tunnel 실행 → 주소 파싱 → `config/server` 기록, 종료 시 정리. 잠자기 방지(`caffeinate`) 포함 실행 스크립트 | (에뮬레이터) `config/server.baseUrl` 기록 확인 / `curl https://<터널>/v1/healthz` 200 |
| **S9 가짜 고령자 도구** | `npm run fake-elder -- sensitive gov24` / `stuck` / `sos` / `approval` / `code` | 에뮬레이터에서 보호자 흐름 전체를 고령자 앱 없이 재현 |
| — | **여기서부터 실제 Firebase 프로젝트 필요** (4장 콘솔 작업) | |
| **S10 보호자 앱 서버 모드** | `firebase_core`·`firebase_auth`·`cloud_firestore`·`firebase_messaging`·`http` 추가, `ServerGuardianRepository`(Firestore 구독 + REST + `readBy`), 익명 로그인 + `POST /v1/users/me`, `--dart-define=BACKEND=mock\|server`(**기본 mock**), 오류 reason 4개 대응 | `flutter analyze` 0건, **기존 67개 테스트 그대로 통과**, `ServerGuardianRepository` 단위 테스트 추가 |
| **S11 Android 원격 푸시** | FCM 토큰 등록·갱신, 알림 탭 → `AlertTarget` 이동(종료 상태 실행 포함), 서버 모드에서 Firestore 변경 기반 로컬 알림은 **앱이 앞에 있을 때만** | Galaxy Z Fold3: **앱 종료·화면 잠금** 상태에서 푸시 수신, 잠금 화면 최소 문구, 탭 → 상세 |
| **S12 iPhone 서버 연동** | 같은 서버 모드로 iPhone 실행. 원격 푸시는 등록하지 않음(APNs 없음), 실행 중 Firestore 변경 → 로컬 알림 | iPhone 14 Pro: 목록 실시간 반영, 승인·연결 동작, 실행 중 로컬 알림 |
| **S13 통합 시나리오** | `GUARDIAN_INTEGRATION.md` 13장 16개 시나리오 (고령자 앱 대신 fake-elder로 먼저) | 시나리오별 결과 기록 (`PROGRESS.md`) |
| **S14 고령자 앱 연동** | 팀원 합의 후 고령자 앱이 v2 API 호출 | 실제 두 앱으로 시나리오 재실행 |

### 3.1 테스트 구성 (기존 테스트와 분리)
| 종류 | 도구 | 실행 | 실제 프로젝트 사용 |
|---|---|---|---|
| 보호자 앱 기존 테스트 (Mock) | `flutter test` | 지금과 동일 | ❌ |
| 서버 규칙 단위 테스트 | vitest | `npm test` | ❌ |
| 서버 API 테스트 | vitest + supertest + 에뮬레이터 | `npm run test:api` (`firebase emulators:exec`) | ❌ (`demo-haebom` 가짜 프로젝트 ID) |
| 보안 규칙 테스트 | `@firebase/rules-unit-testing` + 에뮬레이터 | `npm run test:rules` | ❌ |
| 보호자 앱 서버 모드 단위 테스트 | `flutter test` (가짜 HTTP·Firestore) | `flutter test` | ❌ |
| 실기기 수동 확인 | Fold3, iPhone, fake-elder | 수동 | ✅ |

---

## 4. 직접 하실 Firebase 콘솔 작업

> **반드시 개인 Gmail 계정**으로 진행한다. 학교(Google Workspace) 계정은 조직 정책으로 서비스 계정 키 생성이 막혀 있을 수 있다.
> 기존 고령자 앱 프로젝트 `copilot-demo-c9a74`는 열지도, 바꾸지도 않는다.

### 4.1 프로젝트 만들기
1. https://console.firebase.google.com 접속 → **프로젝트 만들기**
2. 이름: `haebom` (프로젝트 ID는 자동 생성, 예: `haebom-1a2b3`) → **Google 애널리틱스·Gemini는 끄기** → 만들기
3. 왼쪽 아래 요금제가 **Spark(무료)** 인지 확인. **"업그레이드" 버튼은 누르지 않는다.**

### 4.2 Authentication (로그인)
1. 왼쪽 메뉴 **빌드 → Authentication → 시작하기**
2. **Sign-in method** 탭 → **익명** → 사용 설정 → 저장

### 4.3 Firestore
1. **빌드 → Firestore Database → 데이터베이스 만들기**
2. 위치: **`asia-northeast3 (Seoul)`** — ⚠️ 나중에 바꿀 수 없다
3. **프로덕션 모드**로 시작 (모든 접근 거부 상태. 실제 규칙은 S7에서 적용)

### 4.4 Cloud Messaging (푸시)
1. 톱니바퀴 → **프로젝트 설정 → 클라우드 메시징** 탭
2. **Firebase Cloud Messaging API (V1)** 가 "사용 설정됨"인지 확인 (보통 기본값). 이전 API(Legacy)는 켜지 않는다
3. Apple 앱 구성(APNs 인증 키)은 **비워 둔다** (유료 계정 필요)

### 4.5 앱 등록 — 둘 중 하나
- **방법 A (추천)**: 콘솔에서 등록하지 않고, 터미널에서 `! npx firebase-tools login` 으로 로그인만 해 주면 Claude가 `flutterfire configure`로 Android(`com.yju.haebom.guardian_app`)·iOS(`com.yju.haebom.guardianApp`) 앱을 등록하고 설정 파일을 만든다
- **방법 B**: 프로젝트 설정 → 내 앱 → Android 아이콘 → 패키지 이름 `com.yju.haebom.guardian_app` → `google-services.json` 다운로드 / iOS 아이콘 → 번들 ID `com.yju.haebom.guardianApp` → `GoogleService-Info.plist` 다운로드 → 파일 위치를 알려 주기
- 고령자 앱 등록은 **팀원 합의 후** (applicationId 확정 필요)

### 4.6 서비스 계정 키 (서버용 비밀 키) ⚠️
1. 프로젝트 설정 → **서비스 계정** 탭 → Firebase Admin SDK → **새 비공개 키 생성** → 키 생성
2. 다운로드된 파일을 바로 안전한 곳으로 옮기고 권한을 잠근다 (터미널):
   ```bash
   mkdir -p ~/.config/haebom && chmod 700 ~/.config/haebom
   mv ~/Downloads/*-firebase-adminsdk-*.json ~/.config/haebom/service-account.json
   chmod 600 ~/.config/haebom/service-account.json
   ```
3. **이 파일의 내용을 채팅·메신저·Git·클라우드 드라이브에 올리지 않는다.** Claude에게도 경로만 알려 주면 된다
4. "키 생성이 조직 정책으로 차단됨" 오류가 나면 학교 계정으로 만든 것이다 → 개인 Gmail로 다시 만든다
5. 키가 유출된 것 같으면: Google Cloud 콘솔 → IAM 및 관리자 → 서비스 계정 → 키 → **삭제** 후 새로 발급

### 4.7 팀원 초대 (합의 후)
프로젝트 설정 → **사용자 및 권한** → 팀원 이메일 추가. 💡 권한 범위는 합의 (편집자는 서비스 계정 키도 만들 수 있으므로 필요한 만큼만).

### 4.8 하지 말 것
- Blaze 업그레이드, 결제 계정 연결, Cloud Functions "시작하기"
- `copilot-demo-c9a74` 프로젝트 변경
- 서비스 계정 키 공유·커밋
- Firestore를 "테스트 모드"로 만들기 (30일간 누구나 읽기·쓰기 가능)

### 4.9 끝나면 Claude에게 알려 줄 것
- 프로젝트 ID (예: `haebom-1a2b3`, 비밀 아님)
- 서비스 계정 키를 `~/.config/haebom/service-account.json`에 두었는지 여부 (내용은 보내지 않음)
- 앱 등록 방법 A/B 중 무엇으로 할지

---

## 5. 보안 체크리스트
| 항목 | 방법 |
|---|---|
| ID 토큰 검증 | 모든 `/v1/*`(healthz 제외)에서 `verifyIdToken`, 실패 시 401 |
| 역할 임의 변경 방지 | `users` 클라이언트 쓰기 금지(규칙), 서버에서 최초 1회만 설정, 변경 시 409 |
| 연결 관계·권한 | 보호자 API는 `links/{elderId}_{uid}` + `guardianIds` 포함 확인, 고령자 API는 `elderId == uid` |
| 중복 요청·중복 FCM | `Idempotency-Key`, dedupe 트랜잭션, `pushJobs` 상태, Android `tag` |
| FCM 실패·재시도 | 10장 규칙, 무효 토큰 삭제, 재시작 시 재처리 |
| 서비스 계정 키 | 저장소 밖 600 권한, `.gitignore`, 로그·응답에 노출 금지, 유출 시 즉시 폐기 |
| 승인 만료 | 서버 시작 시 + 30초 + 앱 자체 판단 |
| `config/server` 쓰기 | 규칙 `allow write: if false` → Admin SDK(서버)만 가능 |
| 서버 노출 | `127.0.0.1` 바인딩, 터널로만 외부 접속, IP 속도 제한, 본문 크기 제한, 관리자용 엔드포인트 없음 |
| 로그 | 토큰·개인정보 미기록 |
| 연결 코드 대입 | uid 5회 + IP 10회 잠금, IP는 해시 저장 |

## 6. 위험과 대응
| 위험 | 대응 |
|---|---|
| 맥북 잠자기·종료 → 서버 중단 | 시연 중 전원 연결, `caffeinate`, 고령자 앱 실패 처리·자체 만료 |
| Quick Tunnel 주소 변경·일시 장애 | `config/server` 자동 갱신, 시연 전 리허설 |
| Spark 무료 한도 (Firestore 하루 읽기 5만·쓰기 2만) | 시연 규모에서는 충분. 실시간 구독 범위를 본인 관련 문서로 제한 |
| 고령자 앱 연동 지연 | `fake-elder` 도구로 보호자 앱·서버를 먼저 완성 |
| iPhone 원격 푸시 불가 | 실행 중 로컬 알림 + Android로 푸시 시연, 유료 계정 생기면 APNs 키만 추가 |
| 익명 로그인 → 앱 삭제 시 연결 끊김 | 시연 전 앱 재설치 금지, 실서비스 로그인은 합의 |
