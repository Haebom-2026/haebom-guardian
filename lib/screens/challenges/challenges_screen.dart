import 'package:material_ui/material_ui.dart';

import '../../app/dependencies.dart';
import '../../app/theme.dart';
import '../../models/challenge.dart';
import '../../widgets/common.dart';
import '../home/challenge_section.dart';
import '../home/send_challenge_screen.dart';

/// 도전 탭 (💡 제안 단계, Mock 모드에서만 보인다). 홈에는 3개까지만, 여기에는 모든 도전을 상태별로.
/// 순위·점수는 없다. "이번 달 해낸 도전"은 가족이 함께 보는 기록일 뿐이다.
class ChallengesScreen extends StatelessWidget {
  const ChallengesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context).store;
    final t = Theme.of(context);
    final k = HaebomTokens.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('가족의 도전')),
      body: RefreshIndicator(
        onRefresh: store.refresh,
        child: SafeArea(
          top: false,
          child: ListenableBuilder(
            listenable: store,
            builder: (context, _) {
              final me = store.guardianId;
              final now = store.now();
              final elder = store.selectedElderId;
              final all = store.challengesFor(elderId: elder);
              final waiting = all.where((c) => c.isDone && !c.cheeredBy(me)).toList();
              final doing = all.where((c) => c.isAccepted).toList();
              // "다음에 할게요"(later)도 보호자에게는 "보냄"으로 (거절로 알리지 않음)
              final sent = all
                  .where((c) => c.status == ChallengeStatus.sent || c.status == ChallengeStatus.later)
                  .toList();
              final past = all.where((c) => c.isDone && c.cheeredBy(me)).toList();
              final thisMonth = all
                  .where((c) => c.isDone && c.completedAt!.year == now.year && c.completedAt!.month == now.month)
                  .length;

              Widget group(String title, List<Challenge> items, Key countKey) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionHeader(title, count: items.length, countKey: countKey),
                  CardGroup(
                    children: [
                      for (final (i, c) in items.indexed) ...[
                        if (i > 0) const RowDivider(),
                        ChallengeRow(challenge: c, store: store),
                      ],
                    ],
                  ),
                ],
              );

              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.page),
                    child: Text('가족이 해 볼 만한 일을 보내고, 해내면 함께 칭찬해요. 하실지는 가족이 직접 정해요.', style: t.textTheme.bodySmall),
                  ),
                  if (store.links.length >= 2) ...[const SizedBox(height: 12), FamilyFilterBar(store: store)],
                  const SizedBox(height: Space.gap),
                  // 이번 달 기록 + 도전 보내기
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: Space.page - 4),
                    padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
                    decoration: cardDecoration(context),
                    child: Row(
                      children: [
                        IconBadge(
                          Icons.emoji_events_rounded,
                          color: t.brightness == Brightness.light ? const Color(0xFF8A5A00) : k.brand,
                          background: t.colorScheme.secondaryContainer,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('이번 달 해낸 도전', style: t.textTheme.bodySmall?.copyWith(color: k.textSub)),
                              Text(
                                '$thisMonth개',
                                key: const Key('challenges_this_month'),
                                style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                        ),
                        FilledButton.icon(
                          key: const Key('challenges_send'),
                          style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
                          onPressed: store.links.isEmpty
                              ? null
                              : () => openSendChallenge(context, store, elderId: elder),
                          icon: const Icon(Icons.send_rounded, size: 18),
                          label: const Text('도전 보내기'),
                        ),
                      ],
                    ),
                  ),
                  if (all.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: EmptyState(
                        icon: Icons.flag_outlined,
                        title: '아직 보낸 도전이 없어요',
                        message: '"도전 보내기"로 가족이 해 볼 만한 일을 보내 보세요.',
                      ),
                    ),
                  if (waiting.isNotEmpty) group('칭찬을 기다려요', waiting, const ValueKey('challenges_waiting_count')),
                  if (doing.isNotEmpty) group('도전 중', doing, const ValueKey('challenges_doing_count')),
                  if (sent.isNotEmpty) group('보낸 도전', sent, const ValueKey('challenges_sent_count')),
                  if (past.isNotEmpty) group('지난 도전', past, const ValueKey('challenges_past_count')),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
