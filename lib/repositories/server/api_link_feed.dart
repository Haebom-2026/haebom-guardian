import 'dart:async';

import '../../models/family_link.dart';
import '../guardian_repository.dart';

/// 서버 #20(`GET /v1/guardian/links`)으로 받은 가족 목록. 연결 시각 순.
///
/// 다시 조회하는 때 (S1 계약서 5장): 처음 구독, FCM `kind: link`, 앱 복귀·주기 조회, 이 앱에서 연결·해제한 직후.
class ApiLinkFeed extends ApiFeed<FamilyLink> {
  ApiLinkFeed(super.fetch)
      : super(compare: (a, b) => a.connectedAt.compareTo(b.connectedAt));
}

/// 서버 조회 결과를 화면에 흘려보내는 목록 (서버는 실시간 구독이 없으므로 [refresh]로 다시 조회).
///
/// 동시에 여러 번 불려도 요청은 하나만 보내고, 그동안 또 불리면 끝난 뒤 한 번 더 조회한다.
class ApiFeed<T> {
  ApiFeed(this._fetch, {this.compare});

  final Future<List<T>> Function() _fetch;
  final int Function(T a, T b)? compare;
  final _controller = StreamController<List<T>>.broadcast();
  List<T>? _latest;
  Future<void>? _inFlight;
  bool _again = false;

  /// 마지막으로 받은 목록 (아직 없으면 null)
  List<T>? get latest => _latest;

  /// 구독하면 마지막 목록을 먼저 받고, 아직 없으면 조회를 시작한다.
  Stream<List<T>> get stream {
    late StreamController<List<T>> c;
    StreamSubscription<List<T>>? sub;
    c = StreamController<List<T>>(
      onListen: () {
        sub = _controller.stream.listen(c.add, onError: c.addError);
        final last = _latest;
        if (last != null) {
          c.add(last);
        } else {
          unawaited(refresh());
        }
      },
      onCancel: () => sub?.cancel(),
    );
    return c.stream;
  }

  /// 서버에서 다시 조회한다. 실패하면 구독자에게 오류를 보내고(화면 안내), 예외는 밖으로 던지지 않는다.
  Future<void> refresh() {
    if (_inFlight != null) {
      _again = true;
      return _inFlight!;
    }
    return _inFlight = () async {
      try {
        do {
          _again = false;
          try {
            final list = List.of(await _fetch());
            if (compare != null) list.sort(compare);
            _latest = List.unmodifiable(list);
            if (!_controller.isClosed) _controller.add(_latest!);
          } catch (e) {
            if (!_controller.isClosed) {
              _controller.addError(e is RepositoryException ? e : RepositoryException(RepositoryErrorCode.unavailable, '$e'));
            }
          }
        } while (_again);
      } finally {
        _inFlight = null;
      }
    }();
  }

  /// 서버에 다시 묻지 않고 지금 목록만 고친다 (예: 읽음 처리 직후 화면에 바로 반영)
  void patch(List<T> Function(List<T> current) update) {
    final cur = _latest;
    if (cur == null) return;
    _latest = List.unmodifiable(update(List.of(cur)));
    if (!_controller.isClosed) _controller.add(_latest!);
  }

  Future<void> dispose() => _controller.close();
}
