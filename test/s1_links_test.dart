// 서버 S1(사용자·기기·연결) 계약서 기준: #20 가족 목록 조회, 연결 변경 FCM, 503 재시도, 해제 404
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:guardian_app/models/family_link.dart';
import 'package:guardian_app/repositories/guardian_repository.dart';
import 'package:guardian_app/repositories/server/api_link_feed.dart';
import 'package:guardian_app/repositories/server/guardian_server_api.dart';
import 'package:guardian_app/repositories/server/server_repository.dart';
import 'package:guardian_app/services/push_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fake_server_api.dart';

void main() {
  http.Response json(int status, Object body) =>
      http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json'});

  group('HTTP API (S1)', () {
    late List<http.Request> requests;
    HttpGuardianServerApi api(http.Response Function(http.Request, int n) handler) {
      requests = [];
      return HttpGuardianServerApi(
        baseUrl: () async => 'https://srv.example',
        idToken: () async => 'ID_TOKEN',
        client: MockClient((r) async {
          requests.add(r);
          return handler(r, requests.length);
        }),
      );
    }

    test('#20 GET /v1/guardian/links 응답을 연결 목록으로 바꾼다', () async {
      final a = api((_, _) => json(200, {
            'links': [
              {
                'elderId': 'e_1',
                'elderName': '김순자',
                'elderLabel': '어머니',
                'guardianLabel': '큰딸',
                'connectedAt': '2026-11-26T06:00:00.000Z',
              },
              {'elderId': '', 'elderName': '잘못된 항목'},
            ],
          }));
      final links = await a.fetchLinks();
      expect(requests.single.method, 'GET');
      expect(requests.single.url.toString(), 'https://srv.example/v1/guardian/links');
      expect(links, hasLength(1), reason: 'elderId 없는 항목은 버린다');
      expect(links.single.elderId, 'e_1');
      expect(links.single.displayName, '어머니');
      expect(links.single.guardianLabel, '큰딸');
      expect(links.single.connectedAt.toUtc(), DateTime.utc(2026, 11, 26, 6));
    });

    test('호칭이 비어 있으면 이름으로 표시한다', () async {
      final a = api((_, _) => json(200, {
            'links': [
              {'elderId': 'e_1', 'elderName': '김순자', 'elderLabel': '', 'guardianLabel': '', 'connectedAt': '2026-11-26T06:00:00.000Z'},
            ],
          }));
      expect((await a.fetchLinks()).single.displayName, '김순자');
    });

    test('503이면 같은 Idempotency-Key로 한 번만 다시 보낸다', () async {
      final a = api((_, n) => n == 1
          ? json(503, {'error': {'reason': 'unavailable'}})
          : json(201, {'elderId': 'e_1', 'elderName': '김순자', 'elderLabel': '어머니', 'guardianLabel': '딸', 'connectedAt': '2026-11-26T08:55:48.290Z'}));
      final link = await a.connectWithCode('371715', elderLabel: '어머니', guardianLabel: '딸');
      expect(link.elderId, 'e_1');
      expect(requests, hasLength(2));
      expect(requests[0].headers['Idempotency-Key'], requests[1].headers['Idempotency-Key']);
    });

    test('503이 두 번 오면 네트워크 오류로 안내한다', () async {
      final a = api((_, _) => json(503, {'error': {'reason': 'unavailable'}}));
      await expectLater(a.fetchLinks(),
          throwsA(isA<RepositoryException>().having((e) => e.code, 'code', RepositoryErrorCode.unavailable)));
      expect(requests, hasLength(2));
    });

    test('#15 해제: 이미 없는 연결(404)도 해제된 것으로 본다', () async {
      final a = api((_, _) => json(404, {'error': {'reason': 'not-found'}}));
      await a.disconnect('e_1');
      expect(requests.single.method, 'DELETE');
      expect(requests.single.url.path, '/v1/guardian/links/e_1');
    });

    test('#14 오류 reason → 보호자 문구', () async {
      for (final (status, reason, code) in [
        (404, 'invalid-code', RepositoryErrorCode.invalidCode),
        (409, 'code-expired', RepositoryErrorCode.codeExpired),
        (409, 'code-used', RepositoryErrorCode.codeUsed),
        (409, 'already-linked', RepositoryErrorCode.alreadyLinked),
        (429, 'too-many-attempts', RepositoryErrorCode.tooManyAttempts),
      ]) {
        final a = api((_, _) => json(status, {'error': {'reason': reason, 'message': 'x'}}));
        await expectLater(a.connectWithCode('123456', elderLabel: '어머니'),
            throwsA(isA<RepositoryException>().having((e) => e.code, 'code', code)));
      }
    });
  });

  group('ApiLinkFeed', () {
    FamilyLink link(String id, int minute) => FamilyLink(
        elderId: id, guardianId: '', elderName: id, elderLabel: '', connectedAt: DateTime.utc(2026, 11, 26, 6, minute));

    test('구독하면 조회하고, refresh마다 새 목록을 보낸다 (연결 시각 순)', () async {
      var server = [link('b', 2), link('a', 1)];
      var calls = 0;
      final feed = ApiLinkFeed(() async {
        calls++;
        return List.of(server);
      });
      final got = <List<String>>[];
      final sub = feed.stream.listen((l) => got.add(l.map((x) => x.elderId).toList()));
      await pumpEventQueue();
      expect(got, [
        ['a', 'b'],
      ]);
      server = [link('a', 1)];
      await feed.refresh();
      await pumpEventQueue();
      expect(got.last, ['a']);
      expect(calls, 2);
      await sub.cancel();
    });

    test('동시에 여러 번 불려도 겹쳐 보내지 않고, 진행 중에 불리면 끝난 뒤 한 번 더 조회한다', () async {
      final gate = Completer<void>();
      var calls = 0;
      final feed = ApiLinkFeed(() async {
        calls++;
        if (calls == 1) await gate.future;
        return <FamilyLink>[];
      });
      final f1 = feed.refresh();
      final f2 = feed.refresh();
      final f3 = feed.refresh();
      gate.complete();
      await Future.wait([f1, f2, f3]);
      expect(calls, 2);
    });

    test('조회 실패는 구독자에게 오류로 알리고, 다음 조회가 성공하면 목록을 보낸다', () async {
      var fail = true;
      final feed = ApiLinkFeed(() async {
        if (fail) throw const RepositoryException(RepositoryErrorCode.unavailable);
        return [link('a', 1)];
      });
      final errors = <Object>[];
      final lists = <List<FamilyLink>>[];
      final sub = feed.stream.listen(lists.add, onError: errors.add);
      await pumpEventQueue();
      expect(errors.single, isA<RepositoryException>());
      fail = false;
      await feed.refresh();
      await pumpEventQueue();
      expect(lists.single.single.elderId, 'a');
      await sub.cancel();
    });
  });

  group('서버 API 방식 저장소', () {
    late FakeServerApi api;
    late ApiLinkFeed feed;
    late ServerGuardianRepository repo;
    setUp(() {
      api = FakeServerApi();
      feed = ApiLinkFeed(api.fetchLinks);
      repo = ServerGuardianRepository.api(guardianId: 'me', api: api, linkFeed: feed);
    });

    test('가족 목록은 #20에서 받고 guardianId는 나로 채운다. 알림·승인은 아직 빈 목록', () async {
      api.links = [
        FamilyLink(elderId: 'e_1', guardianId: '', elderName: '김순자', elderLabel: '어머니', connectedAt: DateTime(2026)),
      ];
      final links = await repo.watchLinks().first;
      expect(links.single.guardianId, 'me');
      expect(links.single.displayName, '어머니');
      expect(await repo.watchNotifications().first, isEmpty);
      expect(await repo.watchApprovals().first, isEmpty);
    });

    test('연결·해제 뒤 가족 목록을 다시 조회한다', () async {
      final seen = <int>[];
      final sub = repo.watchLinks().listen((l) => seen.add(l.length));
      await pumpEventQueue();
      api.links = [
        FamilyLink(elderId: 'elder_x', guardianId: '', elderName: '박말순', elderLabel: '할머니', connectedAt: DateTime(2026)),
      ];
      await repo.connectWithCode('123456', elderLabel: '할머니', guardianLabel: '손녀');
      await pumpEventQueue();
      expect(seen.last, 1);
      api.links = [];
      await repo.disconnect('elder_x');
      await pumpEventQueue();
      expect(seen.last, 0);
      expect(api.calls.where((c) => c == 'links').length, 3);
      await sub.cancel();
    });
  });

  test('FCM data kind=link 는 연결 변경 메시지 (상세 화면 이동 대상 아님)', () {
    const m = PushMessage({'kind': 'link', 'change': 'created', 'elderId': 'e_1', 'guardianId': 'g_1'});
    expect(m.isLinkChange, isTrue);
    expect(m.target, isNull);
    expect(const PushMessage({'kind': 'approval', 'id': 'a_1'}).isLinkChange, isFalse);
  });
}
