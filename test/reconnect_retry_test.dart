// 실제 서버 연동 준비: 자동 재연결 · 프로필 등록 재시도 · 401/profile-required 재시도,
// 그리고 연결·해제·승인·거절 API 호출과 실시간 수신(다대다 포함) 회귀 검증.
import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guardian_app/controllers/guardian_store.dart';
import 'package:guardian_app/models/approval_request.dart';
import 'package:guardian_app/models/family_link.dart';
import 'package:guardian_app/repositories/mock_backend.dart';
import 'package:guardian_app/repositories/mock_repository.dart';
import 'package:guardian_app/repositories/guardian_repository.dart';
import 'package:guardian_app/repositories/server/guardian_server_api.dart';
import 'package:guardian_app/repositories/server/resilient_stream.dart';
import 'package:guardian_app/repositories/server/server_repository.dart';
import 'package:guardian_app/services/profile_registrar.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fake_server_api.dart';

/// 조건이 맞을 때까지 이벤트 큐를 돌린다 (최대 2초)
Future<void> until(bool Function() ok, {String what = ''}) async {
  for (var i = 0; i < 200; i++) {
    if (ok()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('시간 안에 조건을 만족하지 못함: $what');
}

FirebaseException denied() => FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');

void main() {
  group('resilientStream (자동 재연결)', () {
    test('오류가 나면 오류를 전달한 뒤 다시 구독하고, 데이터를 이어서 받는다', () async {
      var opens = 0;
      final s = resilientStream<int>(() {
        opens++;
        return opens == 1 ? Stream<int>.error(StateError('끊김')) : Stream<int>.fromIterable([1, 2]).asyncExpand((v) => Stream.value(v));
      }, delay: (_) => Duration.zero);
      final values = <int>[];
      final errors = <Object>[];
      final sub = s.listen(values.add, onError: errors.add);
      await until(() => values.length == 2, what: '재연결 후 데이터');
      expect(errors, hasLength(1));
      expect(opens, 2);
      await sub.cancel();
    });

    test('연속 실패하면 대기 시간이 늘고, 데이터를 받으면 처음부터 다시 센다', () async {
      final attempts = <int>[];
      var opens = 0;
      final ctrl = <StreamController<int>>[];
      final s = resilientStream<int>(() {
        opens++;
        final c = StreamController<int>();
        ctrl.add(c);
        return c.stream;
      }, delay: (a) {
        attempts.add(a);
        return Duration.zero;
      });
      final sub = s.listen((_) {}, onError: (_) {});
      await until(() => opens == 1);
      ctrl[0].addError('x');
      await until(() => opens == 2);
      ctrl[1].addError('x');
      await until(() => opens == 3);
      ctrl[2].add(1); // 성공 → 초기화
      await Future<void>.delayed(Duration.zero);
      ctrl[2].addError('x');
      await until(() => opens == 4);
      expect(attempts, [0, 1, 0]);
      expect(defaultReconnectDelay(0), const Duration(seconds: 1));
      expect(defaultReconnectDelay(4), const Duration(seconds: 16));
      expect(defaultReconnectDelay(20), const Duration(seconds: 30));
      await sub.cancel();
    });

    test('구독을 취소하면 예약된 재연결도 하지 않는다', () async {
      var opens = 0;
      final s = resilientStream<int>(() {
        opens++;
        return Stream<int>.error('x');
      }, delay: (_) => const Duration(milliseconds: 30));
      final sub = s.listen((_) {}, onError: (_) {});
      await until(() => opens == 1);
      await sub.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(opens, 1);
    });
  });

  group('ServerGuardianRepository 자동 재연결', () {
    const me = 'guardian_me';
    late FakeFirebaseFirestore db;
    final t0 = DateTime(2026, 11, 26, 10);

    Future<void> link(String elderId, {String guardianId = me}) => db.doc('links/${elderId}_$guardianId').set({
          'elderId': elderId,
          'guardianId': guardianId,
          'elderName': '김순자',
          'elderLabel': '어머니',
          'guardianLabel': '딸',
          'connectedAt': Timestamp.fromDate(t0),
        });

    Future<String> notification(String elderId, {List<String> guardians = const [me]}) async =>
        (await db.collection('notifications').add({
          'elderId': elderId,
          'guardianIds': guardians,
          'appName': '정부24',
          'packageName': 'kr.go.minwon.m',
          'type': 'sensitive_entry',
          'createdAt': Timestamp.fromDate(t0),
          'readBy': <String, Object>{},
        }))
            .id;

    /// 처음 [failFirst]번의 구독만 권한 거부로 실패시키는 저장소
    ServerGuardianRepository repo({String guardianId = me, Set<int> failCalls = const {}}) {
      var calls = 0;
      return ServerGuardianRepository(
        firestore: db,
        guardianId: guardianId,
        api: FakeServerApi(),
        clock: () => t0,
        reconnectDelay: (_) => Duration.zero,
        snapshots: (q) {
          calls++;
          return failCalls.contains(calls) ? Stream.error(denied()) : q.snapshots();
        },
      );
    }

    setUp(() => db = FakeFirebaseFirestore());

    test('가족 목록(links) 구독이 거부돼도 다시 구독해서 목록을 받는다 (앱 재실행 불필요)', () async {
      await link('mom');
      final errors = <Object>[];
      List<Object>? got;
      final sub = repo(failCalls: {1}).watchLinks().listen((l) => got = l, onError: errors.add);
      await until(() => got != null, what: '재연결 후 links');
      expect(got, hasLength(1));
      expect(errors.single, isA<RepositoryException>().having((e) => e.code, 'code', RepositoryErrorCode.permissionDenied));
      await sub.cancel();
    });

    test('한 가족의 알림 쿼리가 실패하면 잠시 비었다가 자동으로 다시 채워진다 (다른 가족은 유지)', () async {
      await link('mom');
      await link('dad');
      await notification('mom');
      await notification('dad');
      // 호출 순서: 1 links, 2 mom 또는 dad 알림 → 2번째 구독만 실패
      final lengths = <int>[];
      var errors = 0;
      final sub = repo(failCalls: {2}).watchNotifications().listen((l) => lengths.add(l.length), onError: (_) => errors++);
      await until(() => lengths.isNotEmpty && lengths.last == 2, what: '두 가족 알림 모두');
      expect(errors, 1);
      expect(lengths, contains(1)); // 실패한 가족만 빠진 상태를 거침
      await sub.cancel();
    });

    test('승인 목록도 재연결 후 다시 받는다', () async {
      await link('mom');
      await db.collection('approvals').add({
        'elderId': 'mom',
        'guardianIds': [me],
        'appName': '정부24',
        'packageName': 'kr.go.minwon.m',
        'action': 'guide_gov24_auth',
        'status': 'pending',
        'createdAt': Timestamp.fromDate(t0),
        'expiresAt': Timestamp.fromDate(t0.add(const Duration(minutes: 5))),
      });
      List<ApprovalRequest>? got;
      final sub = repo(failCalls: {1, 2}).watchApprovals().listen((l) => got = l, onError: (_) {});
      await until(() => got != null && got!.length == 1, what: '재연결 후 승인');
      await sub.cancel();
    });
  });

  group('연결·해제·승인·거절 수신 회귀 (서버 문서 → 보호자 앱)', () {
    late FakeFirebaseFirestore db;
    final t0 = DateTime(2026, 11, 26, 10);

    ServerGuardianRepository repoFor(String uid, FakeServerApi api) =>
        ServerGuardianRepository(firestore: db, guardianId: uid, api: api, clock: () => t0);

    Future<void> link(String elderId, String guardianId) => db.doc('links/${elderId}_$guardianId').set({
          'elderId': elderId,
          'guardianId': guardianId,
          'elderName': elderId,
          'elderLabel': '어머니',
          'guardianLabel': '딸',
          'connectedAt': Timestamp.fromDate(t0),
        });

    setUp(() => db = FakeFirebaseFirestore());

    test('다대다: 어르신 1명 ↔ 보호자 2명, 보호자 1명 ↔ 어르신 2명이 각자 자기 것만 받는다', () async {
      await link('mom', 'g_daughter');
      await link('mom', 'g_son');
      await link('dad', 'g_daughter');
      await db.collection('notifications').add({
        'elderId': 'mom', 'guardianIds': ['g_daughter', 'g_son'], 'appName': '토스', 'packageName': 'viva.republica.toss',
        'type': 'sensitive_entry', 'createdAt': Timestamp.fromDate(t0), 'readBy': <String, Object>{},
      });
      await db.collection('notifications').add({
        'elderId': 'dad', 'guardianIds': ['g_daughter'], 'appName': '정부24', 'packageName': 'kr.go.minwon.m',
        'type': 'sos', 'createdAt': Timestamp.fromDate(t0), 'readBy': <String, Object>{},
      });
      final daughter = await repoFor('g_daughter', FakeServerApi()).watchNotifications().firstWhere((l) => l.length == 2);
      final son = await repoFor('g_son', FakeServerApi()).watchNotifications().firstWhere((l) => l.isNotEmpty);
      expect(daughter.map((n) => n.elderId).toSet(), {'mom', 'dad'});
      expect(son.single.elderId, 'mom');
      expect((await repoFor('g_daughter', FakeServerApi()).watchLinks().first).length, 2);
    });

    test('다른 보호자가 먼저 응답하면 내 승인 목록에 바로 반영되고, 늦은 응답은 already-responded', () async {
      await link('mom', 'g_daughter');
      await link('mom', 'g_son');
      final ref = await db.collection('approvals').add({
        'elderId': 'mom', 'guardianIds': ['g_daughter', 'g_son'], 'appName': '정부24', 'packageName': 'kr.go.minwon.m',
        'action': 'guide_gov24_auth', 'status': 'pending', 'createdAt': Timestamp.fromDate(t0),
        'expiresAt': Timestamp.fromDate(t0.add(const Duration(minutes: 5))),
      });
      final api = FakeServerApi();
      final son = repoFor('g_son', api);
      final seen = <ApprovalStatus>[];
      final sub = son.watchApprovals().listen((l) => seen.addAll(l.map((a) => a.status)));
      await until(() => seen.contains(ApprovalStatus.pending));
      // 서버가 딸의 응답을 반영
      await ref.update({'status': 'approved', 'respondedBy': 'g_daughter', 'respondedAt': Timestamp.fromDate(t0)});
      await until(() => seen.last == ApprovalStatus.approved, what: '다른 보호자 응답 반영');
      final a = await son.getApproval(ref.id);
      expect(a.respondedBy, 'g_daughter');
      api.failWith = const RepositoryException(RepositoryErrorCode.alreadyResponded);
      expect(() => son.respondToApproval(ref.id, approve: false),
          throwsA(isA<RepositoryException>().having((e) => e.code, 'code', RepositoryErrorCode.alreadyResponded)));
      await sub.cancel();
    });

    test('승인·거절·연결·해제는 서버 API로 보낸다 (Firestore에 직접 쓰지 않음)', () async {
      await link('mom', 'g_me');
      final ref = await db.collection('approvals').add({
        'elderId': 'mom', 'guardianIds': ['g_me'], 'appName': '토스', 'packageName': 'viva.republica.toss',
        'action': 'guide_bank_open', 'status': 'pending', 'createdAt': Timestamp.fromDate(t0),
      });
      final api = FakeServerApi();
      final r = repoFor('g_me', api);
      await r.respondToApproval(ref.id, approve: false);
      final link2 = await r.connectWithCode('123456', elderLabel: '할머니', guardianLabel: '손녀');
      await r.disconnect('mom');
      expect(api.calls, ['respond:${ref.id}:false', 'connect:123456', 'disconnect:mom']);
      expect(link2.guardianId, 'g_me');
      // 승인 문서는 서버만 바꾼다
      expect((await ref.get()).data()!['status'], 'pending');
    });

    test('고령자 쪽 해제(서버가 links 삭제) → 그 가족의 승인·알림이 내 목록에서 사라진다', () async {
      await link('mom', 'g_me');
      await db.collection('approvals').add({
        'elderId': 'mom', 'guardianIds': ['g_me'], 'appName': '토스', 'packageName': 'viva.republica.toss',
        'action': 'guide_bank_open', 'status': 'pending', 'createdAt': Timestamp.fromDate(t0),
      });
      final lengths = <int>[];
      final sub = repoFor('g_me', FakeServerApi()).watchApprovals().listen((l) => lengths.add(l.length));
      await until(() => lengths.contains(1));
      await db.doc('links/mom_g_me').delete();
      await until(() => lengths.last == 0, what: '해제 반영');
      await sub.cancel();
    });
  });

  group('HttpGuardianServerApi 재시도', () {
    late List<http.Request> requests;
    http.Response json(int status, Object body) =>
        http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json'});

    HttpGuardianServerApi api(List<http.Response> responses, {Future<String?> Function()? refresh}) {
      requests = [];
      var i = 0;
      return HttpGuardianServerApi(
        baseUrl: () async => 'https://srv.example',
        idToken: () async => 'OLD',
        refreshIdToken: refresh,
        client: MockClient((r) async {
          requests.add(r);
          return responses[i++];
        }),
      );
    }

    test('401이면 토큰을 새로 받아 한 번 다시 보낸다 (같은 Idempotency-Key)', () async {
      final a = api([
        json(401, {'error': {'reason': 'unauthenticated'}}),
        json(200, {'elderId': 'e', 'elderName': '박말순', 'elderLabel': '할머니', 'guardianLabel': '손녀', 'connectedAt': '2026-11-26T01:00:00Z'}),
      ], refresh: () async => 'NEW');
      await a.connectWithCode('123456', elderLabel: '할머니', guardianLabel: '손녀');
      expect(requests.map((r) => r.headers['Authorization']), ['Bearer OLD', 'Bearer NEW']);
      expect(requests[0].headers['Idempotency-Key'], requests[1].headers['Idempotency-Key']);
    });

    test('401이 두 번이면 더 보내지 않고 권한 오류', () async {
      final a = api([
        json(401, {'error': {'reason': 'unauthenticated'}}),
        json(401, {'error': {'reason': 'unauthenticated'}}),
      ]);
      await expectLater(a.disconnect('e'),
          throwsA(isA<RepositoryException>().having((e) => e.code, 'code', RepositoryErrorCode.permissionDenied)));
      expect(requests, hasLength(2));
    });

    test('403 profile-required면 프로필(#2)을 등록하고 원래 요청을 다시 보낸다', () async {
      final a = api([
        json(403, {'error': {'reason': 'profile-required'}}),
        json(200, {'ok': true}), // POST /v1/users/me
        json(200, {'ok': true}), // 다시 보낸 기기 등록
      ]);
      expect(a.profileReady, isFalse);
      await a.registerDevice(deviceId: 'dev1', fcmToken: 'tok', platform: 'android');
      expect(requests.map((r) => '${r.method} ${r.url.path}'),
          ['PUT /v1/devices/dev1', 'POST /v1/users/me', 'PUT /v1/devices/dev1']);
      expect(jsonDecode(requests[1].body), {'role': 'guardian', 'name': '보호자'});
      expect(a.profileReady, isTrue);
    });

    test('프로필 등록이 실패하면 원래 요청은 그 오류로 끝난다 (무한 반복 없음)', () async {
      final a = api([
        json(403, {'error': {'reason': 'profile-required'}}),
        http.Response('<html>502</html>', 502),
      ]);
      await expectLater(a.respondApproval('ap1', approve: true),
          throwsA(isA<RepositoryException>().having((e) => e.code, 'code', RepositoryErrorCode.unavailable)));
      expect(requests, hasLength(2));
      expect(a.profileReady, isFalse);
    });

    test('프로필 등록은 성공한 뒤에는 다시 보내지 않고, 동시에 불려도 한 번만 보낸다', () async {
      final a = api([json(200, {'ok': true})]);
      await Future.wait([a.ensureGuardianProfile(), a.ensureGuardianProfile()]);
      await a.ensureGuardianProfile();
      expect(requests, hasLength(1));
    });
  });

  group('GuardianStore 오류 표시', () {
    test('가족 목록 오류는 다른 구독(알림)의 데이터로 지워지지 않고, 가족 목록이 다시 오면 지워진다', () async {
      final links = StreamController<List<FamilyLink>>();
      final store = GuardianStore(_ControlledLinksRepository(MockBackend(), links.stream));
      links.addError(const RepositoryException(RepositoryErrorCode.permissionDenied));
      await until(() => store.notifications.isNotEmpty && store.lastError != null, what: '알림 수신 + 가족 목록 오류');
      expect(store.isLoaded, isFalse);
      expect(store.lastError, isA<RepositoryException>());
      links.add(const []); // 재연결 후 가족 목록 수신
      await until(() => store.isLoaded);
      expect(store.lastError, isNull);
      store.dispose();
      await links.close();
    });
  });

  group('ProfileRegistrar (프로필 등록 재시도)', () {
    test('서버가 꺼져 있으면 기다렸다가 다시 시도하고, 성공하면 후속 작업(FCM 재등록)을 한 번 한다', () async {
      var calls = 0;
      var after = 0;
      final r = ProfileRegistrar(
        register: () async {
          calls++;
          if (calls < 3) throw const RepositoryException(RepositoryErrorCode.unavailable);
        },
        onRegistered: () => after++,
        delay: (_) => Duration.zero,
      );
      expect(await r.start(), isFalse);
      await until(() => r.isRegistered, what: '재시도 후 등록');
      expect(calls, 3);
      expect(after, 1);
      expect(await r.retryNow(), isTrue);
      expect(calls, 3);
      r.dispose();
    });

    test('앱이 앞으로 오면(retryNow) 예약을 기다리지 않고 바로 시도한다', () async {
      var calls = 0;
      var up = false;
      final r = ProfileRegistrar(
        register: () async {
          calls++;
          if (!up) throw const RepositoryException(RepositoryErrorCode.unavailable);
        },
        delay: (_) => const Duration(hours: 1),
      );
      await r.start();
      up = true;
      expect(await r.retryNow(), isTrue);
      expect(calls, 2);
      r.dispose();
    });

    test('dispose 뒤에는 다시 시도하지 않는다', () async {
      var calls = 0;
      final r = ProfileRegistrar(
        register: () async {
          calls++;
          throw const RepositoryException(RepositoryErrorCode.unavailable);
        },
        delay: (_) => const Duration(milliseconds: 20),
      );
      await r.start();
      r.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(calls, 1);
    });

    test('재시도 간격: 15초부터 두 배씩, 최대 5분', () {
      expect(defaultProfileRetryDelay(0), const Duration(seconds: 15));
      expect(defaultProfileRetryDelay(2), const Duration(seconds: 60));
      expect(defaultProfileRetryDelay(9), const Duration(minutes: 5));
    });
  });
}

/// 가족 목록 스트림만 테스트가 조종하는 저장소 (알림·승인은 Mock 그대로)
class _ControlledLinksRepository extends MockGuardianRepository {
  _ControlledLinksRepository(super.backend, this.links);
  final Stream<List<FamilyLink>> links;
  @override
  Stream<List<FamilyLink>> watchLinks() => links;
}
