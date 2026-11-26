import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guardian_app/models/approval_request.dart';
import 'package:guardian_app/models/notification_item.dart';
import 'package:guardian_app/repositories/guardian_repository.dart';
import 'package:guardian_app/repositories/server/server_repository.dart';

import 'fake_server_api.dart';

void main() {
  const me = 'guardian_me';
  late FakeFirebaseFirestore db;
  late FakeServerApi api;
  late ServerGuardianRepository repo;
  final t0 = DateTime(2026, 11, 25, 10);

  Future<void> link(String elderId, {String guardianId = me}) => db.doc('links/${elderId}_$guardianId').set({
        'elderId': elderId,
        'guardianId': guardianId,
        'elderName': '김순자',
        'relationship': '어머니',
        'connectedAt': Timestamp.fromDate(t0),
      });

  Future<String> notification(String elderId, {List<String> guardians = const [me], int minutes = 0, String type = 'sensitive_entry'}) async {
    final ref = await db.collection('notifications').add({
      'elderId': elderId,
      'guardianIds': guardians,
      'appName': '정부24',
      'packageName': 'kr.go.minwon.m',
      'type': type,
      'createdAt': Timestamp.fromDate(t0.add(Duration(minutes: minutes))),
      'readBy': <String, Object>{},
    });
    return ref.id;
  }

  setUp(() {
    db = FakeFirebaseFirestore();
    api = FakeServerApi();
    repo = ServerGuardianRepository(firestore: db, guardianId: me, api: api, clock: () => t0);
  });

  test('연결된 가족의 알림만, 최신순으로 받는다 (연결 안 된 가족·다른 보호자 알림 제외)', () async {
    await link('mom');
    await link('dad');
    await notification('mom', minutes: 1);
    await notification('dad', minutes: 5);
    await notification('stranger', minutes: 9); // 연결 안 됨
    await notification('mom', guardians: ['guardian_other'], minutes: 7); // 나에게 온 알림 아님

    final list = await repo.watchNotifications().firstWhere((l) => l.length >= 2);
    expect(list.map((n) => n.elderId), ['dad', 'mom']);
    expect(list.first.type, NotificationType.sensitiveEntry);
    expect(list.first.appName, '정부24');
  });

  test('연결이 해제되면 그 가족의 알림이 목록에서 사라진다', () async {
    await link('mom');
    await link('dad');
    await notification('mom');
    await notification('dad');
    final stream = repo.watchNotifications();
    final seen = <int>[];
    final sub = stream.listen((l) => seen.add(l.length));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await db.doc('links/dad_$me').delete();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sub.cancel();
    expect(seen.last, 1);
    expect(seen, contains(2));
  });

  test('연결된 가족이 없으면 빈 목록', () async {
    expect(await repo.watchNotifications().first, isEmpty);
    expect(await repo.watchApprovals().first, isEmpty);
    expect(await repo.watchLinks().first, isEmpty);
  });

  test('"확인했어요": 자기 readBy 항목만 기록하고, 이미 확인했으면 다시 쓰지 않는다', () async {
    await link('mom');
    final id = await notification('mom', guardians: [me, 'sibling']);
    await repo.markNotificationRead(id);
    final data = (await db.doc('notifications/$id').get()).data()!;
    expect((data['readBy'] as Map).keys, [me]);
    final n = await repo.getNotification(id);
    expect(n.isReadBy(me), isTrue);
    expect(n.isReadBy('sibling'), isFalse);
    await repo.markNotificationRead(id); // 두 번째는 아무것도 안 함
    expect(((await db.doc('notifications/$id').get()).data()!['readBy'] as Map).length, 1);
  });

  test('모두 확인은 선택한 가족의 확인 전 알림에만 적용된다', () async {
    await link('mom');
    await link('dad');
    final m = await notification('mom');
    final d = await notification('dad');
    await repo.markAllNotificationsRead(elderId: 'dad');
    expect((await repo.getNotification(d)).isReadBy(me), isTrue);
    expect((await repo.getNotification(m)).isReadBy(me), isFalse);
  });

  test('없는 알림은 not-found, 나에게 온 것이 아니면 permission-denied', () async {
    await expectLater(repo.getNotification('nope'),
        throwsA(isA<RepositoryException>().having((e) => e.code, 'code', RepositoryErrorCode.notFound)));
    final other = await notification('mom', guardians: ['guardian_other']);
    await expectLater(repo.getNotification(other),
        throwsA(isA<RepositoryException>().having((e) => e.code, 'code', RepositoryErrorCode.permissionDenied)));
  });

  test('승인 요청 문서를 모델로 바꾸고, 승인 응답은 서버 API로 보낸 뒤 최신 문서를 돌려준다', () async {
    await link('mom');
    final ref = await db.collection('approvals').add({
      'elderId': 'mom',
      'guardianIds': [me],
      'appName': '정부24',
      'packageName': 'kr.go.minwon.m',
      'action': 'guide_gov24_auth',
      'status': 'pending',
      'createdAt': Timestamp.fromDate(t0),
      'expiresAt': Timestamp.fromDate(t0.add(const Duration(minutes: 5))),
      'respondedAt': null,
      'respondedBy': null,
    });
    final list = await repo.watchApprovals().firstWhere((l) => l.isNotEmpty);
    expect(list.single.status, ApprovalStatus.pending);
    expect(list.single.remaining(t0), const Duration(minutes: 5));

    // 서버가 상태를 바꾸는 것처럼 흉내
    api.onRespond = () => ref.update({'status': 'approved', 'respondedBy': me, 'respondedAt': Timestamp.fromDate(t0)});
    final updated = await repo.respondToApproval(ref.id, approve: true);
    expect(api.calls, ['respond:${ref.id}:true']);
    expect(updated.status, ApprovalStatus.approved);
    expect(updated.respondedBy, me);
  });

  test('서버 오류는 그대로 전달된다 (예: 다른 보호자가 먼저 응답)', () async {
    api.failWith = const RepositoryException(RepositoryErrorCode.alreadyResponded);
    await expectLater(repo.respondToApproval('a1', approve: false),
        throwsA(isA<RepositoryException>().having((e) => e.code, 'code', RepositoryErrorCode.alreadyResponded)));
  });

  test('가족 연결·해제는 서버 API로 보내고, 결과 링크의 보호자는 나로 채운다', () async {
    final l = await repo.connectWithCode('123456', elderLabel: '할머니');
    expect(l.guardianId, me);
    expect(l.elderLabel, '할머니');
    await repo.disconnect('elder_x');
    expect(api.calls, ['connect:123456', 'disconnect:elder_x']);
  });

  test('문서 변환: 서버 타임스탬프 미확정·필드 누락·SOS 앱 정보 선택', () {
    final n = FirestoreMappers.notification('n1', {
      'elderId': 'mom',
      'guardianIds': [me],
      'type': 'sos',
      'createdAt': null,
    }, () => t0);
    expect(n.createdAt, t0);
    expect(n.appName, '');
    expect(n.type, NotificationType.sos);
    final a = FirestoreMappers.approval('a1', {'status': 'expired', 'createdAt': Timestamp.fromDate(t0)}, () => t0);
    expect(a.status, ApprovalStatus.expired);
    expect(a.expiresAt, t0.add(const Duration(minutes: 5)));
  });
}
