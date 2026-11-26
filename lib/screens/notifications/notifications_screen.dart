import 'package:material_ui/material_ui.dart';

import '../../app/dependencies.dart';
import '../../app/routes.dart';
import '../../app/theme.dart';
import '../../models/notification_item.dart';
import '../../utils/formatters.dart';
import '../../widgets/common.dart';

/// 알림 기록: 날짜별로 묶은 목록 (카드 없이 구분선). 위쪽 한 줄에서 전체·확인 전과 가족을 고른다.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _unreadOnly = false;

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context).store;
    final t = Theme.of(context);
    final k = HaebomTokens.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('알림'),
        actions: [
          ListenableBuilder(
            listenable: store,
            builder: (context, _) => TextButton(
              onPressed: store.unreadCount(elderId: store.selectedElderId) == 0
                  ? null
                  : () async {
                      final ok = await confirmDialog(context,
                          title: '모두 확인',
                          message: '확인 전 알림을 모두 확인 처리할까요?\n가족의 해봄 앱에 "확인했어요"로 표시될 수 있습니다.',
                          confirmLabel: '모두 확인');
                      if (ok) await store.repository.markAllNotificationsRead(elderId: store.selectedElderId);
                    },
              child: const Text('모두 확인'),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListenableBuilder(
          listenable: store,
          builder: (context, _) {
            final items = store.notificationsFor(elderId: store.selectedElderId, unreadOnly: _unreadOnly);
            final now = store.now();
            // 날짜별 묶음 (목록은 이미 최신순)
            final rows = <Widget>[];
            String? day;
            for (final n in items) {
              final d = formatDayHeader(n.createdAt, now);
              if (d != day) {
                day = d;
                rows.add(Padding(
                  padding: const EdgeInsets.fromLTRB(Space.page, Space.section - 4, Space.page, 4),
                  child: Semantics(
                    header: true,
                    child: Text(d, style: t.textTheme.bodyMedium?.copyWith(color: k.textSub, fontWeight: FontWeight.w800)),
                  ),
                ));
              } else {
                rows.add(const RowDivider());
              }
              rows.add(_tile(context, n));
            }
            return Column(
              children: [
                const SizedBox(height: 4),
                // 상태(전체·확인 전)와 가족 필터를 한 줄에
                FamilyFilterBar(
                  store: store,
                  leading: [
                    FilterPill(label: '전체', selected: !_unreadOnly, onSelected: () => setState(() => _unreadOnly = false)),
                    FilterPill(
                      label: '확인 전 ${store.unreadCount(elderId: store.selectedElderId)}',
                      selected: _unreadOnly,
                      onSelected: () => setState(() => _unreadOnly = true),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: items.isEmpty
                      ? ListView(children: [
                          EmptyState(
                            icon: Icons.notifications_none_rounded,
                            title: _unreadOnly ? '확인 전 알림이 없습니다' : '알림이 없습니다',
                            message: '가족이 민감한 서비스 이용 알림에 동의하면 이곳에 표시됩니다.',
                          ),
                        ])
                      : ListView(padding: const EdgeInsets.only(bottom: 32), children: rows),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, NotificationItem n) => NotificationTile(
        item: n,
        store: AppScope.of(context).store,
        onTap: () => Navigator.pushNamed(context, AppRoutes.notificationDetail, arguments: n.id),
      );
}
