import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:guardian_app/repositories/guardian_repository.dart';
import 'package:guardian_app/repositories/server/guardian_server_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late List<http.Request> requests;

  HttpGuardianServerApi api(http.Response Function(http.Request) handler, {String? base = 'https://srv.example'}) {
    requests = [];
    return HttpGuardianServerApi(
      baseUrl: () async => base,
      idToken: () async => 'ID_TOKEN',
      client: MockClient((r) async {
        requests.add(r);
        return handler(r);
      }),
    );
  }

  http.Response json(int status, Object body) =>
      http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json'});

  Matcher repoError(RepositoryErrorCode code) =>
      throwsA(isA<RepositoryException>().having((e) => e.code, 'code', code));

  test('Bearer ID 토큰을 붙이고 승인 응답을 보낸다', () async {
    final a = api((_) => json(200, {'status': 'approved', 'respondedAt': '2026-11-25T01:00:00Z'}));
    await a.respondApproval('ap/1', approve: true);
    final r = requests.single;
    expect(r.method, 'POST');
    expect(r.url.toString(), 'https://srv.example/v1/guardian/approvals/ap%2F1/respond');
    expect(r.headers['Authorization'], 'Bearer ID_TOKEN');
    expect(jsonDecode(r.body), {'decision': 'approve'});
  });

  test('가족 연결은 Idempotency-Key(UUID v4)를 붙이고 응답을 링크로 바꾼다', () async {
    final a = api((_) => json(200, {
          'elderId': 'elder_1',
          'elderName': '박말순',
          'relationship': '할머니',
          'connectedAt': '2026-11-25T01:00:00Z',
        }));
    final link = await a.connectWithCode(' 123456 ', elderLabel: '할머니', guardianLabel: ' 손녀 ');
    expect(link.elderId, 'elder_1');
    expect(link.elderName, '박말순');
    // v2.2 전 응답(relationship)도 elderLabel로 읽는다
    expect(link.elderLabel, '할머니');
    expect(link.guardianLabel, '손녀');
    expect(jsonDecode(requests.single.body), {'code': '123456', 'elderLabel': '할머니', 'guardianLabel': '손녀'});
    expect(requests.single.headers['Idempotency-Key'],
        matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
  });

  test('기기 등록: PUT /v1/devices/{deviceId}', () async {
    final a = api((_) => json(200, {'ok': true}));
    await a.registerDevice(deviceId: 'dev1', fcmToken: 'tok', platform: 'android');
    expect(requests.single.method, 'PUT');
    expect(requests.single.url.path, '/v1/devices/dev1');
    expect(jsonDecode(requests.single.body), {'fcmToken': 'tok', 'platform': 'android'});
  });

  test('오류 reason을 보호자 앱 오류 코드로 바꾼다 (기존 12종 + 신규 4종)', () async {
    expect(() => api((_) => json(409, {'error': {'reason': 'already-responded'}})).respondApproval('a', approve: true),
        repoError(RepositoryErrorCode.alreadyResponded));
    expect(() => api((_) => json(410, {'error': {'reason': 'code-expired'}})).connectWithCode('1', elderLabel: 'x'),
        repoError(RepositoryErrorCode.codeExpired));
    expect(errorCodeForReason('unauthenticated'), RepositoryErrorCode.permissionDenied);
    expect(errorCodeForReason('role-locked'), RepositoryErrorCode.permissionDenied);
    expect(errorCodeForReason('rate-limited'), RepositoryErrorCode.tooManyAttempts);
    expect(errorCodeForReason('something-new'), RepositoryErrorCode.unavailable);
  });

  test('서버 주소가 없거나 HTML 오류 페이지(터널 끊김)면 unavailable', () async {
    expect(() => api((_) => json(200, {}), base: null).disconnect('e'), repoError(RepositoryErrorCode.unavailable));
    expect(() => api((_) => http.Response('<html>502 Bad Gateway</html>', 502)).disconnect('e'),
        repoError(RepositoryErrorCode.unavailable));
  });

  test('네트워크 예외도 unavailable로 바꾼다', () async {
    final a = HttpGuardianServerApi(
      baseUrl: () async => 'https://srv.example',
      idToken: () async => 't',
      client: MockClient((_) async => throw http.ClientException('offline')),
    );
    expect(() => a.disconnect('e'), repoError(RepositoryErrorCode.unavailable));
  });
}
