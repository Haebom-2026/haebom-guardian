import 'dart:async';

import '../../models/family_link.dart';
import '../guardian_repository.dart';

/// 서버 #20(`GET /v1/guardian/links`)으로 받은 가족 목록을 화면에 흘려보낸다.
///
/// 서버는 실시간 구독이 없으므로 다음 때마다 [refresh]로 다시 조회한다 (S1 계약서 5장):
/// - 처음 구독할 때
/// - FCM `kind: link` 메시지를 받았을 때 (연결 생성·해제)
/// - 앱이 다시 앞으로 왔을 때, 앱이 켜져 있는 동안 주기적으로 (FCM은 빠질 수 있고, iPhone은 FCM이 없음)
/// - 이 앱에서 연결·해제한 직후
///
/// 동시에 여러 번 불려도 요청은 하나만 보내고, 그동안 또 불리면 끝난 뒤 한 번 더 조회한다.
class ApiLinkFeed {
  ApiLinkFeed(this._fetch);

  final Future<List<FamilyLink>> Function() _fetch;
  final _controller = StreamController<List<FamilyLink>>.broadcast();
  List<FamilyLink>? _latest;
  Future<void>? _inFlight;
  bool _again = false;

  /// 마지막으로 받은 목록 (아직 없으면 null)
  List<FamilyLink>? get latest => _latest;

  /// 구독하면 마지막 목록을 먼저 받고, 아직 없으면 조회를 시작한다.
  Stream<List<FamilyLink>> get stream {
    late StreamController<List<FamilyLink>> c;
    StreamSubscription<List<FamilyLink>>? sub;
    c = StreamController<List<FamilyLink>>(
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
            final list = await _fetch()
              ..sort((a, b) => a.connectedAt.compareTo(b.connectedAt));
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

  Future<void> dispose() => _controller.close();
}
