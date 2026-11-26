import 'dart:async';
import 'dart:math';

/// 재연결 대기 시간: 1, 2, 4, 8, 16, 30, 30 … 초
Duration defaultReconnectDelay(int attempt) => Duration(seconds: min(30, 1 << min(attempt, 5)));

/// 오류가 나면 잠시 뒤 [open]으로 다시 구독하는 스트림.
///
/// Firestore 실시간 구독(`snapshots()`)은 오류(권한 거부·서버 오류 등)가 한 번 나면 끝나고 다시 오지 않는다.
/// 이 함수로 감싸면 오류는 구독자에게 그대로 전달하면서, [delay] 뒤에 같은 쿼리를 다시 구독한다.
/// 데이터가 한 번이라도 다시 오면 대기 시간은 처음(1초)부터 센다.
/// 구독을 취소하면 대기 중인 재연결도 취소된다.
Stream<T> resilientStream<T>(
  Stream<T> Function() open, {
  Duration Function(int attempt) delay = defaultReconnectDelay,
}) {
  late StreamController<T> controller;
  StreamSubscription<T>? sub;
  Timer? timer;
  var attempt = 0;
  var cancelled = false;

  void connect() {
    if (cancelled) return;
    sub = open().listen(
      (v) {
        attempt = 0;
        controller.add(v);
      },
      onError: (Object e, StackTrace st) {
        controller.addError(e, st);
        final failed = sub;
        sub = null;
        unawaited(failed?.cancel());
        if (cancelled) return;
        timer = Timer(delay(attempt++), connect);
      },
      onDone: () {
        // 오류 없이 끝난 경우(정상 종료)만 닫는다. 오류 뒤의 종료는 재연결이 처리한다.
        if (sub != null && !cancelled) controller.close();
      },
    );
  }

  controller = StreamController<T>(
    onListen: connect,
    onPause: () => sub?.pause(),
    onResume: () => sub?.resume(),
    onCancel: () async {
      cancelled = true;
      timer?.cancel();
      await sub?.cancel();
    },
  );
  return controller.stream;
}
