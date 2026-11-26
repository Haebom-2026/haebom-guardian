// 서버 S2(알림) 계약서 기준: #21 알림 목록, #22 읽음
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:guardian_app/models/notification_item.dart';
import 'package:guardian_app/models/sensitivity.dart';
import 'package:guardian_app/repositories/guardian_repository.dart';
import 'package:guardian_app/repositories/server/api_link_feed.dart';
import 'package:guardian_app/repositories/server/guardian_server_api.dart';
import 'package:guardian_app/repositories/server/server_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fake_server_api.dart';

Map<String, Object?> item(String id, {String type = 'sensitive_entry', String? readAt, String? category, String? level}) => {
      'id': id,
      'elderId': 'e_1',
      'elderName': '김순자',
      'elderLabel': '어머니',
      'type': type,
      'packageName': 'viva.republica.toss',
      'appName': '토스',
      'level': ?level,
      'category': ?category,
      'reason': '은행 앱 열기',
      'createdAt': '2026-11-26T10:16:21.625Z',
      'readAt': readAt,
    };

void main() {
  test('#21 GET /v1/guardian/notifications: limit·cursor 쿼리와 페이지 응답', () async {
    final requests = <http.Request>[];
    final api = HttpGuardianServerApi(
      baseUrl: () async => 'https://srv.example',
      idToken: () async => 'T',
      client: MockClient((r) async {
        requests.add(r);
        return http.Response.bytes(
            utf8.encode(jsonEncode({
              'items': [item('n1')],
              'nextCursor': 'C2',
              'serverTime': '2026-11-26T10:16:25.324Z',
            })),
            200);
      }),
    );
    final page = await api.fetchNotifications(limit: 50, cursor: 'C1');
    expect(requests.single.url.path, '/v1/guardian/notifications');
    expect(requests.single.url.queryParameters, {'limit': '50', 'cursor': 'C1'});
    expect(page.items.single['id'], 'n1');
    expect(page.nextCursor, 'C2');
    expect(page.serverTime, '2026-11-26T10:16:25.324Z');

    await api.markNotificationRead('n1');
    expect(requests.last.method, 'POST');
    expect(requests.last.url.path, '/v1/guardian/notifications/n1/read');
  });

  group('서버 API 방식 알림함', () {
    late FakeServerApi api;
    late ServerGuardianRepository repo;
    setUp(() {
      api = FakeServerApi();
      repo = ServerGuardianRepository.api(guardianId: 'me', api: api, linkFeed: ApiLinkFeed(api.fetchLinks));
    });

    test('#21 항목을 알림 모델로 바꾼다 (readAt → 내 확인, 사기 의심 표시)', () async {
      api.notifications = [
        item('n1', readAt: '2026-11-26T10:20:00.000Z'),
        item('n2', type: 'sos', category: 'scam', level: 'L3'),
      ];
      final list = await repo.watchNotifications().first;
      final n1 = list.firstWhere((n) => n.id == 'n1');
      final n2 = list.firstWhere((n) => n.id == 'n2');
      expect(n1.isReadBy('me'), isTrue);
      expect(n1.type, NotificationType.sensitiveEntry);
      expect(n1.appName, '토스');
      expect(n2.isReadBy('me'), isFalse);
      expect(n2.isScam, isTrue);
      expect(n2.level, SensitivityLevel.l3);
      expect(n2.guardianIds, ['me']);
    });

    test('[확인했어요] → #22 호출, 화면에 바로 확인됨으로 반영', () async {
      api.notifications = [item('n1')];
      final seen = <bool>[];
      final sub = repo.watchNotifications().listen((l) => seen.add(l.single.isReadBy('me')));
      await pumpEventQueue();
      await repo.markNotificationRead('n1');
      await pumpEventQueue();
      expect(api.calls, contains('read:n1'));
      expect(seen.first, isFalse);
      expect(seen.last, isTrue);
      await repo.markNotificationRead('n1');
      expect(api.calls.where((c) => c == 'read:n1'), hasLength(1), reason: '이미 확인한 알림은 다시 보내지 않음');
      await sub.cancel();
    });

    test('모두 확인: 안 읽은 알림만 #22', () async {
      api.notifications = [item('n1'), item('n2', readAt: '2026-11-26T10:20:00.000Z'), item('n3')];
      final sub = repo.watchNotifications().listen((_) {});
      await pumpEventQueue();
      await repo.markAllNotificationsRead();
      expect(api.calls.where((c) => c.startsWith('read:')).toList(), ['read:n1', 'read:n3']);
      await sub.cancel();
    });

    test('목록에 없는 알림(FCM으로 막 도착)을 열면 다시 조회해서 찾고, 그래도 없으면 not-found', () async {
      final sub = repo.watchNotifications().listen((_) {});
      await pumpEventQueue();
      api.notifications = [item('n9')];
      expect((await repo.getNotification('n9')).id, 'n9');
      await expectLater(repo.getNotification('none'),
          throwsA(isA<RepositoryException>().having((e) => e.code, 'code', RepositoryErrorCode.notFound)));
      await sub.cancel();
    });

    test('당겨서 새로고침: 가족·알림을 다시 조회', () async {
      final sub = repo.watchNotifications().listen((_) {});
      await pumpEventQueue();
      api.calls.clear();
      await repo.refresh();
      expect(api.calls, containsAll(['links', 'notifications']));
      await sub.cancel();
    });
  });
}
