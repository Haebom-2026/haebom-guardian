import '../models/approval_request.dart';
import '../models/notification_item.dart';
import '../models/sensitivity.dart';

/// 받침 유무에 따라 '이/가'를 붙인다. (예: 어머니가, 할아버지가, 동생이)
String withSubjectParticle(String word) {
  if (word.isEmpty) return word;
  final last = word.runes.last;
  final isHangul = last >= 0xAC00 && last <= 0xD7A3;
  final hasBatchim = isHangul && (last - 0xAC00) % 28 != 0;
  return '$word${hasBatchim ? '이' : '가'}';
}

/// 받침 유무에 따라 '을/를'을 붙인다. (예: 토스를, 정부24를, 카카오뱅크를, 은행을)
/// 숫자로 끝나면 읽는 소리 기준 (0 영, 1 일, 3 삼, 6 육, 7 칠, 8 팔 → '을').
String withObjectParticle(String word) {
  if (word.isEmpty) return word;
  final last = word.runes.last;
  bool hasBatchim;
  if (last >= 0xAC00 && last <= 0xD7A3) {
    hasBatchim = (last - 0xAC00) % 28 != 0;
  } else if (last >= 0x30 && last <= 0x39) {
    hasBatchim = '013678'.contains(String.fromCharCode(last));
  } else {
    hasBatchim = false;
  }
  return '$word${hasBatchim ? '을' : '를'}';
}

String _two(int v) => v.toString().padLeft(2, '0');

/// 오전 9:05 / 오후 3:12
String formatClock(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '${t.hour < 12 ? '오전' : '오후'} $h:${_two(t.minute)}';
}

bool isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// 오늘 오후 3:12 / 어제 오전 9:05 / 11월 20일 오후 1:00 / 2025년 3월 1일 ...
String formatDateTime(DateTime t, DateTime now) {
  if (isSameDay(t, now)) return '오늘 ${formatClock(t)}';
  if (isSameDay(t, now.subtract(const Duration(days: 1)))) return '어제 ${formatClock(t)}';
  if (t.year == now.year) return '${t.month}월 ${t.day}일 ${formatClock(t)}';
  return '${t.year}년 ${t.month}월 ${t.day}일 ${formatClock(t)}';
}

/// 목록의 날짜 묶음 제목: 오늘 / 어제 / 11월 24일 (화) / 2025년 3월 1일 (토)
String formatDayHeader(DateTime t, DateTime now) {
  if (isSameDay(t, now)) return '오늘';
  if (isSameDay(t, now.subtract(const Duration(days: 1)))) return '어제';
  const w = ['월', '화', '수', '목', '금', '토', '일'];
  final day = '${t.month}월 ${t.day}일 (${w[t.weekday - 1]})';
  return t.year == now.year ? day : '${t.year}년 $day';
}

/// 방금 전 / 5분 전 / 2시간 전 / 어제 오후 3:12
String formatAgo(DateTime t, DateTime now) {
  final d = now.difference(t);
  if (d.inSeconds < 60) return '방금 전';
  if (d.inMinutes < 60) return '${d.inMinutes}분 전';
  if (d.inHours < 24 && isSameDay(t, now)) return '${d.inHours}시간 전';
  return formatDateTime(t, now);
}

/// 4분 05초
String formatRemaining(Duration d) {
  if (d <= Duration.zero) return '0초';
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return m > 0 ? '$m분 ${_two(s)}초' : '$s초';
}

/// 보호자 앱에 표시하는 알림 문장.
/// 민감 앱 "이용 사실"만 표현하며 개인정보 입력 여부는 언급하지 않는다.
/// 고령자 앱은 앱을 열기 전에 묻기도 하므로 "접속했다"가 아니라 "사용하려고 한다"로 표현한다.
/// `category: scam`이면 type과 관계없이 사기 의심 문구를 쓴다 (개발지침서 8.2).
String notificationMessage(NotificationItem n, String who) => n.isScam
    ? '${withSubjectParticle(who)} 사기 의심 상황일 수 있습니다. 바로 연락해 확인해 주세요.'
    : switch (n.type) {
      NotificationType.sensitiveEntry => n.appName.isEmpty
          ? '${withSubjectParticle(who)} 민감한 서비스를 사용하려고 합니다.'
          : '${withSubjectParticle(who)} ${withObjectParticle(n.appName)} 사용하려고 합니다.',
      NotificationType.sos => n.appName.isEmpty
          ? '${withSubjectParticle(who)} SOS 도움 요청을 보냈습니다.'
          : '${withSubjectParticle(who)} ${n.appName} 사용 중 SOS 도움 요청을 보냈습니다.',
      NotificationType.stuck => n.appName.isEmpty
          ? '${withSubjectParticle(who)} 휴대폰 사용 중 도움이 필요할 수 있습니다.'
          : '${withSubjectParticle(who)} ${n.appName} 사용 중 도움이 필요할 수 있습니다.',
    };

String notificationTypeLabel(NotificationType t) => switch (t) {
      NotificationType.sensitiveEntry => '앱 이용 알림',
      NotificationType.sos => 'SOS 알림',
      NotificationType.stuck => '도움 필요 알림',
    };

/// 목록·상세의 종류 표시. 사기 의심이면 최우선, L2 이상이면 단계 이름을 덧붙인다(색 + 글자로 구분).
String notificationLabel(NotificationItem n) {
  if (n.isScam) return '사기 의심 알림';
  final base = notificationTypeLabel(n.type);
  final level = n.level;
  if (level == null || level.index < SensitivityLevel.l2.index) return base;
  return '$base · ${level.label}';
}

/// 승인 요청 기기 알림의 상세 문구. 안내 이름이 앱 이름으로 시작하면 앱 이름을 반복하지 않는다.
/// 예) 어머니가 정부24 '주민등록표 등본 발급 안내' 진행 승인을 요청했습니다.
///     어머니가 '정부24 본인인증 단계 안내' 진행 승인을 요청했습니다.
String approvalAlertDetail(ApprovalRequest a, String who) {
  final label = ApprovalActions.label(a.action);
  final app = a.appName.isEmpty || label.startsWith(a.appName) ? '' : '${a.appName} ';
  return "${withSubjectParticle(who)} $app'$label' 진행 승인을 요청했습니다.";
}

String approvalMessage(ApprovalRequest a, String who) =>
    '${withSubjectParticle(who)} ${a.appName} 이용 중 해봄 도우미의 '
    '\'${ApprovalActions.label(a.action)}\'을(를) 계속 받아도 될지 확인을 요청했습니다.';
