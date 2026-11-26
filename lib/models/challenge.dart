/// 가족의 도전: 보호자가 "해 볼 만한 일"을 직접 정해 보내고, 어르신이 스스로 해내면 가족이 칭찬한다.
///
/// 💡 제안 단계 (서버·고령자 앱과 합의 전). 지금은 Mock 서버에서만 동작한다.
/// 원칙: 하라고 시키는 숙제가 아니다. 어르신이 [해 볼게요]/[다음에 할게요]를 직접 고르고,
/// "다음에"를 골라도 보호자에게 거절로 알리지 않는다. 실패·시간 제한·순위는 없다.
/// 도우미 안내를 받으며 해내도 성공이다. 돈·개인정보가 오가는 일은 도전으로 만들 수 없다.
/// 개인정보: 무엇을 입력했는지·어떤 화면을 봤는지는 보내지 않고, 어르신이 누른 [해냈어요]만 전달한다.
library;

/// 도전 예시. 보호자가 눌러서 그대로 보내거나 고쳐 쓴다.
class ChallengeTemplate {
  const ChallengeTemplate({required this.id, required this.title, required this.hint});
  final String id;
  final String title;

  /// 어르신 화면에 보일 도움말 한 줄
  final String hint;

  static const all = [
    ChallengeTemplate(id: 'gov24_resident', title: '정부24에서 등본 떼어 보기', hint: '정부24 → 자주 찾는 서비스 → 주민등록표 등본'),
    ChallengeTemplate(id: 'kakao_photo', title: '카카오톡으로 가족에게 사진 보내기', hint: '대화방 → + 버튼 → 앨범'),
    ChallengeTemplate(id: 'video_call', title: '가족에게 영상통화 걸어 보기', hint: '대화방 → 오른쪽 위 전화 모양 → 페이스톡'),
    ChallengeTemplate(id: 'bus_arrival', title: '버스 도착 시간 확인해 보기', hint: '카카오맵 → 정류장 이름 검색'),
    ChallengeTemplate(id: 'weather', title: '내일 날씨 확인해 보기', hint: '날씨 앱 열고 위로 밀어 보기'),
  ];

  static ChallengeTemplate? byId(String id) {
    for (final t in all) {
      if (t.id == id) return t;
    }
    return null;
  }
}

/// 도전 이름·도움말 길이 (어르신 화면에서 큰 글씨로 두세 줄 안에 들어가도록)
const challengeTitleMax = 30;
const challengeHintMax = 40;

/// 도전으로 만들 수 없는 말. 돈·개인정보가 오가는 일은 막는다
/// (보호자를 사칭한 사람이 "인증번호 알려 주기" 같은 도전을 보내는 경우도 막기 위해).
const challengeBlockedWords = [
  '송금', '이체', '입금', '계좌', '결제', '대출', '돈보내', '돈빌려', '비밀번호', '비번', '인증번호', //
  '카드번호', '보안카드', 'OTP', '주민번호', '주민등록번호', '공인인증', '상품권',
];

/// 도전 이름·도움말 검사. 문제가 없으면 null, 있으면 보여 줄 안내 문구.
String? validateChallenge(String title, [String hint = '']) {
  final t = title.trim();
  if (t.isEmpty) return '도전 이름을 적어 주세요.';
  if (t.length > challengeTitleMax) return '도전 이름은 $challengeTitleMax자까지 쓸 수 있어요.';
  if (hint.trim().length > challengeHintMax) return '도움말은 $challengeHintMax자까지 쓸 수 있어요.';
  final text = '$t ${hint.trim()}'.toUpperCase().replaceAll(' ', '');
  for (final w in challengeBlockedWords) {
    if (text.contains(w.toUpperCase())) return '돈이나 개인정보가 오가는 일은 도전으로 만들 수 없어요. ("$w")';
  }
  return null;
}

enum ChallengeStatus {
  /// 보냈어요 (어르신이 아직 고르지 않음)
  sent,

  /// 어르신이 [다음에 할게요]를 고름. 보호자에게는 [sent]와 똑같이 보인다 (거절로 알리지 않음)
  later,

  /// 어르신이 [해 볼게요]를 고름
  accepted,

  /// 어르신이 [해냈어요]를 누름
  done,
}

/// 칭찬 문구 (미리 정해 둔 것만 보낸다)
const cheerMessages = ['최고예요! 👍', '직접 해내시다니 정말 멋져요!', '다음에도 같이 해 봐요 😊'];

class Challenge {
  const Challenge({
    required this.id,
    required this.elderId,
    required this.title,
    this.hint = '',
    required this.suggestedBy,
    required this.guardianIds,
    required this.createdAt,
    this.status = ChallengeStatus.sent,
    this.completedAt,
    this.withHelp = false,
    this.cheers = const {},
  });

  final String id;
  final String elderId;
  final String title;

  /// 어르신 화면에 보일 도움말 한 줄 (없으면 빈 문자열)
  final String hint;

  /// 보낸 보호자
  final String suggestedBy;

  /// 이 도전을 볼 수 있는 보호자 (연결된 보호자 전체)
  final List<String> guardianIds;
  final DateTime createdAt;
  final ChallengeStatus status;
  final DateTime? completedAt;

  /// 도우미 안내를 받으며 해냈는지 (그래도 성공이다)
  final bool withHelp;

  /// 보호자별 칭찬 문구
  final Map<String, String> cheers;

  bool get isDone => status == ChallengeStatus.done;
  bool get isAccepted => status == ChallengeStatus.accepted;

  /// 아직 해내지 않았고 진행 중이거나 어르신이 고르기 전 (같은 도전을 또 보내지 않는다)
  bool get isActive => !isDone;

  bool cheeredBy(String guardianId) => cheers.containsKey(guardianId);

  /// 목록 정렬용 시각 (해낸 도전은 해낸 시각)
  DateTime get at => completedAt ?? createdAt;

  Challenge copyWith({ChallengeStatus? status, DateTime? completedAt, bool? withHelp, Map<String, String>? cheers}) =>
      Challenge(
        id: id,
        elderId: elderId,
        title: title,
        hint: hint,
        suggestedBy: suggestedBy,
        guardianIds: guardianIds,
        createdAt: createdAt,
        status: status ?? this.status,
        completedAt: completedAt ?? this.completedAt,
        withHelp: withHelp ?? this.withHelp,
        cheers: cheers ?? this.cheers,
      );
}
