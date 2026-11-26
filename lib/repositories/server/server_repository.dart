import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../models/approval_request.dart';
import '../../models/family_link.dart';
import '../../models/notification_item.dart';
import '../../models/sensitivity.dart';
import '../guardian_repository.dart';
import 'api_link_feed.dart';
import 'guardian_server_api.dart';
import 'resilient_stream.dart';

/// 실제 서버용 보호자 저장소. 두 가지 방식으로 만들 수 있다.
///
/// **서버 API 방식** ([ServerGuardianRepository.api] 생성자, 실제 운영 — AWS 서버):
/// - 가족 목록: 서버 #20 조회 ([ApiLinkFeed]). FCM `kind: link`·앱 복귀·주기 조회로 갱신
/// - 연결·해제·기기 등록: 서버 API
/// - 알림·승인: 서버 S2·S3 API가 아직 없어 빈 목록 (API가 나오면 이곳에 연결)
///
/// **Firestore 방식** (기본 생성자, 로컬 Firebase 에뮬레이터 검증용):
/// - **읽기**: Firestore 실시간 구독 (links → 연결된 가족별 notifications / approvals)
/// - **확인(readBy)**: Firestore에 자기 항목만 직접 쓰기 (보안 규칙으로 제한)
/// - **쓰기(승인·연결·해제)**: 공통 서버 API ([GuardianServerApi])
///
/// 알림·승인 조회를 가족(elderId)별로 나눈 이유: 보안 규칙이 "links가 살아 있는 보호자만 읽기"를
/// 검사하므로, 쿼리에 elderId가 고정되어 있어야 규칙이 쿼리를 허용할 수 있다.
/// 연결이 해제되면 해당 가족의 구독도 바로 끊는다.
///
/// 모든 실시간 구독은 [resilientStream]으로 감싼다. 오류(권한 거부·네트워크 등)로 구독이 끊기면
/// 오류를 화면에 알린 뒤 잠시 기다렸다가 같은 쿼리를 다시 구독한다 (앱 재실행 불필요).
class ServerGuardianRepository implements GuardianRepository {
  ServerGuardianRepository({
    required FirebaseFirestore this.firestore,
    required this.guardianId,
    required this.api,
    DateTime Function()? clock,
    this.reconnectDelay = defaultReconnectDelay,
    @visibleForTesting Stream<QuerySnapshot<Map<String, dynamic>>> Function(Query<Map<String, dynamic>> q)? snapshots,
  })  : _clock = clock ?? DateTime.now,
        _snapshots = snapshots ?? ((q) => q.snapshots()),
        linkFeed = null;

  /// 서버 API 방식 (Firestore를 쓰지 않음)
  ServerGuardianRepository.api({
    required this.guardianId,
    required this.api,
    required ApiLinkFeed this.linkFeed,
    DateTime Function()? clock,
  })  : firestore = null,
        _clock = clock ?? DateTime.now,
        reconnectDelay = defaultReconnectDelay,
        _snapshots = ((q) => q.snapshots());

  /// Firestore 방식에서만 사용 (서버 API 방식이면 null)
  final FirebaseFirestore? firestore;

  /// 서버 API 방식의 가족 목록 (Firestore 방식이면 null)
  final ApiLinkFeed? linkFeed;

  bool get _apiMode => linkFeed != null;
  final String guardianId;
  final GuardianServerApi api;
  final DateTime Function() _clock;

  /// 구독 오류 뒤 다시 구독할 때까지 기다리는 시간 (n번째 연속 실패)
  final Duration Function(int attempt) reconnectDelay;
  final Stream<QuerySnapshot<Map<String, dynamic>>> Function(Query<Map<String, dynamic>> q) _snapshots;

  /// 끊기면 자동으로 다시 구독하는 실시간 쿼리
  Stream<QuerySnapshot<Map<String, dynamic>>> _live(Query<Map<String, dynamic>> q) =>
      resilientStream(() => _snapshots(q), delay: reconnectDelay);

  @override
  String get currentGuardianId => guardianId;

  @override
  DateTime now() => _clock();

  CollectionReference<Map<String, dynamic>> get _links => firestore!.collection('links');
  CollectionReference<Map<String, dynamic>> get _notifications => firestore!.collection('notifications');
  CollectionReference<Map<String, dynamic>> get _approvals => firestore!.collection('approvals');

  Query<Map<String, dynamic>> _myLinks() => _links.where('guardianId', isEqualTo: guardianId);

  @override
  Stream<List<FamilyLink>> watchLinks() {
    if (_apiMode) {
      // #20 응답에는 guardianId가 없다 (본인 목록이므로 나)
      return linkFeed!.stream.map((list) => [
            for (final l in list)
              FamilyLink(
                elderId: l.elderId,
                guardianId: guardianId,
                elderName: l.elderName,
                elderLabel: l.elderLabel,
                guardianLabel: l.guardianLabel,
                connectedAt: l.connectedAt,
              ),
          ]);
    }
    return _firestoreLinks();
  }

  Stream<List<FamilyLink>> _firestoreLinks() => _live(_myLinks()).map((s) {
        final list = s.docs.map((d) => FirestoreMappers.link(d.data())).toList()
          ..sort((a, b) => a.connectedAt.compareTo(b.connectedAt));
        return list;
      }).handleError(_rethrowMapped);

  /// 서버 API 방식: 알림·승인 조회 API(S2·S3)가 아직 없어 빈 목록
  @override
  Stream<List<NotificationItem>> watchNotifications() => _apiMode ? Stream.value(const []) : _perElder(
        _notifications,
        (id, data) => FirestoreMappers.notification(id, data, _clock),
        (a, b) => b.createdAt.compareTo(a.createdAt),
      );

  @override
  Stream<List<ApprovalRequest>> watchApprovals() => _apiMode ? Stream.value(const []) : _perElder(
        _approvals,
        (id, data) => FirestoreMappers.approval(id, data, _clock),
        (a, b) => b.createdAt.compareTo(a.createdAt),
      );

  /// 연결된 가족마다 `elderId == X && guardianIds array-contains 나` 쿼리를 구독해 하나의 목록으로 합친다.
  Stream<List<T>> _perElder<T>(
    CollectionReference<Map<String, dynamic>> col,
    T Function(String id, Map<String, dynamic> data) parse,
    int Function(T a, T b) compare,
  ) {
    late StreamController<List<T>> controller;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? linksSub;
    final subs = <String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>{};
    final byElder = <String, List<T>>{};
    var linksReady = false;

    void emit() {
      if (!linksReady || controller.isClosed) return;
      // 모든 가족의 첫 결과가 도착하기 전에는 빈 목록을 섞어 보내지 않는다.
      if (subs.keys.any((e) => !byElder.containsKey(e))) return;
      controller.add(byElder.values.expand((l) => l).toList()..sort(compare));
    }

    void onLinks(QuerySnapshot<Map<String, dynamic>> snap) {
      final elders = snap.docs.map((d) => d.data()['elderId'] as String? ?? '').where((e) => e.isNotEmpty).toSet();
      for (final removed in subs.keys.where((e) => !elders.contains(e)).toList()) {
        subs.remove(removed)?.cancel();
        byElder.remove(removed);
      }
      for (final elderId in elders.where((e) => !subs.containsKey(e))) {
        subs[elderId] = _live(col
                .where('elderId', isEqualTo: elderId)
                .where('guardianIds', arrayContains: guardianId))
            .listen((s) {
          byElder[elderId] = s.docs.map((d) => parse(d.id, d.data())).toList();
          emit();
        }, onError: (Object e) {
          // 한 가족의 쿼리가 실패해도 나머지 가족 목록은 계속 보여 준다 (그 가족은 잠시 뒤 자동 재구독)
          byElder[elderId] = const [];
          controller.addError(mapFirestoreError(e));
          emit();
        });
      }
      linksReady = true;
      emit();
    }

    controller = StreamController<List<T>>(
      onListen: () {
        linksSub = _live(_myLinks()).listen(onLinks, onError: (Object e) => controller.addError(mapFirestoreError(e)));
      },
      onCancel: () async {
        await linksSub?.cancel();
        for (final s in subs.values) {
          await s.cancel();
        }
        subs.clear();
      },
    );
    return controller.stream;
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _get(DocumentReference<Map<String, dynamic>> ref) async {
    try {
      return await ref.get();
    } catch (e) {
      throw mapFirestoreError(e);
    }
  }

  void _checkVisible(String elderId, List<String> guardianIds) {
    if (!guardianIds.contains(guardianId)) throw const RepositoryException(RepositoryErrorCode.permissionDenied);
  }

  @override
  Future<NotificationItem> getNotification(String id) async {
    if (_apiMode) throw const RepositoryException(RepositoryErrorCode.notFound, '알림 조회 API(S2) 준비 중');
    final doc = await _get(_notifications.doc(id));
    final data = doc.data();
    if (!doc.exists || data == null) throw const RepositoryException(RepositoryErrorCode.notFound);
    final n = FirestoreMappers.notification(doc.id, data, _clock);
    _checkVisible(n.elderId, n.guardianIds);
    return n;
  }

  @override
  Future<ApprovalRequest> getApproval(String id) async {
    if (_apiMode) throw const RepositoryException(RepositoryErrorCode.notFound, '승인 조회 API(S3) 준비 중');
    final doc = await _get(_approvals.doc(id));
    final data = doc.data();
    if (!doc.exists || data == null) throw const RepositoryException(RepositoryErrorCode.notFound);
    final a = FirestoreMappers.approval(doc.id, data, _clock);
    _checkVisible(a.elderId, a.guardianIds);
    return a;
  }

  /// "확인했어요": 자기 readBy 항목만 쓴다. 이미 확인한 알림은 다시 쓰지 않는다(처음 확인 시각 유지).
  @override
  Future<void> markNotificationRead(String id) async {
    if (_apiMode) throw const RepositoryException(RepositoryErrorCode.unavailable, '알림 확인 API(S2) 준비 중');
    final n = await getNotification(id);
    if (n.isReadBy(guardianId)) return;
    try {
      await _notifications.doc(id).update({'readBy.$guardianId': FieldValue.serverTimestamp()});
    } catch (e) {
      throw mapFirestoreError(e);
    }
  }

  @override
  Future<void> markAllNotificationsRead({String? elderId}) async {
    if (_apiMode) return; // 서버 API 방식에는 아직 알림이 없다
    try {
      final links = await _myLinks().get();
      final elders = links.docs
          .map((d) => d.data()['elderId'] as String? ?? '')
          .where((e) => e.isNotEmpty && (elderId == null || e == elderId));
      final refs = <DocumentReference<Map<String, dynamic>>>[];
      for (final e in elders) {
        final snap =
            await _notifications.where('elderId', isEqualTo: e).where('guardianIds', arrayContains: guardianId).get();
        for (final d in snap.docs) {
          final readBy = d.data()['readBy'];
          if (readBy is! Map || !readBy.containsKey(guardianId)) refs.add(d.reference);
        }
      }
      // Firestore 일괄 쓰기는 500건 제한
      for (var i = 0; i < refs.length; i += 450) {
        final batch = firestore!.batch();
        for (final r in refs.skip(i).take(450)) {
          batch.update(r, {'readBy.$guardianId': FieldValue.serverTimestamp()});
        }
        await batch.commit();
      }
    } catch (e) {
      throw mapFirestoreError(e);
    }
  }

  @override
  Future<ApprovalRequest> respondToApproval(String id, {required bool approve}) async {
    await api.respondApproval(id, approve: approve);
    return getApproval(id);
  }

  @override
  Future<FamilyLink> connectWithCode(String code, {required String elderLabel, String guardianLabel = ''}) async {
    final link = await api.connectWithCode(code, elderLabel: elderLabel, guardianLabel: guardianLabel);
    unawaited(linkFeed?.refresh());
    return FamilyLink(
      elderId: link.elderId,
      guardianId: guardianId,
      elderName: link.elderName,
      elderLabel: link.elderLabel,
      guardianLabel: link.guardianLabel,
      connectedAt: link.connectedAt,
    );
  }

  @override
  Future<void> disconnect(String elderId) async {
    await api.disconnect(elderId);
    await linkFeed?.refresh();
  }

  static Never _rethrowMapped(Object e) => throw mapFirestoreError(e);
}

/// Firestore 예외 → 보호자 앱 오류 코드
RepositoryException mapFirestoreError(Object e) {
  if (e is RepositoryException) return e;
  if (e is FirebaseException) {
    return RepositoryException(
      switch (e.code) {
        'permission-denied' => RepositoryErrorCode.permissionDenied,
        'not-found' => RepositoryErrorCode.notFound,
        'unauthenticated' => RepositoryErrorCode.permissionDenied,
        'invalid-argument' => RepositoryErrorCode.invalidArgument,
        _ => RepositoryErrorCode.unavailable,
      },
      e.code,
    );
  }
  return RepositoryException(RepositoryErrorCode.unavailable, '$e');
}

/// Firestore 문서 → 보호자 앱 모델. 필드는 `docs/GUARDIAN_INTEGRATION.md` 3장과 같다.
class FirestoreMappers {
  static DateTime _time(Object? v, DateTime Function() fallback) => switch (v) {
        Timestamp t => t.toDate(),
        DateTime d => d,
        String s => DateTime.tryParse(s)?.toLocal() ?? fallback(),
        // 서버 타임스탬프가 아직 확정되지 않은 로컬 쓰기
        _ => fallback(),
      };

  static List<String> _strings(Object? v) => v is List ? v.whereType<String>().toList() : const [];

  static FamilyLink link(Map<String, dynamic> d) => FamilyLink(
        elderId: d['elderId'] as String? ?? '',
        guardianId: d['guardianId'] as String? ?? '',
        elderName: d['elderName'] as String? ?? '',
        // v2.2 전 문서는 relationship 하나뿐 → 보호자가 정한 어르신 호칭으로 읽는다
        elderLabel: d['elderLabel'] as String? ?? d['relationship'] as String? ?? '',
        guardianLabel: d['guardianLabel'] as String? ?? '',
        connectedAt: _time(d['connectedAt'], DateTime.now),
      );

  static NotificationItem notification(String id, Map<String, dynamic> d, DateTime Function() now) {
    final readBy = <String, DateTime>{};
    final raw = d['readBy'];
    if (raw is Map) {
      raw.forEach((k, v) {
        if (k is String) readBy[k] = _time(v, now);
      });
    }
    return NotificationItem(
      id: id,
      elderId: d['elderId'] as String? ?? '',
      guardianIds: _strings(d['guardianIds']),
      appName: d['appName'] as String? ?? '',
      packageName: d['packageName'] as String? ?? '',
      type: NotificationType.fromCode(d['type'] as String? ?? ''),
      createdAt: _time(d['createdAt'], now),
      readBy: readBy,
      level: SensitivityLevel.fromCode(d['level']),
      category: SensitivityCategory.fromCode(d['category']),
      reason: d['reason'] is String ? d['reason'] as String : null,
    );
  }

  static ApprovalRequest approval(String id, Map<String, dynamic> d, DateTime Function() now) {
    final created = _time(d['createdAt'], now);
    return ApprovalRequest(
      id: id,
      elderId: d['elderId'] as String? ?? '',
      guardianIds: _strings(d['guardianIds']),
      appName: d['appName'] as String? ?? '',
      packageName: d['packageName'] as String? ?? '',
      action: d['action'] as String? ?? '',
      status: ApprovalStatus.fromCode(d['status'] as String? ?? 'pending'),
      createdAt: created,
      // expiresAt이 없으면 규격 기본값(생성 + 5분)으로 본다
      expiresAt: d['expiresAt'] == null ? created.add(const Duration(minutes: 5)) : _time(d['expiresAt'], now),
      respondedAt: d['respondedAt'] == null ? null : _time(d['respondedAt'], now),
      respondedBy: d['respondedBy'] as String?,
      category: SensitivityCategory.fromCode(d['category']),
    );
  }
}
