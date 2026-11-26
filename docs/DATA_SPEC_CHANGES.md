# 공통 데이터 규격 변경 — v2.2 (고령자 앱 ↔ 보호자 앱)

> 작성일: 2026-11-25 · 작성: 보호자 앱 담당
> 근거: 고령자 앱 담당의 `해봄_개발지침서.md`(2026-11-25)와 보호자 앱을 비교한 결과, 사용자(보호자 앱 담당)가 결정한 내용
> 기준 규격: `GUARDIAN_INTEGRATION.md` v2.1 → 이 문서의 변경을 더하면 **v2.2**
> 상태: **보호자 앱 반영 완료** (Mock·서버 모드 둘 다). 고령자 앱·서버는 아직 반영 전.
> 범위 밖: 서버 구현 주체·배포 방식(미협의), 보안 규칙 변경, 전화 걸기(전화번호 저장 방식 합의 후)

## 한눈에 보기
| # | 무엇 | 바뀌는 곳 | 기존 데이터 호환 |
|---|---|---|---|
| 1 | 가족 호칭을 **`elderLabel` / `guardianLabel`** 두 개로 분리 (`relationship` 대체) | `links`, #14 요청·응답 | 옛 `relationship` → `elderLabel`로 읽음 |
| 2 | 보호자 이름 대신 **`guardianLabel`(딸·아들 등)** 으로 고령자 앱 안내 | 고령자 앱 문구 | – |
| 3 | 알림에 **`level` · `category` · `reason`** 선택 필드 | `notifications`, #6·#8 요청 | 없으면 기존처럼 표시 |
| 4 | 승인에 **`category`** 선택 필드 | `approvals`, #9 요청 | 없으면 표시 안 함 |
| 5 | 승인 **action 4개 추가** | `approvals.action`, #9 | 모르는 action은 "도우미 안내 진행" |
| 6 | **막힘(stuck)·사기 의심 알림 우선순위 상향** | FCM `channelId` | – |

---

## 1. 가족 호칭 분리 — `elderLabel` / `guardianLabel`
같은 `relationship` 필드에 고령자 앱은 "보호자가 누구인지(딸)"를, 보호자 앱은 "어르신이 누구인지(어머니)"를 넣고 있어 뜻이 반대였다. 둘로 나눈다.

| 필드 | 뜻 | 예 | 누가 정함 | 어디에 쓰나 |
|---|---|---|---|---|
| `elderLabel` | 보호자가 어르신을 부르는 호칭 | 어머니, 아버지, 할머니, 할아버지, 배우자, (직접 입력) | 보호자 (연결할 때) | 보호자 앱: "**어머니가** 토스를 사용하려고 합니다." |
| `guardianLabel` | 어르신이 보호자를 부르는 호칭 | 딸, 아들, 며느리, 사위, 손녀, 손자, 배우자, (직접 입력) | 보호자 (연결할 때) | 고령자 앱: "**딸에게** 알림을 보냈어요", "**딸이** 허락했어요" |

- 둘 다 보호자가 연결 화면에서 고른다. 보호자 앱은 **둘 다 골라야** [연결하기]가 눌린다.
- 같은 어르신에 보호자가 여럿이면 `links` 문서마다 각자의 값이 있다.

**`links/{elderId}_{guardianId}`**
```json
{ "elderId": "...", "guardianId": "...", "elderName": "김순자",
  "elderLabel": "어머니", "guardianLabel": "딸", "connectedAt": "<Timestamp>" }
```
- ~~`relationship`~~ → 새로 만들 때는 쓰지 않는다.
- **호환:** 보호자 앱은 `elderLabel`이 없으면 `relationship`을 `elderLabel`로 읽는다. `guardianLabel`이 없으면 빈 문자열.

**#14 `POST /v1/guardian/links`**
```json
// 요청
{ "code": "123456", "elderLabel": "어머니", "guardianLabel": "딸" }
// 응답 200
{ "elderId": "...", "elderName": "김순자", "elderLabel": "어머니", "guardianLabel": "딸", "connectedAt": "..." }
```
- 서버는 두 값을 앞뒤 공백을 지우고 그대로 저장한다(최대 10자 권장). 응답에 `relationship`만 와도 보호자 앱은 동작한다.

## 2. 고령자 앱이 보호자를 부르는 방법
- 보호자 이름은 **따로 입력받지 않는다** (`users/{uid}.name`은 지금처럼 "보호자").
- 고령자 앱은 `links`(elderId == 나)에서 그 보호자의 **`guardianLabel`** 을 읽어 안내에 쓴다.
  - 승인 결과: `approvals.respondedBy`(uid) → 같은 uid의 `links.guardianLabel` → "딸이 허락했어요"
  - 알림 보냄: 보호자가 한 명이면 "딸에게 알림을 보냈어요", 여럿이면 "가족에게 알림을 보냈어요" (💡 제안)
  - `guardianLabel`이 비어 있으면(옛 연결) "보호자"

## 3. 알림 선택 필드 — `level` · `category` · `reason`
**`notifications/{id}`** 에 선택 필드 3개를 추가한다. 없어도 된다.

| 필드 | 값 | 설명 |
|---|---|---|
| `level` | `"L0"` \| `"L1"` \| `"L2"` \| `"L3"` | 민감도 단계 (지침서 4.2) |
| `category` | `"finance"` \| `"identity"` \| `"public"` \| `"device"` \| `"privacy"` \| `"scam"` \| `"none"` | 분류 (지침서 4.3) |
| `reason` | 문자열 (40자 이내 권장) | 짧은 이유. 예: "은행 앱 열기", "기관 사칭 송금 요청". **개인정보·금액·계좌번호를 넣지 않는다** |

- 요청: #6 `sensitive-entries`, #8 `sos`(L3 멈춤 후 보낸 SOS) 본문에 같은 이름으로 넣으면 서버가 그대로 저장한다.
- 모르는 값·잘못된 형식은 보호자 앱이 **무시**(없는 것과 같게)한다. 대소문자는 구분하지 않는다.

**보호자 앱 표시 규칙 (반영 완료)**
| 조건 | 색 | 종류 표시 | 문장 |
|---|---|---|---|
| `category == "scam"` (type 무관, 최우선) | 빨강 + 경고 아이콘 | 사기 의심 알림 | "어머니가 사기 의심 상황일 수 있습니다. 바로 연락해 확인해 주세요." |
| `level == "L3"` 또는 `type == "sos"` | 빨강 | SOS 알림 / … · 위험 | 기존 문장 |
| `level == "L2"` 또는 `type == "stuck"` | 주황 | … · 주의 / 도움 필요 알림 | 기존 문장 |
| 그 밖 (새 필드 없음 포함) | 그린 | 앱 이용 알림 | "어머니가 토스를 사용하려고 합니다." |
- `reason`이 있으면 목록에 "이유: …", 상세에 "분류"·"이유" 줄을 추가로 보여 준다.
- 색만으로 구분하지 않고 아이콘·글자를 같이 쓴다.

## 4. 승인 선택 필드 — `category`
**`approvals/{id}`** 에 `category`(3장과 같은 값)를 선택 필드로 추가한다. #9 요청 본문에 넣으면 서버가 저장한다. 보호자 앱은 상세 화면에 "분류"로 보여 준다.

## 5. 승인 action 추가
| action | 보호자 앱 표시 문구 | 상태 |
|---|---|---|
| `guide_gov24_auth` | 정부24 본인인증 단계 안내 | 기존 |
| `guide_bank_open` | 은행 앱 이용 안내 | 기존 |
| `guide_money_move` | 송금·이체 화면 안내 | **추가** |
| `guide_identity` | 본인인증·신분증 제출 안내 | **추가** |
| `guide_install` | 앱 설치·권한 허용 안내 | **추가** |
| `guide_privacy_send` | 개인정보·신분증 사진 보내기 안내 | **추가** |
| ~~`guide_unknown_app`~~ | (옛 데이터 표시용으로만 남김) | 고령자 앱은 사용 안 함 |
- 목록에 없는 action이 오면 "도우미 안내 진행"으로 표시한다 → 고령자 앱이 action을 더 늘려도 보호자 앱이 멈추지 않는다.
- 승인 버튼 문구는 그대로 **"계속해도 돼요" / "잠깐 멈춰요"** (지침서의 "계속 도와주기 / 멈추기"는 쓰지 않음).

## 6. 알림 우선순위 (FCM `android.notification.channelId`)
| 알림 | channelId | 중요도 | 변경 |
|---|---|---|---|
| 민감 앱 이용 | `family_activity` | 높음 | – |
| **도움 필요(stuck)** | **`help_alerts`** (새 채널) | **최상** | `family_activity` → `help_alerts` |
| SOS | `sos_alerts` | 최상 | – |
| **사기 의심(`category: scam`) 또는 L3** | **`sos_alerts`** | 최상 | 새 규칙 |
| 승인 요청 | `approval_requests` | 높음 | – |
- FCM `title`: 도움 필요 = "해봄 가족 · 도움 필요", 사기 의심 = "해봄 가족 · 긴급". `body`는 잠금 화면용 최소 문구 그대로.
- 보호자 앱은 시작할 때 `help_alerts` 채널을 만든다. 이미 설치된 폰은 앱을 한 번 실행하면 생긴다.
- 설정의 "SOS 알림" 스위치가 사기 의심도 함께 끈다/켠다. 도움 필요는 "앱 이용 알림" 스위치를 따른다(기존과 같음).

## 7. 문구 변경 (보호자 앱 내부, 규격 영향 없음)
| 위치 | 전 | 후 |
|---|---|---|
| 민감 앱 알림 | 어머니가 토스에 접속했습니다. | 어머니가 **토스를 사용하려고 합니다.** (앱을 열기 전에 묻기도 하므로) |
| 승인 상태 이름 | 시간 만료 / 요청 취소 | **응답 시간 지남 / 요청 취소됨** |
| 만료 안내 | 응답 가능 시간이 지나 요청이 만료되었습니다. | 응답 시간(5분)이 지나 해봄 도우미가 안내를 멈췄습니다. 어머니가 도움이 필요할 수 있으니 연락해 보세요. |
| 취소 안내 | 가족이 요청을 취소했습니다. | 어머니가 요청을 취소했습니다. 더 이상 응답하지 않아도 됩니다. |

## 8. 아직 하지 않은 것
- **전화 걸기 버튼**: `links`에 어르신 전화번호를 어떻게 저장할지(필드 이름, 동의, 누가 입력) 고령자 앱 담당과 합의 후 진행
- 서버 구현 주체·배포 방식, 보안 규칙 배포: 미협의
- 보호자 "확인했어요"(`readBy.{uid}` 직접 쓰기) vs 지침서의 "Firestore 직접 쓰기 금지": 미협의 (`SERVER_API.md` 5장)

## 9. 고령자 앱 담당에게 요청할 것
1. 연결 코드 화면·links 조회에서 `relationship` 대신 `guardianLabel` 사용 (없으면 "보호자")
2. #6·#8에 `level`·`category`·`reason`, #9에 `category`를 넣어 보내기 (보내지 않아도 보호자 앱은 동작)
3. 새 action 4개를 쓸 때 위 이름 그대로 사용
4. 전화번호 저장 방식 제안

## 10. 보호자 앱 반영 내역 (확인용)
| 파일 | 내용 |
|---|---|
| `lib/models/sensitivity.dart` (새 파일) | `SensitivityLevel`, `SensitivityCategory`, `RiskTone` |
| `lib/models/family_link.dart` | `elderLabel`, `guardianLabel` |
| `lib/models/notification_item.dart` | `level`, `category`, `reason`, `risk`, `isScam` |
| `lib/models/approval_request.dart` | `category`, action 4개 문구, 상태 이름 |
| `lib/repositories/server/*` | #14 본문, Firestore 읽기(옛 `relationship` 호환, 새 필드) |
| `lib/repositories/mock_backend.dart` | 새 필드 저장, 사기 의심 SOS, 시드 데이터 호칭 |
| `lib/screens/family/connect_family_screen.dart` | "가족이 나를 부르는 호칭" 선택 추가 |
| `lib/widgets/common.dart`, 알림·승인 상세 | 위험도 색, 사기 의심 라벨, 이유·분류 표시 |
| `lib/services/notification_service.dart` | `help_alerts` 채널, 사기 의심 → 긴급 채널 |
| `test/data_spec_v22_test.dart` (새 파일) | 위 내용 16개 테스트 |
