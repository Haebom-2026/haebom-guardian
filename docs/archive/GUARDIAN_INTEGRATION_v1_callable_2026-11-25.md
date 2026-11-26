# 해봄(고령자 앱) ↔ 해봄 가족(보호자 앱) 연동 규격 — 고령자 앱 담당자 전달용

> ⚠️ **보관본 (v1, Cloud Functions Callable 방식)** — 2026-11-25에 REST 서버 방식(v2)으로 대체됨. 최신 문서는 `docs/GUARDIAN_INTEGRATION.md`, 변경 내역은 `docs/INTEGRATION_CHANGES.md`.

> 작성일: 2026-11-25 · 작성: 보호자 앱 담당
> 기준 자료: ① 고령자 앱 담당자의 `고령자 앱 ↔ 보호자 앱 연동 분석.docx`(2026-11-24) ② 보호자 앱 실제 코드(`guardian_app/lib`) ③ `docs/INTEGRATION.md` v0.1 ④ 최근 논의한 Firebase 연동 방식

## 0. 이 문서를 읽는 방법 (Claude Code에 전달할 때 함께 읽힐 것)

### 표시 규칙
| 표시 | 뜻 |
|---|---|
| ✅ **구현됨** | 보호자 앱 코드에 이미 있고 자동 테스트로 확인한 내용 (단, **Mock 서버 기준**) |
| 🛠 **서버 구현 예정** | 실제 Firebase(Cloud Functions·보안 규칙·FCM)에는 **아직 없음**. 앞으로 만들 내용 |
| 💡 **제안·미합의** | 두 담당자가 아직 합의하지 않은 내용. 합의 전에는 확정 사양이 아님 |

### 가장 중요한 사실
1. **실제 서버는 아직 없다.** 보호자 앱은 메모리 안의 Mock 서버(`MockBackend`)로 모든 규칙을 흉내 내고 있다. Cloud Functions는 하나도 배포되지 않았다. 따라서 고령자 앱에서 아래 함수를 지금 호출하면 실패한다.
   → 고령자 앱도 **`GuardianRepo` 같은 인터페이스 + 가짜 구현(Fake)** 으로 먼저 개발하고, 서버가 준비되면 실제 구현으로 바꾸는 방식을 권장한다(보호자 앱과 같은 방식).
2. **Firebase 프로젝트(`copilot-demo-c9a74` 포함) 설정·데이터·보안 규칙은 합의 전까지 변경하지 않는다.** 유료 서비스 가입, 함수 배포도 하지 않는다.
3. **승인·거절 기능은 현재 규격 그대로 유지한다.** 범위 조정은 10장의 합의 사항으로 남겨 두었고, 제외하거나 연기하기로 정한 것이 아니다.

### 고령자 앱 Claude Code에게 주는 작업 원칙
- 이 문서의 컬렉션명·필드명·값(소문자 코드)·함수명·오류 코드를 **임의로 바꾸지 않는다.** 바꿔야 하면 "💡 제안"으로 보호자 앱 담당자에게 먼저 알린다.
- 수신 보호자(`guardianIds`)는 **서버가 links 기준으로 정한다.** 고령자 앱은 보호자 UID를 보내지 않는다.
- 동의 팝업에서 **"예"일 때만** 서버를 호출한다. "아니요"·"닫기"는 아무것도 보내지 않는다(문서도, 기록도 없음). `consent` 필드는 없다.
- 비밀번호·계좌번호·주민번호·화면 캡처·거래 내용은 보내지 않는다. 앱 **이용 사실**(앱 이름·패키지명)만 보낸다.
- 승인은 "거래 승인"이 아니라 **"도우미 진행 승인"**이다. 실제 금융 거래를 허락하거나 막지 않는다.

---

## 1. 보호자 앱의 현재 구현 및 테스트 상태

### 1.1 구현 범위 (✅, Mock 서버 기준)
| 기능 | 상태 | 비고 |
|---|---|---|
| 홈 대시보드 / 알림 목록·상세 / 승인 목록·상세 / 가족 목록·연결·해제 / 설정 | ✅ | Flutter, Android·iOS 공용 |
| 알림 3종 표시 (`sensitive_entry`, `stuck`, `sos`) | ✅ | 보호자별 읽음(`readBy`) |
| 승인 요청 승인·거절, 남은 시간 표시, 만료·취소 처리 | ✅ | 여러 보호자 중 **먼저 온 응답만** 반영 |
| 6자리 연결 코드 입력 → 가족 연결 | ✅ | 10분 유효·일회용·5회 실패 시 5분 잠금 |
| 연결 해제 → 과거 알림·승인 읽기 차단 | ✅ | |
| 기기 로컬 알림 (Android 채널 3개, iOS 권한) | ✅ | **원격 푸시(FCM/APNs) 아님.** 앱이 실행 중일 때 Mock 데이터 변경을 감지해 띄움 |
| 잠금 화면 최소 문구, "상세 내용 표시" 설정(기기 저장) | ✅ | 기본값 꺼짐 |
| 개발자 테스트 화면 (고령자 앱 + 서버 동작 흉내) | ✅ | 디버그 빌드에서만 보임 |
| Firebase Auth / Firestore / Cloud Functions / FCM | ❌ 🛠 | **미연동** |

UI는 `GuardianRepository` 인터페이스(`lib/repositories/guardian_repository.dart`)에만 의존한다. 현재 구현체는 `MockGuardianRepository`이며, 서버 연동 시 `FirebaseGuardianRepository`로 교체한다. 서버 규칙(권한·중복·상태 전이)은 `lib/repositories/mock_backend.dart`에 있고, 이것이 Cloud Functions로 옮겨질 기준 코드다.

### 1.2 테스트 상태
| 항목 | 결과 |
|---|---|
| `flutter analyze` | 이슈 0건 |
| `flutter test` (단위·위젯) | 67개 통과 |
| `integration_test/app_flow_test.dart` | Android 에뮬레이터·iOS 시뮬레이터 통과 |
| `integration_test/settings_storage_test.dart` | 실제 Galaxy Z Fold3 통과 (iOS 미실행) |
| Android 에뮬레이터 (API 37) | 설치·실행·로컬 알림·알림 탭 이동·승인 처리 확인 |
| 실제 Android 폰 Galaxy Z Fold3 (Android 14) | 설치·실행·알림 팝업·승인 처리·등본 시나리오 알림 2개 확인 |
| 실제 iPhone 14 Pro | 서명·설치·실행까지 확인. **화면·알림 수동 확인은 아직** |
| 실제 서버 연동 테스트 | ❌ 서버 없음 |

---

## 2. 주고받을 데이터 형식 (공통 약속)

| 항목 | 규칙 |
|---|---|
| 통신 경로 | 두 앱은 직접 통신하지 않는다. **고령자 앱 → Cloud Functions 호출 → Firestore 문서 → 보호자 앱 구독/FCM** |
| 사용자 식별 | Firebase Auth UID. 함수에서는 `context.auth.uid`로 호출자를 확인하고, **요청 본문에 UID를 넣지 않는다** |
| 시간 | Firestore `Timestamp`, 서버 시각(`FieldValue.serverTimestamp()` / Admin SDK에서 `Timestamp.now()`) |
| 코드 값 | 모두 **소문자 snake_case 또는 kebab-case** (아래 표 그대로). 현재 고령자 앱 규칙 파일의 대문자 `ENTRY/APPROVAL/SOS`, `PENDING/TIMEOUT`은 사용하지 않는다 |
| 문서 ID | 보호자 앱 모델에서는 `id` 필드로 다룬다(Firestore 문서 ID) |

### 2.1 값 목록 (✅ 보호자 앱 코드와 동일)

**알림 type** (`notifications.type`)
| 값 | 뜻 | 보호자 앱 표시 문구 |
|---|---|---|
| `sensitive_entry` | 민감 앱 이용 (고령자가 "예" 선택) | "어머니가 정부24에 접속했습니다." |
| `stuck` | 앱 사용 중 도움이 필요해 보임 | "어머니가 정부24 사용 중 도움이 필요할 수 있습니다." (`appName`이 비면 "휴대폰 사용 중") |
| `sos` | SOS 버튼 | "어머니가 SOS 도움 요청을 보냈습니다." |

호칭("어머니")은 보호자가 연결할 때 입력한 `links.relationship`이다. 알 수 없는 type 값은 현재 보호자 앱에서 `sensitive_entry`로 처리된다.

**승인 status** (`approvals.status`): `pending` → `approved` | `rejected` | `expired` | `cancelled`

**승인 action** (`approvals.action`)
| 값 | 보호자 앱 표시 문구 |
|---|---|
| `guide_gov24_auth` | 정부24 본인인증 단계 안내 |
| `guide_bank_open` | 은행 앱 이용 안내 |
| `guide_unknown_app` | 처음 사용하는 앱 이용 안내 |
| (그 외) | "도우미 안내 진행"으로 표시 (앱이 멈추지 않음) |

**민감 앱 목록** (보호자 앱 Mock 기준, 💡 고령자 앱 감지 목록과 대조 필요)
| 앱 | packageName | 기본 action |
|---|---|---|
| 정부24 | `kr.go.minwon.m` | `guide_gov24_auth` |
| KB스타뱅킹 | `com.kbstar.kbbank` | `guide_bank_open` |
| 카카오뱅크 | `com.kakaobank.channel` | `guide_bank_open` |
| 토스 | `viva.republica.toss` | `guide_bank_open` |

> 연동 분석 문서 지적대로 은행을 "우리", "하나" 같은 **앱 이름 단어로 찾으면 오탐**이 생긴다. 민감 앱은 **패키지명 목록**으로 구분하고, 실기기에서 `adb shell pm list packages`로 확인한 값으로 목록을 확정한다.

---

## 3. Firestore 컬렉션 및 필드

필드 구조는 보호자 앱 모델(✅)과 연동 분석 문서의 "권장 데이터 통신 규격"이 **일치**한다. 실제 Firestore와 보안 규칙은 🛠 서버 구현 예정이다.

### users/{uid}
| 필드 | 타입 | 쓰는 쪽 |
|---|---|---|
| role | string `elder` \| `guardian` | 각자 본인 |
| name | string | 각자 본인 (고령자 이름 입력칸은 고령자 앱에 추가 필요) |
| createdAt | timestamp | 각자 본인 |

### users/{uid}/devices/{deviceId} (FCM 토큰)
| 필드 | 타입 | 쓰는 쪽 |
|---|---|---|
| fcmToken | string | 각 앱 (`registerDevice` 함수 경유) |
| platform | string `android` \| `ios` | 각 앱 |
| updatedAt | timestamp | 서버 |

### connectCodes/{code} — 문서 ID = 6자리 숫자 문자열 (서버 전용, 클라이언트 읽기·쓰기 금지)
| 필드 | 타입 | 설명 |
|---|---|---|
| elderId | string | 발급한 고령자 UID |
| expiresAt | timestamp | 발급 + 10분 |
| used | bool | 일회용 |

### links/{elderId}_{guardianId} (서버 전용 쓰기)
| 필드 | 타입 | 설명 |
|---|---|---|
| elderId | string | |
| guardianId | string | |
| elderName | string | `users/{elderId}.name` 복사 (표시용) |
| relationship | string | 보호자가 연결할 때 입력한 호칭 (예: 어머니) |
| connectedAt | timestamp | 연결 시각 |

### notifications/{id} (서버가 생성, 보호자는 `readBy`의 자기 항목만 수정)
| 필드 | 타입 | 설명 |
|---|---|---|
| elderId | string | 호출한 고령자 UID (서버가 `context.auth.uid`로 채움) |
| guardianIds | array&lt;string&gt; | **서버가 links 기준으로 채움** |
| appName | string | 예: 정부24 (SOS는 빈 문자열) |
| packageName | string | 예: kr.go.minwon.m (SOS는 빈 문자열) |
| type | string | `sensitive_entry` \| `stuck` \| `sos` |
| createdAt | timestamp | 서버 시각 |
| readBy | map&lt;string, timestamp&gt; | 보호자 UID → 읽은 시각 (보호자별로 따로) |

### approvals/{id} (서버가 생성·상태 변경)
| 필드 | 타입 | 설명 |
|---|---|---|
| elderId | string | |
| guardianIds | array&lt;string&gt; | 서버가 결정 |
| appName / packageName | string | |
| action | string | 2.1 action 값 |
| status | string | `pending` \| `approved` \| `rejected` \| `expired` \| `cancelled` |
| createdAt | timestamp | |
| expiresAt | timestamp | 생성 + 5분 (보호자 앱 Mock 값, 💡 합의 필요) |
| respondedAt | timestamp \| null | 승인·거절·취소 시각 |
| respondedBy | string \| null | 응답한 보호자 UID (취소·만료 시 null) |

### 보안 규칙 원칙 (🛠, 초안은 `docs/INTEGRATION.md` 5장)
- 쓰기는 대부분 **Cloud Functions(Admin SDK)만**. 클라이언트는 읽기 + 제한된 필드 쓰기만.
- `notifications`·`approvals` 읽기: `guardianIds`에 포함되고 **links가 살아 있는** 보호자, 또는 본인(`elderId`).
- 보호자는 `notifications.readBy.{자기 UID}`만 추가 가능.
- 현재 고령자 앱 규칙의 "로그인만 하면 누구나 읽기·쓰기"(`firestore.rules:14`)는 사용하지 않는다.

---

## 4. Cloud Functions 함수명과 요청·응답 형식 (🛠 전부 미구현)

- 모두 **Callable Functions**(`httpsCallable`). 💡 리전 `asia-northeast3`(서울).
- 호출자 확인은 `context.auth.uid`. 역할(`users/{uid}.role`)이 맞지 않으면 `permission-denied`.
- 함수 안의 동작 기준은 보호자 앱 `MockBackend`의 같은 이름 메서드다.

| 함수 | 호출 앱 | 요청 | 성공 응답 | 기준 코드 |
|---|---|---|---|---|
| `reportSensitiveEntry` | 고령자 | `{ packageName, appName }` | `{ result: "created", notificationId }` / `{ result: "duplicate_suppressed" }` / `{ result: "no_guardians" }` | `MockBackend.reportSensitiveEntry` |
| `reportStuck` 💡 | 고령자 | `{ packageName, appName }` (홈 화면 등 앱 밖이면 빈 문자열) | `{ result: "created", notificationId }` / `{ result: "no_guardians" }` | `MockBackend.createStuck` |
| `createSos` | 고령자 | `{}` | `{ result: "created", notificationId }` / `{ result: "no_guardians" }` | `MockBackend.createSos` |
| `requestApproval` | 고령자 | `{ packageName, appName, action }` | `{ approvalId, expiresAt }` | `MockBackend.requestApproval` |
| `cancelApproval` | 고령자 | `{ approvalId }` | `{ status: "cancelled" }` | `MockBackend.cancelApproval` |
| `respondApproval` | 보호자 | `{ approvalId, decision: "approve" \| "reject" }` | `{ status, respondedAt }` | `MockBackend.respond` |
| `issueConnectCode` | 고령자 | `{}` | `{ code, expiresAt }` | `MockBackend.issueConnectCode` |
| `connectWithCode` | 보호자 | `{ code, relationship }` | `{ elderId, elderName, relationship, connectedAt }` | `MockBackend.connectWithCode` |
| `disconnect` | 보호자 / 고령자 | 보호자: `{ elderId }` · 고령자: `{ guardianId }` | `{ ok: true }` | `MockBackend.disconnect` |
| `registerDevice` | 공통 | `{ deviceId, fcmToken, platform }` | `{ ok: true }` | – |
| `unregisterDevice` | 공통 | `{ deviceId }` | `{ ok: true }` | – |

- `reportStuck`은 이번 문서에서 새로 이름을 붙인 💡 제안이다(`INTEGRATION.md` v0.1에는 `stuck` 생성 함수가 빠져 있었다). Mock에는 같은 동작(`createStuck`)이 있다.
- 연동 분석 문서의 `claimCode`는 이 문서의 **`connectWithCode`와 같은 기능**이다. 💡 이름은 `connectWithCode`로 통일을 제안한다(보호자 앱 코드가 이미 이 이름을 쓴다).
- 읽음 처리는 함수 없이 보안 규칙으로 제한된 Firestore 직접 쓰기(`readBy.{uid}`)로 한다.
- 서버 트리거(🛠): `notifications`·`approvals` 문서 생성 시 FCM 발송, `expiresAt`이 지난 `pending` 승인은 Scheduled Function이 `expired`로 변경.

### 4.1 오류 응답 (✅ 보호자 앱 `RepositoryErrorCode`와 1:1)
`HttpsError(code, message, { reason })`의 `details.reason`에 아래 값을 넣는다.

| reason | 언제 |
|---|---|
| `not-found` | 문서 없음, 연결 해제됨 |
| `permission-denied` | 연결되지 않은 사용자, 역할 불일치 |
| `already-responded` | 다른 보호자가 먼저 응답 |
| `approval-expired` | 만료 후 응답 |
| `approval-cancelled` | 고령자가 취소한 요청에 응답 |
| `invalid-code` | 형식 오류(숫자 6자리 아님) 또는 없는 코드 |
| `code-expired` | 발급 후 10분 경과 |
| `code-used` | 이미 사용된 코드 |
| `already-linked` | 이미 연결된 가족 |
| `too-many-attempts` | 연속 실패 5회 → 5분 잠금 |
| `invalid-argument` | 필수 값 누락 등 |
| `unavailable` | 네트워크·서버 오류 |

---

## 5. 고령자 앱 담당자가 구현해야 하는 기능

연동 분석 문서의 "어르신 앱에 추가할 것"과 이 규격을 합친 목록이다. 연동 분석 문서 기준으로 아래 항목은 **현재 모두 미구현**이다.

| 순서 | 기능 | 내용 | 연동 분석 문서의 삽입 지점 |
|---|---|---|---|
| 1 | 로그인·UID 고정 | 앱 시작 시 Firebase 로그인, UID를 `elderId`로 사용. `users/{uid}`에 `role: "elder"`, `name` 기록 | `Sos.kt`의 익명 로그인을 앱 시작 시점으로 이동 |
| 2 | 고령자 이름 입력 | 설정 화면에 이름 입력칸 (`users.name` → `links.elderName`) | 현재 보호자 이름·번호만 있음 |
| 3 | 서버 호출 한곳으로 | 모든 Firebase 호출을 `GuardianRepo` 하나로 모으고, 개발용 Fake 구현을 둔다 | 현재 `Sos.kt` 안에 있음 |
| 4 | 민감 앱 진입 감지 | `TYPE_WINDOW_STATE_CHANGED`의 패키지명을 민감 앱 목록(2.1)과 비교. 음성 명령(task) 여부와 **상관없이** 동작 | 새 `SensitiveAppWatcher`, `GuideService.onAccessibilityEvent` |
| 5 | 동의 팝업 + 닫기 | 문구: **"민감한 개인정보를 사용하는 서비스입니다. 보호자에게 알림을 보내겠습니까?"** 예 → `reportSensitiveEntry` / 아니요·닫기 → 아무것도 안 함 | `Orchestrator.askEntryConsent`, `AskPopup`에 `onDismiss`(X 버튼·바깥 터치) 추가 |
| 6 | 팝업 중복 방지 | 9장 참고 | `SensitiveAppWatcher` |
| 7 | 도움 필요 알림 | 💡 기존 45초 막힘 타이머가 발동하면 `reportStuck` 호출 (발생 조건은 10장 합의) | `Orchestrator.armStuckTimer` |
| 8 | SOS 서버 기록 | 기존 SMS 발송은 유지하고, 추가로 `createSos` 호출 | `Sos.send`, `Orchestrator.sendSos` |
| 9 | 승인 요청 | `requestApproval` → 대기 자막 → `approvals/{id}` 실시간 구독 → 결과에 따라 계속·중단 | `LocalPlanner.gov24`·`bank`, `CaptionBar`, `Orchestrator.step`/`stop` |
| 10 | 승인 요청 취소 | 고령자가 기다리지 않고 멈출 때 `cancelApproval` | 새 버튼 |
| 11 | 가족 연결 코드 | 기기에서 영구 코드를 만들지 않고 `issueConnectCode` 결과(10분 코드)를 화면에 표시 | `MainActivity.kt:120`, `Prefs.familyCode` 대체 |
| 12 | FCM 토큰 등록 | 💡 고령자 앱이 푸시를 받을 경우만 `registerDevice` | – |
| 13 | 보안 규칙 | uid·links 기준 규칙으로 교체 (3장). **합의 후 배포** | `firebase/firestore.rules` |

### 5.1 Kotlin 예시 (💡 서버 준비 전에는 Fake로 대체)

```kotlin
interface GuardianRepo {
    suspend fun reportSensitiveEntry(packageName: String, appName: String): EntryResult
    suspend fun reportStuck(packageName: String, appName: String)
    suspend fun createSos()
    suspend fun requestApproval(packageName: String, appName: String, action: String): String // approvalId
    fun watchApproval(approvalId: String, onStatus: (String) -> Unit): ListenerRegistration
    suspend fun cancelApproval(approvalId: String)
    suspend fun issueConnectCode(): Pair<String, Timestamp> // code, expiresAt
}

class FirebaseGuardianRepo : GuardianRepo {
    private val functions = Firebase.functions("asia-northeast3")
    private val db = Firebase.firestore

    override suspend fun reportSensitiveEntry(packageName: String, appName: String): EntryResult {
        val r = functions.getHttpsCallable("reportSensitiveEntry")
            .call(mapOf("packageName" to packageName, "appName" to appName)).await()
        return when ((r.data as Map<*, *>)["result"]) {
            "created" -> EntryResult.Created
            "duplicate_suppressed" -> EntryResult.Duplicate
            else -> EntryResult.NoGuardians
        }
    }

    override fun watchApproval(approvalId: String, onStatus: (String) -> Unit) =
        db.collection("approvals").document(approvalId)
            .addSnapshotListener { snap, _ -> snap?.getString("status")?.let(onStatus) }
    // ... 나머지 함수도 같은 방식
}

// 동의 팝업
fun onConsent(choice: Choice, app: DetectedApp) {
    if (choice != Choice.YES) return            // 아니요·닫기: 아무것도 보내지 않는다
    scope.launch {
        runCatching { repo.reportSensitiveEntry(app.packageName, app.appName) }
            .onFailure { /* 💡 1회 재시도 후 포기 (오래된 알림을 늦게 보내지 않음) */ }
    }
}

// 승인 결과 처리
when (status) {
    "approved" -> orchestrator.step()
    "rejected" -> orchestrator.stop("가족이 잠깐 멈추자고 했어요")   // 문구는 💡 합의
    "expired"  -> orchestrator.stop("가족이 아직 확인하지 못했어요")
    "cancelled", "pending" -> Unit
}
```

---

## 6. 보호자 앱 담당자(나)가 구현할 기능

| 기능 | 상태 |
|---|---|
| 보호자 앱 화면·흐름 전체 (1.1) | ✅ Mock 기준 완료 |
| 서버 규칙 기준 코드 (`MockBackend`) | ✅ 완료 — Cloud Functions 작성 시 그대로 옮김 |
| `FirebaseGuardianRepository` (Firestore 구독, 함수 호출, `readBy` 쓰기) | 🛠 합의 후 |
| 보호자 로그인 (Firebase Auth) | 🛠 💡 방식 합의 필요 |
| FCM 수신·토큰 등록, 알림 탭 → 상세 이동 (로컬 알림과 같은 `kind:id` 구조) | 🛠 |
| iOS 원격 푸시 (APNs) | 🛠 Apple Developer **유료 계정 필요** → 별도 결정 |
| Cloud Functions (4장 함수 전체) 작성 | 🛠 💡 담당자 합의 필요 (보호자 앱 담당이 작성하는 안을 제안) |
| Firestore 보안 규칙 작성 | 🛠 💡 담당자 합의 필요 |
| 이용 알림 "확인했어요" 버튼 | 💡 10장 합의 후 |

---

## 7. 가족 연결 방식

```
고령자 앱                       서버(🛠)                            보호자 앱
 "가족 연결" 화면
   │ issueConnectCode() ───────► 미사용 6자리 생성(암호학적 난수)
   │                             connectCodes/{code}
   │                             { elderId, expiresAt: +10분, used:false }
   │ ◄──────── { code, expiresAt }
 화면에 "123456 (9:59 남음)"
   ·· 고령자가 보호자에게 전화·문자로 코드를 알려 줌 ··
                                                              코드 + 호칭("어머니") 입력
                                 ◄──────────────────────────── connectWithCode(code, relationship)
                                 트랜잭션 검증 순서:
                                 잠금 여부 → 형식 → 존재 → used → 만료 → 이미 연결
                                 → used=true, links/{elderId}_{guardianId} 생성
                                 ─────────────────────────────► { elderId, elderName, relationship, connectedAt }
```

| 규칙 | 상태 |
|---|---|
| 10분 유효, 일회용 | ✅ Mock |
| 잘못된 코드·만료·사용된 코드 각각 다른 오류 | ✅ Mock |
| 보호자별 연속 실패 5회 → 5분 잠금 (`too-many-attempts`) | ✅ Mock. 💡 실제 서버는 기기·IP 단위 제한 추가 검토 |
| 한 고령자 ↔ 여러 보호자, 한 보호자 ↔ 여러 고령자 | ✅ Mock |
| 코드 검증은 **서버만** (클라이언트가 직접 확인하면 대입 공격 가능) | 연동 분석 문서와 동일 의견 |
| 연결 해제: 보호자 `disconnect({elderId})` → links 삭제 → 과거 알림·승인도 읽기 불가 | ✅ Mock |
| 고령자 쪽 연결 해제 화면 | 💡 필요 여부 합의 |
| 새 코드 발급 시 이전 미사용 코드 무효화 | 💡 합의 필요 |

현재 고령자 앱의 영구 6자리 `familyCode`와 SOS 기록 경로 `families/{코드}/events`는 이 방식으로 **대체**한다(💡 기존 SOS 기록 이전 방법은 합의).

---

## 8. 알림별 연동 방식

### 8.1 일반 알림 — 민감 앱 이용 (`sensitive_entry`)
```
고령자가 정부24 앱을 엶 → SensitiveAppWatcher 감지 → (9장 팝업 중복 방지 통과)
→ 동의 팝업
   ├─ 예   → reportSensitiveEntry({packageName, appName})
   │         → 서버: 연결된 보호자 확인 → 중복 검사 → notifications 생성 → FCM
   │         → 보호자 앱: 목록·상세 "어머니가 정부24에 접속했습니다."
   ├─ 아니요 → 아무것도 하지 않음
   └─ 닫기  → 아무것도 하지 않음
```
- 고령자 앱은 응답을 **기다리지 않고** 안내를 계속한다.
- 보호자 앱 표현은 "이용 사실"만 알린다. 개인정보 입력을 감지했다고 표현하지 않는다.

### 8.2 도움 필요 (`stuck`)
- 고령자 앱이 "어려움을 겪는 것 같다"고 판단하면 `reportStuck` 호출 (💡 함수명·발생 조건 합의).
- 동의 팝업은 없다(💡 필요 여부 합의). 보호자 앱 표시: "어머니가 정부24 사용 중 도움이 필요할 수 있습니다."
- 보호자 앱 데모 시나리오 "⓪ 정부24 등본 발급 따라하기"에서는 발급 신청 화면에서 오래 멈췄을 때 1회 보낸다.

### 8.3 SOS (`sos`)
- 고령자가 SOS 버튼 → **기존 SMS 발송은 그대로** + `createSos()` 호출.
- 서버는 `appName`·`packageName`을 빈 문자열로 `notifications` 생성, FCM은 `sos_alerts` 채널로 발송.
- 보호자 앱: 긴급 표시, "바로 전화로 상황을 확인해 주세요. 긴급한 상황이라면 112 또는 119" 안내.
- 위치 정보는 보내지 않는다(현재 규격에 없음).

### 8.4 승인·거절 (`approvals`) — 현재 규격 유지
```
고령자 앱                         서버(🛠)                        보호자 앱
 requestApproval(pkg, app, action) ─► approvals 생성 (pending, +5분) ─► FCM "확인이 필요한 요청"
 "보호자 답을 기다리고 있어요" 자막                                     상세: "도우미 진행 승인"
 approvals/{id} 구독 ◄───────────── status 변경 ◄───────────────────── respondApproval(approve|reject)
                                    트랜잭션: pending && now < expiresAt 일 때만
```

| status | 고령자 앱 동작 (✅ 보호자 앱 Mock "고령자 앱 수신 결과"와 동일) |
|---|---|
| `approved` | AI 도우미 안내 계속 (`Orchestrator.step()`) |
| `rejected` | 안내 중단 (`Orchestrator.stop(...)`) |
| `expired` | 응답 없음 → 안내 중단 |
| `cancelled` | 고령자 본인이 취소 → 종료 |

규칙 (✅ Mock 구현·테스트):
- `pending`에서만 상태가 바뀐다. 종료 상태는 다시 바뀌지 않는다.
- 보호자 여러 명이 동시에 응답하면 **먼저 처리된 응답 하나만** 반영되고, 나머지는 `already-responded`.
- 만료 시각이 지난 요청에 응답하면 서버가 `expired`로 바꾸고 `approval-expired`를 돌려준다.
- 고령자가 취소한 요청에 응답하면 `approval-cancelled`.
- 🛠 고령자 앱이 결과를 받을 수 있도록, 만료는 **응답 시점 검사 + Scheduled Function** 둘 다로 처리한다.
- 💡 연동 분석 문서 기준 고령자 앱에는 승인 요청·대기·결과 수신 코드가 아직 없다. 연결할 지점(`Orchestrator.step`/`stop`, `CaptionBar`)은 이미 있다.

### 8.5 FCM payload (🛠, 잠금 화면에는 최소 문구)
```json
{
  "notification": { "title": "해봄 가족", "body": "새 가족 알림이 도착했습니다." },
  "data": { "kind": "notification", "id": "<문서 ID>", "type": "sensitive_entry" },
  "android": { "notification": { "channel_id": "family_activity", "visibility": "PRIVATE" } }
}
```
| 종류 | data.kind | Android channel_id | 기본 body (✅ 보호자 앱 로컬 알림 문구) |
|---|---|---|---|
| sensitive_entry | `notification` | `family_activity` | 새 가족 알림이 도착했습니다. |
| stuck | `notification` | `family_activity` | 가족에게 도움이 필요할 수 있습니다. 앱에서 확인해 주세요. |
| sos | `notification` | `sos_alerts` | 가족이 도움을 요청했습니다. 앱에서 확인해 주세요. |
| 승인 요청 | `approval` | `approval_requests` | 확인이 필요한 요청이 도착했습니다. |

---

## 9. 중복 알림 방지 방식

두 단계로 나누며, 역할이 다르므로 둘 다 둔다.

| 단계 | 위치 | 목적 | 규칙 | 상태 |
|---|---|---|---|---|
| ① 팝업 중복 방지 | 고령자 앱 | 고령자가 같은 질문을 반복해서 받지 않게 | 같은 앱 안에서 화면이 바뀌는 것은 진입으로 보지 않음. **다른 앱에 갔다가 돌아올 때만** 다시 판단. 같은 앱은 일정 시간 다시 묻지 않음. 키보드·런처·해봄 앱 자체는 무시 | 💡 연동 분석 문서 제안(10분), 미구현 |
| ② 알림 중복 방지 | 서버 | 보호자에게 같은 알림이 여러 번 가지 않게 | 같은 `elderId + packageName + type=sensitive_entry` 문서가 최근 **N분** 안에 있으면 생성하지 않고 `{ result: "duplicate_suppressed" }` | ✅ Mock N=5분 / 🛠 서버 |

- 💡 **시간 값 합의 필요**: 고령자 앱 안 10분, 서버 Mock 5분으로 서로 다르다. 같은 값(예: 둘 다 10분)으로 맞추면 설명이 쉽다.
- `stuck`·`sos`는 현재 Mock에서 중복 방지를 하지 않는다. 💡 SOS는 매번 보내고, `stuck`은 같은 앱 기준 일정 시간 제한을 둘지 합의.
- 보호자 앱 개발자 테스트에서는 5분 안에 등본 시나리오를 다시 시작하면 "1단계 알림이 중복 방지로 생략된다"는 선택 창을 띄운다(서버 규칙은 그대로).

---

## 10. 추가 합의가 필요한 사항

| # | 항목 | 현재 상황 | 💡 보호자 앱 쪽 제안 |
|---|---|---|---|
| 1 | 공통 Firebase 프로젝트 | 고령자 앱은 `copilot-demo-c9a74`(테스트용) 사용 | 새 공통 프로젝트를 둘지 함께 결정. **결정 전 기존 프로젝트 변경 금지** |
| 2 | Cloud Functions·보안 규칙 담당자 | 미정 | 보호자 앱 담당이 `MockBackend` 기준으로 작성, 함께 리뷰 후 배포 |
| 3 | 알림 문서를 누가 만드나 | 연동 분석 문서: "어르신 앱 생성"(guardianIds는 Function이 채우는 안도 언급) / 이 문서: 서버 함수가 생성 | **서버 함수가 생성.** 고령자 앱은 보호자 UID를 모르고, 직접 쓰기를 열면 보안 규칙이 복잡해짐 |
| 4 | 중복 방지 시간 | 고령자 앱 10분(제안) / 서버 5분(Mock) | 같은 값으로 통일 |
| 5 | 승인 기능 범위·적용 상황 | 보호자 앱은 현재 규격대로 구현 완료, 고령자 앱은 미구현. 보호자 앱 데모 등본 시나리오는 승인 없이 알림만 보냄 | 기능은 유지. **어떤 상황에서 승인을 요청할지**(일상 업무 vs 위험 상황), 1차 데모에 넣을지 함께 결정 (`INTEGRATION.md` 4.6 제안 A·B 참고) |
| 6 | 승인 유효시간·만료 후 동작 | Mock 5분, 만료 시 안내 중단 | 시간 값 결정. 만료 시 자동 진행하지 않기 |
| 7 | 승인·거절 버튼 문구 | 보호자 앱: "승인"/"거절" | 의미에 맞는 문구 검토 (예: "계속해도 돼요"/"잠깐 멈춰요"). 내부 값 `approved`/`rejected`는 유지 |
| 8 | action 코드 목록 | 3개 (`guide_gov24_auth` 등) | 고령자 앱이 실제로 요청할 상황에 맞춰 목록 확정 |
| 9 | 보호자 "확인"의 의미 (`readBy`) | 보호자 앱: 상세 화면을 **열면** 읽음 기록 | 💡 "확인했어요" **버튼을 누를 때만** 기록하는 안. 고령자 앱이 `readBy`를 구독해 "딸이 확인했어요" 표시 (새 필드 없음). 고령자 앱 구독 작업 포함 여부 결정 |
| 10 | `stuck` 발생 조건·함수명 | 고령자 앱에 45초 막힘 타이머 있음 | `reportStuck` 함수, 45초 타이머 기준 여부 |
| 11 | SOS 기록 방식 | 고령자 앱: SMS + `families/{코드}/events` | SMS 유지 + `createSos`로 `notifications` 기록. 기존 경로는 정리 |
| 12 | 민감 앱 패키지명 목록 | 보호자 앱 4개(2.1), 고령자 앱은 정부24 패키지 + 은행 이름 단어 | 패키지명 목록으로 통일, 실기기 확인 |
| 13 | 고령자 UID 유지 | 익명 로그인은 앱을 지우면 UID가 바뀜 → 연결이 끊김 | 계정 연결(전화번호 인증 등) 방식 결정 |
| 14 | 보호자 로그인 방식 | 미정 | 결정 필요 |
| 15 | applicationId | 고령자 앱 `com.example.copilot.parent` (namespace `com.yju.elder`) | `com.example`은 스토어 배포 불가 → 변경 여부. 보호자 앱: Android `com.yju.haebom.guardian_app`, iOS `com.yju.haebom.guardianApp` |
| 16 | 함수 이름 | 연동 분석 문서 `claimCode` / 이 문서 `connectWithCode` | `connectWithCode`로 통일 |
| 17 | 연결 코드 재발급·고령자 쪽 해제 | 미정 | 재발급 시 이전 코드 무효화, 고령자 쪽 해제 화면 필요 여부 |
| 18 | Functions 리전 | 미정 | `asia-northeast3`(서울) |
| 19 | iOS 원격 푸시 | Apple Developer 유료 계정 필요 | 계정 마련 여부 결정. 그 전까지 iOS는 앱 실행 중 표시만 가능 |

---

## 11. 실제 서버 연동 후 통합 테스트 시나리오

| # | 시나리오 | 기대 결과 |
|---|---|---|
| 1 | 정부24 진입 → 예 | 연결된 보호자 기기 모두 수신, "어머니가 정부24에 접속했습니다." |
| 2 | 진입 → 아니요 / 닫기 | 서버 호출 없음, 보호자 목록 변화 없음 |
| 3 | 정부24 안에서 화면 이동 | 추가 팝업·알림 없음 |
| 4 | 중복 방지 시간 안에 같은 앱 재진입 → 예 | `duplicate_suppressed`, 알림 1건 유지 |
| 5 | 45초 막힘 | `stuck` 알림 수신 |
| 6 | SOS 버튼 | SMS 발송 + `sos` 알림 수신 |
| 7 | 보호자 A 읽음 | A만 읽음, B는 안 읽음 유지 |
| 8 | 승인 요청 → 보호자 승인 | 고령자 앱 안내 계속 |
| 9 | 보호자 A·B 동시 응답 | 하나만 반영, 다른 쪽 `already-responded` |
| 10 | 만료 후 승인 시도 | `approval-expired`, 고령자 앱 안내 중단 |
| 11 | 고령자 취소 후 보호자 응답 | `approval-cancelled` |
| 12 | 코드 발급 → 입력 | links 생성, 양쪽 목록 반영 |
| 13 | 만료 / 사용된 / 잘못된 코드 5회 | 각 오류, 5회 후 잠금 |
| 14 | 연결 해제 후 과거 알림 조회 | 읽기 차단, 목록에서 사라짐 |
| 15 | 비행기 모드에서 승인 | `unavailable` 안내, 상태 변경 없음 |
| 16 | 잠금 화면 | 최소 문구만, 서비스명 미노출 |

---

## 부록. 참고 파일 (보호자 앱 저장소)
| 파일 | 내용 |
|---|---|
| `lib/repositories/guardian_repository.dart` | 보호자 앱 데이터 인터페이스, 오류 코드 |
| `lib/repositories/mock_backend.dart` | 서버 규칙 기준 코드 (중복·권한·상태 전이·연결 코드) |
| `lib/models/*.dart` | Firestore 문서 모델 (`toMap()`이 필드 구조) |
| `lib/services/notification_service.dart` | 알림 채널·문구·`kind:id` payload |
| `docs/INTEGRATION.md` | 상세 규격 v0.1 (보안 규칙 초안, 승인 정책 제안 4.6) |
