# 세 파트가 반드시 통일할 규격 (보호자 앱 · 고령자 앱 · 서버)

> 작성일: 2026-11-26 · 작성: 보호자 앱 담당
> 비교 자료: 고령자 앱 `해봄_개발지침서.md`(11-25) 5장 · 보호자 앱 코드(`lib/`) · `docs/SERVER_API.md` · `docs/DATA_SPEC_CHANGES.md`(v2.2)
> 원칙: 엔드포인트 15개, DB 구조, **고령자 ↔ 보호자 다대다(M:N)** 는 유지한다. 아래는 그 안에서 값·이름·동작을 맞추는 항목이다.
> 표시: ✅ 세 문서·코드가 같음 · ⚠️ 서로 다름 (결정 필요) · ❓ 서버 구현에 달림 (확인 필요)

---

## 0. 먼저 결정할 것 (⚠️)

| # | 항목 | 고령자 앱 지침서 | 보호자 앱 | 결정할 사람 |
|---|---|---|---|---|
| A | **서버 담당** | "보호자 앱 담당이 서버(REST API·규칙·FCM·가족 연결)" (1장) | 서버·FCM 발송은 서버 담당 팀원 (11-25 결정) | 팀 전체 |
| B | **서버 방식** | Firebase Functions | 별도 서버 구축·Blaze 가입 금지 원칙. Functions는 Blaze 필요 | 팀 전체 + 프로젝트 소유자 |
| C | **보호자 "확인했어요" 기록** | Firestore는 두 앱 모두 **읽기만** (5.2 마지막) | 보호자 앱이 `notifications/{id}.readBy.{내 uid}`를 **직접 씀** | 서버 담당 (규칙으로 허용할지, API를 추가할지) |
| D | ~~가족 호칭 필드~~ ✅ **합의 (11-26)** | 고령자 앱도 `elderLabel`·`guardianLabel` 두 개로 통일, `relationship` 사용 중단 | 동일 (v2.2). 옛 `relationship`은 elderLabel로 읽음 | 기존 `relationship` 값 이전 방법만 서버 담당이 결정 |

- C를 규칙으로 허용할 경우 조건: 연결된 보호자가 `readBy`의 **자기 uid 키 하나만** 추가·갱신. 다른 필드 변경 불가.
- D: 보호자 앱은 `relationship`만 와도 그 값을 `elderLabel`로 읽는다(동작함). 다만 고령자 앱이 "딸이 허락했어요"처럼 쓰려면 `guardianLabel`이 필요하다.

---

## 1. Firestore 문서 (✅ 대부분 같음)

| 컬렉션 | 필드 | 상태 |
|---|---|---|
| `links/{elderId}_{guardianId}` | elderId, guardianId, elderName, **elderLabel, guardianLabel**, connectedAt(Timestamp) | ✅ (D 합의) |
| `notifications/{id}` | elderId, guardianIds[], appName, packageName, type, createdAt(Timestamp), readBy{uid: Timestamp}, level?, category?, reason? | ✅ (readBy 쓰기 주체는 ⚠️ C) |
| `approvals/{id}` | elderId, guardianIds[], appName, packageName, action, status, createdAt, expiresAt, respondedAt, respondedBy, category? | ✅ |
| `connectCodes/{code}` | elderId, expiresAt, used | ✅ 서버만 읽고 씀. 💡 `links.elderName`을 채울 수 있게 서버가 `users/{elderId}.name`을 읽거나 코드 문서에 이름을 함께 저장 |
| `users/{uid}` | role(elder \| guardian), name | ✅ 보호자 이름은 "보호자" 고정 |
| `users/{uid}/devices/{deviceId}` | fcmToken, platform | ✅ (SERVER_API.md 6장) |
| `config/server` | baseUrl | ❓ 서버 주소를 이 문서로 알릴지 (아니면 보호자 앱 빌드 값 `SERVER_BASE_URL`) |

**값 목록 (철자까지 같아야 함)**
| 필드 | 값 |
|---|---|
| notifications.type | `sensitive_entry` · `sos` · `stuck` |
| approvals.status | `pending` · `approved` · `rejected` · `expired` · `cancelled` |
| approvals.action | `guide_gov24_auth` · `guide_bank_open` · `guide_money_move` · `guide_identity` · `guide_install` · `guide_privacy_send` (보호자 앱은 `guide_unknown_app`도 표시 가능) |
| level | `L0` · `L1` · `L2` · `L3` |
| category | `finance` · `identity` · `public` · `device` · `privacy` · `scam` · `none` |
| users.role | `elder` · `guardian` |

**시간**: Firestore는 `Timestamp`, API 응답은 ISO 8601 UTC 문자열(`2026-11-26T01:00:00Z`). 승인 만료 기본 5분(`expiresAt` 없으면 보호자 앱은 생성 + 5분으로 봄).

**다대다**: 연결은 쌍마다 `links` 문서 1개. 알림·승인의 `guardianIds`는 **서버가 links 기준으로** 채운다(앱은 지정하지 않음).

---

## 2. REST API (✅ 경로 15개 일치)

| 항목 | 규격 | 상태 |
|---|---|---|
| 주소 | `https://<서버>/v1/...` | ❓ 주소 확정 |
| 인증 | `Authorization: Bearer <Firebase ID 토큰>`, 본문에 uid 넣지 않음 | ✅ |
| 중복 요청 | 쓰기 요청에 `Idempotency-Key`(UUID v4), 재시도 때 같은 키 | ✅ 보호자 앱은 연결(#14)에 붙임 · ❓ 서버가 키로 중복 처리하는지 |
| 오류 형식 | `{ "error": { "reason": "...", "message": "..." } }` — 앱은 reason만 봄 | ✅ |
| 재시도 | 401 → 토큰 새로 받아 1번 / 403 `profile-required` → #2 후 1번 | ✅ 보호자 앱 11-26 구현 |
| 재시도 | 503·네트워크 → 같은 키로 1번 | ⚠️ 보호자 앱은 **하지 않음** (아래 참고) |
| #13 승인 응답 | `POST /v1/guardian/approvals/{id}/respond` `{ "decision": "approve" \| "reject" }` | ✅ |
| #14 코드로 연결 | `POST /v1/guardian/links` `{ code, elderLabel, guardianLabel }` → `{ elderId, elderName, elderLabel, guardianLabel, connectedAt }` | ✅ (D 합의) |
| #15 보호자 쪽 해제 | `DELETE /v1/guardian/links/{elderId}` | ✅ |
| #12 고령자 쪽 해제 | `DELETE /v1/elder/links/{guardianId}` | ✅ (고령자 앱 "할 일") |
| #11 코드 발급 | `POST /v1/elder/connect-codes` → `{ code, expiresAt }` | ✅ (고령자 앱 "할 일") |

**503 재시도를 보호자 앱이 하지 않는 이유**: 승인 응답(#13)은 Idempotency-Key가 없다. 첫 요청이 서버에 반영됐는데 응답만 끊긴 경우 다시 보내면 `409 already-responded`가 와서 "다른 보호자가 응답했다"고 잘못 안내된다. 💡 서버가 #13에도 Idempotency-Key를 받아 같은 키면 처음 결과를 돌려주기로 하면 보호자 앱도 재시도를 넣는다.

**오류 reason (보호자 앱이 문구를 가진 것)**
`invalid-code` · `code-expired` · `code-used` · `already-linked` · `too-many-attempts` · `already-responded` · `approval-expired` · `approval-cancelled` · `not-found` · `permission-denied` · `invalid-argument` · `unavailable` + `unauthenticated` · `profile-required` · `role-locked` · `rate-limited`

---

## 3. 서버가 지켜야 할 규칙 (❓ 서버 구현 확인)

| 규칙 | 내용 |
|---|---|
| 승인 동시 응답 | 트랜잭션에서 **status가 pending이고 만료 전일 때만** 반영. 늦은 응답은 409 `already-responded` / 만료 `approval-expired` / 취소 `approval-cancelled` |
| 승인 만료 | expiresAt 지난 pending → `expired` (고령자 앱은 expiresAt + 5초에 자체 처리) |
| 연결 코드 | 6자리, 10분, 일회용, 새 코드 발급 시 이전 미사용 코드 무효, 보호자별 5회 실패 → 5분 잠금 |
| 해제 | `links` 문서 삭제. 보안 규칙이 해제된 보호자의 과거 알림·승인 읽기를 막음 |
| 민감 앱 알림 중복 | 같은 고령자·같은 앱 10분 안에는 새 문서를 만들지 않음 |
| 연결된 보호자 없음 | `{ "result": "no_guardians" }` (고령자 앱 안내용) |

**보안 규칙이 허용해야 하는 보호자 앱 쿼리**
- `links` where `guardianId == 나`
- `notifications` / `approvals` where `elderId == X` and `guardianIds array-contains 나` (X는 내 links의 elderId — 규칙의 `exists(links/{X}_{나})` 검사를 통과하려면 쿼리에 elderId가 고정돼야 함)
- `notifications/{id}` 업데이트: `readBy.{나}`만 (⚠️ C)
- `config/server` 읽기 (서버 주소를 이 문서로 알릴 경우)

---

## 4. FCM (서버 → 보호자 Android)

| 종류 | data.kind | data.id | data.type | android channelId |
|---|---|---|---|---|
| 민감 앱 이용 | `notification` | 문서 ID | `sensitive_entry` | `family_activity` |
| 도움 필요 | `notification` | 문서 ID | `stuck` | `help_alerts` |
| SOS | `notification` | 문서 ID | `sos` | `sos_alerts` |
| 사기 의심 (`category: scam` 또는 `level: L3`) | `notification` | 문서 ID | (그대로) | `sos_alerts` |
| 승인 요청 | `approval` | 문서 ID | – | `approval_requests` |

- 잠금 화면용 `notification.body`는 짧은 문구만 (예: "새 가족 알림이 도착했습니다."). 앱 이름·내용은 넣지 않는다.
- 발송 대상: `users/{보호자 uid}/devices/*`의 **등록 토큰**(`getToken`). Installation ID 방식이 아님. ❓ 서버 확인
- `UNREGISTERED` 응답이면 그 기기 문서 삭제
- iPhone은 원격 푸시 없음 (앱 실행 중 Firestore로 받음)

---

## 5. 로그인

- 1차 시연: **익명 로그인**(두 앱 모두). ⚠️ 앱을 지우거나 데이터를 지우면 uid가 바뀌어 연결이 사라진다 → 시연 기기에서 재설치하지 않기. 2차: 전화번호 인증 연결(`linkWithCredential`, 고령자 앱 검토 #13).
- 처음 실행 때 `POST /v1/users/me` `{ role, name }` → 이후 기기 등록·연결 가능 (아니면 403 `profile-required`).

---

## 6. 보내는 순서 (제안)
1. 0장 A·B를 팀 회의로 결정
2. 고령자 앱 담당: 0장 D, 1장 값 목록 확인
3. 서버 담당: 0장 C, 2장 ❓, 3장 전체, 4장 발송 대상 확인
4. 결정된 내용을 `GUARDIAN_INTEGRATION.md`에 ✅로 반영 → 세 파트가 같은 문서를 기준으로 개발
