# 해봄 공통 서버 API 정리 (서버 담당자 전달용)

> 작성일: 2026-11-25 · 작성: 보호자 앱 담당
> Firebase 프로젝트: `copilot-demo-c9a74` (보호자 앱 Android `com.yju.haebom.guardian_app` / iOS `com.yju.haebom.guardianApp` 등록 완료, FCM 수신 확인)
> **v2.2 반영 (2026-11-25):** 가족 호칭 `elderLabel`/`guardianLabel` 분리, 알림 `level`·`category`·`reason`, 승인 `category`·action 4개, 도움 필요 채널 `help_alerts`. 자세한 내용은 `DATA_SPEC_CHANGES.md`.
> 이 문서는 **제안 규격**이다. 경로·이름을 바꾸고 싶으면 알려 주면 보호자 앱이 맞춘다. 데이터 필드·값은 `GUARDIAN_INTEGRATION.md` 3장과 같다.

---

## 1. 한눈에 보기 — 엔드포인트 15개

| # | 메서드 · 경로 | 호출 앱 | 하는 일 |
|---|---|---|---|
| 1 | `GET /v1/healthz` | (확인용) | 서버 살아 있는지 |
| 2 | `POST /v1/users/me` | 공통 | 처음 1회 프로필·역할 생성 |
| 3 | `PATCH /v1/users/me` | 공통 | 이름 변경 |
| 4 | `PUT /v1/devices/{deviceId}` | 공통 | FCM 토큰 등록·갱신 |
| 5 | `DELETE /v1/devices/{deviceId}` | 공통 | FCM 토큰 해제 |
| 6 | `POST /v1/elder/sensitive-entries` | 고령자 | 민감 앱 이용 알림 (동의 "예"일 때만) |
| 7 | `POST /v1/elder/stuck` | 고령자 | 도움 필요 알림 (고령자 동의 후) |
| 8 | `POST /v1/elder/sos` | 고령자 | SOS 알림 |
| 9 | `POST /v1/elder/approvals` | 고령자 | 도우미 진행 승인 요청 |
| 10 | `POST /v1/elder/approvals/{id}/cancel` | 고령자 | 승인 요청 취소 |
| 11 | `POST /v1/elder/connect-codes` | 고령자 | 가족 연결 코드 발급 |
| 12 | `DELETE /v1/elder/links/{guardianId}` | 고령자 | 고령자 쪽 연결 해제 |
| 13 | `POST /v1/guardian/approvals/{id}/respond` | 보호자 | 승인·거절 응답 |
| 14 | `POST /v1/guardian/links` | 보호자 | 연결 코드로 가족 연결 |
| 15 | `DELETE /v1/guardian/links/{elderId}` | 보호자 | 보호자 쪽 연결 해제 |

- **보호자 앱이 이미 호출하도록 구현된 것: #2, #4, #5, #13, #14, #15 (6개)**
- 고령자 앱용: #6~#12 (7개) · 확인용: #1 · 이름 변경 #3은 아직 앱에서 안 씀
- **읽기용 API는 없다.** 두 앱 모두 Firestore를 실시간 구독해서 읽는다 (5장).

---

## 2. 공통 규칙

| 항목 | 규칙 |
|---|---|
| 주소 | `https://<서버 고정 주소>/v1/...` — **HTTPS 필수** (휴대폰 앱은 http 접속 불가) |
| 인증 | 모든 요청(#1 제외) 헤더 `Authorization: Bearer <Firebase ID 토큰>` → 서버가 Admin SDK `verifyIdToken`으로 uid 확인 |
| uid | **요청 본문에 uid를 넣지 않는다.** 서버가 토큰에서 얻는다 |
| 역할 | `/v1/elder/*`는 `users/{uid}.role == "elder"`, `/v1/guardian/*`는 `"guardian"`만 허용 |
| 형식 | JSON, `Content-Type: application/json; charset=utf-8` |
| 시간 | 응답의 시간은 ISO 8601 UTC 문자열 (예: `2026-11-25T03:12:00.000Z`), Firestore에는 Timestamp |
| 중복 요청 | 생성 요청(#6~#9, #11, #14)은 헤더 `Idempotency-Key: <UUID>`. 같은 uid·같은 키로 다시 오면 **처음 응답을 그대로** 돌려주고 새로 만들지 않는다 |
| 수신 보호자 | `guardianIds`는 **서버가 `links`에서 찾아 채운다.** 앱은 보내지 않는다 |

---

## 3. 엔드포인트별 요청 · 응답

### 공통
**#1 `GET /v1/healthz`** (인증 없음)
- 응답 `200 { "ok": true, "apiVersion": "v1" }`

**#2 `POST /v1/users/me`**
- 요청 `{ "role": "guardian" | "elder", "name": "보호자" }`
- 응답 `200 { "uid", "role", "name" }`
- 이미 같은 역할이면 그대로 200, **다른 역할이면 `409 role-locked`** (역할 변경 금지)
- 서버가 `users/{uid}` 문서 생성 `{ role, name, createdAt }`

**#3 `PATCH /v1/users/me`**
- 요청 `{ "name": "김순자" }` → 응답 `200 { "uid", "role", "name" }`

**#4 `PUT /v1/devices/{deviceId}`**
- 요청 `{ "fcmToken": "<FCM 등록 토큰>", "platform": "android" | "ios" }`
- 응답 `200 { "ok": true }`
- 저장 위치 `users/{uid}/devices/{deviceId}` `{ fcmToken, platform, updatedAt }`
- `deviceId`는 앱 설치마다 고유한 값 (앱이 만듦)

**#5 `DELETE /v1/devices/{deviceId}`** → `200 { "ok": true }`

### 고령자 앱
**#6 `POST /v1/elder/sensitive-entries`** 🔁
- 요청 `{ "packageName": "kr.go.minwon.m", "appName": "정부24", "level"?: "L1", "category"?: "public", "reason"?: "정부24 열기" }` (level·category·reason은 선택, 받은 그대로 저장)
- 응답 `200` 셋 중 하나
  - `{ "result": "created", "notificationId": "..." }`
  - `{ "result": "duplicate_suppressed" }` — 같은 고령자·같은 앱이 **10분** 안에 이미 있음
  - `{ "result": "no_guardians" }` — 연결된 보호자 없음
- 서버: `notifications` 문서 생성(`type: "sensitive_entry"`) + 보호자들에게 FCM

**#7 `POST /v1/elder/stuck`** 🔁
- 요청 `{ "packageName": "...", "appName": "..." }` (앱 밖이면 빈 문자열)
- 응답 `{ "result": "created", "notificationId" }` / `{ "result": "no_guardians" }`
- `type: "stuck"`. 고령자가 "연락할게요"를 골랐을 때만 호출됨

**#8 `POST /v1/elder/sos`** 🔁
- 요청 `{ "packageName"?: "...", "appName"?: "...", "category"?: "scam", "reason"?: "기관 사칭 송금 요청" }` (모두 선택, 앱 정보가 없으면 빈 문자열로 저장. `category: "scam"`이면 `level: "L3"`로 저장)
- 응답 `{ "result": "created", "notificationId" }` / `{ "result": "no_guardians" }`
- `type: "sos"`, 중복 방지 없음 (매번 보냄)

**#9 `POST /v1/elder/approvals`** 🔁
- 요청 `{ "packageName": "kr.go.minwon.m", "appName": "정부24", "action": "guide_gov24_auth", "category"?: "public" }`
- 응답 `{ "result": "created", "approvalId": "...", "expiresAt": "..." }` / `{ "result": "no_guardians" }`
- 서버: `approvals` 문서 생성 `status: "pending"`, `expiresAt = 지금 + 5분` + 보호자들에게 FCM
- action 값: `guide_gov24_auth`, `guide_bank_open`, `guide_money_move`, `guide_identity`, `guide_install`, `guide_privacy_send` (서버는 검사하지 않고 그대로 저장)

**#10 `POST /v1/elder/approvals/{id}/cancel`**
- 본인이 만든 `pending` 요청만 → `200 { "status": "cancelled" }`

**#11 `POST /v1/elder/connect-codes`** 🔁
- 응답 `200 { "code": "123456", "expiresAt": "..." }`
- 6자리 난수, **10분 유효, 일회용**, 같은 고령자의 **이전 미사용 코드는 무효화**
- 저장 `connectCodes/{code}` `{ elderId, expiresAt, used: false }` (서버만 접근)

**#12 `DELETE /v1/elder/links/{guardianId}`** → `200 { "ok": true }` (`links/{elderId}_{guardianId}` 삭제)

### 보호자 앱 (✅ 앱에 구현됨)
**#13 `POST /v1/guardian/approvals/{id}/respond`**
- 요청 `{ "decision": "approve" | "reject" }` (화면 버튼: "계속해도 돼요" / "잠깐 멈춰요")
- 응답 `200 { "status": "approved" | "rejected", "respondedAt": "..." }`
- **Firestore 트랜잭션**: `status == "pending"` 이고 `now < expiresAt`일 때만 → `status`, `respondedAt`, `respondedBy` 기록
  - 이미 다른 보호자가 응답 → `409 already-responded`
  - 만료 → 문서를 `expired`로 바꾸고 `409 approval-expired`
  - 취소됨 → `409 approval-cancelled`

**#14 `POST /v1/guardian/links`** 🔁
- 요청 `{ "code": "123456", "elderLabel": "어머니", "guardianLabel": "딸" }` (elderLabel = 보호자가 어르신을 부르는 호칭, guardianLabel = 어르신이 보호자를 부르는 호칭)
- 응답 `200 { "elderId", "elderName", "elderLabel", "guardianLabel", "connectedAt" }`
- 검증 순서: 잠금 여부 → 6자리 형식 → 존재 → 사용됨 → 만료 → 이미 연결
- 성공 시 코드 `used: true` + `links/{elderId}_{guardianId}` 생성 `{ elderId, guardianId, elderName, elderLabel, guardianLabel, connectedAt }` (`relationship`은 더 이상 쓰지 않음)
- 연속 실패 5회 → 5분 잠금 (`429 too-many-attempts`)

**#15 `DELETE /v1/guardian/links/{elderId}`** → `200 { "ok": true }`

---

## 4. 오류 형식

```json
HTTP 409
{ "error": { "reason": "already-responded", "message": "이미 다른 보호자가 응답한 요청입니다." } }
```

| HTTP | reason |
|---|---|
| 400 | `invalid-argument`, `invalid-code` |
| 401 | `unauthenticated` (토큰 없음·만료) |
| 403 | `permission-denied` (역할 불일치, 연결 안 된 가족), `profile-required` (#2 먼저) |
| 404 | `not-found` |
| 409 | `already-responded`, `approval-expired`, `approval-cancelled`, `code-used`, `already-linked`, `role-locked` |
| 410 | `code-expired` |
| 429 | `too-many-attempts`, `rate-limited` |
| 503 | `unavailable` |

보호자 앱은 `reason` 값을 보고 한국어 안내 문구를 보여 준다. **reason 문자열만 정확히 맞춰 주면 된다.**

---

## 5. API가 아닌 것 — Firestore 직접 (보안 규칙으로 허용 필요)

| 누가 | 무엇을 | 허용해야 할 쿼리 |
|---|---|---|
| 보호자 앱 | 연결된 가족 읽기 | `links` where `guardianId == 내 uid` |
| 보호자 앱 | 알림 읽기 | 가족마다 `notifications` where `elderId == X` and `guardianIds array-contains 내 uid` |
| 보호자 앱 | 승인 요청 읽기 | 가족마다 `approvals` where `elderId == X` and `guardianIds array-contains 내 uid` |
| 보호자 앱 | **"확인했어요"** | `notifications/{id}`의 `readBy.{내 uid}` 필드 **하나만** update |
| 고령자 앱 | 승인 결과 받기 | `approvals/{id}` 읽기 (본인 `elderId`) |
| 두 앱 | (선택) 서버 주소 | `config/server` 읽기 — 고정 주소를 쓰면 필요 없음 |

**지금은 규칙에 이 경로들이 없어서 보호자 앱 읽기가 모두 거부된다** (실제 프로젝트에서 확인: `PERMISSION_DENIED`). 그 외 쓰기는 전부 서버(Admin SDK)만.

---

## 6. FCM 보내는 형식 (서버 → 보호자 폰)

`users/{보호자 uid}/devices/*`의 `fcmToken` 전부에 보낸다.

```js
await admin.messaging().send({
  token,
  notification: { title: '해봄 가족', body: '새 가족 알림이 도착했습니다.' },
  data: { kind: 'notification', id: notificationId, type: 'sensitive_entry' },
  android: { priority: 'high', notification: { channelId: 'family_activity', tag: `notification_${notificationId}` } },
});
```

| 종류 | data.kind | data.type | channelId | title | body (잠금 화면용 짧은 문구) |
|---|---|---|---|---|---|
| 민감 앱 이용 | `notification` | `sensitive_entry` | `family_activity` | 해봄 가족 | 새 가족 알림이 도착했습니다. |
| 도움 필요 | `notification` | `stuck` | **`help_alerts`** | 해봄 가족 · 도움 필요 | 가족에게 도움이 필요할 수 있습니다. 앱에서 확인해 주세요. |
| SOS | `notification` | `sos` | `sos_alerts` | 해봄 가족 · 긴급 | 가족이 도움을 요청했습니다. 앱에서 확인해 주세요. |
| 사기 의심 (`category: "scam"` 또는 `level: "L3"`, type 무관) | `notification` | (그대로) | `sos_alerts` | 해봄 가족 · 긴급 | (type의 문구 그대로) |
| 승인 요청 | `approval` | (생략) | `approval_requests` | 해봄 가족 · 승인 요청 | 확인이 필요한 요청이 도착했습니다. |

- `data.id` = Firestore 문서 ID → 보호자가 알림을 누르면 그 상세 화면으로 이동
- 발송 결과가 `UNREGISTERED`면 그 기기 문서를 삭제
- iPhone은 원격 푸시를 보내지 않아도 된다 (앱 실행 중 Firestore로 받음)
- 테스트용 보호자 폴드3 토큰은 보호자 앱 담당자에게 요청

---

## 7. 서버 담당자에게 받을 것
1. **서버 HTTPS 고정 주소** (예: `https://xxxx.execute-api.ap-northeast-2.amazonaws.com`)
2. 위 15개 중 **경로·이름이 달라진 것** 목록
3. 보안 규칙 배포 완료 알림
4. FCM 보낼 때 `data`에 `kind` / `id` / `type`을 넣는지 확인
