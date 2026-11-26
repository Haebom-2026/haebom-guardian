// 가족의 도전 (💡 제안 단계, Mock 전용): 보호자는 추천만, 어르신이 해내면 칭찬. 실패·순위 없음, 해냈다는 사실만 전달.
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

void main() {
  group('Mock 서버 규칙', () {
    late MockBackend b;
    setUp(() => b = MockBackend(clock: FakeClock().now));

    test('추천하면 연결된 보호자 모두가 보고, 같은 도전을 또 추천할 수는 없다', () {
      final c = b.suggestChallenge(MockBackend.meId, MockBackend.momId, 'weather');
      expect(c.status, ChallengeStatus.open);
      expect(b.challengesFor(MockBackend.siblingId).map((x) => x.id), contains(c.id));
      expect(
        () => b.suggestChallenge(MockBackend.siblingId, MockBackend.momId, 'weather'),
        throwsA(isA<RepositoryException>()),
      );
    });

    test('연결되지 않은 가족에게는 추천할 수 없다', () {
      expect(
        () => b.suggestChallenge(MockBackend.siblingId, MockBackend.dadId, 'weather'),
        throwsA(isA<RepositoryException>().having((e) => e.code, 'code', RepositoryErrorCode.permissionDenied)),
      );
    });

    test('칭찬은 해낸 도전에만, 정해 둔 문구로, 보호자마다 하나', () {
      final c = b.suggestChallenge(MockBackend.meId, MockBackend.dadId, 'weather');
      expect(() => b.cheerChallenge(MockBackend.meId, c.id, cheerMessages.first), throwsA(isA<RepositoryException>()));
      b.completeChallenge(c.id, withHelp: true);
      expect(() => b.cheerChallenge(MockBackend.meId, c.id, '아무 문구'), throwsA(isA<RepositoryException>()));
      b.cheerChallenge(MockBackend.meId, c.id, cheerMessages[1]);
      b.cheerChallenge(MockBackend.meId, c.id, cheerMessages[2]);
      final done = b.challengeFor(MockBackend.meId, c.id);
      expect(done.isDone, isTrue);
      expect(done.withHelp, isTrue, reason: '도우미 안내를 받아도 성공');
      expect(done.cheers, {MockBackend.meId: cheerMessages[2]});
    });
  });

  testWidgets('홈: 해낸 도전이 먼저 나오고 [칭찬하기] → 문구 선택 → "칭찬 보냄"', (tester) async {
    final env = await pumpPhone(tester);
    final done = env.backend.challengesFor(MockBackend.meId).firstWhere((c) => c.isDone);
    final open = env.backend.challengesFor(MockBackend.meId).firstWhere((c) => !c.isDone);
    await reveal(tester, find.byKey(ValueKey('challenge_${open.id}')));
    expect(find.text('가족의 도전'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(ValueKey('challenge_${done.id}'))).dy <
          tester.getTopLeft(find.byKey(ValueKey('challenge_${open.id}'))).dy,
      isTrue,
    );
    expect(find.textContaining('도우미 안내와 함께'), findsOneWidget);
    expect(find.textContaining('가족 1명이 칭찬했어요'), findsOneWidget);

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

  testWidgets('추천하기: 가족을 고르고, 이미 도전 중인 것은 고를 수 없다', (tester) async {
    final env = await pumpPhone(tester);
    await reveal(tester, find.text('가족의 도전'));
    await tester.tap(find.widgetWithText(TextButton, '추천하기'));
    await tester.pumpAndSettle();
    expect(find.text('어떤 도전을 추천할까요?'), findsOneWidget);
    expect(find.textContaining('안 하셔도 따로 알림이 가지 않아요'), findsOneWidget);

    // 아버지는 사진 보내기 도전 중 → 고를 수 없음
    await tester.tap(find.widgetWithText(ChoiceChip, '아버지'));
    await tester.pumpAndSettle();
    expect(tester.widget<ListTile>(find.byKey(const ValueKey('suggest_kakao_photo'))).enabled, isFalse);

    await tester.tap(find.byKey(const ValueKey('suggest_weather')));
    await tester.pumpAndSettle();
    final added = env.backend.challengesFor(MockBackend.meId).where((c) => c.templateId == 'weather').toList();
    expect(added, hasLength(1));
    expect(added.single.elderId, MockBackend.dadId);
    expect(added.single.suggestedBy, MockBackend.meId);
  });

  testWidgets('어르신이 해내면 홈에 바로 반영된다', (tester) async {
    final env = await pumpPhone(tester);
    final open = env.backend.challengesFor(MockBackend.meId).firstWhere((c) => !c.isDone);
    env.backend.completeChallenge(open.id);
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(ValueKey('cheer_${open.id}')));
    expect(find.byKey(ValueKey('cheer_${open.id}')), findsOneWidget);
  });
}
