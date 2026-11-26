import 'package:material_ui/material_ui.dart';

import '../../app/dependencies.dart';
import '../../app/theme.dart';
import '../../controllers/guardian_store.dart';
import '../../models/challenge.dart';
import '../../repositories/guardian_repository.dart';
import '../../utils/formatters.dart';
import '../../widgets/common.dart';
import '../home_shell.dart';
import 'send_challenge_screen.dart';

/// 홈 "가족의 도전" 섹션 (💡 제안 단계, Mock 모드에서만 보인다).
///
/// 위쪽(도움이 필요한 일·확인하지 않은 알림)은 꼭 확인할 일, 이 섹션은 즐거운 소식이다.
/// 알림·SOS는 게임처럼 만들지 않고, 도전만 따로 이 섹션에서 보여 준다.
/// 순서: 해냈는데 내가 아직 칭찬 안 한 것 → 도전 중 → 보냄 → 칭찬까지 한 것. 해낸 도전은 7일 동안만.
class ChallengeSection extends StatelessWidget {
  const ChallengeSection({super.key, required this.store, required this.elderId});
  final GuardianStore store;

  /// 가족 필터 (null = 전체)
  final String? elderId;

  static const limit = 3;
  static const doneVisibleFor = Duration(days: 7);

  @override
  Widget build(BuildContext context) {
    final me = store.guardianId;
    final now = store.now();
    int rank(Challenge c) => switch (c.status) {
      ChallengeStatus.done => c.cheeredBy(me) ? 3 : 0,
      ChallengeStatus.accepted => 1,
      ChallengeStatus.sent || ChallengeStatus.later => 2,
    };
    final items =
        store.challengesFor(elderId: elderId).where((c) => !c.isDone || now.difference(c.at) < doneVisibleFor).toList()
          ..sort((a, b) {
            final r = rank(a).compareTo(rank(b));
            return r != 0 ? r : b.at.compareTo(a.at);
          });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          '가족의 도전',
          actionLabel: '도전 보내기',
          onAction: () => openSendChallenge(context, store, elderId: elderId),
        ),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.page, vertical: 8),
            child: Text('진행 중인 도전이 없어요. 가족이 해 볼 만한 일을 보내 보세요.', style: Theme.of(context).textTheme.bodySmall),
          )
        else
          CardGroup(
            children: [
              for (final (i, c) in items.take(limit).indexed) ...[
                if (i > 0) const RowDivider(),
                ChallengeRow(challenge: c, store: store),
              ],
            ],
          ),
        // 모든 도전(지난 도전 포함)은 도전 탭에서
        if (store.challengesFor(elderId: elderId).length > items.take(limit).length)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.page - 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('home_all_challenges'),
                onPressed: () => AppScope.of(context).tabIndex.value = HomeShell.challengesTab,
                child: const Text('모든 도전 보기 〉'),
              ),
            ),
          ),
      ],
    );
  }
}

class ChallengeRow extends StatelessWidget {
  const ChallengeRow({super.key, required this.challenge, required this.store});
  final Challenge challenge;
  final GuardianStore store;

  @override
  Widget build(BuildContext context) {
    final c = challenge;
    final t = Theme.of(context);
    final k = HaebomTokens.of(context);
    final me = store.guardianId;
    final now = store.now();
    final light = t.brightness == Brightness.light;
    final by = c.suggestedBy == me ? '내가' : '가족이';
    final cheeredByOthers = c.cheers.keys.where((g) => g != me).length;

    // "다음에 할게요"(later)는 보호자에게 "보냄"과 똑같이 보인다 (거절로 알리지 않음)
    final (IconData icon, Color color, Color bg, String sub) = switch (c.status) {
      ChallengeStatus.done => (
        Icons.emoji_events_rounded,
        light ? const Color(0xFF8A5A00) : k.brand,
        t.colorScheme.secondaryContainer,
        [
          '해냈어요 🎉 ${formatAgo(c.completedAt!, now)}',
          if (c.withHelp) '도우미 안내와 함께',
          if (cheeredByOthers > 0) '가족 $cheeredByOthers명이 칭찬했어요',
        ].join(' · '),
      ),
      ChallengeStatus.accepted => (
        Icons.directions_run_rounded,
        k.primary,
        t.colorScheme.primaryContainer,
        '도전 중 · 해 보기로 하셨어요',
      ),
      ChallengeStatus.sent ||
      ChallengeStatus.later => (Icons.send_rounded, k.textSub, k.subtle, '보냄 · $by ${formatAgo(c.createdAt, now)}'),
    };

    return Padding(
      key: ValueKey('challenge_${c.id}'),
      padding: const EdgeInsets.symmetric(horizontal: Space.page, vertical: 12),
      child: Row(
        children: [
          IconBadge(icon, color: color, background: bg),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${store.nameOf(c.elderId)} · ${c.title}',
                  style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  key: ValueKey('challenge_status_${c.id}'),
                  style: t.textTheme.bodySmall?.copyWith(color: k.textSub),
                ),
                // 버튼은 글 아래에 (오른쪽에 두면 제목·설명이 좁아져 여러 줄로 접힌다)
                if (c.isDone) ...[
                  const SizedBox(height: 10),
                  if (c.cheeredBy(me))
                    Text(
                      '칭찬 보냄 ✓',
                      key: ValueKey('cheered_${c.id}'),
                      style: t.textTheme.bodySmall?.copyWith(color: k.primary, fontWeight: FontWeight.w700),
                    )
                  else
                    FilledButton.icon(
                      key: ValueKey('cheer_${c.id}'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(64, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                      ),
                      onPressed: () => showCheerSheet(context, store, c),
                      icon: const Icon(Icons.favorite_rounded, size: 18),
                      label: const Text('칭찬하기'),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 칭찬 보내기: 정해 둔 문구 중 하나를 고른다 (어르신 폰에 그대로 전달)
Future<void> showCheerSheet(BuildContext context, GuardianStore store, Challenge c) async {
  final name = store.nameOf(c.elderId);
  final message = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (ctx) {
      final t = Theme.of(ctx);
      final k = HaebomTokens.of(ctx);
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.page + 4, 0, Space.page, Space.page),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text('$name께 칭찬 보내기', style: t.textTheme.titleLarge?.copyWith(fontSize: 21)),
              ),
              const SizedBox(height: 8),
              Text(c.title, style: t.textTheme.bodyMedium?.copyWith(color: k.textSub)),
              const SizedBox(height: 16),
              for (final (i, m) in cheerMessages.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlinedButton(
                    key: ValueKey('cheer_msg_$i'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                    ),
                    onPressed: () => Navigator.pop(ctx, m),
                    child: Text(m),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
  if (message == null) return;
  try {
    await store.cheerChallenge(c.id, message);
    if (context.mounted) showMessage(context, '$name께 칭찬을 보냈어요.');
  } on RepositoryException catch (e) {
    if (context.mounted) showMessage(context, e.userMessage);
  }
}
