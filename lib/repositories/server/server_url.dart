import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

/// 공통 서버 주소를 알려 준다.
///
/// - 빌드 값(`SERVER_BASE_URL`)이 있으면 그것을 쓴다.
/// - 없으면 Firestore 문서(기본 `config/server`)의 `baseUrl` 필드를 구독한다.
///   서버 주소가 바뀌어도(예: Cloudflare Quick Tunnel 재시작) 앱을 다시 빌드할 필요가 없다.
///   💡 문서 경로·필드 이름은 서버 담당자와 합의 필요.
class ServerUrlResolver {
  ServerUrlResolver({required this.fixedUrl, required this.firestore, required this.configDoc});

  final String fixedUrl;
  final FirebaseFirestore firestore;
  final String configDoc;

  String? _latest;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  Completer<void>? _first;

  void start() {
    if (fixedUrl.isNotEmpty || _sub != null) return;
    _first = Completer<void>();
    _sub = firestore.doc(configDoc).snapshots().listen((s) {
      final v = s.data()?['baseUrl'];
      _latest = v is String && v.isNotEmpty ? v : null;
      if (!(_first?.isCompleted ?? true)) _first!.complete();
    }, onError: (Object _) {
      if (!(_first?.isCompleted ?? true)) _first!.complete();
    });
  }

  /// 현재 주소. 첫 값이 오기 전이면 최대 3초 기다린다. 모르면 null.
  Future<String?> current() async {
    if (fixedUrl.isNotEmpty) return fixedUrl;
    start();
    final first = _first;
    if (first != null && !first.isCompleted) {
      await first.future.timeout(const Duration(seconds: 3), onTimeout: () {});
    }
    return _latest;
  }

  Future<void> dispose() async => _sub?.cancel();
}
