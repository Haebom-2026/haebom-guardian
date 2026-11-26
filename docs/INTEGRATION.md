# 해봄 ↔ 해봄 가족 연동 규격 (v0.1 초안)

> **문서 상태**
> - ✅ **확정(보호자 앱 구현 기준)**: 보호자 앱의 데이터 모델·Mock 서버에 이미 반영되어 자동 테스트로 검증된 내용
> - 💡 **제안**: 고령자 앱 담당자와 아직 **합의되지 않은** 내용. 합의 전까지 확정 사양이 아님
>
> ⚠️ **2026-11-25 갱신**: 서버 방식을 Cloud Functions(Callable)에서 **REST 서버(Node.js, Spark 무료 요금제)** 로 바꾸는 v2 제안이 나왔다. 3장(Cloud Functions)·6장(FCM)·8장은 **`docs/GUARDIAN_INTEGRATION.md` v2가 대체**한다. 변경 내역은 `docs/INTEGRATION_CHANGES.md`.
> 원본 `고령자 앱 ↔ 보호자 앱 연동 분석.docx`(바탕화면 `바이브 코딩/` 폴더)와의 대조는 2026-11-25에 완료했다.

---

## 1. 역할 분담

```
고령자 Android 앱 (Kotlin, 해봄)
      │  ① 민감 앱 감지 → 동의 팝업 → "예"일 때만 요청
      │  ② 승인 요청 생성 / 취소, 결과 실시간 구독
      │  ③ 6자리 연결 코드 발급 요청
      ▼
Firebase 공통 서버 (Auth · Firestore · Cloud Functions · FCM)
      │  - 연결 관계(links) 기준으로 수신 보호자 결정
      │  - 권한 검증 · 중복 방지 · 상태 전이 트랜잭션
      │  - 보호자 기기로 FCM 발송
      ▼
보호자 Flutter 앱 (Android · iOS, 해봄 가족)
         - 알림/승인 목록 실시간 구독, 읽음 처리
         - 승인/거절 응답, 가족 연결/해제
```

두 앱은 **직접 통신하지 않는다.** 모든 데이터는 서버를 거친다.

| 기능 | 고령자 앱 | 서버 | 보호자 앱 |
|---|---|---|---|
| 민감 앱 감지 | 접근성 서비스로 패키지명 감지 (구현됨) | – | – |
| 동의 팝업 | "예/아니요/닫기" 표시 (미구현) | – | – |
| 알림 생성 | "예"일 때만 `reportSensitiveEntry` 호출 | 중복 검사, 수신자 결정, 문서 생성, FCM 발송 | 목록/상세 표시, 읽음 처리 |
| 승인 요청 | `requestApproval` 호출, 결과 구독 | 문서 생성, 만료 처리, 트랜잭션 응답 | 승인/거절 |
| 가족 연결 | 코드 발급 화면 (발급만 존재) | 코드 생성·검증·횟수 제한 | 코드 입력, 해제 |
| SOS | SMS 발송 + Firestore 기록 (일부 구현) | 💡 notifications 문서 생성 + FCM | SOS 알림 표시 |

---

## 2. Firestore 컬렉션 및 필드 (✅ 보호자 앱 모델 기준)

시간 필드는 모두 Firestore `Timestamp`이며 **서버 타임스탬프(`FieldValue.serverTimestamp()`)** 로 기록한다. 보호자 앱 모델에서 문서 ID는 `id`로 다룬다.

### users/{uid}
| 필드 | 타입 | 설명 |
|---|---|---|
| role | string | `elder` \| `guardian` |
| name | string | 표시 이름 |
| createdAt | timestamp | |

### users/{uid}/devices/{deviceId}
| 필드 | 타입 | 설명 |
|---|---|---|
| fcmToken | string | 기기별 FCM 토큰 |
| platform | string | `android` \| `ios` |
| updatedAt | timestamp | |

### connectCodes/{code}  — 문서 ID = 6자리 숫자 문자열
| 필드 | 타입 | 설명 |
|---|---|---|
| elderId | string | 발급한 고령자 UID |
| expiresAt | timestamp | 발급 + 10분 |
| used | bool | 일회용 |

### links/{elderId}_{guardianId}
| 필드 | 타입 | 설명 |
|---|---|---|
| elderId | string | |
| guardianId | string | |
| elderName | string | 고령자 이름 (표시용) |
| relationship | string | 보호자가 입력한 관계 (예: 어머니) |
| connectedAt | timestamp | |

### notifications/{id}
| 필드 | 타입 | 설명 |
|---|---|---|
| elderId | string | |
| guardianIds | array&lt;string&gt; | **서버가 links 기준으로 채움** (클라이언트 지정 금지) |
| appName | string | 예: 정부24 (SOS는 빈 문자열) |
| packageName | string | 예: kr.go.minwon.m (SOS는 빈 문자열) |
| type | string | `sensitive_entry` \| `sos` \| `stuck` |
| createdAt | timestamp | |
| readBy | map&lt;string, timestamp&gt; | 보호자 UID → 읽은 시각 |

- `consent` 필드는 두지 않는다. **"예"를 선택한 경우에만 문서가 생성**되기 때문이다.
- "아니요" 또는 "닫기"는 서버를 호출하지 않는다 → 문서·활동 내역 모두 없음.

### approvals/{id}
| 필드 | 타입 | 설명 |
|---|---|---|
| elderId | string | |
| guardianIds | array&lt;string&gt; | 서버가 결정 |
| appName | string | |
| packageName | string | |
| action | string | 아래 action 코드 |
| status | string | `pending` \| `approved` \| `rejected` \| `expired` \| `cancelled` |
| createdAt | timestamp | |
| expiresAt | timestamp | 💡 생성 + 5분 (보호자 앱 Mock 기본값) |
| respondedAt | timestamp \| null | |
| respondedBy | string \| null | 응답한 보호자 UID (취소·만료 시 null) |

**action 코드 → 보호자 앱 표시 문구**

| action | UI 문구 |
|---|---|
| `guide_gov24_auth` | 정부24 본인인증 단계 안내 |
| `guide_bank_open` | 은행 앱 이용 안내 |
| `guide_unknown_app` | 처음 사용하는 앱 이용 안내 |

알 수 없는 action 값은 보호자 앱에서 "도우미 안내 진행"으로 표시된다(앱이 멈추지 않음). 💡 새 action은 추가 전에 양쪽이 목록을 공유한다.

**민감 앱 패키지명 (💡 고령자 앱 감지 목록과 대조 필요)**

| 앱 | packageName |
|---|---|
| 정부24 | kr.go.minwon.m |
| KB스타뱅킹 | com.kbstar.kbbank |
| 카카오뱅크 | com.kakaobank.channel |
| 토스 | viva.republica.toss |

---

## 3. Cloud Functions 요청/응답 (💡 제안)

모두 Callable Functions(`httpsCallable`)로 제안한다. 호출자 UID는 `context.auth.uid`에서 얻으며 **요청 본문에 UID를 넣지 않는다.**

| 함수 | 호출 앱 | 요청 | 성공 응답 |
|---|---|---|---|
| `reportSensitiveEntry` | 고령자 | `{ packageName, appName }` | `{ result: "created", notificationId }` 또는 `{ result: "duplicate_suppressed" }` / `{ result: "no_guardians" }` |
| `createSos` | 고령자 | `{}` | `{ notificationId }` |
| `requestApproval` | 고령자 | `{ packageName, appName, action }` | `{ approvalId, expiresAt }` |
| `cancelApproval` | 고령자 | `{ approvalId }` | `{ status: "cancelled" }` |
| `respondApproval` | 보호자 | `{ approvalId, decision: "approve" \| "reject" }` | `{ status, respondedAt }` |
| `issueConnectCode` | 고령자 | `{}` | `{ code, expiresAt }` |
| `connectWithCode` | 보호자 | `{ code, relationship }` | `{ elderId, elderName, relationship, connectedAt }` |
| `disconnect` | 보호자/고령자 | `{ elderId }` 또는 `{ guardianId }` | `{ ok: true }` |
| `registerDevice` | 공통 | `{ deviceId, fcmToken, platform }` | `{ ok: true }` |
| `unregisterDevice` | 공통 | `{ deviceId }` | `{ ok: true }` |

읽음 처리(`readBy.{uid}`)는 보안 규칙으로 제한된 Firestore 직접 쓰기로 처리할 수 있다(5장).

### 오류 응답 규격 (✅ 보호자 앱 `RepositoryErrorCode`와 1:1 대응)

`HttpsError(code, message, details)`의 `details.reason`에 아래 문자열을 넣는 것을 제안한다.

| reason | 의미 | 보호자 앱 안내 |
|---|---|---|
| `not-found` | 문서 없음/연결 해제됨 | 찾을 수 없습니다 |
| `permission-denied` | 연결되지 않은 사용자 | 권한 없음 |
| `already-responded` | 다른 보호자가 먼저 응답 | 이미 다른 보호자가 응답 |
| `approval-expired` | 만료 후 응답 | 시간이 지나 만료 |
| `approval-cancelled` | 고령자가 취소 | 가족이 취소 |
| `invalid-code` | 형식 오류/존재하지 않는 코드 | 코드 확인 |
| `code-expired` | 10분 경과 | 새 코드 요청 |
| `code-used` | 이미 사용된 코드 | 새 코드 요청 |
| `already-linked` | 이미 연결됨 | 이미 연결된 가족 |
| `too-many-attempts` | 연속 실패 잠금 | 잠시 후 다시 |
| `invalid-argument` | 잘못된 입력 | 입력 확인 |
| `unavailable` | 네트워크/서버 오류 | 네트워크 확인 |

---

## 4. 처리 규칙

### 4.1 가족 연결 코드
1. 고령자 앱 → `issueConnectCode` → 서버가 **암호학적 난수**로 100000–999999 중 미사용 코드를 생성, `expiresAt = now + 10분`, `used = false`.
2. 보호자 앱 → `connectWithCode` → 서버 트랜잭션에서 순서대로 검증:
   형식(숫자 6자리) → 존재 → `used` → 만료 → 이미 연결 여부 → `used = true` 설정 + `links` 생성.
3. **무작위 대입 방지(✅ Mock 구현)**: 보호자별 연속 실패 5회 시 5분 잠금(`too-many-attempts`). 💡 실제 서버에서는 IP/기기 단위 제한을 추가 검토.
4. 한 고령자–여러 보호자, 한 보호자–여러 고령자 모두 허용(links 문서 ID가 쌍 단위).
5. 💡 고령자가 새 코드를 발급하면 이전 미사용 코드는 무효화할지 합의 필요.

### 4.2 민감 앱 알림 중복 방지 (✅ Mock 구현)
- **고령자 앱 측(💡 제안)**: 같은 패키지 안에서 화면(Activity)이 바뀌는 것은 새 진입으로 보지 않는다. 다른 패키지로 전환된 뒤 다시 들어올 때만 "진입"으로 간주하고, 팝업 자체도 같은 앱에 대해 일정 시간 다시 띄우지 않는다.
- **서버 측**: 같은 `elderId + packageName + type=sensitive_entry`가 **최근 5분 이내**에 있으면 새 문서를 만들지 않고 `duplicate_suppressed`를 반환한다.
- 표현 원칙: "이용 사실"만 알린다. 개인정보 입력 여부를 감지했다고 표현하지 않는다.

### 4.3 승인 상태 전이 (✅ Mock 구현)

```
             respondApproval(approve)   ┌──────────┐
          ┌────────────────────────────►│ approved │
          │                             └──────────┘
┌─────────┤  respondApproval(reject)    ┌──────────┐
│ pending ├────────────────────────────►│ rejected │
└─────────┤                             └──────────┘
          │  now ≥ expiresAt            ┌──────────┐
          ├────────────────────────────►│ expired  │
          │                             └──────────┘
          │  cancelApproval (고령자)     ┌───────────┐
          └────────────────────────────►│ cancelled │
                                        └───────────┘
```
- `pending`에서만 전이 가능. 종료 상태는 변경 불가.
- 만료 시각이 지났는데 아직 `pending`인 문서에 응답이 오면, 서버는 `expired`로 바꾸고 `approval-expired`를 반환한다.
- 💡 만료는 응답 시점 검사 + 주기적 Scheduled Function 둘 다로 처리한다(고령자 앱이 결과를 받을 수 있도록).

### 4.4 여러 보호자의 동시 응답 (✅ Mock 구현)
`respondApproval`은 **Firestore 트랜잭션** 안에서 `status == pending && now < expiresAt`을 확인한 뒤 갱신한다. 따라서 **최초의 유효한 응답 하나만** 반영되고, 나머지는 `already-responded`를 받는다. 보호자 앱은 이 오류를 받으면 최신 상태를 다시 표시한다.

### 4.5 고령자 앱의 결과 수신
고령자 앱은 자신이 만든 `approvals/{id}` 문서를 `addSnapshotListener`로 구독한다.

| status | 고령자 앱 동작 |
|---|---|
| approved | AI 도우미 안내 계속 |
| rejected | 안내 중단 |
| expired | 응답 없음 → 안내 중단 |
| cancelled | (고령자 본인이 취소) 종료 |

보호자 앱 개발자 테스트 화면의 "고령자 앱 수신 결과 (9)" 영역에서 이 동작을 Mock으로 확인할 수 있다.

---

### 4.6 💡 제안: 이용 알림과 승인 요청의 구분, 승인 대기 정책 (미합의)

> 보호자 앱 테스트 중 나온 문제 제기를 정리한 것이다. **현재 구현(4.3~4.5)을 바꾸지 않았으며**, 고령자 앱 담당자와 합의한 뒤 반영한다.

**문제**
1. 고령자는 민감 앱에 들어갈 때 이미 "보호자에게 알릴지"를 직접 고른다. 등본 발급 같은 일상 업무에 승인까지 받게 하면 같은 동의를 두 번 묻는 셈이다.
2. 거절해도 실제로 막을 수 있는 것은 없다. 해봄 도우미의 안내만 멈추고, 고령자가 앱을 직접 쓰는 것은 그대로 가능하다.
3. 현재 규격(보호자 앱 Mock 기본값)대로라면 고령자 앱은 승인 응답을 **최대 5분 동안 기다리고**, 아무도 응답하지 않으면 `expired → 안내 중단`이 된다. 보호자가 알림을 못 보면 고령자는 기다리다가 아무 도움도 받지 못한다. (정정 2026-11-25: 연동 분석 문서 기준 고령자 앱에는 승인 요청 코드가 아직 없다. 이전 판에는 "현재 고령자 앱은"이라고 잘못 적었다.)

**제안 A — 두 기능의 역할을 나눈다**

| 구분 | 이용 알림 (`notifications`) | 승인 요청 (`approvals`) |
|---|---|---|
| 쓰는 상황 | 일상 업무: 정부24 등본, 은행 앱 열기, 조회 | 위험할 수 있는 순간에만: 보이스피싱 의심(통화 중 앱 설치나 링크 지시), 처음 보는 앱 설치, 송금·이체 화면 첫 진입 |
| 고령자 앱 | **기다리지 않고** 계속 진행 | 응답을 기다림 (제안 B) |
| 보호자 앱 | "확인"만 하면 됨 | "계속해도 돼요" / "잠깐 멈춰요(제가 전화할게요)" |

- 보호자가 이용 알림을 확인하면 이미 있는 `notifications.readBy.{guardianUid}`가 기록된다. 고령자 앱이 이 값을 구독해 "딸이 확인했어요"를 보여줄 수 있다. **새 필드가 필요 없다.**
- 승인 버튼 문구는 실제 의미에 맞게 바꾼다. 승인 = 도우미 안내 계속, 거절 = 고령자에게 "잠깐 멈추세요, 가족이 연락할 거예요" 표시. 내부 상태값(`approved`/`rejected`)은 그대로 둔다.
- action 코드는 위험 상황 위주로 다시 정한다. 예) `guide_suspicious_call`, `guide_app_install`, `guide_transfer_first` (이름 미정)

**제안 B — 승인 대기 정책 (위험 상황에만 적용)**

| 시점 | 고령자 앱 | 서버 / 보호자 앱 |
|---|---|---|
| 요청 직후 | "가족에게 물어보는 중이에요 (남은 시간 2:00)" + **바로 전화 걸기** 버튼 + "기다리지 않고 멈추기" | 연결된 보호자 **전원**에게 동시 발송 (현재와 동일), 가장 먼저 온 응답만 반영 |
| 1분 경과·응답 없음 | (변화 없음) | 💡 서버가 보호자 전원에게 알림 한 번 더 발송 |
| 만료 (💡 2~5분) | "가족이 아직 확인하지 못했어요. 확실하지 않으면 지금은 멈추고, 가족과 통화한 뒤 다시 해 보세요." + 전화 걸기 | `expired` |
| 만료 후 기본 동작 | **자동으로 진행시키지 않는다** (위험 상황이므로) | — |

**보호자 앱 쪽 반영 상태**
- 데모 시나리오 "⓪ 정부24 등본 발급 따라하기"는 제안 A에 맞춰 **승인 요청 없이** 이용 알림과 도움 필요 알림만 보낸다.
- 승인 화면, 상태 전이, 만료 처리는 4.3~4.5의 현재 규격 그대로다.

## 5. Firestore 보안 규칙 설계 (💡 제안)

원칙: **쓰기는 대부분 Cloud Functions(Admin SDK)만**, 클라이언트는 읽기 + 제한된 필드 쓰기. 기존 테스트 프로젝트의 광범위한 `allow read, write: if true` 류 규칙은 사용하지 않는다.

```js
rules_version = '2';
service cloud.firestore {
  match /databases/{db}/documents {
    function signedIn() { return request.auth != null; }
    function me() { return request.auth.uid; }
    function linked(elderId) {
      return exists(/databases/$(db)/documents/links/$(elderId + '_' + me()));
    }

    match /users/{uid} {
      allow read: if signedIn() && me() == uid;
      allow create, update: if signedIn() && me() == uid
        && request.resource.data.role in ['elder', 'guardian'];
      match /devices/{deviceId} {
        allow read, write: if signedIn() && me() == uid;
      }
    }

    match /connectCodes/{code} { allow read, write: if false; } // Functions 전용

    match /links/{id} {
      allow read: if signedIn()
        && (resource.data.guardianId == me() || resource.data.elderId == me());
      allow write: if false; // connectWithCode / disconnect 함수 전용
    }

    match /notifications/{id} {
      allow read: if signedIn() && (
        (me() in resource.data.guardianIds && linked(resource.data.elderId))
        || resource.data.elderId == me());
      // 보호자는 자기 readBy 항목만 추가 가능
      allow update: if signedIn()
        && me() in resource.data.guardianIds && linked(resource.data.elderId)
        && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['readBy'])
        && request.resource.data.readBy.diff(resource.data.readBy).affectedKeys().hasOnly([me()]);
      allow create, delete: if false;
    }

    match /approvals/{id} {
      allow read: if signedIn() && (
        (me() in resource.data.guardianIds && linked(resource.data.elderId))
        || resource.data.elderId == me());
      allow write: if false; // 상태 변경은 트랜잭션 함수 전용
    }
  }
}
```

연결이 해제된 보호자는 `linked()` 검사로 과거 알림·승인도 읽을 수 없다(✅ Mock에서도 동일하게 차단, 자동 테스트 있음).

---

## 6. FCM

### 6.1 기기 토큰 (💡 제안)
- 로그인 직후, 그리고 `onTokenRefresh` 때마다 `registerDevice({deviceId, fcmToken, platform})`.
- `deviceId`는 앱 설치 단위 UUID(로컬 저장). 한 보호자가 여러 기기를 쓸 수 있다.
- 로그아웃 시 `unregisterDevice` 후 `deleteToken()`.
- 발송 시 `UNREGISTERED`/`INVALID_ARGUMENT` 응답을 받은 토큰은 서버가 삭제.

### 6.2 payload (💡 제안, 보호자 앱 로컬 알림과 동일한 구조)

잠금 화면에 민감 정보가 드러나지 않도록 **notification 영역은 최소 문구**, 상세는 앱에서 조회한다.

```json
{
  "notification": { "title": "해봄 가족", "body": "새 가족 알림이 도착했습니다." },
  "data": {
    "kind": "notification",
    "id": "<notifications 문서 ID>",
    "type": "sensitive_entry"
  },
  "android": { "notification": { "channel_id": "family_activity", "visibility": "PRIVATE" } },
  "apns": { "payload": { "aps": { "thread-id": "family_activity" } } }
}
```

| 알림 | data.kind | Android channel_id | title | 기본 body (✅ 로컬 알림 구현 문구) |
|---|---|---|---|---|
| 민감 앱 이용 (sensitive_entry) | `notification` | `family_activity` | 해봄 가족 | 새 가족 알림이 도착했습니다. |
| 도움 필요 (stuck) | `notification` | `family_activity` | 해봄 가족 | 가족에게 도움이 필요할 수 있습니다. 앱에서 확인해 주세요. |
| SOS (sos) | `notification` | `sos_alerts` | 해봄 가족 · 긴급 | 가족이 도움을 요청했습니다. 앱에서 확인해 주세요. |
| 승인 요청 | `approval` | `approval_requests` | 해봄 가족 · 승인 요청 | 확인이 필요한 요청이 도착했습니다. |

보호자가 설정에서 "알림에 상세 내용 표시"를 켠 경우에만 body에 "어머니가 정부24에 접속했습니다." 같은 상세 문구를 넣는다(기본값 꺼짐).

보호자 앱은 `data.kind:data.id`를 기존 로컬 알림 payload(`AlertTarget`)와 같은 방식으로 해석해 상세 화면으로 이동한다. 대상 문서가 없거나(연결 해제 등) 이미 만료된 경우에는 상세 화면에서 안내 문구를 표시한다(✅ 구현).

### 6.3 iOS
APNs 인증 키(.p8) 등록, Xcode Push Notifications / Background Modes(remote notifications) capability가 필요하다. **Apple Developer 유료 계정이 필요**하므로 이번 Mock 단계에서는 진행하지 않았다.

---

## 7. 오프라인 / 네트워크 오류 (💡 제안)

- 읽기: Firestore 오프라인 캐시 사용. 화면에는 마지막 동기화 데이터를 표시.
- 승인 응답·가족 연결은 **오프라인 큐잉 금지** — 즉시 `unavailable` 오류를 표시하고 재시도 버튼 제공(만료 시간이 있는 작업이므로).
- 고령자 앱의 `reportSensitiveEntry` 실패 시: 💡 재시도 1회 후 포기(오래된 알림을 늦게 보내지 않음).

---

## 8. 고령자 앱(Kotlin) 담당자 전달 사항

### 구현이 필요한 항목
1. 민감 앱 진입 감지 (패키지명 목록은 2장 표 기준, 같은 앱 내 화면 전환은 무시)
2. 동의 팝업: **"민감한 개인정보를 사용하는 서비스입니다. 보호자에게 알림을 보내겠습니까?"** — 예/아니요/닫기. 예일 때만 서버 호출
3. 승인 요청 생성 + `approvals/{id}` 스냅샷 구독 + 결과별 도우미 동작
4. 승인 요청 취소
5. 연결 코드 발급을 서버 함수 호출 방식으로 변경(현재 클라이언트 생성이라면)
6. FCM 토큰 등록(고령자 앱이 결과를 푸시로도 받을 경우)

### Kotlin 호출 예시 (💡 함수 이름 합의 전)

```kotlin
val functions = Firebase.functions("asia-northeast3")

// 1) 동의 팝업에서 "예"를 누른 경우에만
fun onConsentYes(app: DetectedApp) {
    functions.getHttpsCallable("reportSensitiveEntry")
        .call(mapOf("packageName" to app.packageName, "appName" to app.appName))
        .addOnFailureListener { /* 재시도 1회 후 포기 */ }
}
// "아니요"/"닫기": 아무 것도 호출하지 않는다.

// 2) 승인 요청 + 결과 구독
fun requestApproval(app: DetectedApp, action: String) {
    functions.getHttpsCallable("requestApproval")
        .call(mapOf("packageName" to app.packageName, "appName" to app.appName, "action" to action))
        .addOnSuccessListener { r ->
            val id = (r.data as Map<*, *>)["approvalId"] as String
            Firebase.firestore.collection("approvals").document(id)
                .addSnapshotListener { snap, _ ->
                    when (snap?.getString("status")) {
                        "approved" -> helper.continueGuide()
                        "rejected", "expired" -> helper.stopGuide()
                        else -> Unit // pending, cancelled
                    }
                }
        }
}
```

### 확인/합의가 필요한 사항
| # | 항목 | 현재 상황 |
|---|---|---|
| 1 | 공통 Firebase 프로젝트 | 고령자 앱은 `copilot-demo-c9a74` 사용 중. 공통 사용 여부 미정 → **현재 해당 프로젝트는 변경하지 않음** |
| 2 | applicationId | `com.example.copilot.parent` (namespace `com.yju.elder`) — `com.example`은 Play 스토어 배포 불가, 변경 여부 |
| 3 | 보호자 앱 ID | Android `com.yju.haebom.guardian_app`, iOS `com.yju.haebom.guardianApp` |
| 4 | 민감 앱 패키지명 목록 | 2장 표 대조 |
| 5 | 승인 유효시간 | 보호자 앱 Mock 5분 |
| 6 | 중복 알림 기준 시간 | 서버 5분 |
| 7 | 연결 코드 재발급 시 이전 코드 무효화 | 미정 |
| 8 | SOS를 notifications로도 기록할지 | 현재 SMS + 일부 Firestore 기록 |
| 9 | `stuck`(도움 필요) 알림 발생 조건 | 고령자 앱 정의 필요 |
| 10 | 고령자 이름/관계 표시 | `links.elderName`(고령자 등록 이름) + `relationship`(보호자 입력) |
| 11 | Functions 리전 | 💡 asia-northeast3(서울) |
| 12 | 이용 알림과 승인 요청의 구분, 승인 대기 정책 | 💡 4.6 제안 A·B — 일상 업무는 승인 없이 진행, 위험 상황만 승인 대기, 만료 시 자동 진행 금지 |
| 13 | 보호자 "확인"을 고령자 앱에 표시 | 💡 `readBy` 구독으로 "딸이 확인했어요" 표시 (새 필드 없음) |

---

## 9. 통합 테스트 시나리오 (실제 Firebase 연동 후)

| # | 시나리오 | 기대 결과 |
|---|---|---|
| 1 | 고령자 정부24 진입 → 예 | 보호자 기기 2대 모두 푸시 수신, 목록에 "어머니가 정부24에 접속했습니다." |
| 2 | 진입 → 아니요 / 닫기 | 서버 호출 없음, 보호자 목록 변화 없음 |
| 3 | 정부24 안에서 화면 이동 | 추가 알림 없음 |
| 4 | 5분 내 같은 앱 재진입 → 예 | `duplicate_suppressed`, 알림 1건 유지 |
| 5 | 보호자 A 읽음 | A만 읽음, B는 읽지 않음 유지 |
| 6 | 승인 요청 → 보호자 승인 | 고령자 앱 1초 내 안내 계속 |
| 7 | 보호자 A·B 동시 승인/거절 | 하나만 반영, 다른 쪽 `already-responded` |
| 8 | 5분 경과 후 승인 시도 | `approval-expired`, 고령자 앱 안내 중단 |
| 9 | 고령자 취소 후 보호자 응답 | `approval-cancelled` |
| 10 | 코드 발급 → 입력 | links 생성, 양쪽 목록 반영 |
| 11 | 만료 코드 / 사용된 코드 / 잘못된 코드 5회 | 각 오류 코드, 5회 후 잠금 |
| 12 | 연결 해제 후 과거 알림 조회 | `permission-denied`, 목록에서 사라짐 |
| 13 | 보호자 로그아웃 | 해당 기기 푸시 중단 |
| 14 | 비행기 모드에서 승인 | `unavailable` 안내, 상태 변경 없음 |
| 15 | iPhone 잠금 화면 | 최소 문구만 표시, 서비스명 미노출 |
