import 'package:flutter_test/flutter_test.dart';
import 'package:guardian_app/utils/formatters.dart';
import 'package:guardian_app/models/approval_request.dart';
import 'package:guardian_app/models/notification_item.dart';
import 'package:guardian_app/models/sensitive_app.dart';
import 'package:guardian_app/repositories/guardian_repository.dart';
import 'package:guardian_app/repositories/mock_backend.dart';
import 'package:guardian_app/repositories/mock_repository.dart';

import 'helpers.dart';

const me = MockBackend.meId;
const sibling = MockBackend.siblingId;
const mom = MockBackend.momId;
const dad = MockBackend.dadId;
const grandma = MockBackend.grandmaId;

Matcher throwsRepo(RepositoryErrorCode code) =>
    throwsA(isA<RepositoryException>().having((e) => e.code, 'code', code));

void main() {
  late FakeClock clock;
  late MockBackend b;

  setUp(() {
    clock = FakeClock();
    b = MockBackend(clock: clock.now);
  });

  group('민감 앱 이용 알림', () {
    test('예 선택 시 알림이 생성되고 연결된 모든 보호자가 수신 대상이 된다', () {
      final before = b.allNotifications.length;
      final (outcome, n) = b.reportSensitiveEntry(elderId: mom, app: SensitiveApp.gov24, choice: ConsentChoice.yes);
      expect(outcome, SensitiveEntryOutcome.created);
      expect(b.allNotifications.length, before + 1);
      expect(n!.type, NotificationType.sensitiveEntry);
      expect(n.appName, '정부24');
      expect(n.guardianIds, unorderedEquals([me, sibling])); // 서버가 links 기준으로 결정
      expect(n.readBy, isEmpty);
      expect(b.notificationsFor(me).first.id, n.id);
    });

    test('아니요 선택 시 알림 문서가 생성되지 않는다', () {
      final before = b.allNotifications.length;
      final (outcome, n) = b.reportSensitiveEntry(elderId: mom, app: SensitiveApp.toss, choice: ConsentChoice.no);
      expect(outcome, SensitiveEntryOutcome.skippedNoConsent);
      expect(n, isNull);
      expect(b.allNotifications.length, before);
    });

    test('팝업 닫기 시 알림 문서가 생성되지 않는다', () {
      final before = b.allNotifications.length;
      final (outcome, _) =
          b.reportSensitiveEntry(elderId: mom, app: SensitiveApp.kakaoBank, choice: ConsentChoice.dismissed);
      expect(outcome, SensitiveEntryOutcome.skippedNoConsent);
      expect(b.allNotifications.length, before);
    });

    test('같은 앱 중복 알림은 10분 이내 생성되지 않고, 이후에는 다시 생성된다', () {
      b.reportSensitiveEntry(elderId: mom, app: SensitiveApp.gov24, choice: ConsentChoice.yes);
      final count = b.allNotifications.length;
      clock.advance(const Duration(minutes: 3));
      final (dup, _) = b.reportSensitiveEntry(elderId: mom, app: SensitiveApp.gov24, choice: ConsentChoice.yes);
      expect(dup, SensitiveEntryOutcome.duplicateSuppressed);
      expect(b.allNotifications.length, count);
      expect(b.isRecentSensitiveEntry(mom, SensitiveApp.gov24), isTrue);
      expect(b.isRecentSensitiveEntry(dad, SensitiveApp.gov24), isFalse);
      // 다른 앱은 중복이 아님
      final (other, _) = b.reportSensitiveEntry(elderId: mom, app: SensitiveApp.toss, choice: ConsentChoice.yes);
      expect(other, SensitiveEntryOutcome.created);
      clock.advance(const Duration(minutes: 6)); // 9분: 아직 중복
      final (stillDup, _) = b.reportSensitiveEntry(elderId: mom, app: SensitiveApp.gov24, choice: ConsentChoice.yes);
      expect(stillDup, SensitiveEntryOutcome.duplicateSuppressed);
      clock.advance(const Duration(minutes: 2)); // 11분
      final (again, _) = b.reportSensitiveEntry(elderId: mom, app: SensitiveApp.gov24, choice: ConsentChoice.yes);
      expect(again, SensitiveEntryOutcome.created);
    });

    test('연결된 보호자가 없는 고령자는 알림이 생성되지 않는다', () {
      final (outcome, _) = b.reportSensitiveEntry(elderId: grandma, app: SensitiveApp.gov24, choice: ConsentChoice.yes);
      expect(outcome, SensitiveEntryOutcome.noGuardians);
    });

    test('SOS 알림은 앱 이용 알림과 구분되어 생성된다', () {
      final n = b.createSos(mom)!;
      expect(n.type, NotificationType.sos);
      expect(n.type.code, 'sos');
    });

    test('SOS는 사용 중이던 앱 정보를 선택적으로 담는다 (없으면 빈 문자열)', () {
      final inApp = b.createSos(mom, app: SensitiveApp.gov24)!;
      expect(inApp.appName, '정부24');
      expect(inApp.packageName, 'kr.go.minwon.m');
      expect(notificationMessage(inApp, '어머니'), '어머니가 정부24 사용 중 SOS 도움 요청을 보냈습니다.');
      final home = b.createSos(mom)!;
      expect(home.appName, isEmpty);
      expect(notificationMessage(home, '어머니'), '어머니가 SOS 도움 요청을 보냈습니다.');
    });
  });

  group('읽음 상태', () {
    test('읽음 처리는 보호자별로 독립 관리된다', () {
      final (_, n) = b.reportSensitiveEntry(elderId: mom, app: SensitiveApp.gov24, choice: ConsentChoice.yes);
      b.markRead(me, n!.id);
      final after = b.notificationFor(me, n.id);
      expect(after.isReadBy(me), isTrue);
      expect(after.isReadBy(sibling), isFalse);
      b.markRead(sibling, n.id);
      expect(b.notificationFor(sibling, n.id).isReadBy(sibling), isTrue);
    });

    test('모두 읽음은 선택한 가족의 알림에만 적용된다', () {
      b.markAllRead(me, elderId: dad);
      expect(b.notificationsFor(me).where((n) => n.elderId == dad).every((n) => n.isReadBy(me)), isTrue);
      expect(b.notificationsFor(me).where((n) => n.elderId == mom).any((n) => !n.isReadBy(me)), isTrue);
    });
  });

  group('승인 요청', () {
    ApprovalRequest create() => b.requestApproval(elderId: mom, app: SensitiveApp.gov24)!;

    test('승인 요청이 pending 상태와 5분 만료 시각으로 생성된다', () {
      final a = create();
      expect(a.status, ApprovalStatus.pending);
      expect(a.action, 'guide_gov24_auth');
      expect(a.expiresAt.difference(a.createdAt), const Duration(minutes: 5));
      expect(a.guardianIds, unorderedEquals([me, sibling]));
    });

    test('승인 처리 후 고령자 앱에 결과가 전달된다', () {
      final a = create();
      final r = b.respond(me, a.id, approve: true);
      expect(r.status, ApprovalStatus.approved);
      expect(r.respondedBy, me);
      expect(r.respondedAt, clock.value);
      expect(b.elderInbox.first.approvalId, a.id);
      expect(b.elderInbox.first.status, ApprovalStatus.approved);
    });

    test('거절 처리', () {
      final a = create();
      expect(b.respond(me, a.id, approve: false).status, ApprovalStatus.rejected);
      expect(b.elderInbox.first.status, ApprovalStatus.rejected);
    });

    test('이미 응답한 요청에 다시 응답할 수 없다 (중복 승인 방지)', () {
      final a = create();
      b.respond(me, a.id, approve: true);
      expect(() => b.respond(me, a.id, approve: false), throwsRepo(RepositoryErrorCode.alreadyResponded));
      expect(b.approvalFor(me, a.id).status, ApprovalStatus.approved);
    });

    test('여러 보호자가 응답하면 최초의 유효한 응답만 반영된다', () {
      final a = create();
      b.respond(sibling, a.id, approve: false);
      expect(() => b.respond(me, a.id, approve: true), throwsRepo(RepositoryErrorCode.alreadyResponded));
      final r = b.approvalFor(me, a.id);
      expect(r.status, ApprovalStatus.rejected);
      expect(r.respondedBy, sibling);
      expect(b.elderInbox.where((d) => d.approvalId == a.id).length, 1);
    });

    test('만료 시간이 지나면 expired가 되고 승인할 수 없다', () {
      final a = create();
      clock.advance(const Duration(minutes: 5));
      expect(b.approvalFor(me, a.id).effectiveStatus(clock.value), ApprovalStatus.expired);
      expect(() => b.respond(me, a.id, approve: true), throwsRepo(RepositoryErrorCode.approvalExpired));
      expect(b.approvalFor(me, a.id).status, ApprovalStatus.expired);
      expect(b.elderInbox.first.status, ApprovalStatus.expired);
    });

    test('만료 직전에는 승인할 수 있다', () {
      final a = create();
      clock.advance(const Duration(minutes: 4, seconds: 59));
      expect(b.respond(me, a.id, approve: true).status, ApprovalStatus.approved);
    });

    test('expireOverdue가 만료 시간이 지난 요청을 일괄 만료 처리한다', () {
      final a = create();
      clock.advance(const Duration(minutes: 6));
      expect(b.expireOverdue(), greaterThanOrEqualTo(1));
      expect(b.approvalFor(me, a.id).status, ApprovalStatus.expired);
    });

    test('고령자가 취소한 요청은 응답할 수 없다', () {
      final a = create();
      expect(b.cancelApproval(a.id), isTrue);
      expect(b.approvalFor(me, a.id).status, ApprovalStatus.cancelled);
      expect(() => b.respond(me, a.id, approve: true), throwsRepo(RepositoryErrorCode.approvalCancelled));
      expect(b.cancelApproval(a.id), isFalse, reason: '이미 취소된 요청은 다시 취소할 수 없음');
    });

    test('응답 완료된 요청은 취소할 수 없다', () {
      final a = create();
      b.respond(me, a.id, approve: true);
      expect(b.cancelApproval(a.id), isFalse);
      expect(b.approvalFor(me, a.id).status, ApprovalStatus.approved);
    });
  });

  group('가족 연결', () {
    test('유효한 코드로 연결되고 코드는 사용 처리된다', () {
      final code = b.issueConnectCode(grandma);
      expect(code, matches(RegExp(r'^\d{6}$')));
      final link = b.connectWithCode(me, code, elderLabel: '할머니');
      expect(link.elderId, grandma);
      expect(link.elderName, '박말순');
      expect(b.isLinked(grandma, me), isTrue);
      expect(b.codeInfo(code)!.used, isTrue);
    });

    test('잘못된 코드 형식과 존재하지 않는 코드를 거부한다', () {
      expect(() => b.connectWithCode(me, '12ab', elderLabel: '할머니'), throwsRepo(RepositoryErrorCode.invalidCode));
      var unknown = '000000';
      while (b.codeInfo(unknown) != null) {
        unknown = '000001';
      }
      expect(() => b.connectWithCode(me, unknown, elderLabel: '할머니'), throwsRepo(RepositoryErrorCode.invalidCode));
    });

    test('10분이 지난 코드는 만료로 거부된다', () {
      final code = b.issueConnectCode(grandma);
      clock.advance(const Duration(minutes: 10));
      expect(() => b.connectWithCode(me, code, elderLabel: '할머니'), throwsRepo(RepositoryErrorCode.codeExpired));
      expect(b.isLinked(grandma, me), isFalse);
    });

    test('사용된 코드는 재사용할 수 없다 (다른 보호자 포함)', () {
      final code = b.issueConnectCode(grandma);
      b.connectWithCode(me, code, elderLabel: '할머니');
      expect(() => b.connectWithCode(sibling, code, elderLabel: '할머니'), throwsRepo(RepositoryErrorCode.codeUsed));
    });

    test('이미 연결된 가족은 중복 연결되지 않는다', () {
      final code = b.issueConnectCode(mom);
      expect(() => b.connectWithCode(me, code, elderLabel: '어머니'), throwsRepo(RepositoryErrorCode.alreadyLinked));
    });

    test('연속 실패 5회 시 일정 시간 입력이 제한된다 (무작위 대입 방지)', () {
      for (var i = 0; i < MockBackend.maxFailedCodeAttempts; i++) {
        expect(() => b.connectWithCode(me, '99999$i'.substring(0, 6), elderLabel: 'x'),
            throwsA(isA<RepositoryException>()));
      }
      final valid = b.issueConnectCode(grandma);
      expect(() => b.connectWithCode(me, valid, elderLabel: '할머니'), throwsRepo(RepositoryErrorCode.tooManyAttempts));
      clock.advance(MockBackend.codeLockDuration);
      expect(b.connectWithCode(me, valid, elderLabel: '할머니').elderId, grandma);
    });

    test('새 코드를 발급하면 같은 고령자의 이전 미사용 코드는 무효화된다', () {
      final old = b.issueConnectCode(grandma);
      final other = b.issueConnectCode(mom); // 다른 고령자 코드는 영향 없음
      final fresh = b.issueConnectCode(grandma);
      expect(() => b.connectWithCode(me, old, elderLabel: '할머니'), throwsRepo(RepositoryErrorCode.codeExpired));
      expect(b.connectWithCode(me, fresh, elderLabel: '할머니').elderId, grandma);
      expect(b.codeInfo(other)!.expiresAt.isAfter(b.now()), isTrue);
    });

    test('고령자도 연결을 해제할 수 있고, 해제된 보호자는 기록에 접근할 수 없다', () {
      final (_, n) = b.reportSensitiveEntry(elderId: mom, app: SensitiveApp.toss, choice: ConsentChoice.yes);
      b.disconnectByElder(mom, sibling);
      expect(b.isLinked(mom, sibling), isFalse);
      expect(b.isLinked(mom, me), isTrue, reason: '다른 보호자 연결은 유지');
      expect(() => b.notificationFor(sibling, n!.id), throwsRepo(RepositoryErrorCode.permissionDenied));
      expect(b.notificationFor(me, n!.id).id, n.id);
      expect(() => b.disconnectByElder(mom, sibling), throwsRepo(RepositoryErrorCode.notFound));
    });

    test('한 고령자에 여러 보호자, 한 보호자에 여러 고령자 연결', () {
      expect(b.linksForElder(mom).map((l) => l.guardianId), unorderedEquals([me, sibling]));
      expect(b.linksForGuardian(me).map((l) => l.elderId), unorderedEquals([mom, dad]));
    });

    test('연결 해제 후에는 해당 가족의 알림과 승인 요청에 접근할 수 없다', () {
      final (_, n) = b.reportSensitiveEntry(elderId: dad, app: SensitiveApp.bank, choice: ConsentChoice.yes);
      final a = b.requestApproval(elderId: dad, app: SensitiveApp.bank)!;
      b.disconnect(me, dad);
      expect(b.isLinked(dad, me), isFalse);
      expect(b.notificationsFor(me).any((x) => x.elderId == dad), isFalse);
      expect(b.approvalsFor(me).any((x) => x.elderId == dad), isFalse);
      expect(() => b.notificationFor(me, n!.id), throwsRepo(RepositoryErrorCode.permissionDenied));
      expect(() => b.respond(me, a.id, approve: true), throwsRepo(RepositoryErrorCode.permissionDenied));
      expect(() => b.disconnect(me, dad), throwsRepo(RepositoryErrorCode.notFound));
    });
  });

  group('접근 제한', () {
    test('연결되지 않은 보호자는 다른 가족의 알림·승인을 보거나 응답할 수 없다', () {
      // 동생은 아버지와 연결되어 있지 않음
      final (_, n) = b.reportSensitiveEntry(elderId: dad, app: SensitiveApp.kakaoBank, choice: ConsentChoice.yes);
      final a = b.requestApproval(elderId: dad, app: SensitiveApp.kakaoBank)!;
      expect(b.notificationsFor(sibling).any((x) => x.elderId == dad), isFalse);
      expect(() => b.notificationFor(sibling, n!.id), throwsRepo(RepositoryErrorCode.permissionDenied));
      expect(() => b.respond(sibling, a.id, approve: true), throwsRepo(RepositoryErrorCode.permissionDenied));
      expect(() => b.markRead(sibling, n!.id), throwsRepo(RepositoryErrorCode.permissionDenied));
      expect(b.approvalFor(me, a.id).status, ApprovalStatus.pending);
    });

    test('존재하지 않는 문서는 notFound', () {
      expect(() => b.notificationFor(me, 'nope'), throwsRepo(RepositoryErrorCode.notFound));
      expect(() => b.approvalFor(me, 'nope'), throwsRepo(RepositoryErrorCode.notFound));
    });
  });

  group('MockGuardianRepository 스트림', () {
    test('구독 즉시 현재 값을 받고, 변경 시 새 값을 받는다', () async {
      final repo = MockGuardianRepository(b);
      final values = <int>[];
      final sub = repo.watchNotifications().listen((v) => values.add(v.length));
      await Future<void>.delayed(Duration.zero);
      b.reportSensitiveEntry(elderId: mom, app: SensitiveApp.gov24, choice: ConsentChoice.yes);
      await Future<void>.delayed(Duration.zero);
      expect(values.length, 2);
      expect(values[1], values[0] + 1);
      await sub.cancel();
    });

    test('오류는 Future 오류로 전달된다', () async {
      final repo = MockGuardianRepository(b);
      await expectLater(repo.getApproval('none'), throwsRepo(RepositoryErrorCode.notFound));
    });
  });
}
