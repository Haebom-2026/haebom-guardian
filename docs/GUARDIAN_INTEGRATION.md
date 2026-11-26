# 해봄(고령자 앱) ↔ 해봄 가족(보호자 앱) 연동 규격 v2.1 — REST 서버 방식

> 작성일: 2026-11-25 · 작성: 보호자 앱 담당
> **v2.2 변경(2026-11-25 밤):** 가족 호칭 `elderLabel`/`guardianLabel` 분리(`relationship` 대체), 알림 `level`·`category`·`reason`, 승인 `category`·action 4개, 도움 필요 채널 `help_alerts` → **`docs/DATA_SPEC_CHANGES.md`**. 이 문서 본문과 다르면 DATA_SPEC_CHANGES.md가 우선한다.
> 이전 버전(v1, Cloud Functions Callable 방식): `docs/archive/GUARDIAN_INTEGRATION_v1_callable_2026-11-25.md`
> v1 → v2 변경 내역과 합의가 필요한 사항: **`docs/INTEGRATION_CHANGES.md`**
> 기준 자료: 고령자 앱 담당자의 `고령자 앱 ↔ 보호자 앱 연동 분석.docx`(2026-11-24), 보호자 앱 실제 코드(`guardian_app/lib`), `docs/INTEGRATION.md` v0.1

---

## v2.1 갱신 (2026-11-25 오후) — 먼저 읽을 것

**역할 분담 정정**: 공통 서버와 FCM 발송은 **서버 담당 팀원**이 개발 중이다. 보호자 앱 담당자는 서버·터널을 만들지 않고 **보호자 앱과 FCM 수신**만 맡는다. 이 문서의 서버 관련 내용(4장·5장·10장·12장)은 서버 담당자가 확정할 **요청 사항(💡)** 으로 읽는다. 서버 담당자에게 필요한 확인 목록은 `docs/SERVER_REQUIREMENTS.md`.

**`INTEGRATION_REVIEW.md`(고령자 앱 검토, 2026-11-25) 합의 반영** — 보호자 앱 Mock·화면·테스트에 반영 완료(✅):
| # | 합의 | 보호자 앱 반영 |
|---|---|---|
| 1 | 중복 방지 시간: 고령자 앱 팝업·서버 모두 **10분** | ✅ `MockBackend.duplicateWindow` 10분 |
| 2 | 승인·거절 **유지**, 공모전 시연 포함, 유효시간 **5분** | ✅ 그대로 유지 |
| 3 | 승인 만료 시 고령자 앱은 안내 중단 + **SOS 문자 보낼지 묻기** | ✅ 개발자 화면 "고령자 앱 수신 결과"에 반영 |
| 4 | 도움 필요(`stuck`)는 **고령자가 동의("연락할게요")했을 때만** 전송 | ✅ 등본 시나리오에 동의 단계 반영 |
| 5 | SOS에 `appName`·`packageName` **선택 필드** 허용 (없으면 빈 문자열) | ✅ "어머니가 정부24 사용 중 SOS 도움 요청을 보냈습니다." |
| 6 | 보호자 **"확인했어요" 버튼**을 눌러야 `readBy` 기록 (상세를 열기만 해서는 기록 안 함) | ✅ 알림 상세 버튼, "확인 전"/"모두 확인" 표시 |
| 7 | 고령자·보호자 **모두 연결 해제 가능** | ✅ `MockBackend.disconnectByElder` + 테스트 |
| 8 | 연결 코드 **재발급 시 이전 미사용 코드 무효화** | ✅ |
| 9 | 정부24 등본 데모에 **승인 요청 추가** (본인 인증 단계) | ✅ 등본 시나리오 6단계 |
| 10 | 고령자 앱 연동 코드 상당 부분 구현됨(실행 미검증) — 6장 표 참고 | 문서 반영 |
| 11 | 서버는 `packageName`을 민감 앱 목록으로 검증하지 않고 받은 그대로 저장 | 💡 서버 담당자 확인 |
| 12 | 보안 규칙: 고령자 본인의 `links`·`notifications`·`approvals` 읽기 허용, `users.role`은 생성 시에만 | 💡 서버 담당자 확인 |
| 13 | 고령자 앱 `readBy` 구독("○○가 확인했어요")은 **2차** | – |

---

## 0. 먼저 읽을 것

### 0.1 표시 규칙
| 표시 | 뜻 |
|---|---|
| ✅ **구현됨** | 보호자 앱 코드에 있고 자동 테스트로 확인함 (**Mock 서버 기준**) |
| 🛠 **구현 예정** | 실제 서버·Firebase에는 아직 없음 |
| 💡 **제안·미합의** | 고령자 앱 담당자와 아직 합의하지 않음. 합의 전에는 확정 사양이 아님 |

> **v2 전체가 💡 제안이다.** 서버 방식(REST), 새 공통 Firebase 프로젝트, 엔드포인트, 인증 방식은 고령자 앱 담당자의 동의를 받아야 확정된다. 다만 **컬렉션·필드·값·오류 코드는 v1에서 바뀌지 않았다.**

### 0.2 v2의 서버 구조 (무료)
```
고령자 Android 앱 (Kotlin)                    보호자 앱 (Flutter, Android·iOS)
   │  ① Firebase Auth 로그인 → ID 토큰               │
   │  ② 쓰기 요청: HTTPS REST + Bearer 토큰          │  쓰기 요청: HTTPS REST (응답·연결·해제)
   │  ③ 읽기: Firestore 실시간 구독                   │  읽기: Firestore 실시간 구독, readBy만 직접 쓰기
   ▼                                                  ▼
(💡 외부 HTTPS 주소 — 서버 담당자가 확정. 보호자 앱은 고정 주소 또는 config/server 문서 둘 다 지원)
   ▼
해봄 공통 서버 — 💡 서버 담당 팀원이 개발 중 (기술·실행 위치는 서버 담당자가 확정)
   - ID 토큰 검증, 역할·연결 관계 권한 검사
   - 중복 방지, 상태 전이(Firestore 트랜잭션), 연결 코드 검증
   - FCM 발송·재시도, 승인 만료 처리
   ▼ Firebase Admin SDK (서비스 계정)
해봄 공통 Firebase 프로젝트 (신규, Spark 무료 요금제)
   - Authentication · Firestore · Cloud Messaging(FCM HTTP v1)
```

- **Cloud Functions를 쓰지 않는다** (Blaze 유료 요금제가 필요하기 때문). 서버 기능은 같은 규칙의 REST API로 제공한다.
- **기존 고령자 앱 프로젝트(`copilot-demo-c9a74`)는 변경하지 않는다.** 해봄 공통 프로젝트를 새로 만든다.
- Blaze 가입·결제 카드 등록은 하지 않는다.

### 0.3 고령자 앱 Claude Code에게 주는 작업 원칙
- 컬렉션명·필드명·값(소문자)·엔드포인트·오류 `reason`을 **임의로 바꾸지 않는다.** 바꿔야 하면 "💡 제안"으로 보호자 앱 담당자에게 먼저 알린다.
- 수신 보호자(`guardianIds`)는 **서버가 links 기준으로 정한다.** 고령자 앱은 보호자 UID를 보내지 않는다.
- 요청 본문에 **uid를 넣지 않는다.** 서버는 ID 토큰에서 uid를 얻는다.
- 동의 팝업에서 **"예"일 때만** 서버를 호출한다. "아니요"·"닫기"는 아무것도 보내지 않는다. `consent` 필드는 없다.
- 비밀번호·계좌번호·주민번호·화면 캡처·거래 내용은 보내지 않는다. 앱 **이용 사실**(앱 이름·패키지명)만 보낸다.
- 승인은 "거래 승인"이 아니라 **"도우미 진행 승인"**이다. 실제 금융 거래를 허락하거나 막지 않는다.
- 서버는 맥북에서 돌기 때문에 **언제든 꺼져 있을 수 있다.** 서버 호출 실패 시 앱이 멈추지 않게 하고, 승인 대기는 `expiresAt`이 지나면 **앱이 스스로 끝낸다**(8.4).
- 서버가 준비되기 전에는 `GuardianRepo` 인터페이스 + **Fake 구현**으로 개발한다.

---

## 1. 보호자 앱의 현재 구현 및 테스트 상태

### 1.1 구현 범위
| 기능 | 상태 |
|---|---|
| 홈 / 알림 목록·상세 / 승인 목록·상세 / 가족 연결·해제 / 설정 | ✅ Mock |
| 알림 3종 (`sensitive_entry`, `stuck`, `sos`), 보호자별 읽음(`readBy`) | ✅ Mock |
| 승인·거절, 남은 시간, 만료·취소, **먼저 온 응답만 반영** | ✅ Mock |
| 6자리 연결 코드 (10분·일회용·5회 실패 시 5분 잠금), 연결 해제 시 과거 기록 차단 | ✅ Mock |
| 기기 로컬 알림 (Android 채널 3개, iOS 권한), 잠금 화면 최소 문구, 설정 기기 저장 | ✅ (원격 푸시 아님) |
| 개발자 테스트 화면 (고령자 앱 + 서버 동작 흉내, 디버그 빌드 전용) | ✅ |
| Firebase Auth / Firestore / 서버 API / FCM 수신 | ✅ 보호자 앱 코드 구현(테스트는 가짜 Firestore·HTTP·FCM) / ❌ 실제 프로젝트·서버 연결 미검증 |

UI는 `GuardianRepository` 인터페이스에만 의존한다. 현재 구현체는 `MockGuardianRepository`(서버 규칙은 `MockBackend`)이며, 🛠 실제 서버용 `ServerGuardianRepository`를 **추가**한다. Mock 구현과 기존 테스트는 삭제하지 않고, 실행 옵션(`--dart-define=BACKEND=mock|server`, 기본값 mock)으로 고른다.

### 1.2 테스트 상태
| 항목 | 결과 |
|---|---|
| `flutter analyze` / `flutter test` | 이슈 0건 / **104개 통과** (기존 67 + 합의 반영·서버 연동 37) |
| `integration_test` | `app_flow_test` Android 에뮬레이터·iOS 시뮬레이터 통과, `settings_storage_test` 실제 Galaxy Z Fold3 통과 |
| 실제 기기 | Android 에뮬레이터·Galaxy Z Fold3 수동 확인 완료 / iPhone 14 Pro 설치·실행까지 (화면 수동 확인 전) |
| 실제 서버 연동 | 🛠 서버 없음 |

---

## 2. 공통 데이터 약속

| 항목 | 규칙 |
|---|---|
| 통신 | 두 앱은 직접 통신하지 않는다. **쓰기 = REST 서버, 읽기 = Firestore 실시간 구독** |
| 서버 주소 | Firestore `config/server` 문서의 `baseUrl`에서 읽는다 (3장). 앱에 주소를 고정하지 않는다 |
| 인증 | 모든 REST 요청에 `Authorization: Bearer <Firebase ID 토큰>` |
| 사용자 식별 | Firebase Auth UID. 요청 본문에 uid를 넣지 않는다 |
| 시간 | Firestore `Timestamp`(서버 시각). REST 응답에서는 ISO 8601 UTC 문자열 (예: `2026-11-25T03:12:00.000Z`) |
| 코드 값 | 모두 소문자. 고령자 앱 기존 규칙 파일의 대문자 `ENTRY/APPROVAL/SOS`, `PENDING/TIMEOUT`은 쓰지 않는다 |
| 문자 인코딩 | JSON UTF-8, `Content-Type: application/json` |

### 2.1 값 목록 (✅ 보호자 앱 코드와 동일, v1과 같음)

**알림 type**
| 값 | 뜻 | 보호자 앱 표시 문구 |
|---|---|---|
| `sensitive_entry` | 민감 앱 이용 (고령자가 "예" 선택) | "어머니가 정부24에 접속했습니다." |
| `stuck` | 앱 사용 중 도움이 필요해 보임 | "어머니가 정부24 사용 중 도움이 필요할 수 있습니다." (`appName`이 비면 "휴대폰 사용 중") |
| `sos` | SOS 버튼 | "어머니가 SOS 도움 요청을 보냈습니다." |

**승인 status**: `pending` → `approved` | `rejected` | `expired` | `cancelled`

**승인 action**
| 값 | 보호자 앱 표시 문구 |
|---|---|
| `guide_gov24_auth` | 정부24 본인인증 단계 안내 |
| `guide_bank_open` | 은행 앱 이용 안내 |
| `guide_unknown_app` | 처음 사용하는 앱 이용 안내 |
| (그 외) | "도우미 안내 진행" |

**민감 앱 목록** (💡 실기기 `adb shell pm list packages`로 최종 확인)
| 앱 | packageName | 기본 action |
|---|---|---|
| 정부24 | `kr.go.minwon.m` | `guide_gov24_auth` |
| KB스타뱅킹 | `com.kbstar.kbbank` | `guide_bank_open` |
| 카카오뱅크 | `com.kakaobank.channel` | `guide_bank_open` |
| 토스 | `viva.republica.toss` | `guide_bank_open` |

은행을 앱 이름 단어("우리", "하나")로 찾으면 오탐이 생기므로 **패키지명 목록**으로 구분한다.

---

## 3. Firestore 컬렉션 및 필드

**공유 컬렉션(두 앱이 읽음)의 필드는 v1과 같다.** v2에서 `config`와 서버 전용 컬렉션이 추가되었다. 🛠 실제 Firestore·보안 규칙은 구현 예정.

### 3.1 공유 컬렉션

**users/{uid}** — 💡 v2: 클라이언트 직접 쓰기 금지, `POST /v1/users/me`로만 생성
| 필드 | 타입 | 설명 |
|---|---|---|
| role | string `elder` \| `guardian` | **최초 1회만 설정, 이후 변경 불가** |
| name | string | 표시 이름 (고령자 앱에 이름 입력칸 필요) |
| createdAt | timestamp | |

**users/{uid}/devices/{deviceId}** — 서버 전용 쓰기 (`PUT /v1/devices/{deviceId}`)
| 필드 | 타입 | 설명 |
|---|---|---|
| fcmToken | string | |
| platform | string `android` \| `ios` | |
| updatedAt | timestamp | |

**links/{elderId}_{guardianId}** — 서버 전용 쓰기
| 필드 | 타입 | 설명 |
|---|---|---|
| elderId / guardianId | string | |
| elderName | string | 연결 시 `users/{elderId}.name` 복사 |
| relationship | string | 보호자가 입력한 호칭 (예: 어머니) |
| connectedAt | timestamp | |

**notifications/{id}** — 서버가 생성, 보호자는 `readBy.{자기 uid}`만 직접 쓰기
| 필드 | 타입 | 설명 |
|---|---|---|
| elderId | string | 서버가 토큰 uid로 채움 |
| guardianIds | array&lt;string&gt; | 서버가 links 기준으로 채움 |
| appName / packageName | string | SOS는 빈 문자열 |
| type | string | `sensitive_entry` \| `stuck` \| `sos` |
| createdAt | timestamp | |
| readBy | map&lt;string, timestamp&gt; | 보호자 UID → 읽은 시각 |

**approvals/{id}** — 서버 전용 쓰기
| 필드 | 타입 | 설명 |
|---|---|---|
| elderId / guardianIds / appName / packageName | | notifications와 같은 규칙 |
| action | string | 2.1 action 값 |
| status | string | `pending` \| `approved` \| `rejected` \| `expired` \| `cancelled` |
| createdAt | timestamp | |
| expiresAt | timestamp | 생성 + 5분 (💡 합의) |
| respondedAt | timestamp \| null | 승인·거절·취소 시각 |
| respondedBy | string \| null | 응답한 보호자 UID (취소·만료 시 null) |

**config/server** — 💡 v2 신규. **서버(Admin SDK)만 쓰기**, 로그인한 사용자 읽기
| 필드 | 타입 | 설명 |
|---|---|---|
| baseUrl | string | 현재 Quick Tunnel 주소 (예: `https://abc-def.trycloudflare.com`) |
| apiVersion | string | `v1` |
| updatedAt | timestamp | 서버가 시작될 때마다 갱신 |

### 3.2 서버 전용 컬렉션 (💡 v2 신규, 앱은 읽기·쓰기 모두 불가)
| 컬렉션 | 용도 |
|---|---|
| `connectCodes/{code}` | 연결 코드 `{ elderId, expiresAt, used }` (v1과 같음) |
| `dedupe/{elderId}_{packageName}` | 민감 앱 알림 중복 방지 `{ lastNotificationId, lastAt }` |
| `idempotency/{uid}_{key}` | 같은 요청 재전송 시 같은 응답 반환 `{ status, body, createdAt }` |
| `pushJobs/{kind}_{docId}` | FCM 발송 상태·재시도 `{ kind, targetId, guardianIds, status, attempts, nextAttemptAt, lastError, createdAt, sentAt }` |
| `rateLimits/{key}` | 연결 코드 실패 횟수·잠금 (uid 기준, IP는 해시로 저장) |

공유 컬렉션(`notifications` 등)에 서버용 필드를 추가하지 않기 위해 별도 컬렉션으로 분리했다.

### 3.3 보안 규칙 원칙 (🛠, 초안은 `docs/INTEGRATION.md` 5장 + 아래 변경)
- 쓰기는 **서버(Admin SDK)만**. 예외는 보호자의 `notifications.readBy.{자기 uid}` 하나뿐.
- `users/{uid}`: 본인 읽기만. **클라이언트 create·update 금지** (역할 임의 변경 방지) — v1 초안에서 변경.
- `notifications`·`approvals` 읽기: `guardianIds`에 포함 + links가 살아 있는 보호자, 또는 본인(`elderId`).
- `config/server`: `allow read: if signedIn(); allow write: if false;` — Admin SDK는 규칙을 거치지 않으므로 **서버만 쓸 수 있다.**
- 3.2 서버 전용 컬렉션: `allow read, write: if false;`

---

## 4. REST API (💡 v2, 🛠 미구현)

### 4.1 공통
| 항목 | 규칙 |
|---|---|
| 기본 주소 | `config/server.baseUrl` + `/v1` |
| 인증 | `Authorization: Bearer <ID 토큰>`. 서버는 Admin SDK `verifyIdToken`으로 검증하고 uid를 얻는다 |
| 역할 검사 | `/v1/elder/*`는 `users/{uid}.role == "elder"`, `/v1/guardian/*`는 `"guardian"`만 허용 |
| 중복 요청 방지 | 생성 요청(표의 🔁)은 `Idempotency-Key: <UUID v4>` 헤더 **필수**. 같은 uid·같은 키로 24시간 안에 다시 오면 **처음 응답을 그대로** 돌려주고 아무것도 새로 만들지 않는다. 앱은 **재시도할 때 같은 키를 다시 쓴다** |
| 요청 크기 | 본문 최대 10KB |
| 속도 제한 | IP당 분당 60회 (초과 시 429 `rate-limited`) |

### 4.2 엔드포인트
| 메서드·경로 | 호출 앱 | 요청 본문 | 성공 응답 | v1 함수 |
|---|---|---|---|---|
| `GET /v1/healthz` | 공통 (인증 없음) | – | `200 { ok: true, apiVersion: "v1" }` | – |
| `POST /v1/users/me` | 공통 | `{ role: "elder"\|"guardian", name }` | `200 { uid, role, name }` (이미 같은 역할이면 그대로 반환) | (신규) |
| `PATCH /v1/users/me` | 공통 | `{ name }` | `200 { uid, role, name }` | (신규) |
| `PUT /v1/devices/{deviceId}` | 공통 | `{ fcmToken, platform }` | `200 { ok: true }` | `registerDevice` |
| `DELETE /v1/devices/{deviceId}` | 공통 | – | `200 { ok: true }` | `unregisterDevice` |
| 🔁 `POST /v1/elder/sensitive-entries` | 고령자 | `{ packageName, appName }` | `200 { result: "created", notificationId }` / `{ result: "duplicate_suppressed" }` / `{ result: "no_guardians" }` | `reportSensitiveEntry` |
| 🔁 `POST /v1/elder/stuck` | 고령자 | `{ packageName, appName }` (앱 밖이면 빈 문자열) | `200 { result: "created", notificationId }` / `{ result: "no_guardians" }` | `reportStuck` |
| 🔁 `POST /v1/elder/sos` | 고령자 | `{ packageName?, appName? }` (선택) | `200 { result: "created", notificationId }` / `{ result: "no_guardians" }` | `createSos` |
| 🔁 `POST /v1/elder/approvals` | 고령자 | `{ packageName, appName, action }` | `200 { result: "created", approvalId, expiresAt }` / `{ result: "no_guardians" }` | `requestApproval` |
| `POST /v1/elder/approvals/{id}/cancel` | 고령자 (본인 요청만) | – | `200 { status: "cancelled" }` | `cancelApproval` |
| 🔁 `POST /v1/elder/connect-codes` | 고령자 | – | `200 { code, expiresAt }` | `issueConnectCode` |
| `DELETE /v1/elder/links/{guardianId}` | 고령자 | – | `200 { ok: true }` | `disconnect` |
| `POST /v1/guardian/approvals/{id}/respond` | 보호자 | `{ decision: "approve"\|"reject" }` | `200 { status, respondedAt }` | `respondApproval` |
| `POST /v1/guardian/links` | 보호자 | `{ code, relationship }` | `200 { elderId, elderName, relationship, connectedAt }` | `connectWithCode` |
| `DELETE /v1/guardian/links/{elderId}` | 보호자 | – | `200 { ok: true }` | `disconnect` |

- 읽음 처리: REST 없음. 보호자 앱이 Firestore `notifications/{id}.readBy.{uid}`에 직접 쓴다 (보안 규칙으로 제한).
- 조회: REST 없음. 두 앱 모두 Firestore 실시간 구독.
- `respond`·`cancel`은 상태 검사로 이미 중복이 막히므로 Idempotency-Key가 필요 없다 (두 번째 요청은 `already-responded` 등 오류).

### 4.3 오류 응답
```json
HTTP 409
{ "error": { "reason": "already-responded", "message": "이미 다른 보호자가 응답한 요청입니다." } }
```
| HTTP | reason | 언제 |
|---|---|---|
| 400 | `invalid-argument` | 필수 값 누락·형식 오류 |
| 400 | `invalid-code` | 코드 형식 오류(숫자 6자리 아님) 또는 없는 코드 |
| 401 | `unauthenticated` 💡신규 | 토큰 없음·만료·위조 |
| 403 | `permission-denied` | 역할 불일치, 연결되지 않은 사용자, 본인 것이 아닌 요청 |
| 403 | `profile-required` 💡신규 | `users/{uid}` 문서가 아직 없음 → `POST /v1/users/me` 먼저 |
| 404 | `not-found` | 문서 없음, 연결 해제됨 |
| 409 | `already-responded` | 다른 보호자가 먼저 응답 |
| 409 | `approval-expired` | 만료 후 응답 |
| 409 | `approval-cancelled` | 취소된 요청에 응답 |
| 409 | `code-used` | 이미 사용된 코드 |
| 409 | `already-linked` | 이미 연결됨 |
| 409 | `role-locked` 💡신규 | 이미 다른 역할로 가입된 계정이 역할 변경 시도 |
| 410 | `code-expired` | 발급 후 10분 경과 |
| 429 | `too-many-attempts` | 연결 코드 연속 실패 잠금 |
| 429 | `rate-limited` 💡신규 | 속도 제한 초과 |
| 503 / 네트워크 실패 | `unavailable` | 서버 꺼짐·터널 끊김·Firebase 오류 |

v1의 12개 reason은 그대로이며, 💡 4개(`unauthenticated`, `profile-required`, `role-locked`, `rate-limited`)가 추가되었다. 보호자 앱은 4개를 기존 오류 코드에 대응시켜 표시한다(🛠).

---

## 5. 인증·권한 (🛠 서버 구현 예정)

1. **로그인**: 앱 시작 시 Firebase Auth 로그인 (💡 시연은 두 앱 모두 **익명 로그인**. 앱을 지우면 uid가 바뀌어 연결이 끊긴다 → 실서비스 로그인 방식은 합의).
2. **프로필 생성**: 처음 한 번 `POST /v1/users/me { role, name }`. 서버가 `users/{uid}`를 만든다. 이미 다른 역할이면 `409 role-locked`. 클라이언트는 `users` 문서를 직접 쓸 수 없다.
3. **토큰**: 매 요청마다 `getIdToken()`(SDK가 1시간마다 자동 갱신)을 Bearer로 보낸다. 서버는 서명·만료·프로젝트 ID를 검증한다.
4. **권한 검사** (✅ `MockBackend`와 같은 규칙):
   - 고령자 API: 토큰 uid = `elderId`. 승인 취소는 본인이 만든 요청만.
   - 보호자 API: `links/{elderId}_{uid}`가 있어야 하고, 대상 문서의 `guardianIds`에 uid가 포함돼야 한다.
   - 수신 보호자는 항상 서버가 links에서 조회한다.

---

## 6. 고령자 앱 담당자가 구현할 기능

v1 목록에서 **서버 호출 방식만 REST로 바뀌었다.** ⚠️ 정정: `INTEGRATION_REVIEW.md` 1장 기준 고령자 앱은 2026-11-24에 아래 5·6·7·9·10·11번(감지·동의 팝업·팝업 중복 방지·SOS·승인 요청·취소)이 **구현 완료(실행 미검증)** 상태이고, 1·3번은 부분 구현, 2·12·13번은 미구현이다. 고령자 앱은 지금 Firestore에 **직접 쓰는** 임시 구현을 서버 호출로 바꾸면 된다.

| 순서 | 기능 | 내용 | 삽입 지점 (연동 분석 문서) |
|---|---|---|---|
| 1 | 새 Firebase 프로젝트 연결 | 해봄 공통 프로젝트의 `google-services.json`으로 교체 (💡 합의 후, 기존 `copilot-demo-c9a74` 설정은 건드리지 않고 교체) | `app/google-services.json` |
| 2 | 로그인·프로필 | 앱 시작 시 익명 로그인 → `POST /v1/users/me { role: "elder", name }` | `Sos.kt`의 익명 로그인 이동 |
| 3 | 이름 입력칸 | 설정 화면에 고령자 이름 (`PATCH /v1/users/me`) | 현재 보호자 이름·번호만 있음 |
| 4 | 서버 주소·호출 모음 | `config/server` 문서 구독으로 `baseUrl`을 얻고, 모든 REST 호출을 `GuardianRepo` 하나로. 개발용 Fake 구현 | 현재 `Sos.kt` 안 |
| 5 | 민감 앱 진입 감지 | `TYPE_WINDOW_STATE_CHANGED`의 패키지명을 목록과 비교. 음성 명령 여부와 상관없이 동작 | 새 `SensitiveAppWatcher`, `GuideService.onAccessibilityEvent` |
| 6 | 동의 팝업 + 닫기 | **"민감한 개인정보를 사용하는 서비스입니다. 보호자에게 알림을 보내겠습니까?"** 예 → `POST /v1/elder/sensitive-entries` / 아니요·닫기 → 아무것도 안 함 | `Orchestrator.askEntryConsent`, `AskPopup`에 `onDismiss` |
| 7 | 팝업 중복 방지 | 9장 | `SensitiveAppWatcher` |
| 8 | 도움 필요 | 45초 막힘 타이머 → "가족에게 연락할까요?" → 고령자가 **예**를 고를 때만 `POST /v1/elder/stuck` (+ SMS) | `Orchestrator.armStuckTimer` |
| 9 | SOS | 기존 SMS 유지 + `POST /v1/elder/sos { packageName?, appName? }` (사용 중인 앱, 홈 화면이면 생략) | `Sos.send`, `Orchestrator.sendSos` |
| 10 | 승인 요청 | `POST /v1/elder/approvals` → 대기 자막 → `approvals/{id}` 구독 → 계속·중단, `expiresAt` 지나면 스스로 종료 | `LocalPlanner`, `CaptionBar`, `Orchestrator.step`/`stop` |
| 11 | 승인 취소 | 기다리지 않고 멈출 때 `POST /v1/elder/approvals/{id}/cancel` | 새 버튼 |
| 12 | 가족 연결 코드 | 기기 영구 코드 대신 `POST /v1/elder/connect-codes` 결과(10분)를 표시 | `MainActivity.kt:120`, `Prefs.familyCode` 대체 |
| 13 | FCM 토큰 | 💡 고령자 앱이 푸시를 받을 경우만 `PUT /v1/devices/{deviceId}` | – |

### 6.1 Kotlin 예시 (💡, OkHttp + kotlinx.serialization 기준)
```kotlin
class ServerGuardianRepo(
    private val http: OkHttpClient,
    private val auth: FirebaseAuth,
    private val db: FirebaseFirestore,
) : GuardianRepo {
    @Volatile private var baseUrl: String? = null

    fun start() {   // 서버 주소는 config/server 문서에서 받는다 (Quick Tunnel 주소가 바뀌어도 자동 반영)
        db.collection("config").document("server")
            .addSnapshotListener { snap, _ -> baseUrl = snap?.getString("baseUrl") }
    }

    private suspend fun post(path: String, body: JSONObject, idempotencyKey: String? = null): JSONObject {
        val url = baseUrl ?: throw ServerUnavailable()
        val token = auth.currentUser!!.getIdToken(false).await().token
        val req = Request.Builder().url("$url/v1$path")
            .header("Authorization", "Bearer $token")
            .apply { idempotencyKey?.let { header("Idempotency-Key", it) } }
            .post(body.toString().toRequestBody("application/json".toMediaType()))
            .build()
        http.newCall(req).await().use { res ->
            val json = JSONObject(res.body!!.string())
            if (!res.isSuccessful) throw ServerError(json.getJSONObject("error").getString("reason"))
            return json
        }
    }

    // 동의 팝업에서 "예"일 때만 호출. 재시도할 때는 같은 key를 다시 쓴다.
    override suspend fun reportSensitiveEntry(pkg: String, appName: String): String {
        val key = UUID.randomUUID().toString()
        return retryOnce { post("/elder/sensitive-entries",
            JSONObject().put("packageName", pkg).put("appName", appName), key) }
            .getString("result")   // created | duplicate_suppressed | no_guardians
    }

    override fun watchApproval(id: String, onStatus: (String) -> Unit) =
        db.collection("approvals").document(id)
            .addSnapshotListener { snap, _ -> snap?.getString("status")?.let(onStatus) }
}

// 승인 결과 처리 + 만료 시 스스로 종료 (서버가 꺼져 있어도 고령자가 기다리지 않게)
when (status) {
    "approved" -> orchestrator.step()
    "rejected" -> orchestrator.stop("가족이 잠깐 멈추자고 했어요")   // 문구 💡 합의
    "expired"  -> orchestrator.stop("가족이 아직 확인하지 못했어요")
}
handler.postDelayed({ if (stillPending) orchestrator.stop("가족이 아직 확인하지 못했어요") },
    expiresAt - now)
```

---

## 7. 보호자 앱 담당자(나)가 구현할 기능

| 기능 | 상태 |
|---|---|
| 보호자 앱 화면·흐름 전체, Mock 서버(`MockBackend`), 자동 테스트 | ✅ |
| `INTEGRATION_REVIEW.md` 합의 반영 (v2.1 표) | ✅ |
| Firebase 패키지 (`firebase_core`·`firebase_auth`·`cloud_firestore`·`firebase_messaging`·`http`) | ✅ 추가, Android·iOS 빌드 확인 |
| 실행 모드 선택: Mock(기본) / 실제 서버 (`--dart-define-from-file=config/firebase.json`) | ✅ 설정 값이 없으면 안내 화면 |
| Firebase Auth 익명 로그인 → 보호자 프로필 생성 요청 | ✅ 구현, 실제 프로젝트 미검증 |
| `ServerGuardianRepository`: links → 가족별 알림·승인 실시간 구독, "확인했어요" `readBy` 쓰기 | ✅ 구현, 가짜 Firestore 테스트 통과, 실제 프로젝트 미검증 |
| 서버 API 클라이언트 (승인·거절, 가족 연결·해제, 기기 등록): Bearer ID 토큰, Idempotency-Key, 오류 reason 대응 | ✅ 구현(v2 초안 경로), 실제 서버 미검증 |
| FCM 토큰 발급·서버 등록·갱신, 포그라운드 메시지 표시, 알림 탭 → 상세 이동 | ✅ 구현, 실제 푸시 미검증 |
| Android 백그라운드·잠금 화면: 서버의 `notification` 메시지를 시스템이 표시, 기본 채널 지정 | ✅ 설정, 실제 푸시 미검증 |
| 로컬 알림 ↔ 원격 푸시 중복 방지 | ✅ 구현·테스트 |
| iPhone: 실제 서버 데이터 + 앱 실행 중 로컬 알림 (APNs 없음 → 원격 푸시 안 받음) | ✅ 구현, 실제 프로젝트 미검증 |
| iOS APNs (Apple 유료 계정 필요) | 준비만 (`docs/SERVER_REQUIREMENTS.md`, PROGRESS) |

## 8. 기능별 연동 흐름

### 8.1 일반 알림 — 민감 앱 이용 (`sensitive_entry`)
```
고령자 앱: 정부24 진입 감지 → 팝업 중복 방지 통과 → 동의 팝업
  ├─ 예   → POST /v1/elder/sensitive-entries (Idempotency-Key)
  │         서버: 토큰·역할 확인 → links에서 보호자 조회 → dedupe 트랜잭션(9장)
  │               → notifications 생성 + pushJobs 생성(같은 트랜잭션) → FCM 발송
  │         보호자 앱: 푸시 "새 가족 알림이 도착했습니다." → 상세 "어머니가 정부24에 접속했습니다."
  └─ 아니요·닫기 → 아무것도 하지 않음
```
고령자 앱은 응답을 기다리지 않고 안내를 계속한다. 서버가 꺼져 있으면 1회 재시도 후 포기한다(오래된 알림을 늦게 보내지 않음).

### 8.2 도움 필요 (`stuck`)
45초 진행 없음 → 고령자 앱이 "가족에게 연락할까요?"를 묻고, **고령자가 예를 고를 때만** `POST /v1/elder/stuck` (+ SMS). 같은 작업에서 한 번만 묻기 때문에 서버 중복 방지는 필요 없다(INTEGRATION_REVIEW #10).

### 8.3 SOS (`sos`)
기존 SMS 발송은 **그대로 먼저** 하고, 추가로 `POST /v1/elder/sos { packageName?, appName? }`. 사용 중이던 앱이 있으면 보호자 앱에 "어머니가 정부24 사용 중 SOS 도움 요청을 보냈습니다."로 표시된다(없으면 "어머니가 SOS 도움 요청을 보냈습니다."). SOS는 중복 방지 없이 매번 보낸다(Idempotency-Key로 같은 요청의 재전송만 막음). FCM `sos_alerts` 채널. 위치 정보는 보내지 않는다.

### 8.4 승인·거절 (`approvals`) — 기능 유지
```
고령자 앱                               서버                                  보호자 앱
POST /v1/elder/approvals ──────────► approvals 생성(pending, +5분)+pushJobs ─► 푸시 "확인이 필요한 요청이 도착했습니다."
"보호자 답을 기다리고 있어요"                                                   상세: "도우미 진행 승인"
approvals/{id} 구독 ◄────────────── 트랜잭션: pending && now < expiresAt ◄──── POST /v1/guardian/approvals/{id}/respond
```
| status | 고령자 앱 동작 |
|---|---|
| `approved` | 안내 계속 |
| `rejected` | 안내 중단 |
| `expired` | 응답 없음 → 안내 중단 + **SOS 문자 보낼지 묻기** (자동 진행 아님) |
| `cancelled` | 본인 취소 → 종료 |

규칙 (✅ Mock 구현·테스트, 🛠 서버는 Firestore 트랜잭션으로 구현):
- `pending`에서만 상태 변경. 종료 상태는 다시 바뀌지 않는다.
- 여러 보호자 동시 응답 → **먼저 커밋된 하나만** 반영, 나머지 `409 already-responded`.
- 만료 후 응답 → 서버가 `expired`로 바꾸고 `409 approval-expired`. 취소된 요청 → `409 approval-cancelled`.
- **만료 처리 (서버가 꺼져 있을 수 있으므로 3중으로)**
  1. 서버 시작 시: `status == pending && expiresAt <= now`인 문서를 모두 `expired`로 변경
  2. 서버 실행 중: 30초마다 같은 처리
  3. 앱: 보호자 앱은 `expiresAt`이 지나면 서버 반영 전이라도 "만료"로 표시(✅ `ApprovalRequest.effectiveStatus` 구현됨), 고령자 앱은 `expiresAt`에 스스로 대기 종료
- 💡 어떤 상황에서 승인을 요청할지, 승인 대기 시간, 버튼 문구는 합의 사항(`INTEGRATION_CHANGES.md`).

### 8.5 FCM 푸시 (🛠)
**Android** — FCM `notification` 메시지라 앱이 백그라운드·종료 상태여도 시스템이 표시한다.
```json
{
  "token": "<기기 토큰>",
  "notification": { "title": "해봄 가족", "body": "새 가족 알림이 도착했습니다." },
  "data": { "kind": "notification", "id": "<문서 ID>", "type": "sensitive_entry" },
  "android": {
    "priority": "high",
    "notification": { "channel_id": "family_activity", "tag": "notification_<문서 ID>", "visibility": "PRIVATE" }
  }
}
```
| 종류 | data.kind | channel_id | 기본 body (✅ 보호자 앱 로컬 알림 문구와 동일) |
|---|---|---|---|
| sensitive_entry | `notification` | `family_activity` | 새 가족 알림이 도착했습니다. |
| stuck | `notification` | `family_activity` | 가족에게 도움이 필요할 수 있습니다. 앱에서 확인해 주세요. |
| sos | `notification` | `sos_alerts` | 가족이 도움을 요청했습니다. 앱에서 확인해 주세요. |
| 승인 요청 | `approval` | `approval_requests` | 확인이 필요한 요청이 도착했습니다. |

- 잠금 화면에는 최소 문구만 보낸다. 상세는 앱이 Firestore에서 조회한다. 💡 "상세 내용 표시" 설정을 원격 푸시에도 반영하려면 설정을 서버에 저장해야 하므로 별도 합의.
- `tag`를 문서 ID로 지정해 같은 알림이 두 번 와도 **알림창에는 하나만** 남게 한다.
- **iOS**: APNs 키는 Apple Developer 유료 계정이 필요하다. v2에서는 iOS 원격 푸시를 보내지 않고, 보호자 앱이 **실행 중일 때** Firestore 변경을 받아 로컬 알림으로 표시한다. 유료 계정이 생기면 서버 코드 변경 없이 APNs 키 등록만으로 켤 수 있게 구조를 유지한다.

---

## 9. 중복 방지

| 대상 | 위치 | 방법 | 상태 |
|---|---|---|---|
| ① 같은 질문 반복 | 고령자 앱 | 같은 앱 안 화면 이동은 무시, 다른 앱에 갔다 올 때만 판단, 같은 앱은 일정 시간 다시 묻지 않음, 키보드·런처·해봄 앱 무시 | 💡 연동 분석 문서 제안(10분), 미구현 |
| ② 같은 알림 반복 | 서버 | 같은 고령자·같은 앱의 `sensitive_entry`가 **10분** 안에 있으면 `duplicate_suppressed` (💡 구현 예: `dedupe/{elderId}_{packageName}` 트랜잭션) | ✅ Mock 10분 / 🛠 서버 |
| ③ 같은 요청 재전송 (네트워크 재시도) | 서버 | `Idempotency-Key` → `idempotency/{uid}_{key}`에 첫 응답 저장, 24시간 동안 같은 응답 반환 | 🛠 |
| ④ 같은 푸시 두 번 | 서버·앱 | `pushJobs` 상태가 `pending`일 때만 발송하고 즉시 `sent`로 기록, Android `tag`로 알림창 중복 제거, 보호자 앱은 서버 모드에서 Firestore 변경 기반 로컬 알림을 **앱이 앞에 있을 때만** 띄움 | 🛠 |
| ⑤ 승인 동시 응답 | 서버 | 트랜잭션에서 `status == pending` 확인 | ✅ Mock / 🛠 서버 |

- ② 방식은 복합 인덱스가 필요 없고, 동시에 두 요청이 와도 트랜잭션이 하나만 통과시킨다.
- 보호자 앱 개발자 테스트에서는 10분 안에 등본 시나리오를 다시 시작하면 "1단계 알림이 중복 방지로 생략된다"는 선택 창을 띄운다(✅).

---

## 10. FCM 발송 실패와 재시도 (🛠)

| 실패 유형 (FCM 오류) | 처리 |
|---|---|
| `UNREGISTERED`, 토큰 관련 `INVALID_ARGUMENT` | 해당 `devices` 문서 삭제, 재시도 안 함 |
| `UNAVAILABLE`, `INTERNAL`, `QUOTA_EXCEEDED`(429) | 재시도: 10초 → 30초 → 2분 → 5분 (최대 5회) |
| 그 밖의 오류 | `failed`로 기록, 재시도 안 함 |

- 보호자 여러 명·기기 여러 대 중 일부만 실패하면 실패한 토큰만 재시도한다.
- **유효 기간**: 이용 알림·도움 필요는 생성 후 10분, SOS는 30분, 승인 요청은 `expiresAt`까지만 재시도한다. 그 뒤에는 늦은 알림을 보내지 않는다(알림 문서는 목록에 그대로 남는다).
- **서버 재시작 시**: `pushJobs`에서 `pending`·`retrying`이면서 유효 기간이 남은 작업을 다시 처리한다.
- 푸시가 실패해도 알림 문서는 이미 저장돼 있으므로, 보호자가 앱을 열면 목록에서 볼 수 있다.

---

## 11. 가족 연결

```
고령자 앱                        서버                                         보호자 앱
POST /v1/elder/connect-codes ─► 암호학적 난수 6자리(미사용), connectCodes 생성
                                (같은 고령자의 이전 미사용 코드는 무효화 — 합의됨)
화면 "123456 (9:59 남음)" ◄──── { code, expiresAt }
  ·· 전화·문자로 코드 전달 ··                                                 코드 + 호칭 입력
                               ◄────────────────────────────────────────── POST /v1/guardian/links
                               검증: 잠금(uid·IP) → 형식 → 존재 → used → 만료 → 이미 연결
                               트랜잭션: used=true, links/{elderId}_{guardianId} 생성
                               ──────────────────────────────────────────► { elderId, elderName, relationship, connectedAt }
```
| 규칙 | 상태 |
|---|---|
| 10분 유효, 일회용, 오류별 reason | ✅ Mock |
| 보호자 **uid별** 연속 실패 5회 → 5분 잠금 | ✅ Mock |
| **IP별** 연속 실패 10회 → 15분 잠금 (익명 계정을 새로 만들어 uid 제한을 피하는 것 방지, IP는 해시로만 저장) | 💡 🛠 |
| 한 고령자 ↔ 여러 보호자, 한 보호자 ↔ 여러 고령자 | ✅ Mock |
| 연결 해제 → links 삭제 → 과거 알림·승인 읽기 차단 | ✅ Mock / 🛠 규칙 |
| **고령자도 연결 해제 가능** (`DELETE /v1/elder/links/{guardianId}`), 고령자 앱 1차 화면: 연결된 가족 목록 + 해제 | ✅ Mock(`disconnectByElder`) / 합의됨 |
| 새 코드 발급 시 이전 미사용 코드 무효화 (이전 코드 입력 시 `code-expired`) | ✅ Mock / 합의됨 |

현재 고령자 앱의 영구 `familyCode`와 `families/{코드}/events` 경로는 이 방식으로 대체한다(💡 기존 기록 처리 합의).

---

## 12. 서버 운영 (💡 서버 담당자가 확정 — 아래는 v2 초안의 제안)

| 항목 | 내용 |
|---|---|
| 실행 | 서버는 `127.0.0.1:8787`에만 열고, 외부 접속은 Cloudflare Quick Tunnel로만 받는다 |
| 주소 | Quick Tunnel 주소는 실행할 때마다 바뀐다 → 서버가 시작할 때 `config/server.baseUrl`에 기록, 앱은 자동으로 새 주소 사용 |
| 가동 | 맥북이 잠들거나 꺼지면 모든 쓰기·푸시가 멈춘다 (읽기는 Firestore라 계속 됨). 시연 중에는 전원 연결 + 잠자기 방지 |
| 서비스 계정 키 | 저장소 밖 `~/.config/haebom/service-account.json`(권한 600), 환경 변수로 경로 지정, Git·앱·채팅에 올리지 않음. 키는 보호자 앱 담당자만 보관 |
| 로그 | ID 토큰·FCM 토큰·개인정보는 로그에 남기지 않는다 |

---

## 13. 실제 서버 연동 후 통합 테스트

| # | 시나리오 | 기대 결과 |
|---|---|---|
| 1 | 정부24 진입 → 예 | 보호자 Android 폰(**앱 종료·화면 잠금 상태**)에 푸시, 잠금 화면 최소 문구 |
| 2 | 진입 → 아니요 / 닫기 | 서버 호출 없음 |
| 3 | 정부24 안 화면 이동 | 추가 팝업·알림 없음 |
| 4 | 중복 방지 시간 안 재진입 → 예 | `duplicate_suppressed`, 알림 1건 |
| 5 | 같은 Idempotency-Key로 2번 전송 | 알림 1건, 같은 응답 |
| 6 | 45초 막힘 / SOS | `stuck` / `sos` 푸시 |
| 7 | 보호자 A 읽음 | A만 읽음 |
| 8 | 승인 요청 → 승인 | 고령자 앱 안내 계속 |
| 9 | 보호자 A·B 동시 응답 | 하나만 반영, 다른 쪽 `already-responded` |
| 10 | 서버를 끈 채 승인 만료 시간 경과 → 서버 재시작 | 재시작 직후 `expired`로 바뀜, 고령자 앱은 이미 스스로 종료 |
| 11 | 코드 발급 → 입력 / 만료·사용·잘못된 코드 5회 | 연결 / 각 오류, 잠금 |
| 12 | 보호자 앱이 역할을 `elder`로 바꾸려 함 | `409 role-locked`, Firestore 직접 쓰기도 거부 |
| 13 | 연결되지 않은 보호자가 승인 응답 | `403 permission-denied` |
| 14 | 서버 재시작 (터널 주소 변경) | 두 앱이 새 주소로 자동 연결 |
| 15 | iPhone 보호자 앱 실행 중 | 목록 실시간 반영, 로컬 알림 표시, 승인·연결 동작 |
| 16 | 비행기 모드에서 승인 | `unavailable` 안내, 상태 변경 없음 |

---

## 부록. 참고 파일
| 파일 | 내용 |
|---|---|
| `docs/INTEGRATION_CHANGES.md` | v1 → v2 변경 내역, 합의 필요 사항 |
| `docs/SERVER_REQUIREMENTS.md` | 서버 담당자에게 받을 정보, Firebase 프로젝트 확인 목록 |
| `docs/INTEGRATION.md` | 상세 규격 v0.1 (보안 규칙 초안, 승인 정책 제안 4.6) |
| `lib/repositories/mock_backend.dart` | 서버 규칙 기준 코드 |
| `lib/repositories/guardian_repository.dart` | 보호자 앱 인터페이스·오류 코드 |
