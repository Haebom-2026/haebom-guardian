/// 가족의 도전: 보호자가 "해 볼 만한 일"을 추천하고, 어르신이 스스로 해내면 가족이 칭찬한다.
///
/// 💡 제안 단계 (서버·고령자 앱과 합의 전). 지금은 Mock 서버에서만 동작한다.
/// 원칙: 하라고 시키는 숙제가 아니다. 어르신이 할지 직접 고르고, 안 해도 보호자에게 알리지 않는다.
/// 실패·시간 제한·순위는 없다. 도우미 안내를 받으며 해내도 성공이다. 금융 거래는 도전으로 만들지 않는다.
/// 개인정보: 무엇을 입력했는지·어떤 화면을 봤는지는 보내지 않고 "해냈다"는 사실만 전달한다.
library;

/// 추천할 수 있는 도전 (미리 정해 둔 목록)
class ChallengeTemplate {
  const ChallengeTemplate({required this.id, required this.title, required this.appName, required this.hint});
  final String id;
  final String title;
  final String appName;

  /// 추천 화면에 보여 줄 한 줄 설명
  final String hint;

  static const all = [
    ChallengeTemplate(id: 'gov24_resident', title: '정부24에서 등본 혼자 떼어 보기', appName: '정부24', hint: '주민센터에 가지 않아도 돼요'),
    ChallengeTemplate(id: 'kakao_photo', title: '카카오톡으로 가족에게 사진 보내기', appName: '카카오톡', hint: '찍은 사진을 가족 대화방에 보내요'),
    ChallengeTemplate(id: 'video_call', title: '가족에게 영상통화 걸어 보기', appName: '카카오톡', hint: '얼굴 보며 안부를 나눠요'),
    ChallengeTemplate(id: 'bus_arrival', title: '버스 도착 시간 확인해 보기', appName: '카카오맵', hint: '정류장에서 오래 기다리지 않아요'),
    ChallengeTemplate(id: 'weather', title: '내일 날씨 확인해 보기', appName: '날씨', hint: '우산을 챙길지 미리 알 수 있어요'),
  ];

  static ChallengeTemplate? byId(String id) {
    for (final t in all) {
      if (t.id == id) return t;
    }
    return null;
  }
}

enum ChallengeStatus {
  /// 추천됨 (어르신이 아직 해내지 않음. 하실지 말지는 어르신이 정한다)
  open,

  /// 해냈어요
  done,
}

/// 칭찬 문구 (미리 정해 둔 것만 보낸다)
const cheerMessages = ['최고예요! 👍', '직접 해내시다니 정말 멋져요!', '다음에도 같이 해 봐요 😊'];

class Challenge {
  const Challenge({
    required this.id,
    required this.elderId,
    required this.templateId,
    required this.title,
    required this.appName,
    required this.suggestedBy,
    required this.guardianIds,
    required this.createdAt,
    this.status = ChallengeStatus.open,
    this.completedAt,
    this.withHelp = false,
    this.cheers = const {},
  });

  final String id;
  final String elderId;
  final String templateId;
  final String title;
  final String appName;

  /// 추천한 보호자
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
  bool cheeredBy(String guardianId) => cheers.containsKey(guardianId);

  /// 목록 정렬용 시각 (해낸 도전은 해낸 시각)
  DateTime get at => completedAt ?? createdAt;

  Challenge copyWith({ChallengeStatus? status, DateTime? completedAt, bool? withHelp, Map<String, String>? cheers}) =>
      Challenge(
        id: id,
        elderId: elderId,
        templateId: templateId,
        title: title,
        appName: appName,
        suggestedBy: suggestedBy,
        guardianIds: guardianIds,
        createdAt: createdAt,
        status: status ?? this.status,
        completedAt: completedAt ?? this.completedAt,
        withHelp: withHelp ?? this.withHelp,
        cheers: cheers ?? this.cheers,
      );
}
