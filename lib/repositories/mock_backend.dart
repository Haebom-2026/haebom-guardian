import 'dart:async';
import 'dart:math';

import '../models/approval_request.dart';
import '../models/challenge.dart';
import '../models/family_link.dart';
import '../models/notification_item.dart';
import '../models/sensitive_app.dart';
import '../models/sensitivity.dart';
import 'guardian_repository.dart';

typedef Clock = DateTime Function();

/// 사용자 문서 (users/{uid})
class MockUser {
  const MockUser({required this.id, required this.name, required this.role});
  final String id;
  final String name;

  /// elder | guardian
  final String role;
}

/// 고령자 앱이 실시간으로 수신하는 승인 결과 (approvals 문서 변경을 구독한 결과를 기록).
class ElderDelivery {
  const ElderDelivery({
    required this.approvalId,
    required this.elderId,
    required this.status,
    required this.at,
    this.respondedBy,
  });
  final String approvalId;
  final String elderId;
  final ApprovalStatus status;
  final DateTime at;
  final String? respondedBy;

  /// 고령자 앱이 취할 동작
  String get elderAppBehavior => switch (status) {
        ApprovalStatus.approved => 'AI 도우미 안내 계속',
        ApprovalStatus.rejected => 'AI 도우미 안내 중단',
        ApprovalStatus.expired => '응답 없음 → 안내 중단, SOS 문자 보낼지 묻기',
        ApprovalStatus.cancelled => '고령자가 요청 취소',
        ApprovalStatus.pending => '대기',
      };
}

enum SensitiveEntryOutcome {
  created('알림이 생성되어 보호자에게 전송되었습니다.'),
  duplicateSuppressed('같은 앱의 중복 알림이라 전송하지 않았습니다.'),
  skippedNoConsent('고령자가 동의하지 않아 알림을 생성하지 않았습니다.'),
  noGuardians('연결된 보호자가 없어 알림을 생성하지 않았습니다.');

  const SensitiveEntryOutcome(this.message);
  final String message;
}

/// Firebase(Firestore + Cloud Functions)의 역할을 대신하는 메모리 내 Mock 서버.
///
/// - 수신 보호자(guardianIds)는 클라이언트가 아니라 서버가 links 기준으로 결정한다.
/// - 승인 응답은 단일 스레드에서 원자적으로 처리되어 "최초의 유효한 응답"만 반영된다.
/// - 실제 연동 시 이 클래스의 규칙이 Cloud Functions/보안 규칙으로 옮겨진다.
class MockBackend {
  MockBackend({Clock? clock, Random? random, bool seed = true})
      : _clock = clock ?? DateTime.now,
        _random = random ?? Random() {
    if (seed) _seed();
  }

  // ---- 정책 값 (제안 사항, docs/INTEGRATION.md 참고) ----
  static const connectCodeTtl = Duration(minutes: 10);
  static const approvalTtl = Duration(minutes: 5);
  /// 같은 앱 알림 중복 방지 시간. 고령자 앱 팝업 쿨다운과 같은 10분 (INTEGRATION_REVIEW #4 합의)
  static const duplicateWindow = Duration(minutes: 10);
  static const maxFailedCodeAttempts = 5;
  static const codeLockDuration = Duration(minutes: 5);

  static const meId = 'guardian_me';
  static const siblingId = 'guardian_sibling';
  static const momId = 'elder_mom';
  static const dadId = 'elder_dad';
  static const grandmaId = 'elder_grandma';

  final Clock _clock;
  final Random _random;
  int _seq = 0;

  final Map<String, MockUser> users = {};
  final Map<String, FamilyLink> _links = {};
  final Map<String, ConnectCode> _codes = {};
  final Map<String, NotificationItem> _notifications = {};
  final Map<String, ApprovalRequest> _approvals = {};
  final Map<String, Challenge> _challenges = {};
  final List<ElderDelivery> _elderInbox = [];
  final Map<String, int> _failedAttempts = {};
  final Map<String, DateTime> _lockedUntil = {};

  final StreamController<void> _changes = StreamController<void>.broadcast();
  Timer? _ticker;

  /// 데이터가 바뀔 때마다 이벤트 발생 (Firestore snapshot listener 역할)
  Stream<void> get changes => _changes.stream;

  DateTime now() => _clock();

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  String _newId(String prefix) => '${prefix}_${now().microsecondsSinceEpoch}_${_seq++}';

  /// 앱 실행 중 만료 시간이 지난 승인 요청을 주기적으로 만료 처리한다.
  /// (실제 서버에서는 스케줄 함수 또는 응답 시점 검증으로 처리)
  void startExpiryTicker([Duration interval = const Duration(seconds: 1)]) {
    _ticker?.cancel();
    _ticker = Timer.periodic(interval, (_) => expireOverdue());
  }

  void dispose() {
    _ticker?.cancel();
    _changes.close();
  }

  // ======================= 읽기 (보안 규칙 적용) =======================

  bool isLinked(String elderId, String guardianId) =>
      _links.containsKey('${elderId}_$guardianId');

  List<FamilyLink> linksForGuardian(String guardianId) =>
      _links.values.where((l) => l.guardianId == guardianId).toList()
        ..sort((a, b) => a.connectedAt.compareTo(b.connectedAt));

  List<FamilyLink> linksForElder(String elderId) =>
      _links.values.where((l) => l.elderId == elderId).toList();

  bool _canRead(String guardianId, String elderId, List<String> guardianIds) =>
      guardianIds.contains(guardianId) && isLinked(elderId, guardianId);

  List<NotificationItem> notificationsFor(String guardianId) => _notifications.values
      .where((n) => _canRead(guardianId, n.elderId, n.guardianIds))
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  List<ApprovalRequest> approvalsFor(String guardianId) => _approvals.values
      .where((a) => _canRead(guardianId, a.elderId, a.guardianIds))
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  NotificationItem notificationFor(String guardianId, String id) {
    final n = _notifications[id];
    if (n == null) throw const RepositoryException(RepositoryErrorCode.notFound);
    if (!_canRead(guardianId, n.elderId, n.guardianIds)) {
      throw const RepositoryException(RepositoryErrorCode.permissionDenied);
    }
    return n;
  }

  ApprovalRequest approvalFor(String guardianId, String id) {
    final a = _approvals[id];
    if (a == null) throw const RepositoryException(RepositoryErrorCode.notFound);
    if (!_canRead(guardianId, a.elderId, a.guardianIds)) {
      throw const RepositoryException(RepositoryErrorCode.permissionDenied);
    }
    return a;
  }

  /// 개발자 화면용 전체 조회 (서버 관리자 시점)
  List<NotificationItem> get allNotifications =>
      _notifications.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  List<ApprovalRequest> get allApprovals =>
      _approvals.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  List<ElderDelivery> get elderInbox => List.unmodifiable(_elderInbox.reversed);
  List<MockUser> get elders => users.values.where((u) => u.role == 'elder').toList();
  String userName(String id) => users[id]?.name ?? id;

  // ======================= 보호자 요청 처리 =======================

  void markRead(String guardianId, String notificationId) {
    final n = notificationFor(guardianId, notificationId);
    if (n.isReadBy(guardianId)) return;
    // 보호자 본인의 readBy 항목만 변경 가능 (보안 규칙)
    _notifications[n.id] = n.copyWith(readBy: {...n.readBy, guardianId: now()});
    _notify();
  }

  void markAllRead(String guardianId, {String? elderId}) {
    var changed = false;
    for (final n in notificationsFor(guardianId)) {
      if (elderId != null && n.elderId != elderId) continue;
      if (n.isReadBy(guardianId)) continue;
      _notifications[n.id] = n.copyWith(readBy: {...n.readBy, guardianId: now()});
      changed = true;
    }
    if (changed) _notify();
  }

  /// 승인/거절 처리 (Cloud Functions 트랜잭션 역할).
  ApprovalRequest respond(String guardianId, String approvalId, {required bool approve}) {
    final a = approvalFor(guardianId, approvalId);
    if (a.status == ApprovalStatus.cancelled) {
      throw const RepositoryException(RepositoryErrorCode.approvalCancelled);
    }
    if (a.status == ApprovalStatus.expired ||
        (a.status == ApprovalStatus.pending && !now().isBefore(a.expiresAt))) {
      _expire(a);
      _notify();
      throw const RepositoryException(RepositoryErrorCode.approvalExpired);
    }
    if (a.status != ApprovalStatus.pending) {
      throw const RepositoryException(RepositoryErrorCode.alreadyResponded);
    }
    final updated = a.copyWith(
      status: approve ? ApprovalStatus.approved : ApprovalStatus.rejected,
      respondedAt: now(),
      respondedBy: guardianId,
    );
    _approvals[a.id] = updated;
    _deliverToElder(updated);
    _notify();
    return updated;
  }

  FamilyLink connectWithCode(String guardianId, String rawCode,
      {required String elderLabel, String guardianLabel = ''}) {
    final lockedUntil = _lockedUntil[guardianId];
    if (lockedUntil != null && now().isBefore(lockedUntil)) {
      throw const RepositoryException(RepositoryErrorCode.tooManyAttempts);
    }
    final code = rawCode.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      throw const RepositoryException(RepositoryErrorCode.invalidCode);
    }
    final entry = _codes[code];
    if (entry == null) {
      _registerFailure(guardianId);
      throw const RepositoryException(RepositoryErrorCode.invalidCode);
    }
    if (entry.used) {
      _registerFailure(guardianId);
      throw const RepositoryException(RepositoryErrorCode.codeUsed);
    }
    if (!now().isBefore(entry.expiresAt)) {
      _registerFailure(guardianId);
      throw const RepositoryException(RepositoryErrorCode.codeExpired);
    }
    if (isLinked(entry.elderId, guardianId)) {
      throw const RepositoryException(RepositoryErrorCode.alreadyLinked);
    }
    _failedAttempts.remove(guardianId);
    _codes[code] = entry.markUsed();
    final link = FamilyLink(
      elderId: entry.elderId,
      guardianId: guardianId,
      elderName: userName(entry.elderId),
      elderLabel: elderLabel.trim(),
      guardianLabel: guardianLabel.trim(),
      connectedAt: now(),
    );
    _links[link.id] = link;
    _notify();
    return link;
  }

  void _registerFailure(String guardianId) {
    final count = (_failedAttempts[guardianId] ?? 0) + 1;
    _failedAttempts[guardianId] = count;
    if (count >= maxFailedCodeAttempts) {
      _lockedUntil[guardianId] = now().add(codeLockDuration);
      _failedAttempts.remove(guardianId);
    }
  }

  void disconnect(String guardianId, String elderId) {
    final removed = _links.remove('${elderId}_$guardianId');
    if (removed == null) throw const RepositoryException(RepositoryErrorCode.notFound);
    _notify();
  }

  /// 고령자 앱에서 연결 해제 (`disconnect({guardianId})`, INTEGRATION_REVIEW #17).
  /// 보호자 쪽 해제와 결과가 같다: links 삭제 → 해당 보호자는 과거 알림·승인도 읽을 수 없다.
  void disconnectByElder(String elderId, String guardianId) => disconnect(guardianId, elderId);

  // ======================= 가족의 도전 (💡 제안 단계) =======================

  List<Challenge> challengesFor(String guardianId) => _challenges.values
      .where((c) => _canRead(guardianId, c.elderId, c.guardianIds))
      .toList()
    ..sort((a, b) => b.at.compareTo(a.at));

  Challenge challengeFor(String guardianId, String id) {
    final c = _challenges[id];
    if (c == null) throw const RepositoryException(RepositoryErrorCode.notFound);
    if (!_canRead(guardianId, c.elderId, c.guardianIds)) {
      throw const RepositoryException(RepositoryErrorCode.permissionDenied);
    }
    return c;
  }

  /// 보호자가 도전을 추천한다. 같은 도전이 이미 진행 중이면 새로 만들지 않는다.
  Challenge suggestChallenge(String guardianId, String elderId, String templateId) {
    if (!isLinked(elderId, guardianId)) throw const RepositoryException(RepositoryErrorCode.permissionDenied);
    final template = ChallengeTemplate.byId(templateId);
    if (template == null) throw const RepositoryException(RepositoryErrorCode.invalidArgument, '없는 도전');
    for (final c in _challenges.values) {
      if (c.elderId == elderId && c.templateId == templateId && !c.isDone) {
        throw const RepositoryException(RepositoryErrorCode.invalidArgument, '이미 추천한 도전');
      }
    }
    final c = Challenge(
      id: _newId('challenge'),
      elderId: elderId,
      templateId: templateId,
      title: template.title,
      appName: template.appName,
      suggestedBy: guardianId,
      guardianIds: _guardiansOf(elderId),
      createdAt: now(),
    );
    _challenges[c.id] = c;
    _notify();
    return c;
  }

  /// 고령자 앱 시뮬레이션: 어르신이 도전을 해냈다 (도우미 안내를 받았는지 여부만 전달)
  Challenge? completeChallenge(String id, {bool withHelp = false}) {
    final c = _challenges[id];
    if (c == null || c.isDone) return null;
    final done = c.copyWith(status: ChallengeStatus.done, completedAt: now(), withHelp: withHelp);
    _challenges[id] = done;
    _notify();
    return done;
  }

  /// 해낸 도전에 칭찬 보내기 (보호자마다 한 번)
  void cheerChallenge(String guardianId, String id, String message) {
    final c = challengeFor(guardianId, id);
    if (!c.isDone) throw const RepositoryException(RepositoryErrorCode.invalidArgument, '아직 해내지 않은 도전');
    if (!cheerMessages.contains(message)) throw const RepositoryException(RepositoryErrorCode.invalidArgument);
    _challenges[id] = c.copyWith(cheers: {...c.cheers, guardianId: message});
    _notify();
  }

  // ======================= 고령자 앱 시뮬레이션 =======================

  List<String> _guardiansOf(String elderId) =>
      linksForElder(elderId).map((l) => l.guardianId).toList();

  /// 민감 앱 진입 → 고령자 팝업 선택 결과 처리.
  /// "아니요"/"닫기"는 서버에 아무 요청도 보내지 않은 것과 같다 (문서 미생성).
  (SensitiveEntryOutcome, NotificationItem?) reportSensitiveEntry({
    required String elderId,
    required SensitiveApp app,
    required ConsentChoice choice,
    SensitivityLevel? level = SensitivityLevel.l1,
    SensitivityCategory? category,
    String? reason,
  }) {
    if (choice != ConsentChoice.yes) return (SensitiveEntryOutcome.skippedNoConsent, null);
    final guardians = _guardiansOf(elderId);
    if (guardians.isEmpty) return (SensitiveEntryOutcome.noGuardians, null);
    if (isRecentSensitiveEntry(elderId, app)) return (SensitiveEntryOutcome.duplicateSuppressed, null);
    final n = _addNotification(elderId, guardians, app.appName, app.packageName,
        NotificationType.sensitiveEntry,
        level: level,
        category: category ?? app.sensitivity,
        reason: reason ?? (app.entryReason.isEmpty ? null : app.entryReason));
    return (SensitiveEntryOutcome.created, n);
  }

  /// 같은 고령자·같은 앱의 민감 앱 진입 알림이 [duplicateWindow] 안에 이미 있는지 (중복 방지 기준)
  bool isRecentSensitiveEntry(String elderId, SensitiveApp app) {
    final windowStart = now().subtract(duplicateWindow);
    return _notifications.values.any((n) =>
        n.elderId == elderId &&
        n.type == NotificationType.sensitiveEntry &&
        n.packageName == app.packageName &&
        n.createdAt.isAfter(windowStart));
  }

  /// SOS 알림. [app]은 선택 값: SOS를 누를 때 사용 중이던 앱 (INTEGRATION_REVIEW 수정 제안 1).
  /// 홈 화면 등 앱 밖이면 null → appName·packageName은 빈 문자열.
  /// [category]·[reason]은 L3(사기 의심) 멈춤 후 보낸 SOS일 때의 선택 필드 (v2.2).
  NotificationItem? createSos(String elderId,
      {SensitiveApp? app, SensitivityCategory? category, String? reason}) {
    final guardians = _guardiansOf(elderId);
    if (guardians.isEmpty) return null;
    return _addNotification(
        elderId, guardians, app?.appName ?? '', app?.packageName ?? '', NotificationType.sos,
        level: category == SensitivityCategory.scam ? SensitivityLevel.l3 : null,
        category: category,
        reason: reason);
  }

  NotificationItem? createStuck(String elderId, SensitiveApp app) {
    final guardians = _guardiansOf(elderId);
    if (guardians.isEmpty) return null;
    return _addNotification(elderId, guardians, app.appName, app.packageName, NotificationType.stuck);
  }

  NotificationItem _addNotification(String elderId, List<String> guardians, String appName,
      String packageName, NotificationType type,
      {DateTime? createdAt,
      Map<String, DateTime> readBy = const {},
      SensitivityLevel? level,
      SensitivityCategory? category,
      String? reason}) {
    final n = NotificationItem(
      id: _newId('n'),
      elderId: elderId,
      guardianIds: guardians,
      appName: appName,
      packageName: packageName,
      type: type,
      createdAt: createdAt ?? now(),
      readBy: readBy,
      level: level,
      category: category,
      reason: reason,
    );
    _notifications[n.id] = n;
    _notify();
    return n;
  }

  ApprovalRequest? requestApproval({
    required String elderId,
    required SensitiveApp app,
    String? action,
    SensitivityCategory? category,
  }) {
    final guardians = _guardiansOf(elderId);
    if (guardians.isEmpty) return null;
    final created = now();
    final a = ApprovalRequest(
      id: _newId('a'),
      elderId: elderId,
      guardianIds: guardians,
      appName: app.appName,
      packageName: app.packageName,
      action: action ?? app.defaultAction,
      status: ApprovalStatus.pending,
      createdAt: created,
      expiresAt: created.add(approvalTtl),
      category: category ?? app.sensitivity,
    );
    _approvals[a.id] = a;
    _notify();
    return a;
  }

  /// 고령자가 요청 취소 (pending 상태에서만 가능)
  bool cancelApproval(String approvalId) {
    final a = _approvals[approvalId];
    if (a == null || a.effectiveStatus(now()) != ApprovalStatus.pending) return false;
    final updated = a.copyWith(status: ApprovalStatus.cancelled, respondedAt: now());
    _approvals[a.id] = updated;
    _deliverToElder(updated);
    _notify();
    return true;
  }

  /// 개발자 테스트: 남은 시간과 관계없이 즉시 만료
  bool forceExpire(String approvalId) {
    final a = _approvals[approvalId];
    if (a == null || a.status != ApprovalStatus.pending) return false;
    _approvals[a.id] = a.copyWith(expiresAt: now());
    _expire(_approvals[a.id]!);
    _notify();
    return true;
  }

  /// 만료 시각이 지난 pending 요청을 expired로 변경
  int expireOverdue() {
    var count = 0;
    for (final a in _approvals.values.toList()) {
      if (a.status == ApprovalStatus.pending && !now().isBefore(a.expiresAt)) {
        _expire(a);
        count++;
      }
    }
    if (count > 0) _notify();
    return count;
  }

  void _expire(ApprovalRequest a) {
    if (a.status != ApprovalStatus.pending) return;
    final updated = a.copyWith(status: ApprovalStatus.expired);
    _approvals[a.id] = updated;
    _deliverToElder(updated);
  }

  void _deliverToElder(ApprovalRequest a) {
    _elderInbox.add(ElderDelivery(
      approvalId: a.id,
      elderId: a.elderId,
      status: a.status,
      at: now(),
      respondedBy: a.respondedBy,
    ));
  }

  /// 고령자 앱에서 6자리 일회용 연결 코드 발급 (서버에서 생성).
  /// 같은 고령자의 이전 미사용 코드는 무효화한다(만료 처리, INTEGRATION_REVIEW #17).
  String issueConnectCode(String elderId, {Duration? ttl}) {
    for (final c in _codes.values.toList()) {
      if (c.elderId == elderId && !c.used && now().isBefore(c.expiresAt)) {
        _codes[c.code] = c.expire(now());
      }
    }
    String code;
    do {
      code = (_random.nextInt(900000) + 100000).toString();
    } while (_codes.containsKey(code));
    _codes[code] = ConnectCode(
      code: code,
      elderId: elderId,
      expiresAt: now().add(ttl ?? connectCodeTtl),
    );
    return code;
  }

  /// 개발자 테스트: 이미 만료된 코드 발급
  String issueExpiredConnectCode(String elderId) =>
      issueConnectCode(elderId, ttl: const Duration(minutes: -1));

  ConnectCode? codeInfo(String code) => _codes[code];

  // ======================= 초기화 =======================

  void reset() {
    _links.clear();
    _codes.clear();
    _notifications.clear();
    _approvals.clear();
    _challenges.clear();
    _elderInbox.clear();
    _failedAttempts.clear();
    _lockedUntil.clear();
    users.clear();
    _seed();
    _notify();
  }

  /// 데모용 초기 데이터 (가상의 인물)
  void _seed() {
    final t = now();
    users
      ..[meId] = const MockUser(id: meId, name: '나', role: 'guardian')
      ..[siblingId] = const MockUser(id: siblingId, name: '동생', role: 'guardian')
      ..[momId] = const MockUser(id: momId, name: '김순자', role: 'elder')
      ..[dadId] = const MockUser(id: dadId, name: '이정호', role: 'elder')
      ..[grandmaId] = const MockUser(id: grandmaId, name: '박말순', role: 'elder');

    void link(String elder, String guardian, String rel, String guardianRel, Duration ago) {
      final l = FamilyLink(
        elderId: elder,
        guardianId: guardian,
        elderName: userName(elder),
        elderLabel: rel,
        guardianLabel: guardianRel,
        connectedAt: t.subtract(ago),
      );
      _links[l.id] = l;
    }

    link(momId, meId, '어머니', '딸', const Duration(days: 30));
    link(dadId, meId, '아버지', '딸', const Duration(days: 29));
    link(momId, siblingId, '어머니', '아들', const Duration(days: 20));

    final momG = [meId, siblingId];
    final dadG = [meId];
    _addNotification(dadId, dadG, '카카오뱅크', SensitiveApp.kakaoBank.packageName,
        NotificationType.sensitiveEntry,
        createdAt: t.subtract(const Duration(minutes: 40)),
        level: SensitivityLevel.l1,
        category: SensitivityCategory.finance,
        reason: '은행 앱 열기');
    _addNotification(momId, momG, '정부24', SensitiveApp.gov24.packageName,
        NotificationType.sensitiveEntry,
        createdAt: t.subtract(const Duration(hours: 2)),
        readBy: {meId: t.subtract(const Duration(hours: 1))},
        level: SensitivityLevel.l1,
        category: SensitivityCategory.public,
        reason: '주민등록표 등본 발급');
    _addNotification(momId, momG, '토스', SensitiveApp.toss.packageName, NotificationType.stuck,
        createdAt: t.subtract(const Duration(days: 1, hours: 3)),
        readBy: {meId: t.subtract(const Duration(days: 1)), siblingId: t.subtract(const Duration(days: 1))});
    _addNotification(momId, momG, '토스', SensitiveApp.toss.packageName,
        NotificationType.sensitiveEntry,
        createdAt: t.subtract(const Duration(days: 1, hours: 3, minutes: 5)),
        readBy: {siblingId: t.subtract(const Duration(days: 1))});

    void approval(String elder, List<String> g, SensitiveApp app, ApprovalStatus status,
        Duration ago, {String? by}) {
      final created = t.subtract(ago);
      final a = ApprovalRequest(
        id: _newId('a'),
        elderId: elder,
        guardianIds: g,
        appName: app.appName,
        packageName: app.packageName,
        action: app.defaultAction,
        status: status,
        createdAt: created,
        expiresAt: created.add(approvalTtl),
        respondedAt: status == ApprovalStatus.pending || status == ApprovalStatus.expired
            ? null
            : created.add(const Duration(minutes: 1)),
        respondedBy: by,
      );
      _approvals[a.id] = a;
    }

    approval(momId, momG, SensitiveApp.gov24, ApprovalStatus.pending, const Duration(seconds: 30));
    approval(dadId, dadG, SensitiveApp.bank, ApprovalStatus.approved, const Duration(days: 1),
        by: meId);
    approval(momId, momG, SensitiveApp.toss, ApprovalStatus.rejected,
        const Duration(days: 2), by: siblingId);
    approval(dadId, dadG, SensitiveApp.kakaoBank, ApprovalStatus.expired,
        const Duration(days: 3));
    approval(momId, momG, SensitiveApp.kakaoBank, ApprovalStatus.cancelled,
        const Duration(days: 4));

    // 가족의 도전: 어머니는 등본 떼기를 해냄(동생이 이미 칭찬), 아버지는 사진 보내기 도전 중
    void challenge(String elder, List<String> g, String templateId, Duration ago,
        {Duration? doneAgo, bool withHelp = false, Map<String, String> cheers = const {}}) {
      final tpl = ChallengeTemplate.byId(templateId)!;
      final c = Challenge(
        id: _newId('challenge'),
        elderId: elder,
        templateId: templateId,
        title: tpl.title,
        appName: tpl.appName,
        suggestedBy: g.first,
        guardianIds: g,
        createdAt: t.subtract(ago),
        status: doneAgo == null ? ChallengeStatus.open : ChallengeStatus.done,
        completedAt: doneAgo == null ? null : t.subtract(doneAgo),
        withHelp: withHelp,
        cheers: cheers,
      );
      _challenges[c.id] = c;
    }

    challenge(momId, momG, 'gov24_resident', const Duration(days: 2),
        doneAgo: const Duration(minutes: 90), withHelp: true, cheers: {siblingId: cheerMessages.first});
    challenge(dadId, dadG, 'kakao_photo', const Duration(days: 1));
  }
}
