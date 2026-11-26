import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

/// 프로필 등록 재시도 간격: 15, 30, 60, 120, 300, 300 … 초
Duration defaultProfileRetryDelay(int attempt) => Duration(seconds: min(300, 15 * (1 << min(attempt, 5))));

/// 보호자 프로필(`POST /v1/users/me`) 등록을 성공할 때까지 다시 시도한다.
///
/// 서버가 꺼져 있을 때 앱을 켜도, 서버가 켜지면 앱을 다시 실행하지 않아도 등록된다.
/// - 실패하면 [delay] 뒤에 다시 시도한다 (점점 길게, 최대 5분).
/// - [retryNow]: 앱이 다시 화면 앞으로 왔을 때 기다리지 않고 바로 시도한다.
/// - 성공하면 [onRegistered]를 한 번 부른다 (예: 실패했던 FCM 토큰 등록 다시 시도).
class ProfileRegistrar {
  ProfileRegistrar({
    required this.register,
    this.onRegistered,
    this.delay = defaultProfileRetryDelay,
  });

  final Future<void> Function() register;
  final FutureOr<void> Function()? onRegistered;
  final Duration Function(int attempt) delay;

  bool get isRegistered => _registered;
  bool _registered = false;
  bool _disposed = false;
  int _attempt = 0;
  Timer? _timer;
  Future<bool>? _inFlight;

  /// 등록을 시도한다. 이미 성공했으면 바로 true. 동시에 여러 번 불려도 요청은 하나.
  Future<bool> start() => _inFlight ??= _try().whenComplete(() => _inFlight = null);

  /// 예약된 재시도를 기다리지 않고 지금 시도한다.
  Future<bool> retryNow() {
    if (_registered || _disposed) return Future.value(_registered);
    _timer?.cancel();
    return start();
  }

  Future<bool> _try() async {
    if (_registered || _disposed) return _registered;
    try {
      await register();
    } catch (e) {
      debugPrint('보호자 프로필 등록 실패, 다시 시도 예정 (서버 확인 필요): $e');
      if (!_disposed) {
        _timer?.cancel();
        _timer = Timer(delay(_attempt++), () => unawaited(start()));
      }
      return false;
    }
    _registered = true;
    _timer?.cancel();
    try {
      await onRegistered?.call();
    } catch (e) {
      debugPrint('프로필 등록 후 작업 실패: $e');
    }
    return true;
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }
}
