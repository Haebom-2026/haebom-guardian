import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/approval_request.dart';
import '../models/family_link.dart';
import '../models/notification_item.dart';
import '../repositories/guardian_repository.dart';

/// 저장소의 실시간 스트림을 구독해 화면에 필요한 상태를 제공한다.
///
/// - UI는 [ListenableBuilder]로 이 객체를 구독한다.
/// - 쓰기 작업은 저장소에 위임하고, 결과는 스트림을 통해 다시 반영된다.
class GuardianStore extends ChangeNotifier {
  GuardianStore(this.repository) {
    _subs = [
      repository.watchLinks().listen((v) {
        links = v;
        _errors.remove(_Feed.links); // 자동 재연결로 다시 받으면 이 구독의 이전 오류는 지운다
        _linksLoaded = true;
        _fixSelection();
        notifyListeners();
      }, onError: (Object e) => _onError(_Feed.links, e)),
      repository.watchNotifications().listen((v) {
        notifications = v;
        _errors.remove(_Feed.notifications);
        _notificationsLoaded = true;
        notifyListeners();
      }, onError: (Object e) => _onError(_Feed.notifications, e)),
      repository.watchApprovals().listen((v) {
        approvals = v;
        _errors.remove(_Feed.approvals);
        _approvalsLoaded = true;
        notifyListeners();
      }, onError: (Object e) => _onError(_Feed.approvals, e)),
    ];
  }

  final GuardianRepository repository;
  late final List<StreamSubscription<Object?>> _subs;

  List<FamilyLink> links = const [];
  List<NotificationItem> notifications = const [];
  List<ApprovalRequest> approvals = const [];
  /// 구독별 마지막 오류. 그 구독이 다시 데이터를 받으면 지운다 (다른 구독의 데이터로는 지우지 않는다).
  final Map<_Feed, Object> _errors = {};
  Object? get lastError => _errors.isEmpty ? null : _errors.values.last;

  bool _linksLoaded = false;
  bool _notificationsLoaded = false;
  bool _approvalsLoaded = false;
  bool get isLoaded => _linksLoaded && _notificationsLoaded && _approvalsLoaded;

  /// 선택된 가족 (null = 전체)
  String? _selectedElderId;
  String? get selectedElderId => _selectedElderId;
  void selectElder(String? elderId) {
    if (_selectedElderId == elderId) return;
    _selectedElderId = elderId;
    notifyListeners();
  }

  void _fixSelection() {
    if (_selectedElderId != null && !links.any((l) => l.elderId == _selectedElderId)) {
      _selectedElderId = null;
    }
  }

  void _onError(_Feed feed, Object e) {
    _errors[feed] = e;
    notifyListeners();
  }

  /// 화면을 당겨 새로고침: 서버에서 다시 조회 (결과는 스트림으로 반영)
  Future<void> refresh() => repository.refresh();

  String get guardianId => repository.currentGuardianId;
  DateTime now() => repository.now();

  FamilyLink? linkFor(String elderId) {
    for (final l in links) {
      if (l.elderId == elderId) return l;
    }
    return null;
  }

  /// 호칭 (연결 해제된 가족이면 '가족')
  String nameOf(String elderId) => linkFor(elderId)?.displayName ?? '가족';

  bool _matches(String elderId, String? filter) => filter == null || elderId == filter;

  bool isUnread(NotificationItem n) => !n.isReadBy(guardianId);

  List<NotificationItem> notificationsFor({String? elderId, bool unreadOnly = false}) =>
      notifications
          .where((n) => _matches(n.elderId, elderId) && (!unreadOnly || isUnread(n)))
          .toList();

  List<ApprovalRequest> approvalsFor({String? elderId, ApprovalStatus? status}) {
    final t = now();
    return approvals
        .where((a) =>
            _matches(a.elderId, elderId) && (status == null || a.effectiveStatus(t) == status))
        .toList();
  }

  int unreadCount({String? elderId}) => notificationsFor(elderId: elderId, unreadOnly: true).length;

  int todayCount({String? elderId}) {
    final t = now();
    return notificationsFor(elderId: elderId)
        .where((n) => n.createdAt.year == t.year && n.createdAt.month == t.month && n.createdAt.day == t.day)
        .length;
  }

  int pendingCount({String? elderId}) =>
      approvalsFor(elderId: elderId, status: ApprovalStatus.pending).length;

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}

enum _Feed { links, notifications, approvals }
