// 가족의 도전 (💡 제안 단계, Mock 전용): 보호자가 직접 정해 보내고, 어르신이 [해 볼게요]/[다음에 할게요]를 고른다.
// 돈·개인정보가 오가는 도전은 막는다. "다음에"는 보호자에게 거절로 보이지 않는다. 해내면 칭찬.
import 'package:flutter_test/flutter_test.dart';
import 'package:guardian_app/models/challenge.dart';
import 'package:guardian_app/repositories/guardian_repository.dart';
import 'package:guardian_app/repositories/mock_backend.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers.dart';

Future<TestEnv> pumpPhone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(412, 915) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final env = TestEnv();
  await tester.pumpWidget(env.app);
  await tester.pumpAndSettle();
  addTearDown(env.deps.dispose);
  return env;
}

Future<void> reveal(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 150, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

Finder rowOf(Challenge c) => find.byKey(ValueKey('challenge_${c.id}'));
String statusText(WidgetTester tester, Challenge c) =>
    tester.widget<Text>(find.byKey(ValueKey('challenge_status_${c.id}'))).data!;

void main() {
  group('도전 이름 검사', () {
    test('돈·개인정보가 오가는 일은 막는다 (띄어쓰기·대소문자 무시)', () {
      for (final bad in ['엄마 계좌로 송금해 보기', '인증 번호 알려 주기', 'otp 입력해 보기', '쿠팡에서 결제해 보기', '돈 보내 보기']) {
        expect(validateChallenge(bad), isNotNull, reason: bad);
      }
      expect(validateChallenge('사진 보내기', '비밀번호 입력'), isNotNull, reason: '도움말도 검사');
      expect(validateChallenge('손주 사진을 프로필로 바꿔 보기', '카톡 → 내 프로필 → 연필'), isNull);
    });

    test('빈 이름·너무 긴 이름은 안 된다', () {
      expect(validateChallenge('  '), isNotNull);
      expect(validateChallenge('가' * (challengeTitleMax + 1)), isNotNull);
      expect(validateChallenge('날씨 보기', '가' * (challengeHintMax + 1)), isNotNull);
    });
  });

  group('Mock 서버 규칙', () {
    late MockBackend b;
    setUp(() => b = MockBackend(clock: FakeClock().now));

    test('보내면 연결된 보호자 모두가 보고, 같은 도전을 또 보낼 수는 없다', () {
      final c = b.suggestChallenge(MockBackend.meId, MockBackend.momId, '손주 사진 프로필로 바꾸기', hint: '카톡 → 내 프로필');
      expect(c.status, ChallengeStatus.sent);
      expect(c.hint, '카톡 → 내 프로필');
      expect(b.challengesFor(MockBackend.siblingId).map((x) => x.id), contains(c.id));
      expect(
        () => b.suggestChallenge(MockBackend.siblingId, MockBackend.momId, ' 손주 사진 프로필로 바꾸기 '),
        throwsA(isA<RepositoryException>()),
      );
    });

    test('서버도 막는 말을 검사한다 (앱을 거치지 않은 요청 대비)', () {
      expect(
        () => b.suggestChallenge(MockBackend.meId, MockBackend.momId, '인증번호 알려 주기'),
        throwsA(isA<RepositoryException>().having((e) => e.code, 'code', RepositoryErrorCode.invalidArgument)),
      );
    });

    test('연결되지 않은 가족에게는 보낼 수 없다', () {
      expect(
        () => b.suggestChallenge(MockBackend.siblingId, MockBackend.dadId, '날씨 보기'),
        throwsA(isA<RepositoryException>().having((e) => e.code, 'code', RepositoryErrorCode.permissionDenied)),
      );
    });

    test('어르신 흐름: 보냄 → 다음에 → 해 볼게요 → 해냈어요. 순서를 건너뛸 수 없다', () {
      final c = b.suggestChallenge(MockBackend.meId, MockBackend.dadId, '날씨 보기');
      expect(b.completeChallenge(c.id), isNull, reason: '해 보기로 하기 전에는 해냄 처리 불가');
      expect(b.postponeChallenge(c.id)!.status, ChallengeStatus.later);
      expect(b.acceptChallenge(c.id)!.status, ChallengeStatus.accepted, reason: '다음에 골랐어도 나중에 할 수 있다');
      final done = b.completeChallenge(c.id, withHelp: true)!;
      expect(done.isDone, isTrue);
      expect(done.withHelp, isTrue, reason: '도우미 안내를 받아도 성공');
    });

    test('칭찬은 해낸 도전에만, 정해 둔 문구로, 보호자마다 하나', () {
      final c = b.suggestChallenge(MockBackend.meId, MockBackend.dadId, '날씨 보기');
      expect(() => b.cheerChallenge(MockBackend.meId, c.id, cheerMessages.first), throwsA(isA<RepositoryException>()));
      b.acceptChallenge(c.id);
      b.completeChallenge(c.id);
      expect(() => b.cheerChallenge(MockBackend.meId, c.id, '아무 문구'), throwsA(isA<RepositoryException>()));
      b.cheerChallenge(MockBackend.meId, c.id, cheerMessages[1]);
      b.cheerChallenge(MockBackend.meId, c.id, cheerMessages[2]);
      expect(b.challengeFor(MockBackend.meId, c.id).cheers, {MockBackend.meId: cheerMessages[2]});
    });
  });

  testWidgets('홈: 해낸 도전 → 도전 중 → 보냄 순서, [칭찬하기] → 문구 선택 → "칭찬 보냄"', (tester) async {
    final env = await pumpPhone(tester);
    final all = env.backend.challengesFor(MockBackend.meId);
    final done = all.firstWhere((c) => c.isDone);
    final accepted = all.firstWhere((c) => c.isAccepted);
    final sent = all.firstWhere((c) => c.status == ChallengeStatus.sent);
    await reveal(tester, rowOf(sent));
    expect(find.text('가족의 도전'), findsOneWidget);
    double y(Challenge c) => tester.getTopLeft(rowOf(c)).dy;
    expect(y(done) < y(accepted) && y(accepted) < y(sent), isTrue);
    expect(statusText(tester, done), contains('도우미 안내와 함께'));
    expect(statusText(tester, done), contains('가족 1명이 칭찬했어요'));
    expect(statusText(tester, accepted), startsWith('도전 중'));
    expect(statusText(tester, sent), startsWith('보냄'));

    await tester.ensureVisible(find.byKey(ValueKey('cheer_${done.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('cheer_${done.id}')));
    await tester.pumpAndSettle();
    expect(find.text('어머니께 칭찬 보내기'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cheer_msg_1')));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('cheered_${done.id}')), findsOneWidget);
    expect(env.backend.challengeFor(MockBackend.meId, done.id).cheers[MockBackend.meId], cheerMessages[1]);
  });

  testWidgets('"다음에 할게요"를 골라도 보호자 화면은 "보냄" 그대로 (거절로 알리지 않음)', (tester) async {
    final env = await pumpPhone(tester);
    final sent = env.backend.challengesFor(MockBackend.meId).firstWhere((c) => c.status == ChallengeStatus.sent);
    await reveal(tester, rowOf(sent));
    final before = statusText(tester, sent);
    env.backend.postponeChallenge(sent.id);
    await tester.pumpAndSettle();
    expect(statusText(tester, sent), before);
    expect(find.textContaining('거절'), findsNothing);
  });

  testWidgets('도전 보내기: 직접 쓰고, 막는 말은 보내기 버튼이 꺼지며, 어르신 화면 미리 보기가 바뀐다', (tester) async {
    final env = await pumpPhone(tester);
    await reveal(tester, find.text('가족의 도전'));
    await tester.tap(find.widgetWithText(TextButton, '도전 보내기'));
    await tester.pumpAndSettle();
    expect(find.text('어머니께 해 볼 만한 일을 보내요'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, '아버지'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('challenge_title_field')), '아들 계좌로 송금해 보기');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('challenge_error')), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('challenge_send'))).onPressed, isNull);

    await tester.enterText(find.byKey(const Key('challenge_title_field')), '손주 사진을 프로필로 바꿔 보기');
    await tester.enterText(find.byKey(const Key('challenge_hint_field')), '카톡 → 내 프로필 → 연필 모양');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('challenge_error')), findsNothing);
    final preview = find.byKey(const Key('elder_preview'));
    expect(find.descendant(of: preview, matching: find.text('손주 사진을 프로필로 바꿔 보기')), findsOneWidget);
    expect(find.descendant(of: preview, matching: find.text('💡 카톡 → 내 프로필 → 연필 모양')), findsOneWidget);
    expect(find.descendant(of: preview, matching: find.text('딸이 도전을 보냈어요 🌱')), findsOneWidget);

    await tester.tap(find.byKey(const Key('challenge_send')));
    await tester.pumpAndSettle();
    final added = env.backend.challengesFor(MockBackend.meId).where((c) => c.title == '손주 사진을 프로필로 바꿔 보기');
    expect(added.single.elderId, MockBackend.dadId);
    expect(added.single.hint, '카톡 → 내 프로필 → 연필 모양');
    expect(added.single.status, ChallengeStatus.sent);
    expect(find.text('가족의 도전'), findsOneWidget, reason: '보내면 홈으로 돌아온다');
  });

  testWidgets('예시를 누르면 이름·도움말이 채워진다 (고쳐 쓸 수 있음)', (tester) async {
    await pumpPhone(tester);
    await reveal(tester, find.text('가족의 도전'));
    await tester.tap(find.widgetWithText(TextButton, '도전 보내기'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('example_video_call')));
    await tester.tap(find.byKey(const ValueKey('example_video_call')));
    await tester.pumpAndSettle();
    final tpl = ChallengeTemplate.byId('video_call')!;
    // 입력칸은 위로 스크롤되어 있을 수 있어 어르신 화면 미리 보기로 확인 (입력칸 값이 그대로 들어간다)
    final preview = find.byKey(const Key('elder_preview'));
    await tester.ensureVisible(preview);
    await tester.pumpAndSettle();
    expect(find.descendant(of: preview, matching: find.text(tpl.title)), findsOneWidget);
    expect(find.descendant(of: preview, matching: find.text('💡 ${tpl.hint}')), findsOneWidget);
  });

  testWidgets('어르신이 해내면 홈에 바로 반영된다', (tester) async {
    final env = await pumpPhone(tester);
    final accepted = env.backend.challengesFor(MockBackend.meId).firstWhere((c) => c.isAccepted);
    env.backend.completeChallenge(accepted.id);
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(ValueKey('cheer_${accepted.id}')));
    expect(find.byKey(ValueKey('cheer_${accepted.id}')), findsOneWidget);
  });
}
