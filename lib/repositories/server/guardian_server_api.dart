import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../../models/family_link.dart';
import '../guardian_repository.dart';

/// 공통 서버(다른 팀원 담당)에 보내는 쓰기 요청.
///
/// 읽기는 Firestore 실시간 구독으로 하므로 여기에 없다.
/// 서버 규격이 확정되지 않았으므로(`docs/SERVER_REQUIREMENTS.md`) 경로·형식은 [ServerEndpoints] 한곳에 모았다.
abstract class GuardianServerApi {
  /// 보호자 프로필(users/{uid}, role=guardian)을 서버가 만들게 한다. 이미 있으면 그대로 둔다.
  Future<void> ensureGuardianProfile({String? name});

  /// 승인/거절. 서버 트랜잭션에서 최초의 유효한 응답만 반영된다.
  Future<void> respondApproval(String approvalId, {required bool approve});

  /// 6자리 코드로 가족 연결
  Future<FamilyLink> connectWithCode(String code, {required String elderLabel, String guardianLabel = ''});

  /// 보호자 쪽 연결 해제
  Future<void> disconnect(String elderId);

  /// FCM 토큰 등록·갱신 (기기마다 1개)
  Future<void> registerDevice({required String deviceId, required String fcmToken, required String platform});

  /// 로그아웃 등으로 이 기기의 푸시를 끊을 때
  Future<void> unregisterDevice(String deviceId);
}

/// 서버 엔드포인트 정의. 💡 v2 초안(`docs/GUARDIAN_INTEGRATION.md` 4장) 기준이며, 서버 담당자 규격에 맞춰 이곳만 고친다.
class ServerEndpoints {
  const ServerEndpoints({this.prefix = '/v1'});
  final String prefix;

  String profile() => '$prefix/users/me';
  String respondApproval(String id) => '$prefix/guardian/approvals/${Uri.encodeComponent(id)}/respond';
  String links() => '$prefix/guardian/links';
  String link(String elderId) => '$prefix/guardian/links/${Uri.encodeComponent(elderId)}';
  String device(String deviceId) => '$prefix/devices/${Uri.encodeComponent(deviceId)}';
}

/// 서버 오류 reason → 보호자 앱 오류 코드.
/// 기존 12개는 같은 이름, v2 💡 신규 4개는 가장 가까운 기존 코드로 보여 준다.
RepositoryErrorCode errorCodeForReason(String? reason) {
  for (final c in RepositoryErrorCode.values) {
    if (c.wire == reason) return c;
  }
  return switch (reason) {
    'unauthenticated' || 'profile-required' || 'role-locked' => RepositoryErrorCode.permissionDenied,
    'rate-limited' => RepositoryErrorCode.tooManyAttempts,
    _ => RepositoryErrorCode.unavailable,
  };
}

/// HTTPS REST 구현. 모든 요청에 Firebase ID 토큰을 Bearer로 붙인다.
///
/// 재시도 (공통 규격 5.1, 요청마다 한 번씩만):
/// - `401` → ID 토큰을 새로 받아 다시 보낸다.
/// - `403 profile-required` → 보호자 프로필(#2)을 등록한 뒤 다시 보낸다.
/// 다시 보낼 때도 같은 Idempotency-Key를 쓴다.
class HttpGuardianServerApi implements GuardianServerApi {
  HttpGuardianServerApi({
    required this.baseUrl,
    required this.idToken,
    this.refreshIdToken,
    http.Client? client,
    this.endpoints = const ServerEndpoints(),
    this.timeout = const Duration(seconds: 10),
    String Function()? newIdempotencyKey,
  })  : _client = client ?? http.Client(),
        _newKey = newIdempotencyKey ?? _randomKey;

  /// 현재 서버 주소. 주소가 바뀔 수 있어(터널) 요청할 때마다 읽는다. null이면 `unavailable`.
  final Future<String?> Function() baseUrl;

  /// Firebase Auth ID 토큰 (SDK가 만료 전에 자동 갱신)
  final Future<String?> Function() idToken;

  /// 강제로 새로 받은 ID 토큰 (401 뒤 재시도용). 없으면 [idToken]을 다시 부른다.
  final Future<String?> Function()? refreshIdToken;

  final http.Client _client;
  final ServerEndpoints endpoints;
  final Duration timeout;
  final String Function() _newKey;

  static final _rng = Random.secure();

  /// 이번 실행에서 보호자 프로필 등록(#2)이 성공했는지
  bool get profileReady => _profileReady;
  bool _profileReady = false;
  Future<void>? _profileInFlight;
  String? _profileName;

  /// UUID v4 (재시도할 때 같은 요청임을 서버가 알아보게 하는 키)
  static String _randomKey() {
    final b = List<int>.generate(16, (_) => _rng.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  Future<Map<String, Object?>> _send(
    String method,
    String path, {
    Map<String, Object?>? body,
    bool idempotent = false,
  }) async {
    final key = idempotent ? _newKey() : null;
    var refreshedToken = false;
    var registeredProfile = false;
    while (true) {
      try {
        return await _sendOnce(method, path, body: body, idempotencyKey: key, freshToken: refreshedToken);
      } on _HttpFailure catch (f) {
        if (f.status == 401 && !refreshedToken) {
          refreshedToken = true;
          continue;
        }
        if (f.reason == 'profile-required' && !registeredProfile && path != endpoints.profile()) {
          registeredProfile = true;
          _profileReady = false;
          await ensureGuardianProfile();
          continue;
        }
        throw f.exception;
      }
    }
  }

  Future<Map<String, Object?>> _sendOnce(
    String method,
    String path, {
    Map<String, Object?>? body,
    String? idempotencyKey,
    bool freshToken = false,
  }) async {
    final base = await baseUrl();
    if (base == null || base.isEmpty) {
      throw const RepositoryException(RepositoryErrorCode.unavailable, '서버 주소 없음');
    }
    final token = freshToken ? await (refreshIdToken ?? idToken)() : await idToken();
    if (token == null) {
      throw const RepositoryException(RepositoryErrorCode.permissionDenied, '로그인 필요');
    }
    final uri = Uri.parse(base.endsWith('/') ? base.substring(0, base.length - 1) + path : base + path);
    final req = http.Request(method, uri)
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Content-Type'] = 'application/json; charset=utf-8'
      ..headers['Accept'] = 'application/json';
    if (idempotencyKey != null) req.headers['Idempotency-Key'] = idempotencyKey;
    if (body != null) req.body = jsonEncode(body);

    final http.Response res;
    try {
      res = await http.Response.fromStream(await _client.send(req).timeout(timeout));
    } on TimeoutException {
      throw const RepositoryException(RepositoryErrorCode.unavailable, '응답 시간 초과');
    } catch (e) {
      throw RepositoryException(RepositoryErrorCode.unavailable, '네트워크 오류: $e');
    }

    Map<String, Object?> json = const {};
    if (res.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        if (decoded is Map<String, Object?>) json = decoded;
      } on FormatException {
        // HTML 오류 페이지 등 (터널이 끊긴 경우)
      }
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return json;

    final error = json['error'];
    final reason = error is Map ? error['reason'] as String? : null;
    throw _HttpFailure(
      res.statusCode,
      reason,
      RepositoryException(errorCodeForReason(reason), 'HTTP ${res.statusCode} ${reason ?? ''}'.trim()),
    );
  }

  /// 이번 실행에서 이미 성공했으면 다시 보내지 않고, 동시에 여러 번 불려도 요청은 하나만 보낸다.
  @override
  Future<void> ensureGuardianProfile({String? name}) {
    if (name != null) _profileName = name;
    if (_profileReady) return Future.value();
    return _profileInFlight ??= () async {
      try {
        await _send('POST', endpoints.profile(), body: {'role': 'guardian', 'name': _profileName ?? '보호자'});
        _profileReady = true;
      } finally {
        _profileInFlight = null;
      }
    }();
  }

  @override
  Future<void> respondApproval(String approvalId, {required bool approve}) =>
      _send('POST', endpoints.respondApproval(approvalId), body: {'decision': approve ? 'approve' : 'reject'});

  @override
  Future<FamilyLink> connectWithCode(String code, {required String elderLabel, String guardianLabel = ''}) async {
    final json = await _send('POST', endpoints.links(),
        body: {'code': code.trim(), 'elderLabel': elderLabel.trim(), 'guardianLabel': guardianLabel.trim()},
        idempotent: true);
    return FamilyLink(
      elderId: json['elderId'] as String? ?? '',
      guardianId: '',
      elderName: json['elderName'] as String? ?? '',
      elderLabel: json['elderLabel'] as String? ?? json['relationship'] as String? ?? elderLabel.trim(),
      guardianLabel: json['guardianLabel'] as String? ?? guardianLabel.trim(),
      connectedAt: DateTime.tryParse(json['connectedAt'] as String? ?? '')?.toLocal() ?? DateTime.now(),
    );
  }

  @override
  Future<void> disconnect(String elderId) => _send('DELETE', endpoints.link(elderId));

  @override
  Future<void> registerDevice({required String deviceId, required String fcmToken, required String platform}) =>
      _send('PUT', endpoints.device(deviceId), body: {'fcmToken': fcmToken, 'platform': platform});

  @override
  Future<void> unregisterDevice(String deviceId) => _send('DELETE', endpoints.device(deviceId));
}

/// 재시도 판단용 HTTP 실패 (밖으로는 [exception]만 나간다)
class _HttpFailure implements Exception {
  const _HttpFailure(this.status, this.reason, this.exception);
  final int status;
  final String? reason;
  final RepositoryException exception;
}
