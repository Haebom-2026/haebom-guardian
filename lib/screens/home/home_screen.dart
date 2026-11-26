import 'package:material_ui/material_ui.dart';

import '../../app/dependencies.dart';
import '../../app/routes.dart';
import '../../app/theme.dart';
import '../../controllers/guardian_store.dart';
import '../../models/approval_request.dart';
import '../../models/family_link.dart';
import '../../models/notification_item.dart';
import '../../models/sensitivity.dart';
import '../../repositories/guardian_repository.dart';
import '../../utils/formatters.dart';
import '../../widgets/common.dart';

/// 홈: 처음 보는 보호자도 바로 알 수 있게
/// ① 누구의 정보인지(가족) ② 지금 확인할 일(도움이 필요한 일) ③ 어떤 알림·요청이 있었는지(확인하지 않은 알림·최근 소식)
///
/// 같은 항목은 한 곳에만 나온다: 확인 전 SOS·도움 필요 → "도움이 필요한 일", 확인 전 일반 알림 → "확인하지 않은 알림",
/// 나머지(확인한 알림·처리된 승인) → "최근 소식". 승인·거절은 홈에서 하지 않고 상세 화면에서 내용을 보고 결정한다.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const _recentLimit = 3;
  static const _unreadLimit = 3;

  @override
  Widget build(BuildContext context) {
    final deps = AppScope.of(context);
    final store = deps.store;
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            BrandMark(size: 34),
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
          const SizedBox(width: 8),
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
            if (store.links.isEmpty) return const _NoFamily();

            final elder = store.selectedElderId;
            void openNotification(String id) => Navigator.pushNamed(context, AppRoutes.notificationDetail, arguments: id);
            void openApproval(String id) => Navigator.pushNamed(context, AppRoutes.approvalDetail, arguments: id);

            // ── 데이터 나누기 (중복 없음)
            final unread = store.notificationsFor(elderId: elder, unreadOnly: true);
            final sos = unread.where((n) => n.risk == RiskTone.danger).toList();
            final stuck = unread.where((n) => n.risk == RiskTone.caution).toList();
            final pending = store.approvalsFor(elderId: elder, status: ApprovalStatus.pending);
            final unreadNormal = unread.where((n) => n.risk == RiskTone.normal).toList();
            final now = store.now();
            final recent = <_News>[
              for (final n in store.notificationsFor(elderId: elder).where((n) => !store.isUnread(n))) _News.notification(n),
              for (final a in store.approvalsFor(elderId: elder).where((a) => a.effectiveStatus(now) != ApprovalStatus.pending))
                _News.approval(a),
            ]..sort((a, b) => b.at.compareTo(a.at));
            final helpCount = sos.length + stuck.length + pending.length;

            return ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                // ① 누구의 정보인지
                _FamilyHeader(store: store),
                if (store.links.length >= 2) ...[
                  const SizedBox(height: 12),
                  FamilyFilterBar(store: store),
                ],

                // ② 도움이 필요한 일: SOS → 도움 필요 → 승인 대기
                SectionHeader('도움이 필요한 일', count: helpCount == 0 ? null : helpCount, countKey: const ValueKey('help_count')),
                if (helpCount == 0)
                  const _NothingToCheck()
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.page),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final n in [...sos, ...stuck])
                          Padding(
                            padding: const EdgeInsets.only(bottom: Space.gap),
                            child: _notificationHelp(context, store, n, () => openNotification(n.id)),
                          ),
                        for (final a in pending)
                          Padding(
                            padding: const EdgeInsets.only(bottom: Space.gap),
                            child: _approvalHelp(context, store, a, () => openApproval(a.id)),
                          ),
                      ],
                    ),
                  ),

                // ③ 확인하지 않은 알림 (도움이 필요한 일에 나온 것은 제외)
                SectionHeader(
                  '확인하지 않은 알림',
                  count: unreadNormal.length,
                  countKey: const ValueKey('unread_count'),
                  actionLabel: '알림 보기',
                  onAction: () => deps.tabIndex.value = 1,
                ),
                if (unreadNormal.isEmpty)
                  const _Quiet('확인하지 않은 알림이 없어요.')
                else
                  for (final (i, n) in unreadNormal.take(_unreadLimit).indexed) ...[
                    if (i > 0) const RowDivider(),
                    NotificationTile(item: n, store: store, onTap: () => openNotification(n.id)),
                  ],
                if (unreadNormal.length > _unreadLimit)
                  _MoreLink('확인하지 않은 알림 ${unreadNormal.length - _unreadLimit}건 더 보기', () => deps.tabIndex.value = 1),

                // ④ 최근 소식 (확인한 알림·처리된 승인, 최대 3건)
                const SectionHeader('최근 소식'),
                if (recent.isEmpty)
                  const _Quiet('최근 소식이 없어요.')
                else
                  for (final (i, item) in recent.take(_recentLimit).indexed) ...[
                    if (i > 0) const RowDivider(),
                    item.notification != null
                        ? NotificationTile(
                            item: item.notification!, store: store, onTap: () => openNotification(item.notification!.id))
                        : ApprovalCard(request: item.approval!, store: store, onTap: () => openApproval(item.approval!.id)),
                  ],
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.page),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          key: const Key('home_all_notifications'),
                          onPressed: () => deps.tabIndex.value = 1,
                          child: const Text('알림 기록'),
                        ),
                      ),
                      const SizedBox(width: Space.gap),
                      Expanded(
                        child: OutlinedButton(
                          key: const Key('home_all_approvals'),
                          onPressed: () => deps.tabIndex.value = 2,
                          child: const Text('승인 기록'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Space.section),
                const _PrivacyNote(),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 확인 전 SOS·사기 의심(긴급) / 도움 필요(주의)
  Widget _notificationHelp(BuildContext context, GuardianStore store, NotificationItem n, VoidCallback onOpen) {
    final t = Theme.of(context);
    return HelpCard(
      key: ValueKey('help_${n.id}'),
      tone: n.risk,
      icon: notificationItemIcon(n),
      tag: '${notificationLabel(n)} · ${formatAgo(n.createdAt, store.now())}',
      title: notificationMessage(n, store.nameOf(n.elderId)),
      lines: [if (n.reasonText != null) Text('이유: ${n.reasonText}', style: t.textTheme.bodyMedium)],
      buttonLabel: '확인하기',
      buttonKey: ValueKey('help_open_${n.id}'),
      onPressed: onOpen,
    );
  }

  /// 승인 대기: 요청 내용 + 남은 시간, "요청 확인하기" → 승인 상세 (홈에서 바로 승인·거절하지 않음)
  Widget _approvalHelp(BuildContext context, GuardianStore store, ApprovalRequest a, VoidCallback onOpen) {
    final t = Theme.of(context);
    final k = HaebomTokens.of(context);
    return CountdownBuilder(
      builder: (context) => HelpCard(
        key: ValueKey('help_${a.id}'),
        tone: RiskTone.caution,
        icon: Icons.hourglass_top_rounded,
        tag: '승인 대기 · ${formatRemaining(a.remaining(store.now()))} 남음',
        title: '${store.nameOf(a.elderId)} · ${a.appName}',
        lines: [Text(ApprovalActions.label(a.action), style: t.textTheme.bodyLarge?.copyWith(color: k.text))],
        buttonLabel: '요청 확인하기',
        buttonKey: ValueKey('help_open_${a.id}'),
        onPressed: onOpen,
      ),
    );
  }
}

/// 최근 소식 한 건 (알림 또는 처리된 승인)
class _News {
  _News.notification(NotificationItem this.notification)
      : approval = null,
        at = notification.createdAt;
  _News.approval(ApprovalRequest this.approval)
      : notification = null,
        at = approval.respondedAt ?? approval.createdAt;
  final NotificationItem? notification;
  final ApprovalRequest? approval;
  final DateTime at;
}

/// 누구의 정보를 보고 있는지: 한 명이면 "어머니 (김순자)", 여러 명이면 호칭 목록 + 가족 선택 칩
class _FamilyHeader extends StatelessWidget {
  const _FamilyHeader({required this.store});
  final GuardianStore store;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final links = store.links;
    final selected = store.selectedElderId == null ? null : store.linkFor(store.selectedElderId!);
    final FamilyLink? one = selected ?? (links.length == 1 ? links.first : null);
    final title = one != null ? '${one.displayName} (${one.elderName})' : links.map((l) => l.displayName).join(', ');
    final latest = store.notificationsFor(elderId: store.selectedElderId).firstOrNull;
    final sub = [
      '연결된 가족 ${links.length}명',
      if (latest != null) '최근 알림 ${formatAgo(latest.createdAt, store.now())}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.page, 4, Space.page, 0),
      child: Row(
        children: [
          if (one != null)
            FamilyAvatar(avatarText(one.elderName, fallback: one.displayName), radius: 24)
          else
            // 여러 명: 겹친 이름 대신 가족 아이콘 하나 (이름은 오른쪽 제목에)
            ExcludeSemantics(
              child: CircleAvatar(
                radius: 24,
                backgroundColor: t.colorScheme.secondaryContainer,
                foregroundColor: t.colorScheme.onSecondaryContainer,
                child: const Icon(Icons.people_alt_rounded, size: 26),
              ),
            ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.textTheme.titleLarge, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(sub, style: t.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 확인할 요청이 없을 때. 부모님의 활동이 모두 안전하다는 뜻으로 표현하지 않는다.
class _NothingToCheck extends StatelessWidget {
  const _NothingToCheck();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final k = HaebomTokens.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: Space.page),
      padding: const EdgeInsets.all(Space.card),
      decoration: BoxDecoration(color: k.subtle, borderRadius: BorderRadius.circular(Space.radius)),
      child: Row(
        children: [
          Icon(Icons.verified_user_outlined, color: k.primary, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('지금 확인할 요청이 없어요', style: t.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text('새로운 승인 요청이 오면 알려드릴게요.', style: t.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 빈 섹션 한 줄 안내
class _Quiet extends StatelessWidget {
  const _Quiet(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.page, vertical: 8),
        child: Text(text, style: Theme.of(context).textTheme.bodySmall),
      );
}

class _MoreLink extends StatelessWidget {
  const _MoreLink(this.label, this.onTap);
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.page - 8),
        child: Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: onTap, child: Text('$label 〉'))),
      );
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.page),
        child: Text(
          '가족이 직접 동의한 알림과 요청만 표시됩니다. 위치나 실시간 접속 상태는 수집하지 않습니다.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
}

/// 연결된 가족이 없을 때
class _NoFamily extends StatelessWidget {
  const _NoFamily();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(Space.page),
      children: [
        const SizedBox(height: 24),
        const Center(child: BrandMark(size: 64)),
        const SizedBox(height: 20),
        Text('아직 연결된 가족이 없습니다', textAlign: TextAlign.center, style: t.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          '가족의 해봄 앱에서 [가족 연결]을 누르면 6자리 코드가 나옵니다.\n그 코드를 입력하면 연결됩니다.',
          textAlign: TextAlign.center,
          style: t.textTheme.bodySmall,
        ),
        const SizedBox(height: Space.section),
        FilledButton(
          onPressed: () => Navigator.pushNamed(context, AppRoutes.connectFamily),
          child: const Text('가족 연결하기'),
        ),
      ],
    );
  }
}
