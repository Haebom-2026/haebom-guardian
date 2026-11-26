import 'dart:math' as math;

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
import '../onboarding/notification_permission.dart';

/// 홈: 처음 보는 보호자도 바로 알 수 있게
/// ① 누구의 정보인지(가족) ② 지금 확인할 일(도움이 필요한 일) ③ 어떤 알림·요청이 있었는지(확인하지 않은 알림·최근 소식)
///
/// 같은 항목은 한 곳에만 나온다: 확인 전 SOS·도움 필요 → "도움이 필요한 일", 확인 전 일반 알림 → "확인하지 않은 알림",
/// 나머지(확인한 알림·처리된 승인) 중 오늘·어제 것 → "최근 소식". 승인·거절은 홈에서 하지 않고 상세 화면에서 내용을 보고 결정한다.
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
      // 알림 권한이 꺼져 있으면 맨 위에 고정 (가족 연결 전·오류 화면에서도 보이도록, SOS를 놓치지 않게)
      body: Column(
        children: [
          const NotificationOffBanner(),
          Expanded(
            child: RefreshIndicator(
              // 아래로 당기면 서버에서 다시 조회 (서버 모드). Mock은 실시간이라 바로 끝난다
              onRefresh: store.refresh,
              child: SafeArea(
                top: false,
                child: ListenableBuilder(
                  listenable: store,
                  builder: (context, _) {
                    if (!store.isLoaded) {
                      // 서버가 읽기를 거부하거나 연결이 안 되면 무한 로딩 대신 안내한다
                      final e = store.lastError;
                      if (e != null) {
                        return ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            EmptyState(
                              icon: Icons.cloud_off_rounded,
                              title: '가족 정보를 불러오지 못했습니다',
                              message: e is RepositoryException && e.code == RepositoryErrorCode.permissionDenied
                                  ? '서버에서 아직 이 계정의 접근을 허용하지 않았습니다. 서버 준비가 끝나면 자동으로 다시 불러옵니다.'
                                  : '네트워크 연결을 확인해 주세요.',
                            ),
                          ],
                        );
                      }
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (store.links.isEmpty) return const _NoFamily();

                    final elder = store.selectedElderId;
                    void openNotification(String id) =>
                        Navigator.pushNamed(context, AppRoutes.notificationDetail, arguments: id);
                    void openApproval(String id) =>
                        Navigator.pushNamed(context, AppRoutes.approvalDetail, arguments: id);

                    // ── 데이터 나누기 (중복 없음)
                    final unread = store.notificationsFor(elderId: elder, unreadOnly: true);
                    final sos = unread.where((n) => n.risk == RiskTone.danger).toList();
                    final stuck = unread.where((n) => n.risk == RiskTone.caution).toList();
                    final pending = store.approvalsFor(elderId: elder, status: ApprovalStatus.pending);
                    final unreadNormal = unread.where((n) => n.risk == RiskTone.normal).toList();
                    final now = store.now();
                    final recent =
                        <_News>[
                            for (final n in store.notificationsFor(elderId: elder).where((n) => !store.isUnread(n)))
                              _News.notification(n),
                            for (final a
                                in store
                                    .approvalsFor(elderId: elder)
                                    .where((a) => a.effectiveStatus(now) != ApprovalStatus.pending))
                              _News.approval(a),
                          ]
                          ..removeWhere((x) => x.at.isBefore(DateTime(now.year, now.month, now.day - 1)))
                          ..sort((a, b) => b.at.compareTo(a.at));
                    final helpCount = sos.length + stuck.length + pending.length;
                    final todayCount = store
                        .notificationsFor(elderId: elder)
                        .where((n) => isSameDay(n.createdAt, now))
                        .length;

                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 32),
                      children: [
                        // 첫 문구: 지금 확인할 일이 몇 건인지 (햇살 그림은 장식)
                        _HomeHero(count: helpCount + unreadNormal.length, today: todayCount, now: now),

                        // ① 누구의 정보인지
                        _FamilyHeader(store: store),
                        if (store.links.length >= 2) ...[const SizedBox(height: 12), FamilyFilterBar(store: store)],

                        // ② 도움이 필요한 일: SOS → 도움 필요 → 승인 대기
                        SectionHeader(
                          '도움이 필요한 일',
                          count: helpCount == 0 ? null : helpCount,
                          countKey: const ValueKey('help_count'),
                        ),
                        if (helpCount == 0)
                          const _NothingToCheck()
                        else
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: Space.page - 4),
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
                          CardGroup(
                            children: [
                              for (final (i, n) in unreadNormal.take(_unreadLimit).indexed) ...[
                                if (i > 0) const RowDivider(),
                                NotificationTile(item: n, store: store, onTap: () => openNotification(n.id)),
                              ],
                            ],
                          ),
                        if (unreadNormal.length > _unreadLimit)
                          _MoreLink(
                            '확인하지 않은 알림 ${unreadNormal.length - _unreadLimit}건 더 보기',
                            () => deps.tabIndex.value = 1,
                          ),

                        // ④ 최근 소식 (오늘·어제 확인한 알림·처리된 승인, 최대 3건. 더 있으면 알림 탭으로)
                        const SectionHeader('최근 소식'),
                        if (recent.isEmpty)
                          const _Quiet('오늘과 어제 처리한 소식이 없어요.')
                        else
                          CardGroup(
                            children: [
                              for (final (i, item) in recent.take(_recentLimit).indexed) ...[
                                if (i > 0) const RowDivider(),
                                item.notification != null
                                    ? NotificationTile(
                                        item: item.notification!,
                                        store: store,
                                        onTap: () => openNotification(item.notification!.id),
                                      )
                                    : ApprovalCard(
                                        request: item.approval!,
                                        store: store,
                                        onTap: () => openApproval(item.approval!.id),
                                      ),
                              ],
                            ],
                          ),
                        if (recent.length > _recentLimit)
                          _MoreLink('최근 소식 ${recent.length - _recentLimit}건 더 보기', () => deps.tabIndex.value = 1),
                        const SizedBox(height: Space.section),
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
            ),
          ),
        ],
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
  _News.notification(NotificationItem this.notification) : approval = null, at = notification.createdAt;
  _News.approval(ApprovalRequest this.approval) : notification = null, at = approval.respondedAt ?? approval.createdAt;
  final NotificationItem? notification;
  final ApprovalRequest? approval;
  final DateTime at;
}

/// 홈 첫 문구: "확인할 일이 N건 있어요" + 날짜. 오른쪽 위 햇살은 장식(낭독 안 함).
/// 확인할 일이 없을 때도 '안전하다'고 말하지 않는다.
class _HomeHero extends StatelessWidget {
  const _HomeHero({required this.count, required this.today, required this.now});
  final int count;

  /// 오늘 온 알림 수 (확인한 것 포함). 따로 숫자 카드를 두지 않고 첫 문구 아래 한 줄로 보여 준다
  final int today;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final k = HaebomTokens.of(context);
    const w = ['월', '화', '수', '목', '금', '토', '일'];
    final headline = t.textTheme.headlineSmall?.copyWith(fontSize: 27, fontWeight: FontWeight.w700, height: 1.35);
    return ClipRect(
      child: Stack(
        children: [
          const Positioned(top: -50, right: -56, child: _Sun(size: 210)),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.page, 8, 120, Space.section),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${now.month}월 ${now.day}일 ${w[now.weekday - 1]}요일',
                  style: t.textTheme.bodyMedium?.copyWith(color: k.textSub, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Semantics(
                  header: true,
                  child: count == 0
                      ? Text('지금은 확인할\n일이 없어요', style: headline)
                      : Text.rich(
                          TextSpan(
                            children: [
                              const TextSpan(text: '확인할 일이\n'),
                              TextSpan(
                                text: '$count건',
                                style: TextStyle(color: k.primary),
                              ),
                              const TextSpan(text: ' 있어요'),
                            ],
                          ),
                          style: headline,
                        ),
                ),
                const SizedBox(height: 8),
                Text(
                  today == 0 ? '오늘 온 알림은 없어요' : '오늘 알림 $today건',
                  key: const Key('home_today_count'),
                  style: t.textTheme.bodyMedium?.copyWith(color: k.textSub),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 장식용 햇살 (동심원 + 빛줄기). 다크 모드에서는 은은하게.
class _Sun extends StatelessWidget {
  const _Sun({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Opacity(
      opacity: Theme.of(context).brightness == Brightness.dark ? 0.35 : 1,
      child: CustomPaint(size: Size.square(size), painter: _SunPainter()),
    ),
  );
}

class _SunPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(c, r * 0.95, Paint()..color = const Color(0xFFFFF3CC));
    canvas.drawCircle(c, r * 0.67, Paint()..color = const Color(0xFFFFE7A0));
    canvas.drawCircle(c, r * 0.40, Paint()..color = const Color(0xFFFFCB3D));
    final ray = Paint()
      ..color = const Color(0xFFFFCB3D)
      ..strokeWidth = r * 0.064
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + d * (r * 0.50), c + d * (r * 0.58), ray);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
    final title = one != null ? one.labelWithName : links.map((l) => l.displayName).join(', ');
    final latest = store.notificationsFor(elderId: store.selectedElderId).firstOrNull;
    final sub = [
      '연결된 가족 ${links.length}명',
      if (latest != null) '최근 알림 ${formatAgo(latest.createdAt, store.now())}',
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: Space.page - 4),
      padding: const EdgeInsets.all(Space.card + 2),
      decoration: cardDecoration(context),
      child: Row(
        children: [
          if (one != null)
            FamilyAvatar(avatarText(one.elderName, fallback: one.displayName), radius: 26)
          else
            // 여러 명: 겹친 이름 대신 가족 아이콘 하나 (이름은 오른쪽 제목에)
            ExcludeSemantics(
              child: CircleAvatar(
                radius: 26,
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
      margin: const EdgeInsets.symmetric(horizontal: Space.page - 4),
      padding: const EdgeInsets.all(Space.card + 2),
      decoration: cardDecoration(context),
      child: Row(
        children: [
          IconBadge(Icons.verified_user_outlined, color: k.primary, background: k.positiveBg),
          const SizedBox(width: 14),
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
    child: Align(
      alignment: Alignment.centerLeft,
      child: TextButton(onPressed: onTap, child: Text('$label 〉')),
    ),
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
      physics: const AlwaysScrollableScrollPhysics(),
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
