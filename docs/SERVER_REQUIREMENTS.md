# 보호자 앱 ↔ 공통 서버: 서버 담당자에게 받아야 할 정보

> 작성일: 2026-11-25 · 작성: 보호자 앱 담당
> 역할 분담 (2026-11-25 확정)
> - 고령자 Android 앱: 팀원 A
> - **공통 백엔드 서버 + FCM 발송: 팀원 B (개발 중)**
> - **보호자 Flutter 앱(Android/iOS) + FCM 수신: 나**
> - Firebase 프로젝트: **`copilot-demo-c9a74` 공동 사용으로 결정** (2026-11-25 사용자 결정). 설정·규칙 변경은 소유자 동의 후, 규칙 배포는 서버 담당자
>
> 보호자 앱은 서버 없이도 개발할 수 있게 만들어 두었다. 아래 값을 받으면 **코드 수정 없이 설정 파일만 채워서** 연결한다.
> 보호자 앱 쪽 구현 위치: `lib/repositories/server/` (API·Firestore), `lib/services/push_service.dart` (FCM)

---

## 1. Firebase 프로젝트 정보 (보호자 앱 실행에 꼭 필요)

| # | 받을 정보 | 용도 | 보호자 앱 설정 키 |
|---|---|---|---|
| 1 | 프로젝트 ID | Firebase 초기화 | `FIREBASE_PROJECT_ID` |
| 2 | 프로젝트 번호(Sender ID) | FCM | `FIREBASE_MESSAGING_SENDER_ID` |
| 3 | **보호자 Android 앱 등록** (패키지 `com.yju.haebom.guardian_app`) 후 API 키·앱 ID | Android 연결 | `FIREBASE_ANDROID_API_KEY`, `FIREBASE_ANDROID_APP_ID` |
| 4 | **보호자 iOS 앱 등록** (번들 ID `com.yju.haebom.guardianApp`) 후 API 키·앱 ID | iOS 연결 | `FIREBASE_IOS_API_KEY`, `FIREBASE_IOS_APP_ID` |

- 앱 등록은 **프로젝트 설정 변경**이므로 프로젝트 소유자(팀원)가 하거나, 소유자 동의 후 내가 한다.
- 등록 후 받은 `google-services.json` / `GoogleService-Info.plist`에서 위 값만 `config/firebase.json`에 옮긴다 (파일 자체는 Git에 올리지 않음, `config/firebase.example.json` 참고).

## 2. 서버 API 규격 (아직 미정 — 확정본 필요)

보호자 앱은 아래 **v2 초안**(`docs/GUARDIAN_INTEGRATION.md` 4장)으로 구현해 두었고, 경로는 `ServerEndpoints` 한곳에서 바꿀 수 있다. 실제 서버 규격과 다르면 그 차이를 알려 주면 된다.

| # | 확인할 것 | 보호자 앱 현재 가정 |
|---|---|---|
| 1 | 서버 방식 | HTTPS REST (Cloud Functions Callable이면 알려 주기 — 구조 변경 필요) |
| 2 | 서버 주소 전달 방식 | 고정 주소(`SERVER_BASE_URL`) 또는 Firestore `config/server` 문서의 `baseUrl` 필드 구독 |
| 3 | 인증 | `Authorization: Bearer <Firebase ID 토큰>`, 서버가 `verifyIdToken` |
| 4 | 보호자 프로필 생성 | `POST /v1/users/me { role: "guardian", name }` (역할은 최초 1회, 서버가 기록) |
| 5 | 승인·거절 | `POST /v1/guardian/approvals/{id}/respond { decision: "approve"\|"reject" }` → `{ status, respondedAt }` |
| 6 | 가족 연결 | `POST /v1/guardian/links { code, relationship }` + `Idempotency-Key` → `{ elderId, elderName, relationship, connectedAt }` |
| 7 | 연결 해제 | `DELETE /v1/guardian/links/{elderId}` |
| 8 | FCM 기기 등록 | `PUT /v1/devices/{deviceId} { fcmToken, platform }`, 해제 `DELETE /v1/devices/{deviceId}` |
| 9 | 오류 형식 | HTTP 상태 + `{ "error": { "reason": "...", "message": "..." } }`, reason은 기존 12종(+ `unauthenticated`, `profile-required`, `role-locked`, `rate-limited`) |
| 10 | 읽음(확인) | 서버 API 없이 보호자 앱이 Firestore `notifications/{id}.readBy.{uid}`에 직접 쓰기 (보안 규칙으로 자기 항목만 허용) |

## 3. FCM 발송 형식 (보호자 앱 수신과 맞춰야 함)

| # | 확인할 것 | 보호자 앱 현재 가정 |
|---|---|---|
| 1 | **발송 대상** | **FCM 등록 토큰**(Admin SDK `send({ token })`). firebase_messaging 17의 새 방식(Firebase Installation ID direct-send)을 쓰면 알려 주기 |
| 2 | 메시지 종류 | `notification` + `data`가 함께 있는 메시지 (백그라운드·종료 상태에서 Android 시스템이 직접 표시) |
| 3 | `data` | `kind`: `notification` \| `approval`, `id`: Firestore 문서 ID, `type`: `sensitive_entry` \| `stuck` \| `sos` (승인은 생략 가능) — 알림을 누르면 이 값으로 상세 화면 이동 |
| 4 | Android 채널 | `android.notification.channel_id`: `family_activity`(이용·도움 필요) / `sos_alerts`(SOS) / `approval_requests`(승인) — 보호자 앱이 이미 만든 채널 |
| 5 | 잠금 화면 문구 | 최소 문구: "새 가족 알림이 도착했습니다." / "가족에게 도움이 필요할 수 있습니다. 앱에서 확인해 주세요." / "가족이 도움을 요청했습니다. 앱에서 확인해 주세요." / "확인이 필요한 요청이 도착했습니다." 제목 "해봄 가족"(SOS "해봄 가족 · 긴급", 승인 "해봄 가족 · 승인 요청") |
| 6 | 중복 방지 | `android.notification.tag` = 문서 ID 권장 (같은 알림이 두 번 와도 알림창에 하나) |
| 7 | 우선순위 | `android.priority: "high"` |
| 8 | 무효 토큰 | 발송 결과 `UNREGISTERED`면 서버가 기기 문서 삭제 |
| 9 | iOS | APNs 키가 없으므로 iOS 원격 푸시는 보내지 않아도 됨 (Apple 유료 계정 생기면 추가) |

예시 (Admin SDK)
```js
await admin.messaging().send({
  token,
  notification: { title: '해봄 가족', body: '새 가족 알림이 도착했습니다.' },
  data: { kind: 'notification', id: notificationId, type: 'sensitive_entry' },
  android: { priority: 'high', notification: { channelId: 'family_activity', tag: `notification_${notificationId}` } },
});
```

## 4. Firestore 데이터·보안 규칙 (보호자 앱이 직접 읽음)

| # | 확인할 것 | 보호자 앱이 실제로 하는 쿼리 |
|---|---|---|
| 1 | links 읽기 | `links where guardianId == 나` |
| 2 | 알림 읽기 | 연결된 가족마다 `notifications where elderId == X && guardianIds array-contains 나` (정렬은 앱에서) |
| 3 | 승인 읽기 | 같은 방식으로 `approvals` |
| 4 | 확인 쓰기 | `notifications/{id}`의 `readBy.{나}`만 update |
| 5 | 서버 주소 문서 | `config/server` 읽기 (2장 #2를 이 방식으로 할 경우) |

- 위 쿼리가 **보안 규칙에서 허용되는지** 확인 필요. (쿼리에 `elderId`를 고정한 이유: 규칙의 `exists(links/{elderId}_{uid})` 검사를 통과시키기 위해)
- 필드 구조는 `docs/GUARDIAN_INTEGRATION.md` 3장 그대로. `createdAt`·`expiresAt`·`respondedAt`·`readBy` 값은 Firestore Timestamp.

## 5. 기존 Firebase 프로젝트 공동 사용 — 확인 목록

> 나는 콘솔에 직접 접속해 확인하지 않았다. **아래는 사용자(나)가 콘솔에서 직접 보거나 소유자에게 물어볼 항목**이다. 확인 전에는 아무 설정도 바꾸지 않는다.
> 참고: 고령자 앱 검토 문서에 따르면 고령자 앱은 `copilot-demo-c9a74`를 쓰고 있고, 이 프로젝트는 옛 학습용 앱 4개·`families` 규칙·Hosting APK가 섞여 있어 **고령자 앱 담당자는 새 공통 프로젝트를 권장**했다. 공유받은 프로젝트가 이 프로젝트인지 먼저 확인한다.

| # | 항목 | 콘솔에서 보는 곳 | 판단 기준 |
|---|---|---|---|
| 1 | 프로젝트 ID | 톱니바퀴 → 프로젝트 설정 → 일반 | `copilot-demo-c9a74`인지 |
| 2 | **요금제** | 왼쪽 아래 (Spark / Blaze) | Blaze면 결제는 **소유자 계정**에 걸려 있음 → 보호자 앱 사용량도 소유자 비용이 될 수 있다는 점을 소유자와 공유. 나는 가입·카드 등록하지 않음 |
| 3 | 내 권한 | 프로젝트 설정 → 사용자 및 권한 | 뷰어면 앱 등록 불가 → 소유자에게 등록 요청 / 편집자·소유자면 **동의 후** 등록 가능 |
| 4 | 등록된 앱 | 프로젝트 설정 → 일반 → 내 앱 | `com.yju.haebom.guardian_app`(Android), `com.yju.haebom.guardianApp`(iOS)가 없으면 추가 등록 필요. 같은 패키지가 이미 다른 용도로 있으면 안 됨 |
| 5 | Authentication | 빌드 → Authentication → Sign-in method | **익명** 로그인 사용 설정 여부 (보호자 앱은 익명 로그인으로 시작) |
| 6 | Firestore 위치·규칙 | 빌드 → Firestore → 규칙 | 현재 `families` 규칙만 있으면 보호자 앱 읽기는 모두 거부됨 → 서버 담당자가 규칙을 바꿀 때까지 실제 데이터 수신 불가 |
| 7 | Firestore 데이터 | Firestore → 데이터 | `notifications`/`approvals`/`links` 컬렉션 존재 여부. **삭제·수정하지 않는다** |
| 8 | FCM API | 프로젝트 설정 → 클라우드 메시징 | "Firebase Cloud Messaging API (V1) 사용 설정됨" |
| 9 | 서비스 계정 | 프로젝트 설정 → 서비스 계정 | 서버 담당자가 Admin SDK 키를 가지고 있는지 (나는 키가 필요 없음 — 보호자 앱은 키를 쓰지 않는다) |
| 10 | Cloud Functions `guide` | 빌드 → Functions | 배포돼 있으면 Blaze 요금제라는 뜻. 보호자 앱 등록·FCM 수신은 `guide` 함수에 영향 없음. **보안 규칙 교체는 `families` 경로를 쓰는 옛 앱에 영향** → 서버 담당자·고령자 앱 담당자 합의 후 |

### 기존 프로젝트를 안전하게 함께 쓰기 위한 조건 (💡 제안)
1. 보호자 앱이 프로젝트에 하는 변경은 **앱 2개 등록뿐**이며, 소유자 동의 후에 한다.
2. 보안 규칙·인덱스·Functions 배포는 **서버 담당자만** 하고, 배포 전 세 사람이 규칙 내용을 확인한다.
3. 옛 `families` 규칙·데이터 정리는 고령자 앱 담당자가 결정한다 (보호자 앱은 사용하지 않음).
4. Blaze 프로젝트라면 소유자가 예산 알림을 설정한다 (보호자 앱은 Firestore 읽기·FCM 수신만 하므로 추가 비용 거의 없음 — FCM은 무료).
5. 서비스 계정 키는 서버 담당자만 보관하고 공유하지 않는다.
6. 나중에 새 공통 프로젝트로 옮겨도 보호자 앱은 `config/firebase.json` 값만 바꾸면 된다.

## 6. 받은 뒤 보호자 앱에서 할 일
1. `config/firebase.json` 작성 → `flutter run --dart-define-from-file=config/firebase.json`
2. 익명 로그인 → 보호자 프로필 생성 → FCM 토큰 등록 확인 (설정 → "원격 알림: 사용 중")
3. 서버가 테스트 알림 발송 → Android **앱 종료·화면 잠금** 상태에서 수신, 알림 탭 → 상세 이동
4. 승인·거절, 가족 연결·해제를 실제 서버로 확인
5. iPhone: 실제 데이터 수신·승인·연결 + 앱 실행 중 로컬 알림 확인

---

## 7. 서버를 AWS에 올릴 때 (2026-11-25 추가)

서버 담당자가 공통 서버를 AWS에 배포한다고 해서 정리했다. FCM 발송·Firestore 쓰기·ID 토큰 검증은 **Firebase Admin SDK**로 하며, AWS를 포함해 어디서든 동작한다(Firebase Blaze 불필요).

### 7.1 서버 담당자 순서
| # | 할 일 | 메모 |
|---|---|---|
| 1 | **서비스 계정 키 발급** — 프로젝트 소유자가 Firebase 콘솔 → 프로젝트 설정 → 서비스 계정 → "새 비공개 키 생성" | 키 파일은 **서버에만** 보관 (AWS Secrets Manager 또는 서버 환경 변수). Git·메신저·앱에 넣지 않는다 |
| 2 | 서버 코드에서 Admin SDK 초기화 → `verifyIdToken`(로그인 확인), Firestore 쓰기, `messaging().send()` | 3장 FCM 형식 참고 |
| 3 | **HTTPS 고정 주소로 배포** | 휴대폰 앱은 `http://` 접속 불가. 도메인 구입 없이 HTTPS 주소가 바로 나오는 방식: **API Gateway + Lambda**, **Lambda 함수 URL**, **App Runner**. EC2를 쓰면 도메인 + 인증서(Let's Encrypt 또는 ALB+ACM) 필요 |
| 4 | **보안 규칙 배포** (4장 쿼리 허용) — 소유자·고령자 앱 담당 확인 후 | 지금 보호자 앱은 규칙 때문에 "가족 정보를 불러오지 못했습니다" 상태 |
| 5 | 동작 확인: `GET /v1/healthz`, 보호자 폴드3 토큰으로 FCM 발송 | 보호자 앱 담당자가 토큰을 알려 줌 |
| 6 | **서버 주소와 API 목록**을 보호자 앱 담당자에게 전달 | 보호자 앱 `config/firebase.json`의 `SERVER_BASE_URL`에 넣으면 끝 |

### 7.2 비용·보안 메모
- AWS 계정 비용은 서버 담당자 계정에 걸린다. 프리 티어 범위·예산 알림 설정 권장.
- 서버에는 관리용 API를 외부에 열지 않고, 모든 `/v1/*` 요청은 Firebase ID 토큰을 검증한다.
- 고정 주소를 쓰면 `config/server` 문서는 필요 없다 (보호자 앱은 `SERVER_BASE_URL`을 우선 사용).
