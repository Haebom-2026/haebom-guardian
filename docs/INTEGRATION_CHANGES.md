# 연동 규격 변경 내역 (v1 → v2)과 합의 필요 사항

> 작성일: 2026-11-25 (v2.1 갱신: 같은 날 오후) · 작성: 보호자 앱 담당
> v1(보관본): `docs/archive/GUARDIAN_INTEGRATION_v1_callable_2026-11-25.md` · v2(최신): `docs/GUARDIAN_INTEGRATION.md`
> 고령자 앱 담당자에게 **이 문서를 먼저** 보내고, 합의되면 v2를 확정한다.

## 0. v2.1 갱신 (2026-11-25 오후) — 팀원에게 전달할 최신 변경 사항

### 0.1 역할 분담 (확정)
| 담당 | 범위 |
|---|---|
| 고령자 앱 담당 | 고령자 Android 앱 |
| **서버 담당** | 공통 백엔드 서버 + FCM 발송 (개발 중) |
| 보호자 앱 담당 | 보호자 Flutter 앱(Android/iOS) + FCM 수신 |

→ 아래 2~4장의 "보호자 앱 담당자 맥북에서 Node 서버 + Cloudflare Tunnel" 제안(A1·A3·A4)은 **취소**한다. 서버 기술·실행 위치·주소 전달 방식은 서버 담당자가 정한다. 보호자 앱이 서버에 기대하는 것은 `docs/SERVER_REQUIREMENTS.md`에 정리했다.

### 0.2 `INTEGRATION_REVIEW.md` 검토 결과 — 합의 확정, 보호자 앱 반영 완료
| 항목 | 결정 | 보호자 앱 |
|---|---|---|
| 중복 방지 시간 (B2) | 고령자 앱 팝업·서버 모두 **10분** | ✅ Mock 10분 |
| 승인 범위 (B3) | 승인·거절 **유지**, 공모전 시연 포함 | ✅ 등본 데모에 승인 요청 추가 |
| 승인 유효시간 (B4) | **5분**, 자동 진행 금지 | ✅ |
| 승인 만료 시 | 고령자 앱이 안내 중단 + **SOS 문자 제안** | ✅ 규격·개발자 화면 반영 |
| 승인 버튼 문구 (B5) | 보호자 "계속해도 돼요" / "잠깐 멈춰요" 제안에 동의 (내부 값 유지) | 💡 문구 교체는 아직 안 함 — 다음 작업 |
| "확인했어요" (B7) | **버튼을 눌러야** `readBy` 기록. 고령자 앱 구독은 2차 | ✅ 버튼, "확인 전"/"모두 확인" |
| `stuck` (B8) | 45초 기준 + **고령자 동의 후에만** 전송 | ✅ 데모 시나리오 동의 단계 |
| SOS (B9) | SMS 유지 + 서버 기록, `appName`/`packageName` **선택 필드** | ✅ "정부24 사용 중 SOS" 표시 |
| 민감 앱 목록 (B10) | 패키지 목록(고령자 앱 11개 기준) + 이름 단어 보조 감지, **서버는 목록 검증 안 함** | 보호자 앱은 `appName` 그대로 표시 |
| 코드 재발급 (B11) | 이전 미사용 코드 **무효화** | ✅ |
| 고령자 쪽 해제 (B12) | **필요** (연결된 가족 목록 + 해제) | ✅ Mock `disconnectByElder` |
| applicationId (B13) | 고령자 앱 `com.yju.haebom.elder` 제안 | – |
| 함수 이름 | `connectWithCode` 통일 | ✅ |
| 고령자 UID (A5) | 1차 익명 로그인, 2차 전화번호 인증 계정 연결 | – |

### 0.3 아직 합의가 필요한 것
| # | 항목 | 누구와 |
|---|---|---|
| 1 | ✅ **Firebase 프로젝트: `copilot-demo-c9a74` 공동 사용** (2026-11-25 사용자 결정, 보호자 앱 담당). 고령자 앱 담당의 새 프로젝트 권장 의견은 기록으로 남김 — 규칙 교체 전 옛 학습용 앱·`families` 정리 여부 확인 필요 | 세 명 확인 |
| 2 | 기존 프로젝트를 쓴다면: 보호자 앱 Android·iOS **앱 등록** 동의, 보안 규칙 교체 시점(옛 `families` 규칙 영향) | 소유자·서버 담당 |
| 3 | 서버 API 방식(REST/Callable), 경로, 서버 주소 전달 방식, 오류 형식 | 서버 담당 |
| 4 | FCM 발송: 등록 토큰 vs Installation ID, payload(`data.kind/id/type`, 채널, 최소 문구, `tag`) | 서버 담당 |
| 5 | 보안 규칙이 보호자 앱 쿼리(가족별 `elderId` 고정 + `guardianIds` array-contains)를 허용하는지 | 서버 담당 |
| 6 | 보호자 로그인 방식 (1차 익명) | 세 명 |

---

## 1. 한 줄 요약
**Firebase 유료 요금제(Blaze) 없이** 실제 원격 푸시를 보내기 위해, Cloud Functions 대신 **보호자 앱 담당자의 맥북에서 도는 Node.js REST 서버**를 쓰는 방식으로 바꾸자는 제안이다. Firestore 데이터 구조(컬렉션·필드·값)와 기능(알림, 도움 필요, SOS, 승인·거절, 가족 연결)은 **그대로**다.

## 2. 왜 바꾸나
| 문제 | v1 (Cloud Functions) | v2 (REST 서버) |
|---|---|---|
| 비용 | Cloud Functions는 **Blaze(종량제, 결제 카드 등록)** 필요 | Spark **무료** 요금제로 가능. FCM·Auth·Firestore는 무료 |
| 서버 위치 | Google 서버 | 보호자 앱 담당자 맥북 + Cloudflare Quick Tunnel(무료 HTTPS) |
| 규칙 | 같음 | 같음 (보호자 앱 `MockBackend` 규칙을 TypeScript로 옮김) |

## 3. 바뀌는 것

### 3.1 고령자 앱 담당자에게 영향 있음
| # | 항목 | v1 | v2 | 고령자 앱 작업 변화 |
|---|---|---|---|---|
| C1 | Firebase 프로젝트 | 미정 (`copilot-demo-c9a74` 사용 중) | **해봄 공통 프로젝트 신규 생성** (Spark). 기존 프로젝트는 변경하지 않음 | `google-services.json` 교체 |
| C2 | 서버 호출 | `Firebase.functions().getHttpsCallable("함수명")` | `POST https://<서버>/v1/...` + `Authorization: Bearer <ID 토큰>` | Functions SDK 대신 OkHttp 등 HTTP 호출 |
| C3 | 서버 주소 | 불필요 | Firestore `config/server.baseUrl` 구독 (주소가 실행할 때마다 바뀜) | 주소 구독 코드 추가 |
| C4 | 사용자 문서 생성 | 각 앱이 `users/{uid}` 직접 쓰기 | `POST /v1/users/me { role, name }`로만 생성, **역할은 이후 변경 불가** | 직접 쓰기 대신 API 호출 |
| C5 | 중복 요청 방지 | 없음 | 생성 요청에 `Idempotency-Key` 헤더 필수, 재시도 시 같은 키 사용 | 헤더 추가 |
| C6 | 오류 형식 | `HttpsError` + `details.reason` | HTTP 상태 + `{ "error": { "reason", "message" } }` | 오류 파싱 변경 (reason 값은 그대로) |
| C7 | 오류 reason | 12개 | 12개 + 💡 `unauthenticated`, `profile-required`, `role-locked`, `rate-limited` | 4개 처리 추가 |
| C8 | 함수 → 엔드포인트 | `reportSensitiveEntry` 등 | `POST /v1/elder/sensitive-entries` 등 (대응표: v2 4.2장) | 호출 경로만 변경 |
| C9 | 승인 만료 | 서버(Scheduled Function) | 서버 시작 시 + 30초마다 + **앱도 `expiresAt`에 스스로 대기 종료** | 고령자 앱 자체 타이머 필수 |
| C10 | 서버 가용성 | Google이 항상 실행 | 맥북이 꺼지면 쓰기·푸시 중단 (읽기는 계속) | 실패 시 앱이 멈추지 않게 처리 |
| C11 | 연결 해제 | `disconnect({guardianId})` | `DELETE /v1/elder/links/{guardianId}` | 경로만 변경 |
| C12 | 연결 코드 대입 방지 | uid별 5회 | uid별 5회 + **IP별 10회** | 없음 |

### 3.2 고령자 앱 작업에 영향 없음 (서버·보호자 앱 내부)
- 서버 전용 컬렉션 추가: `dedupe`, `idempotency`, `pushJobs`, `rateLimits` (앱은 접근 불가)
- FCM 발송 실패 재시도, 무효 토큰 삭제, 서버 재시작 시 미발송 푸시 재처리
- Android 푸시에 `tag`를 넣어 알림창 중복 제거
- 보호자 앱에 `ServerGuardianRepository` 추가 (Mock 구현·자동 테스트는 그대로 유지)
- 서버 자동 테스트는 Firebase 로컬 에뮬레이터로 실행 (실제 프로젝트를 쓰지 않음)

### 3.3 바뀌지 않는 것
- 공유 컬렉션 `users`, `links`, `notifications`, `approvals`, `connectCodes`의 **필드·타입·값**
- 알림 type 3종, 승인 status 5종, action 3종, 민감 앱 패키지명 4개
- 성공 응답 본문 (`{ result: "created", notificationId }` 등)
- 수신 보호자는 서버가 links로 결정, `consent` 필드 없음, "예"일 때만 전송
- 승인·거절 기능과 상태 전이 규칙, 먼저 온 응답만 반영
- 연결 코드 10분·일회용·uid별 5회 실패 잠금

### 3.4 v1 문서의 잘못된 내용 정정
- `docs/INTEGRATION.md` 4.6에 "현재 고령자 앱은 승인 응답을 최대 5분 기다린다"고 적었으나, 연동 분석 문서 기준 **고령자 앱에는 승인 요청 코드가 아직 없다.** 보호자 앱 Mock 기본값을 고령자 앱 동작으로 잘못 적은 것이다.

## 4. 합의가 필요한 사항

### 4.1 v2 서버 방식 관련 (먼저 합의)
| # | 항목 | 💡 보호자 앱 쪽 제안 | 결정 |
|---|---|---|---|
| A1 | REST 서버 방식 채택 | Node.js + Express + TypeScript, 보호자 앱 담당자 맥북 실행, Cloudflare Quick Tunnel | ☐ |
| A2 | 해봄 공통 Firebase 프로젝트 | 보호자 앱 담당자의 **개인 Gmail** 계정으로 새로 생성(Spark), 고령자 앱 담당자는 멤버로 초대. 학교 계정은 서비스 계정 키 생성이 막혀 있을 수 있음 | ☐ |
| A3 | 서버·보안 규칙 담당 | 보호자 앱 담당자가 작성·운영, 고령자 앱 담당자가 리뷰 | ☐ |
| A4 | 서비스 계정 키 보관 | 보호자 앱 담당자만 보관. 공유하지 않음 | ☐ |
| A5 | 로그인 방식 | 시연은 두 앱 모두 **익명 로그인** (앱 삭제 시 연결 끊김 감수). 실서비스 방식은 이후 결정 | ☐ |
| A6 | 서버가 꺼져 있을 때 고령자 앱 동작 | 알림·도움 필요: 1회 재시도 후 포기 / SOS: SMS는 항상 먼저 발송 / 승인: `expiresAt`에 스스로 종료 | ☐ |
| A7 | 신규 오류 reason 4개 | `unauthenticated`, `profile-required`, `role-locked`, `rate-limited` | ☐ |
| A8 | `Idempotency-Key` 필수화 | 생성 요청 6종에 필수 | ☐ |
| A9 | 고령자 앱 FCM 수신 | 1차에서는 받지 않음 (승인 결과는 Firestore 구독으로 충분) | ☐ |
| A10 | iPhone | 보호자 앱 iPhone은 실제 서버 연동 + 앱 실행 중 로컬 알림까지. 원격 푸시는 Apple 유료 계정이 생기면 추가 | ☐ |

### 4.2 v1부터 이어진 기능·정책 합의 (변동 없음)
| # | 항목 | 현재 상황 | 💡 제안 |
|---|---|---|---|
| B1 | 알림 문서 생성 주체 | 연동 분석 문서: 어르신 앱 생성 / 규격: 서버 생성 | **서버 생성** (고령자 앱은 보호자 uid를 모르고, 직접 쓰기는 보안상 위험) |
| B2 | 중복 방지 시간 | 고령자 앱 팝업 10분(제안) / 서버 Mock 5분 | 같은 값으로 통일 (예: 10분) |
| B3 | 승인 기능 범위·적용 상황 | 보호자 앱 구현 완료, 고령자 앱 미구현 | **기능 유지.** 어떤 상황에서 요청할지(일상 업무 vs 위험 상황), 1차 시연 포함 여부 결정 (`INTEGRATION.md` 4.6 제안 A·B) |
| B4 | 승인 유효시간 | 5분 | 값 결정, 만료 시 자동 진행 금지 |
| B5 | 승인 버튼 문구 | "승인"/"거절" | 의미에 맞는 문구 검토, 내부 값은 유지 |
| B6 | action 코드 목록 | 3개 | 실제 요청 상황에 맞춰 확정 |
| B7 | "확인했어요" (`readBy`) | 상세 화면을 열면 기록 | 버튼을 눌러야 기록하는 안(B안) + 고령자 앱이 구독해 "○○가 확인했어요" 표시 여부 |
| B8 | `stuck` 발생 조건 | 45초 막힘 타이머 있음 | 45초 기준 + 같은 앱 10분 중복 방지 |
| B9 | SOS 기록 | SMS + `families/{코드}/events` | SMS 유지 + `POST /v1/elder/sos`, 기존 경로 정리 |
| B10 | 민감 앱 패키지명 | 보호자 4개 / 고령자 정부24 + 은행 이름 단어 | 패키지명 목록 통일, 실기기 확인 |
| B11 | 연결 코드 재발급 | 미정 | 새 코드 발급 시 이전 미사용 코드 무효화 |
| B12 | 고령자 쪽 연결 해제 화면 | 없음 | 필요 여부 |
| B13 | applicationId | 고령자 앱 `com.example.copilot.parent` | 스토어 배포 고려 시 변경 (보호자 앱: `com.yju.haebom.guardian_app` / iOS `com.yju.haebom.guardianApp`) |
| B14 | 원격 푸시에 상세 문구 | 기본 최소 문구 | 보호자의 "상세 내용 표시" 설정을 서버에 저장해 푸시에도 반영할지 |

## 5. 고령자 앱 담당자에게 보낼 메시지 (예시)
> 보호자 앱 쪽에서 Firebase 유료 요금제 없이 실제 푸시를 보내려고, Cloud Functions 대신 제 맥북에서 Node 서버를 돌리는 방식(v2)을 제안해요.
> 데이터 구조는 그대로고, 고령자 앱은 함수 호출 대신 REST 호출로 바꾸면 됩니다.
> `INTEGRATION_CHANGES.md` 4장 합의 항목(특히 A1~A6, B1~B3) 확인 부탁드려요. 상세 규격은 `GUARDIAN_INTEGRATION.md`예요.
