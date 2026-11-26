# 서버 기획(초안 v0.1)에 대한 보호자 앱 답변

- 작성일: 2026-11-26
- 작성: 보호자 앱 담당
- 대상 문서: `해봄 서버 기획 (초안 v0.1)` (2026-11-26)
- 같이 볼 문서: `docs/ALIGNMENT_CHECKLIST.md`(세 파트 통일 규격), `docs/SERVER_API.md`(보호자 앱이 지금 쓰는 API 규격)

> 표시: **동의** · **수정 요청**(맞추지 않으면 보호자 앱 기능이 깨짐) · **제안**(있으면 좋음) · **질문**

---

## 0. 요약

- AWS(Lambda + DynamoDB) 전환, Firestore 직접 읽기 → GET API + FCM 대체에 **동의**합니다. 보호자 앱은 데이터 처리가 `lib/repositories/server/` 한곳에 모여 있어 화면 변경 없이 바꿀 수 있습니다.
- Firebase Auth(ID 토큰)·FCM을 그대로 쓰는 것도 **동의**. 보호자 앱은 지금 **익명 로그인**이며 JWT Authorizer로 그대로 검증됩니다.
- 다만 아래 **수정 요청 5건**은 맞추지 않으면 보호자 앱의 안내 문구·기능이 깨집니다 (2장).
- iPhone은 원격 푸시(APNs)를 쓸 수 없어 **앱이 켜져 있는 동안 폴링**으로 받습니다. 폴링을 가볍게 할 수 있도록 `since` 조회를 요청합니다 (4장).

---

## 1. 서버 기획 14장 협의 항목에 대한 답

| # | 내용 | 답 |
|---|---|---|
| 1 | Firestore 직접 읽기 → GET(#18~#24) + FCM | **동의**. 단 #23에 지난 승인 조회 필요 (2.4) |
| 2 | #13·#14·#15 경로 | **동의**. 보호자 앱이 이미 같은 경로를 씀. 단 본문·응답 값 수정 요청 (2.1, 2.2) |
| 3 | `readBy{uid}` → 보호자별 `readAt` | **동의**. 앱 안에서 `readAt`을 내 확인 시각으로 읽음 |
| 4 | Firebase는 Auth·FCM 용도만 | **동의** |
| 9 | 연결 해제 시 기존 알림·승인 기록 | **제안**: 해제된 어르신의 알림·승인은 보호자 GET 응답에서 **빼 주세요** (저장은 서버 판단). 지금 보호자 앱·고령자 앱 Mock 모두 "해제하면 그 한 쌍만 양쪽 목록에서 바로 빠짐"으로 동작하고, 고령자 앱 담당자와도 그렇게 확인함 |

---

## 2. 수정 요청 (맞추지 않으면 기능이 깨짐)

### 2.1 가족 호칭: `relationship` → `elderLabel` + `guardianLabel`

11-26에 **고령자 앱 담당자와 합의 완료**: 호칭은 두 필드로 통일하고 고령자 앱은 `relationship`을 더 이상 쓰지 않습니다.

| 필드 | 뜻 | 예 | 쓰는 곳 |
|---|---|---|---|
| `elderLabel` | 보호자가 어르신을 부르는 호칭 | 어머니 | 보호자 앱 화면 |
| `guardianLabel` | 어르신이 보호자를 부르는 호칭 | 큰딸 | 고령자 앱 안내 ("큰딸 님이 허락했어요") |

요청:
- #14 요청 본문: `{ "code": "123456", "elderLabel": "어머니", "guardianLabel": "큰딸" }`
- #14 응답: `{ "elderId", "elderName", "elderLabel", "guardianLabel", "connectedAt" }`
- DynamoDB 연결 항목(3.2 표 `LINK#<gid>`)의 `relationship` → `elderLabel`, `guardianLabel`
- #18·#20 응답에도 두 필드

### 2.2 승인 응답 #13 `decision` 값

| | 값 |
|---|---|
| 서버 기획 | `approved` \| `rejected` |
| 보호자 앱 (지금) | `approve` \| `reject` (`SERVER_API.md`) |

→ 서버 기획대로 **`approved` / `rejected`로 맞추겠습니다** (status 값과 같아서 더 명확). 서버 쪽은 그대로 두시면 됩니다.

### 2.3 오류 reason을 구체적으로

보호자 앱은 reason별로 다른 안내 문구를 보여 줍니다. `conflict`, `code-invalid` 하나로 묶이면 "네트워크를 확인하세요" 같은 엉뚱한 문구가 나옵니다.

**승인 응답 #13 (409)**
| 상황 | 요청 reason | 앱 문구 |
|---|---|---|
| 다른 보호자가 먼저 응답 | `already-responded` | 이미 다른 보호자가 응답한 요청입니다. |
| 만료됨 | `approval-expired` | 응답 가능 시간이 지나 요청이 만료되었습니다. |
| 어르신이 취소 | `approval-cancelled` | 가족이 요청을 취소했습니다. |

**코드로 연결 #14**
| 상황 | 요청 reason | HTTP |
|---|---|---|
| 없는 코드 | `invalid-code` | 400 또는 404 |
| 10분 지남 | `code-expired` | 409 |
| 이미 사용됨 / 새 코드 발급으로 무효 | `code-used` | 409 |
| 이미 연결된 어르신 | `already-linked` | 409 |
| 5회 실패 잠금 | `too-many-attempts` (또는 `rate-limited`, 앱이 같은 문구로 처리) | 429 |

- 철자 주의: 서버 기획의 `code-invalid` ↔ 보호자 앱 `invalid-code`. **`invalid-code`로 맞춰 주세요** (고령자 앱 Mock 계약서도 확인 필요).
- 409 `conflict`는 위에 해당하지 않는 경우에만 쓰면 됩니다.

### 2.4 지난 승인 목록 조회

보호자 앱 승인 탭은 위에 "응답이 필요한 요청", 아래에 **"지난 요청"**(허락함·멈춤·응답 시간 지남·요청 취소됨)을 보여 주고, 홈의 "최근 소식"에도 처리된 승인이 나옵니다. #23이 `status=pending`만 있으면 이 부분이 비게 됩니다.

요청: `GET /v1/guardian/approvals` (status 없으면 전체, 최신순 페이지 `cursor`) — 기획 3.2의 `GUARDIAN#<gid>` / `APPROVAL#<createdAt>#<aid>` 인덱스로 가능해 보입니다.

### 2.5 FCM 메시지 내용

보호자 앱이 알림을 눌렀을 때 상세 화면으로 가려면 `data`에 아래 값이 필요합니다 (`ALIGNMENT_CHECKLIST.md` 4장과 같음).

| 종류 | data.kind | data.id | data.type | data.elderId | android.notification.channel_id |
|---|---|---|---|---|---|
| 민감 앱 이용 | `notification` | 알림 ID | `sensitive_entry` | 어르신 uid | `family_activity` |
| 도움 필요 | `notification` | 알림 ID | `stuck` | 〃 | `help_alerts` |
| SOS | `notification` | 알림 ID | `sos` | 〃 | `sos_alerts` |
| 사기 의심 (`category: scam` 또는 `level: L3`) | `notification` | 알림 ID | (그대로) | 〃 | `sos_alerts` |
| 승인 요청 | `approval` | 승인 ID | – | 〃 | `approval_requests` |

- 잠금 화면에 보이는 `notification.body`는 짧은 문구만 (예: "새 가족 알림이 도착했습니다."). 앱 이름·내용은 넣지 않음.
- 발송 대상: `PUT /v1/devices/{deviceId}`로 등록한 **FCM 등록 토큰**(`getToken`). `UNREGISTERED`면 기기 삭제 (기획 8장과 같음).
- `data.elderId`는 새로 추가 요청 (앱이 받은 즉시 해당 어르신 목록만 새로 고치기 위해, 없어도 동작은 함).

---

## 3. GET 응답 모양 (제안)

기획 3.3 "앱 쪽 필드 이름은 그대로"에 맞춰, 보호자 앱이 지금 쓰는 모양을 적습니다. 시간은 ISO 8601 UTC 문자열.

**#20 `GET /v1/guardian/links`**
```json
{ "links": [
  { "elderId": "e1", "elderName": "김순자", "elderLabel": "어머니", "guardianLabel": "큰딸",
    "connectedAt": "2026-11-26T01:00:00Z" }
] }
```

**#21 `GET /v1/guardian/notifications?cursor=&since=&elderId=`**
```json
{ "items": [
  { "id": "n1", "elderId": "e1", "elderName": "김순자", "type": "sensitive_entry",
    "appName": "토스", "packageName": "viva.republica.toss",
    "level": "L1", "category": "finance", "reason": "금융 앱 진입",
    "createdAt": "2026-11-26T01:00:00Z", "readAt": null }
], "nextCursor": "..." }
```
- `level`·`category`·`reason`은 없어도 됨 (선택 필드)
- `elderId`로 거르기는 있으면 좋음 (없으면 앱이 거름)

**#23 `GET /v1/guardian/approvals?status=&cursor=&since=`**, **#24 `GET /v1/guardian/approvals/{id}`**
```json
{ "id": "a1", "elderId": "e1", "elderName": "김순자", "appName": "정부24",
  "packageName": "kr.go.minwon.m", "action": "guide_gov24_auth", "category": "public",
  "status": "pending", "createdAt": "2026-11-26T01:00:00Z", "expiresAt": "2026-11-26T01:05:00Z",
  "respondedAt": null, "respondedBy": null }
```
- `respondedBy`는 uid. 보호자 앱이 "다른 보호자가 응답함"을 표시할 때 씀 (호칭까지 주면 더 좋음: `respondedByLabel` — **제안**)
- 상태가 pending이어도 만료 시각이 지났으면 lazy 만료 규칙대로 `expired`로 돌려 주세요

**#22 `POST /v1/guardian/notifications/{id}/read`**
- 본문 없음, 응답 `{ "readAt": "..." }`. 이미 읽은 알림이면 같은 값으로 200 (두 번 눌러도 오류 아님)

---

## 4. iPhone: 폴링으로 받기 (질문 + 제안)

- 보호자 iPhone은 **Apple 무료 개발자 계정**이라 APNs(원격 푸시)를 쓸 수 없습니다. 지금은 Firestore 실시간 구독으로 앱이 켜져 있을 때만 받고 있고, 시연은 앱을 켜 둔 채 진행하기로 했습니다.
- Firestore가 빠지면 iPhone은 **앱이 화면에 있는 동안 몇 초마다 GET**으로 새 알림·승인을 확인해야 합니다. Android도 FCM을 못 받는 경우 같은 방식으로 보조합니다.
- 제안:
  1. #21·#23에 `since=<마지막 받은 시각 또는 커서>` 지원 → 대부분 빈 응답이라 가벼움 (디버그 뷰어 12.6과 같은 방식)
  2. 보호자 앱 폴링 간격: **앱이 앞에 있을 때 5초**, 백그라운드에서는 안 함 → 기기당 분당 약 24회(알림+승인). **API Gateway 스로틀이 이 정도를 허용하는지 확인** 부탁드립니다
  3. 승인 요청은 5분 안에 응답해야 하므로 iPhone은 최대 5초 늦게 보게 됩니다. 시연에서 문제면 Apple 유료 계정(APNs) 여부를 팀에서 결정
- 질문: 보호자 앱 폴링 간격을 서버 쪽에서 정해 주고 싶으면 알려 주세요 (예: 응답 헤더 `Retry-After`나 값으로).

---

## 5. 그 밖의 제안·질문

| # | 내용 | 구분 |
|---|---|---|
| 5.1 | **#13에도 `Idempotency-Key`**: 응답이 서버에 반영됐는데 네트워크가 끊겨 앱이 다시 보내면, 지금 규칙으로는 409 `already-responded`가 와서 "다른 보호자가 응답했다"고 잘못 안내됩니다. 같은 키면 처음 결과를 돌려주면 보호자 앱도 503 재시도를 넣겠습니다 | 제안 |
| 5.2 | 503·네트워크 오류 재시도: #14·#2·#4는 같은 키로 1번 재시도 (기획 4.1과 같음) | 동의 |
| 5.3 | 연결 코드 잠금: 기획은 "보호자당 10분 5회 실패 → 429", 보호자 앱 Mock은 "5회 실패 → 5분 잠금". 서버 값으로 맞추고 Mock도 고치겠습니다. 잠금이 풀리는 시각을 오류 `message`에 넣어 주면 앱이 안내 가능 | 동의 |
| 5.4 | 서버 주소 전달: Firestore `config/server` 대신 **앱 빌드 값**(`SERVER_BASE_URL`)으로 넣겠습니다. dev/prod 주소가 정해지면 알려 주세요 | 질문 |
| 5.5 | #2 `POST /v1/users/me`: 보호자 앱은 처음 실행 때 `{ role: "guardian", name: "보호자" }`를 보냄. 이미 있으면 409 → 앱은 성공으로 처리해도 되는지 (role이 같으면 200을 주면 더 간단) | 질문 |
| 5.6 | #3 `PATCH /v1/users/me` 이름 변경: 보호자 앱에 이름 입력 화면을 넣으면 사용 예정 | 참고 |
| 5.7 | dev 환경 열리면(S1) 테스트용 **고령자 계정 하나**와 코드 발급 방법이 필요 — 보호자 앱 혼자 연결·알림 흐름을 시험하기 위해 (예: dev 전용 "가짜 알림 만들기" 또는 고령자 앱 debug 빌드) | 질문 |

---

## 6. 보호자 앱이 할 일 (서버 확정 후)

1. 서버가 위 2장 수정 + 3장 응답 모양을 확정 → 보호자 앱이 Firestore 구독을 GET + FCM 갱신 + 폴링으로 교체 (`lib/repositories/server/`만 변경, 화면 변경 없음)
2. 자동 테스트: 가짜 HTTP 서버로 같은 흐름을 검증 (지금 Firestore 에뮬레이터 테스트를 대체)
3. 서버 S1(연결) → S2(알림) → S3(승인) 단계가 dev에 올라올 때마다 실제 기기로 확인

필요한 것: **dev 서버 주소**, 확정된 응답 JSON, Firebase 프로젝트 ID (지금 `copilot-demo-c9a74` 그대로인지).
