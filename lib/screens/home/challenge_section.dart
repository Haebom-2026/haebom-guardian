import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../controllers/guardian_store.dart';
import '../../models/challenge.dart';
import '../../repositories/guardian_repository.dart';
import '../../utils/formatters.dart';
import '../../widgets/common.dart';

/// 홈 "가족의 도전" 섹션 (💡 제안 단계, Mock 모드에서만 보인다).
///
/// 위쪽(도움이 필요한 일·확인하지 않은 알림)은 꼭 확인할 일, 이 섹션은 즐거운 소식이다.
/// 알림·SOS는 게임처럼 만들지 않고, 도전만 따로 이 섹션에서 보여 준다.
/// 보여 주는 순서: 해냈는데 내가 아직 칭찬 안 한 것 → 도전 중 → 칭찬까지 한 것. 해낸 도전은 7일 동안만.
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
    int rank(Challenge c) => c.isDone ? (c.cheeredBy(me) ? 2 : 0) : 1;
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
          actionLabel: '추천하기',
          onAction: () => showSuggestChallengeSheet(context, store, elderId: elderId),
        ),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.page, vertical: 8),
            child: Text('진행 중인 도전이 없어요. 가족이 해 볼 만한 일을 추천해 보세요.', style: Theme.of(context).textTheme.bodySmall),
          )
        else
          CardGroup(
            children: [
              for (final (i, c) in items.take(limit).indexed) ...[
                if (i > 0) const RowDivider(),
                _ChallengeRow(challenge: c, store: store),
              ],
            ],
          ),
      ],
    );
  }
}

class _ChallengeRow extends StatelessWidget {
  const _ChallengeRow({required this.challenge, required this.store});
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

    final String sub;
    if (c.isDone) {
      final others = c.cheers.keys.where((g) => g != me).length;
      sub = [
        '해냈어요 🎉 ${formatAgo(c.completedAt!, now)}',
        if (c.withHelp) '도우미 안내와 함께',
        if (others > 0) '가족 $others명이 칭찬했어요',
      ].join(' · ');
    } else {
      sub = '도전 중 · ${c.suggestedBy == me ? '내가' : '가족이'} ${formatAgo(c.createdAt, now)} 추천';
    }

    return Padding(
      key: ValueKey('challenge_${c.id}'),
      padding: const EdgeInsets.symmetric(horizontal: Space.page, vertical: 12),
      child: Row(
        children: [
          IconBadge(
            c.isDone ? Icons.emoji_events_rounded : Icons.flag_rounded,
            color: c.isDone ? (light ? const Color(0xFF8A5A00) : k.brand) : k.textSub,
            background: c.isDone ? t.colorScheme.secondaryContainer : k.subtle,
          ),
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
                Text(sub, style: t.textTheme.bodySmall?.copyWith(color: k.textSub)),
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

Future<T?> _sheet<T>(BuildContext context, Widget Function(BuildContext ctx) builder) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  useSafeArea: true,
  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
  builder: (ctx) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Space.page + 4, 0, Space.page, Space.page),
      child: builder(ctx),
    ),
  ),
);

/// 도전 추천하기: 어떤 가족에게(여럿일 때) 어떤 도전을. 이미 도전 중인 것은 고를 수 없다.
Future<void> showSuggestChallengeSheet(BuildContext context, GuardianStore store, {String? elderId}) async {
  if (store.links.isEmpty) return;
  var target = elderId ?? store.links.first.elderId;
  final picked = await _sheet<(String, ChallengeTemplate)>(
    context,
    (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final t = Theme.of(ctx);
        final k = HaebomTokens.of(ctx);
        final open = store.challengesFor(elderId: target).where((c) => !c.isDone).map((c) => c.templateId).toSet();
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text('어떤 도전을 추천할까요?', style: t.textTheme.titleLarge?.copyWith(fontSize: 21)),
            ),
            const SizedBox(height: 8),
            Text(
              '하실지는 ${store.nameOf(target)}가 직접 정해요. 안 하셔도 따로 알림이 가지 않아요.',
              style: t.textTheme.bodyMedium?.copyWith(color: k.textSub),
            ),
            if (elderId == null && store.links.length >= 2) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final l in store.links)
                    ChoiceChip(
                      label: Text(l.displayName),
                      selected: target == l.elderId,
                      onSelected: (_) => setState(() => target = l.elderId),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            for (final tpl in ChallengeTemplate.all)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: open.contains(tpl.id) ? k.subtle : k.card,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Space.radius),
                    side: BorderSide(color: k.divider),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    key: ValueKey('suggest_${tpl.id}'),
                    enabled: !open.contains(tpl.id),
                    title: Text(tpl.title, style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    subtitle: Text('${tpl.appName} · ${open.contains(tpl.id) ? '이미 도전 중이에요' : tpl.hint}'),
                    trailing: open.contains(tpl.id) ? null : const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.pop(ctx, (target, tpl)),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
  if (picked == null) return;
  final (elder, tpl) = picked;
  try {
    await store.suggestChallenge(elder, tpl.id);
    if (context.mounted) showMessage(context, '${store.nameOf(elder)}께 "${tpl.title}"를 추천했어요.');
  } on RepositoryException catch (e) {
    if (context.mounted) showMessage(context, e.userMessage);
  }
}

/// 칭찬 보내기: 정해 둔 문구 중 하나를 고른다 (어르신 폰에 그대로 전달)
Future<void> showCheerSheet(BuildContext context, GuardianStore store, Challenge c) async {
  final name = store.nameOf(c.elderId);
  final message = await _sheet<String>(context, (ctx) {
    final t = Theme.of(ctx);
    final k = HaebomTokens.of(ctx);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(header: true, child: Text('$name께 칭찬 보내기', style: t.textTheme.titleLarge?.copyWith(fontSize: 21))),
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
    );
  });
  if (message == null) return;
  try {
    await store.cheerChallenge(c.id, message);
    if (context.mounted) showMessage(context, '$name께 칭찬을 보냈어요.');
  } on RepositoryException catch (e) {
    if (context.mounted) showMessage(context, e.userMessage);
  }
}
