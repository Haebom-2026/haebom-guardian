import 'package:material_ui/material_ui.dart';

import '../../app/dependencies.dart';
import '../../app/routes.dart';
import '../../app/theme.dart';
import '../../models/approval_request.dart';
import '../../repositories/guardian_repository.dart';
import '../../widgets/common.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final deps = AppScope.of(context);
    final store = deps.store;
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const Row(
          children: [
            SproutMark(size: 34),
            SizedBox(width: 10),
            Flexible(child: Text('해봄 가족', overflow: TextOverflow.ellipsis)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '설정',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.pushNamed(context, AppRoutes.settings),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            if (!store.isLoaded) {
              // 서버가 읽기를 거부하거나 연결이 안 되면 무한 로딩 대신 안내한다
              final e = store.lastError;
              if (e != null) {
                return ListView(children: [
                  EmptyState(
                    icon: Icons.cloud_off_rounded,
                    title: '가족 정보를 불러오지 못했습니다',
                    message: e is RepositoryException && e.code == RepositoryErrorCode.permissionDenied
                        ? '서버에서 아직 이 계정의 접근을 허용하지 않았습니다. 서버 준비가 끝나면 자동으로 다시 불러옵니다.'
                        : '네트워크 연결을 확인해 주세요.',
                  ),
                ]);
              }
              return const Center(child: CircularProgressIndicator());
            }
            if (store.links.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const _SloganCard(),
                  const SizedBox(height: 16),
                  const EmptyState(
                    icon: Icons.link_rounded,
                    title: '아직 연결된 가족이 없습니다',
                    message: '가족의 해봄 앱에서 발급한 6자리 연결 코드를 입력해 주세요.',
                  ),
                  FilledButton.icon(
                    onPressed: () => Navigator.pushNamed(context, AppRoutes.connectFamily),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('가족 연결하기'),
                  ),
                ],
              );
            }
            final elder = store.selectedElderId;
            final pending = store.approvalsFor(elderId: elder, status: ApprovalStatus.pending);
            final recentApprovals = store.approvalsFor(elderId: elder).take(3).toList();
            final shownApprovals = pending.isNotEmpty ? pending : recentApprovals;
            final recent = store.notificationsFor(elderId: elder).take(4).toList();
            return ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                const Padding(padding: EdgeInsets.fromLTRB(16, 4, 16, 12), child: _SloganCard()),
                FamilyFilterBar(store: store),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: _FamilySummary(names: store.links.map((l) => l.displayName).toList()),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: _StatsRow(
                    today: store.todayCount(elderId: elder),
                    unread: store.unreadCount(elderId: elder),
                    pending: store.pendingCount(elderId: elder),
                    onTapUnread: () => deps.tabIndex.value = 1,
                    onTapPending: () => deps.tabIndex.value = 2,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SectionHeader(pending.isNotEmpty ? '응답이 필요한 승인 요청' : '최근 승인 요청',
                          actionLabel: '전체 보기', onAction: () => deps.tabIndex.value = 2),
                      if (shownApprovals.isEmpty)
                        const Card(child: EmptyState(icon: Icons.verified_user_outlined, title: '승인 요청이 없습니다'))
                      else
                        for (final a in shownApprovals)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: ApprovalCard(
                              request: a,
                              store: store,
                              onTap: () => Navigator.pushNamed(context, AppRoutes.approvalDetail, arguments: a.id),
                            ),
                          ),
                      SectionHeader('최근 활동', actionLabel: '전체 보기', onAction: () => deps.tabIndex.value = 1),
                      if (recent.isEmpty)
                        const Card(child: EmptyState(icon: Icons.notifications_none_rounded, title: '최근 활동이 없습니다'))
                      else
                        for (final n in recent)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: NotificationTile(
                              item: n,
                              store: store,
                              onTap: () => Navigator.pushNamed(context, AppRoutes.notificationDetail, arguments: n.id),
                            ),
                          ),
                      const SizedBox(height: 8),
                      Text(
                        '가족의 위치나 실시간 접속 상태는 수집하지 않습니다.\n가족이 직접 동의한 알림만 표시됩니다.',
                        textAlign: TextAlign.center,
                        style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SloganCard extends StatelessWidget {
  const _SloganCard();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.colorScheme.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.wb_sunny_outlined, color: t.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('오늘도, 스스로 해봄.',
                    style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: t.colorScheme.onPrimaryContainer)),
                const SizedBox(height: 2),
                Text('가족이 스스로 해낼 수 있도록, 필요한 순간에만 곁에 있어 주세요.',
                    style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onPrimaryContainer)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FamilySummary extends StatelessWidget {
  const _FamilySummary({required this.names});
  final List<String> names;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Row(
      children: [
        for (final n in names.take(4))
          Padding(padding: const EdgeInsets.only(right: 6), child: FamilyAvatar(n, radius: 16)),
        const SizedBox(width: 4),
        Expanded(
          child: Text('연결된 가족 ${names.length}명 · ${names.join(', ')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
        ),
      ],
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.today,
    required this.unread,
    required this.pending,
    required this.onTapUnread,
    required this.onTapPending,
  });
  final int today;
  final int unread;
  final int pending;
  final VoidCallback onTapUnread;
  final VoidCallback onTapPending;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Row(
      children: [
        Expanded(child: _StatTile(label: '오늘 알림', value: today, color: t.colorScheme.primary, onTap: onTapUnread)),
        const SizedBox(width: 8),
        Expanded(child: _StatTile(label: '확인 전', value: unread, color: t.colorScheme.error, onTap: onTapUnread)),
        const SizedBox(width: 8),
        Expanded(
          child: _StatTile(
            label: '승인 대기',
            value: pending,
            color: StatusStyle.of(ApprovalStatus.pending, t.brightness).color,
            onTap: onTapPending,
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, required this.color, required this.onTap});
  final String label;
  final int value;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Semantics(
          label: '$label $value',
          excludeSemantics: true,
          button: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
            child: Column(
              children: [
                FittedBox(
                  child: Text('$value',
                      key: ValueKey('stat_$label'),
                      style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: color)),
                ),
                const SizedBox(height: 2),
                FittedBox(child: Text(label, style: t.textTheme.bodySmall)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
